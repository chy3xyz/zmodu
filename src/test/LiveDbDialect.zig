//! Live-server dialect checks: exercise the SQL each embedded store really
//! sends on PostgreSQL / MySQL (DDL, idempotent inserts, aggregates), which a
//! SQLite-only unit test cannot answer.
//!
//! Gating and env vars follow `web4.x402_store` / `core.DistributedLock`:
//!   ZMODU_TEST_PG=1  with PGHOST / PGPORT / PGUSER / PGPASSWORD / PGDATABASE
//!   DB=mysql         with MYSQL_HOST / MYSQL_PORT / MYSQL_USER / MYSQL_PASSWORD / MYSQL_DATABASE
//! Anything else skips, so the default suite never needs a server.

const std = @import("std");
const sqlx = @import("../sqlx/sqlx.zig");
const SqlxBackend = @import("../persistence/backends/SqlxBackend.zig").SqlxBackend;
const run_audit = @import("../ai/run_audit.zig");
const approval_store = @import("../ai/ops/approval_store.zig");
const x402_mod = @import("../web4/x402.zig");
const x402_store = @import("../web4/x402_store.zig");
const CatalogPermDb = @import("../security/CatalogPermDb.zig");
const Time = @import("../core/Time.zig");

const Env = struct {
    fn get(name: [:0]const u8, default: []const u8) []const u8 {
        const raw = std.c.getenv(name) orelse return default;
        return std.mem.span(raw);
    }
    fn port(name: [:0]const u8, default: u16) u16 {
        const raw = std.c.getenv(name) orelse return default;
        return std.fmt.parseInt(u16, std.mem.span(raw), 10) catch default;
    }
};

fn liveConfig(driver: sqlx.Driver) !sqlx.Config {
    if (!sqlx.DriverFeatures.isEnabled(driver)) return error.SkipZigTest;
    switch (driver) {
        .postgres => {
            const gate = std.c.getenv("ZMODU_TEST_PG") orelse return error.SkipZigTest;
            if (std.mem.eql(u8, std.mem.span(gate), "0")) return error.SkipZigTest;
            return .{
                .driver = .postgres,
                .host = Env.get("PGHOST", "127.0.0.1"),
                .port = Env.port("PGPORT", 5432),
                .username = Env.get("PGUSER", "postgres"),
                .password = Env.get("PGPASSWORD", ""),
                .database = Env.get("PGDATABASE", "postgres"),
                .max_open_conns = 2,
                .max_idle_conns = 1,
            };
        },
        .mysql => {
            const gate = std.c.getenv("DB") orelse return error.SkipZigTest;
            if (!std.mem.eql(u8, std.mem.span(gate), "mysql")) return error.SkipZigTest;
            return .{
                .driver = .mysql,
                .host = Env.get("MYSQL_HOST", "127.0.0.1"),
                .port = Env.port("MYSQL_PORT", 3306),
                .username = Env.get("MYSQL_USER", "root"),
                .password = Env.get("MYSQL_PASSWORD", ""),
                .database = Env.get("MYSQL_DATABASE", "zigzero_test"),
                .max_open_conns = 2,
                .max_idle_conns = 1,
            };
        },
        .sqlite => return error.SkipZigTest,
    }
}

fn uniqueTable(driver: sqlx.Driver, comptime prefix: []const u8) ![]u8 {
    var seed: [8]u8 = undefined;
    try std.Io.randomSecure(std.testing.io, &seed);
    return try std.testing.allocator.print("{s}_{s}_{s}", .{ prefix, @tagName(driver), std.fmt.bytesToHex(seed, .lower) });
}

fn dropTable(client: *sqlx.Client, table: []const u8) void {
    var buf: [128]u8 = undefined;
    const sql = std.fmt.bufPrint(&buf, "DROP TABLE IF EXISTS {s}", .{table}) catch return;
    // Cleanup is best-effort, but a failed DROP still gets a line — the next
    // run's unique table must not inherit a silent leftover.
    _ = client.exec(sql, &.{}) catch |err| std.log.debug("dropTable({s}) failed: {s}", .{ table, @errorName(err) });
}

fn exerciseRunAudit(driver: sqlx.Driver) !void {
    const allocator = std.testing.allocator;
    var client = sqlx.Client.init(allocator, std.testing.io, try liveConfig(driver));
    defer client.deinit();
    try client.connect();

    const table = try uniqueTable(driver, "ai_run_audit_live");
    defer allocator.free(table);
    defer dropTable(&client, table);

    var backend = SqlxBackend{ .allocator = allocator, .client = &client };
    var store = run_audit.RunAuditStore.init(allocator, &backend);
    store.table = table;
    // The whole point of the dialect work: this must actually create the table
    // on this server, not merely look right as a string.
    try store.migrate();
    try store.record(.{
        .run_id = "live-1",
        .kind = .agent,
        .status = "completed",
        .tenant_id = 7,
        .steps = 2,
        .duration_ms = 5,
        .model = "m1",
        .prompt_tokens = 120,
        .completion_tokens = 30,
    });
    try store.record(.{ .run_id = "live-2", .kind = .agent, .status = "failed", .tenant_id = 7, .model = "m1", .prompt_tokens = 80, .completion_tokens = 20 });
    try std.testing.expectEqual(@as(usize, 2), try store.count());

    var rows = std.ArrayList(run_audit.RunAuditStore.UsageRow).empty;
    defer {
        for (rows.items) |r| allocator.free(r.model);
        rows.deinit(allocator);
    }
    try store.aggregate(allocator, &rows, 7, null);
    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    // SUM() arrives as NUMERIC on PostgreSQL and DECIMAL on MySQL; the reader
    // must return the integer regardless.
    try std.testing.expectEqual(@as(u64, 200), rows.items[0].prompt_tokens);
    try std.testing.expectEqual(@as(u64, 50), rows.items[0].completion_tokens);
    try std.testing.expectEqual(@as(u64, 2), rows.items[0].runs);
}

fn exerciseApproval(driver: sqlx.Driver) !void {
    const allocator = std.testing.allocator;
    var client = sqlx.Client.init(allocator, std.testing.io, try liveConfig(driver));
    defer client.deinit();
    try client.connect();

    const table = try uniqueTable(driver, "approval_queue_live");
    defer allocator.free(table);
    defer dropTable(&client, table);

    var backend = SqlxBackend{ .allocator = allocator, .client = &client };
    var queue = approval_store.PersistentApprovalQueue.init(allocator, &backend);
    queue.table = table;
    try queue.migrate();
    try queue.push(.{
        .run_id = "ap-live",
        .subject = "order 9",
        .amount = 50000,
        .note = "needs CFO",
        .step_name = "finance",
        .tenant_id = 7,
    });
    try std.testing.expectEqual(@as(usize, 1), try queue.count(7));
    try std.testing.expect(try queue.resolve("ap-live", 7));
    try std.testing.expectEqual(@as(usize, 0), try queue.count(7));
}

fn exerciseX402(driver: sqlx.Driver) !void {
    const allocator = std.testing.allocator;
    var client = sqlx.Client.init(allocator, std.testing.io, try liveConfig(driver));
    defer client.deinit();
    try client.connect();

    const table = try uniqueTable(driver, "web4_invoice_live");
    defer allocator.free(table);
    defer dropTable(&client, table);

    var backend = SqlxBackend{ .allocator = allocator, .client = &client };
    var store = x402_store.X402Store.init(allocator, &backend);
    store.table = table;
    try store.migrate();
    const invoice = x402_mod.Invoice{
        .id = "inv-live",
        .payee_did = "did:key:z6MkDemo",
        .amount = 1,
        .currency = .usdc,
        .deadline = Time.wallClockSeconds(std.testing.io) + 3600,
        .description = "",
    };
    try store.create(invoice, "did:key:z6MkPayer");
    try std.testing.expectError(error.DuplicateInvoice, store.create(invoice, "did:key:z6MkPayer"));
    try std.testing.expectEqual(x402_store.RedeemResult.redeemed, try store.redeem("inv-live", "tx-live", "did:key:z6MkPayer"));
    try std.testing.expectEqual(x402_store.RedeemResult.already_used, try store.redeem("inv-live", "tx-live-2", "did:key:z6MkPayer"));
}

fn exerciseCatalogPerms(driver: sqlx.Driver) !void {
    const allocator = std.testing.allocator;
    var client = sqlx.Client.init(allocator, std.testing.io, try liveConfig(driver));
    defer client.deinit();
    try client.connect();

    // `CatalogPermDb` names its table in the API, so drop first: a leftover from
    // an earlier run would otherwise grant stale permissions.
    dropTable(&client, "role_permission");
    defer dropTable(&client, "role_permission");
    try CatalogPermDb.ensureSchema(&client);
    try CatalogPermDb.grant(&client, "admin", "tenant:read");
    try CatalogPermDb.grant(&client, "admin", "tenant:suspend");
    try CatalogPermDb.grant(&client, "user", "tenant:read");
    // Idempotent on every dialect — re-running the seed must not error.
    try CatalogPermDb.grant(&client, "admin", "tenant:read");
    try CatalogPermDb.grant(&client, "admin", "tenant:suspend");
    try CatalogPermDb.grant(&client, "auditor", "audit:read");

    const csv = try CatalogPermDb.permissionsCsv(allocator, &client, &.{ "admin", "user", "auditor" });
    defer allocator.free(csv);
    try std.testing.expect(std.mem.indexOf(u8, csv, "tenant:suspend") != null);
    try std.testing.expect(std.mem.indexOf(u8, csv, "audit:read") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, csv, "tenant:read"));
}

test "live PostgreSQL: cursor decodes typed cells" {
    const allocator = std.testing.allocator;
    var client = sqlx.Client.init(allocator, std.testing.io, try liveConfig(.postgres));
    defer client.deinit();
    try client.connect();

    var cursor = try client.queryCursorEx("SELECT 42 AS answer, 'x' AS label", &.{}, .{});
    defer cursor.deinit();
    const row = (try cursor.next()) orelse return error.ExpectedRow;
    switch (row.get("answer").?) {
        .int => |v| try std.testing.expectEqual(@as(i64, 42), v),
        else => |tag| {
            std.debug.print("cursor decoded answer as {s}\n", .{@tagName(tag)});
            return error.UnexpectedValueTag;
        },
    }
}

test "live PostgreSQL: RunAuditStore migrates, records and aggregates" {
    try exerciseRunAudit(.postgres);
}

test "live MySQL: RunAuditStore migrates, records and aggregates" {
    try exerciseRunAudit(.mysql);
}

test "live PostgreSQL: PersistentApprovalQueue migrates, pushes and resolves" {
    try exerciseApproval(.postgres);
}

test "live MySQL: PersistentApprovalQueue migrates, pushes and resolves" {
    try exerciseApproval(.mysql);
}

test "live PostgreSQL: X402Store migrates, creates and redeems" {
    try exerciseX402(.postgres);
}

test "live MySQL: X402Store migrates, creates and redeems" {
    try exerciseX402(.mysql);
}

test "live PostgreSQL: CatalogPermDb seeds and reads permissions" {
    try exerciseCatalogPerms(.postgres);
}

test "live MySQL: CatalogPermDb seeds and reads permissions" {
    try exerciseCatalogPerms(.mysql);
}
