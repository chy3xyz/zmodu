# zmodu AI-First Core Goals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MCP Server, verify command, and incremental generation to make zmodu an AI-callable code generation framework.

**Architecture:** Three new modules (`mcp_types.zig` + `mcp_server.zig`, `verify.zig`, `sql_diff.zig` + `incremental.zig`) imported from `main.zig`. MCP Server wraps existing CLI functions as JSON-RPC tools over stdio. Verify runs `zig build` + file integrity checks. Incremental scaffold uses SHA256 hash tracking to protect AI-modified files.

**Tech Stack:** Zig 0.17+, std.json for JSON-RPC, std.crypto.hash.sha2 for file hashing, std.process.Child for zig build subprocess.

**Spec:** `docs/superpowers/specs/2026-06-15-ai-core-goals-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/mcp_types.zig` | **Create** | JSON-RPC 2.0 types, MCP protocol types (Request, Response, Tool, ToolResult) |
| `src/mcp_server.zig` | **Create** | MCP server: stdio transport, request dispatch, tool registry |
| `src/verify.zig` | **Create** | Verify logic: compile check, module integrity, import consistency |
| `src/sql_diff.zig` | **Create** | SQL AST diff engine: TableDiff, ColumnChange types, diffTables() |
| `src/incremental.zig` | **Create** | Hash tracking (generated_hashes.json read/write), SHA256 computation |
| `src/main.zig` | **Modify** | Add `mcp`, `verify`, `diff` to Command enum; add dispatch cases; import new modules |
| `build.zig` | **Modify** | Add `mcp_server.zig`, `verify.zig`, `sql_diff.zig` as test root modules |
| `docs/ZMODU-FIRST-PRINCIPLE.md` | **Modify** | Remove ext file boundary, add MCP workflow |
| `shopdemo/AGENTS.md` | **Modify** | Update safe-to-edit list, add MCP workflow |
| `docs/AI-DEVELOP-PROMPT.md` | **Modify** | Add MCP call examples |
| `docs/AI-MIGRATION-PROMPT.md` | **Modify** | Add MCP call examples |

---

## Phase 1: MCP Server

### Task 1: MCP Protocol Types (`src/mcp_types.zig`)

**Files:**
- Create: `src/mcp_types.zig`
- Test: embedded `test` blocks in `src/mcp_types.zig`

- [ ] **Step 1: Write MCP types with tests**

```zig
// src/mcp_types.zig
const std = @import("std");

/// JSON-RPC 2.0 Request
pub const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?i64 = null,
    method: []const u8,
    params: ?std.json.Value = null,
};

/// JSON-RPC 2.0 Response
pub const JsonRpcResponse = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?i64 = null,
    result: ?std.json.Value = null,
    @"error": ?JsonRpcError = null,
};

pub const JsonRpcError = struct {
    code: i64,
    message: []const u8,
    data: ?std.json.Value = null,
};

/// MCP Tool definition (for tools/list response)
pub const McpTool = struct {
    name: []const u8,
    description: []const u8,
    inputSchema: std.json.Value,
};

/// MCP server info (for initialize response)
pub const ServerInfo = struct {
    name: []const u8,
    version: []const u8,
};

/// Build a JSON-RPC success response as a string.
/// Caller owns the returned memory.
pub fn successResponse(allocator: std.mem.Allocator, id: ?i64, result: std.json.Value) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = result,
        .@"error" = null,
    }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

/// Build a JSON-RPC error response as a string.
/// Caller owns the returned memory.
pub fn errorResponse(allocator: std.mem.Allocator, id: ?i64, code: i64, message: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = null,
        .@"error" = .{ .code = code, .message = message },
    }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

// ── Tests ──

test "successResponse produces valid JSON-RPC 2.0" {
    const allocator = std.testing.allocator;
    const result = try successResponse(allocator, 1, .{ .string = "ok" });
    defer allocator.free(result);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("2.0", obj.get("jsonrpc").?.string);
    try std.testing.expectEqual(@as(i64, 1), obj.get("id").?.integer);
    try std.testing.expectEqualStrings("ok", obj.get("result").?.string);
}

test "errorResponse produces valid JSON-RPC 2.0 error" {
    const allocator = std.testing.allocator;
    const resp = try errorResponse(allocator, 2, -32601, "Method not found");
    defer allocator.free(resp);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expect(obj.get("result") == null);
    const err_obj = obj.get("@" ++ "error").?.object;
    try std.testing.expectEqual(@as(i64, -32601), err_obj.get("code").?.integer);
    try std.testing.expectEqualStrings("Method not found", err_obj.get("message").?.string);
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -20`
Expected: All existing tests + new mcp_types tests pass (note: existing tests in main.zig must still pass).

- [ ] **Step 3: Commit**

```bash
git add src/mcp_types.zig
git commit -m "feat(mcp): add JSON-RPC 2.0 protocol types with tests"
```

---

### Task 2: MCP Server Core (`src/mcp_server.zig`)

**Files:**
- Create: `src/mcp_server.zig`
- Test: embedded `test` blocks in `src/mcp_server.zig`

- [ ] **Step 1: Write MCP server with tests**

```zig
// src/mcp_server.zig
const std = @import("std");
const mcp_types = @import("mcp_types.zig");

/// Start the MCP server loop on stdin/stdout.
/// Blocks until stdin is closed or an exit is requested.
pub fn start(allocator: std.mem.Allocator) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buf: [65536]u8 = undefined;

    while (true) {
        // Read one line of JSON (newline-delimited, MCP stdio transport)
        const line = stdin.readUntilDelimiter(&buf, '\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (line.len == 0) continue;

        const response = handleMessage(allocator, line) catch |err| {
            // Last resort: generic internal error
            const resp = try mcp_types.errorResponse(allocator, null, -32603, @errorName(err));
            defer allocator.free(resp);
            try stdout.print("{s}\n", .{resp});
            continue;
        };
        defer allocator.free(response);
        try stdout.print("{s}\n", .{response});
    }
}

/// Parse a JSON-RPC request line and dispatch to the appropriate handler.
/// Returns an owned response string. Caller must free.
fn handleMessage(allocator: std.mem.Allocator, line: []const u8) ![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch {
        return mcp_types.errorResponse(allocator, null, -32700, "Parse error");
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const method = root.get("method").?.string;
    const id_val = root.get("id");
    const id: ?i64 = if (id_val) |v| switch (v) {
        .integer => |i| i,
        else => null,
    } else null;
    const params = root.get("params");

    // Deep-copy params before parsed is freed
    const params_copy = if (params) |p| try deepCopyJson(allocator, p) else null;
    defer if (params_copy) |p| freeJson(allocator, p);

    if (std.mem.eql(u8, method, "initialize")) {
        return handleInitialize(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/list")) {
        return handleToolsList(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/call")) {
        return handleToolsCall(allocator, id, params_copy);
    } else if (std.mem.eql(u8, method, "notifications/initialized")) {
        // Notification (no id) — no response needed
        if (id == null) return allocator.dupe(u8, "") catch "";
        return mcp_types.errorResponse(allocator, id, -32601, "Method not found");
    } else {
        return mcp_types.errorResponse(allocator, id, -32601, "Method not found");
    }
}

fn handleInitialize(allocator: std.mem.Allocator, id: ?i64) ![]const u8 {
    // Return server info + capabilities
    const result = .{
        .protocolVersion = "2024-11-05",
        .capabilities = .{ .tools = .{} },
        .serverInfo = .{ .name = "zmodu", .version = "0.14.9" },
    };
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = result,
        .@"error" = null,
    }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

fn handleToolsList(allocator: std.mem.Allocator, id: ?i64) ![]const u8 {
    const tools = [_]std.json.Value{
        try makeToolSchema(allocator, "zmodu_scaffold", "Generate a full ZigModu project from SQL DDL", &.{
            .{ .name = "sql_path", .type = "string", .description = "Path to SQL file" },
            .{ .name = "output_dir", .type = "string", .description = "Output directory for the project" },
            .{ .name = "orm_backend", .type = "string", .description = "ORM backend: sqlx (default) or zent", .optional = true },
        }),
        try makeToolSchema(allocator, "zmodu_module", "Generate a single module skeleton", &.{
            .{ .name = "name", .type = "string", .description = "Module name (snake_case)" },
            .{ .name = "output_dir", .type = "string", .description = "Project root directory", .optional = true },
        }),
        try makeToolSchema(allocator, "zmodu_version", "Get zmodu version info", &.{}),
        try makeToolSchema(allocator, "zmodu_verify", "Verify a generated project compiles and has correct structure", &.{
            .{ .name = "project_dir", .type = "string", .description = "Path to the project directory" },
        }),
        try makeToolSchema(allocator, "zmodu_diff", "Compare two SQL files and show table-level changes", &.{
            .{ .name = "old_sql", .type = "string", .description = "Path to the old SQL file" },
            .{ .name = "new_sql", .type = "string", .description = "Path to the new SQL file" },
        }),
    };
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = .{ .tools = tools },
        .@"error" = null,
    }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

fn handleToolsCall(allocator: std.mem.Allocator, id: ?i64, params: ?std.json.Value) ![]const u8 {
    if (params == null) return mcp_types.errorResponse(allocator, id, -32602, "Missing params");
    const p = params.?.object;
    const tool_name = p.get("name").?.string;
    const arguments = p.get("arguments");

    const result = if (std.mem.eql(u8, tool_name, "zmodu_version"))
        try callVersion(allocator)
    else if (std.mem.eql(u8, tool_name, "zmodu_scaffold"))
        try callScaffold(allocator, arguments)
    else if (std.mem.eql(u8, tool_name, "zmodu_module"))
        try callModule(allocator, arguments)
    else if (std.mem.eql(u8, tool_name, "zmodu_verify"))
        try callVerify(allocator, arguments)
    else if (std.mem.eql(u8, tool_name, "zmodu_diff"))
        try callDiff(allocator, arguments)
    else
        return mcp_types.errorResponse(allocator, id, -32602, "Unknown tool");

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = .{
            .content = [_]std.json.Value{.{ .type = "text", .text = result }},
            .isError = false,
        },
        .@"error" = null,
    }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

// ── Tool implementations (stubs, wired in Task 4) ──

fn callVersion(allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{
        .version = "0.14.9",
        .zig_version = @tagName(builtin.zig_backend),
    }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

fn callScaffold(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    _ = args;
    // Stub — wired to real scaffold in Task 4
    return allocator.dupe(u8, "{\"error\":\"scaffold not yet wired\"}");
}

fn callModule(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    _ = args;
    return allocator.dupe(u8, "{\"error\":\"module not yet wired\"}");
}

fn callVerify(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    _ = args;
    return allocator.dupe(u8, "{\"error\":\"verify not yet wired\"}");
}

fn callDiff(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    _ = args;
    return allocator.dupe(u8, "{\"error\":\"diff not yet wired\"}");
}

// ── Helpers ──

const builtin = @import("builtin");

const ToolParam = struct {
    name: []const u8,
    type: []const u8,
    description: []const u8,
    optional: bool = false,
};

fn makeToolSchema(allocator: std.mem.Allocator, name: []const u8, description: []const u8, params: []const ToolParam) !std.json.Value {
    _ = allocator;
    // Build JSON schema for input
    var required_arr = std.json.Array{};
    var properties = std.json.ObjectMap{};

    for (params) |p| {
        try properties.put(p.name, .{ .object = blk: {
            var m = std.json.ObjectMap{};
            try m.put("type", .{ .string = p.type });
            try m.put("description", .{ .string = p.description });
            break :blk m;
        } });
        if (!p.optional) {
            try required_arr.append(.{ .string = p.name });
        }
    }

    var schema = std.json.ObjectMap{};
    try schema.put("type", .{ .string = "object" });
    try schema.put("properties", .{ .object = properties });
    if (required_arr.items.len > 0) {
        try schema.put("required", .{ .array = required_arr });
    }

    var tool_obj = std.json.ObjectMap{};
    try tool_obj.put("name", .{ .string = name });
    try tool_obj.put("description", .{ .string = description });
    try tool_obj.put("inputSchema", .{ .object = schema });

    return .{ .object = tool_obj };
}

/// Deep-copy a JSON Value so it survives after the parsed buffer is freed.
fn deepCopyJson(allocator: std.mem.Allocator, val: std.json.Value) !std.json.Value {
    return switch (val) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var new_arr = std.json.Array{};
            for (arr.items) |item| {
                try new_arr.append(try deepCopyJson(allocator, item));
            }
            return .{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj = std.json.ObjectMap{};
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try deepCopyJson(allocator, entry.value_ptr.*);
                try new_obj.put(key, value);
            }
            return .{ .object = new_obj };
        },
    };
}

/// Free a deep-copied JSON Value.
fn freeJson(allocator: std.mem.Allocator, val: std.json.Value) void {
    switch (val) {
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr.items) |item| freeJson(allocator, item);
            arr.deinit();
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeJson(allocator, entry.value_ptr.*);
            }
            obj.deinit();
        },
        else => {},
    }
}

// ── Tests ──

test "handleMessage returns error for invalid JSON" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "not json");
    defer allocator.free(resp);
    // Should contain parse error
    try std.testing.expect(std.mem.indexOf(u8, resp, "Parse error") != null);
}

test "handleMessage dispatches initialize" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}");
    defer allocator.free(resp);
    try std.testing.expect(std.mem.indexOf(u8, resp, "zmodu") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "protocolVersion") != null);
}

test "handleMessage dispatches tools/list" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}");
    defer allocator.free(resp);
    try std.testing.expect(std.mem.indexOf(u8, resp, "zmodu_scaffold") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "zmodu_version") != null);
}

test "handleMessage returns error for unknown method" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"unknown\"}");
    defer allocator.free(resp);
    try std.testing.expect(std.mem.indexOf(u8, resp, "Method not found") != null);
}

test "handleMessage dispatches tools/call for version" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"zmodu_version\",\"arguments\":{}}}");
    defer allocator.free(resp);
    try std.testing.expect(std.mem.indexOf(u8, resp, "0.14.9") != null);
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -30`
Expected: All tests pass including new mcp_server tests.

- [ ] **Step 3: Commit**

```bash
git add src/mcp_server.zig
git commit -m "feat(mcp): add MCP server core with request dispatch and tool registry"
```

---

### Task 3: Wire `mcp` Command into `main.zig`

**Files:**
- Modify: `src/main.zig`

- [ ] **Step 1: Add `mcp` to the Command enum (line 4)**

In `src/main.zig`, add `mcp` to the `Command` enum at line 4:

```zig
const Command = enum {
    new, module, event, api, orm, generate, scaffold, add,
    migration, health, config, @"test", plugin, life, upgrade,
    mcp, help, version,
};
```

- [ ] **Step 2: Add `mcp` to `runCommand` dispatch (around line 197)**

In the `runCommand` function, add a new case to the switch after `.upgrade`:

```zig
.mcp => try cmdMcp(allocator),
```

- [ ] **Step 3: Add `mcp` to `parseCommand` (around line 297)**

In the `parseCommand` function, add:

```zig
if (std.mem.eql(u8, cmd, "mcp")) return .mcp;
```

- [ ] **Step 4: Add `cmdMcp` function and import**

At the top of `main.zig` (after existing imports), add:

```zig
const mcp_server = @import("mcp_server.zig");
```

Add the command handler function (near other cmd functions):

```zig
fn cmdMcp(allocator: std.mem.Allocator) !void {
    try mcp_server.start(allocator);
}
```

- [ ] **Step 5: Add `mcp` to `printUsage` (around line 340)**

In the `printUsage` function, add `mcp` to the command list.

- [ ] **Step 6: Run tests + verify CLI help**

```bash
cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -5
zig build && ./zig-out/bin/zmodu help 2>&1 | grep mcp
```
Expected: Tests pass, `mcp` appears in help output.

- [ ] **Step 7: Commit**

```bash
git add src/main.zig
git commit -m "feat(mcp): wire mcp command into CLI dispatch"
```

---

### Task 4: Wire Real Tool Implementations into MCP Server

**Files:**
- Modify: `src/mcp_server.zig`

- [ ] **Step 1: Replace stub `callScaffold` with real implementation**

Replace the `callScaffold` function in `mcp_server.zig`:

```zig
fn callScaffold(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (args == null) return try jsonError(allocator, "Missing arguments");
    const a = args.?.object;
    const sql_path = a.get("sql_path") orelse return try jsonError(allocator, "Missing sql_path");
    const output_dir = a.get("output_dir") orelse return try jsonError(allocator, "Missing output_dir");

    // Build CLI args for cmdScaffold
    var cli_args = std.ArrayList([]const u8).init(allocator);
    defer cli_args.deinit();
    try cli_args.append("--sql");
    try cli_args.append(sql_path.string);
    try cli_args.append("--out");
    try cli_args.append(output_dir.string);
    if (a.get("orm_backend")) |backend| {
        if (std.mem.eql(u8, backend.string, "zent")) {
            // Zent backend is handled differently — for now default to sqlx
        }
    }

    // Run scaffold in-process
    const main = @import("main.zig");
    var result_buf = std.ArrayList(u8).init(allocator);
    errdefer result_buf.deinit();

    main.cmdScaffold(std.io.null_io, allocator, cli_args.items) catch |err| {
        try std.json.stringify(.{ .success = false, .error_message = @errorName(err) }, .{}, result_buf.writer());
        return result_buf.toOwnedSlice();
    };

    try std.json.stringify(.{ .success = true, .message = "Scaffold completed" }, .{}, result_buf.writer());
    return result_buf.toOwnedSlice();
}
```

> **NOTE:** The above assumes `cmdScaffold` is made `pub` in main.zig (Step 2). If `cmdScaffold` cannot be made pub due to the monolithic structure, the alternative is to shell out to `zmodu scaffold` via `std.process.Child`. See Step 3 for the fallback.

- [ ] **Step 2: Make `cmdScaffold`, `cmdModule` pub in main.zig**

In `src/main.zig`, change the function signatures:

```zig
pub fn cmdScaffold(io: std.Io, allocator: std.mem.Allocator, args: []const []const u8) !void {
```

```zig
pub fn cmdModule(io: std.Io, allocator: std.mem.Allocator, args: []const []const u8) !void {
```

Also make `parseSqlSchema` pub:

```zig
pub fn parseSqlSchema(allocator: std.mem.Allocator, sql: []const u8) ![]TableDef {
```

And make `TableDef`, `ColumnDef`, `ColumnType`, `ForeignKey` pub:

```zig
pub const TableDef = struct {
    name: []const u8,
    columns: []ColumnDef,
    foreign_keys: []ForeignKey,
};

pub const ColumnDef = struct {
    name: []const u8,
    col_type: ColumnType,
    nullable: bool,
    is_primary_key: bool,
    is_unique: bool,
    has_default: bool,
    comment: ?[]const u8,
};

pub const ColumnType = enum { int, string, bool, float, datetime, unknown };

pub const ForeignKey = struct {
    column_name: []const u8,
    ref_table: []const u8,
    ref_column: []const u8,
};
```

- [ ] **Step 3: Fallback — use subprocess if direct call is impractical**

If making functions pub causes compile issues (circular imports, etc.), replace the direct call approach with subprocess:

```zig
fn callScaffold(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (args == null) return try jsonError(allocator, "Missing arguments");
    const a = args.?.object;
    const sql_path = a.get("sql_path") orelse return try jsonError(allocator, "Missing sql_path");
    const output_dir = a.get("output_dir") orelse return try jsonError(allocator, "Missing output_dir");

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("zmodu");
    try argv.append("scaffold");
    try argv.append("--sql");
    try argv.append(sql_path.string);
    try argv.append("--out");
    try argv.append(output_dir.string);

    var child = std.process.Child.init(argv.items, allocator);
    child.stderr_behavior = .pipe;
    child.stdout_behavior = .pipe;

    try child.spawn();
    const result = try child.wait();
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    switch (result) {
        .exited => |code| {
            if (code == 0) {
                try std.json.stringify(.{ .success = true, .message = "Scaffold completed" }, .{}, buf.writer());
            } else {
                try std.json.stringify(.{ .success = false, .exit_code = code, .stderr = stderr }, .{}, buf.writer());
            }
        },
        else => {
            try std.json.stringify(.{ .success = false, .error_message = "Process terminated abnormally" }, .{}, buf.writer());
        },
    }
    return buf.toOwnedSlice();
}
```

Use the same subprocess pattern for `callModule`, `callVerify`, and `callDiff`.

- [ ] **Step 4: Wire `callModule` via subprocess**

```zig
fn callModule(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (args == null) return try jsonError(allocator, "Missing arguments");
    const a = args.?.object;
    const name = a.get("name") orelse return try jsonError(allocator, "Missing name");

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("zmodu");
    try argv.append("module");
    try argv.append(name.string);
    if (a.get("output_dir")) |dir| {
        try argv.append("--out");
        try argv.append(dir.string);
    }

    return runSubprocess(allocator, argv.items);
}
```

- [ ] **Step 5: Add `jsonError` and `runSubprocess` helpers**

```zig
fn jsonError(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try std.json.stringify(.{ .success = false, .error_message = message }, .{}, buf.writer());
    return buf.toOwnedSlice();
}

fn runSubprocess(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stderr_behavior = .pipe;
    child.stdout_behavior = .pipe;

    try child.spawn();
    const result = try child.wait();
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    switch (result) {
        .exited => |code| {
            if (code == 0) {
                try std.json.stringify(.{ .success = true, .message = "Command completed" }, .{}, buf.writer());
            } else {
                try std.json.stringify(.{ .success = false, .exit_code = code, .stderr = stderr }, .{}, buf.writer());
            }
        },
        else => {
            try std.json.stringify(.{ .success = false, .error_message = "Process terminated" }, .{}, buf.writer());
        },
    }
    return buf.toOwnedSlice();
}
```

- [ ] **Step 6: Run tests + manual MCP test**

```bash
cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -5
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./zig-out/bin/zmodu mcp 2>&1 | head -5
```
Expected: Tests pass, MCP responds to initialize.

- [ ] **Step 7: Commit**

```bash
git add src/mcp_server.zig src/main.zig
git commit -m "feat(mcp): wire scaffold, module, version tool implementations"
```

---

### Task 5: MCP Integration Test (Manual End-to-End)

**Files:**
- Test: manual test via stdin pipe

- [ ] **Step 1: Test MCP initialize handshake**

```bash
cd /Users/n0x/w4_proj/zig_ws/zmodu
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' | ./zig-out/bin/zmodu mcp
```
Expected: JSON response with `protocolVersion`, `capabilities`, `serverInfo`.

- [ ] **Step 2: Test tools/list**

```bash
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./zig-out/bin/zmodu mcp
```
Expected: JSON with array of 5 tools (zmodu_scaffold, zmodu_module, zmodu_version, zmodu_verify, zmodu_diff).

- [ ] **Step 3: Test tools/call for zmodu_version**

```bash
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"zmodu_version","arguments":{}}}' | ./zig-out/bin/zmodu mcp
```
Expected: JSON with version "0.14.9".

- [ ] **Step 4: Test tools/call for zmodu_scaffold with real SQL**

```bash
mkdir -p /tmp/zmodu-mcp-test
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"zmodu_scaffold","arguments":{"sql_path":"src/shopdemo/init.sql","output_dir":"/tmp/zmodu-mcp-test"}}}' | ./zig-out/bin/zmodu mcp
```
Expected: JSON with `success: true`.

- [ ] **Step 5: Verify scaffold output exists**

```bash
ls /tmp/zmodu-mcp-test/src/modules/ | head -10
```
Expected: Module directories exist.

- [ ] **Step 6: Cleanup and commit**

```bash
rm -rf /tmp/zmodu-mcp-test
git add -A
git commit -m "test(mcp): verify MCP end-to-end integration"
```

---

## Phase 2: Verify

### Task 6: Verify Module (`src/verify.zig`)

**Files:**
- Create: `src/verify.zig`
- Test: embedded `test` blocks

- [ ] **Step 1: Write verify module with tests**

```zig
// src/verify.zig
const std = @import("std");

pub const VerifyStatus = enum { pass, fail, warn, skip };

pub const CheckResult = struct {
    name: []const u8,
    status: VerifyStatus,
    details: ?[]const u8 = null,
    duration_ms: ?u64 = null,
};

pub const VerifyReport = struct {
    pass: bool,
    checks: []CheckResult,
    errors: [][]const u8,
    warnings: [][]const u8,
    summary: []const u8,
};

/// Run all verify checks on a project directory.
/// Caller owns the returned VerifyReport memory.
pub fn verifyProject(allocator: std.mem.Allocator, project_dir: []const u8) !VerifyReport {
    var checks = std.ArrayList(CheckResult).init(allocator);
    errdefer checks.deinit();
    var errors = std.ArrayList([]const u8).init(allocator);
    errdefer errors.deinit();
    var warnings = std.ArrayList([]const u8).init(allocator);
    errdefer warnings.deinit();

    // Check 1: Module integrity
    const integrity = try checkModuleIntegrity(allocator, project_dir);
    try checks.append(integrity);
    if (integrity.status == .fail) {
        try errors.append(try allocator.dupe(u8, integrity.details orelse "Module integrity check failed"));
    }

    // Check 2: Import consistency
    const imports = try checkImportConsistency(allocator, project_dir);
    try checks.append(imports);
    if (imports.status == .fail) {
        try errors.append(try allocator.dupe(u8, imports.details orelse "Import consistency check failed"));
    }
    if (imports.status == .warn) {
        try warnings.append(try allocator.dupe(u8, imports.details orelse "Import warnings found"));
    }

    // Check 3: Compile
    const compile = try checkCompile(allocator, project_dir);
    try checks.append(compile);
    if (compile.status == .fail) {
        try errors.append(try allocator.dupe(u8, compile.details orelse "Compilation failed"));
    }

    const pass = for (checks.items) |c| {
        if (c.status == .fail) break false;
    } else true;

    const err_count = errors.items.len;
    const warn_count = warnings.items.len;
    const pass_count = for (checks.items) |c, i| {
        if (c.status != .pass) break i;
    } else checks.items.len;

    var summary_buf = std.ArrayList(u8).init(allocator);
    try summary_buf.writer().print("{} checks: {} pass, {} warn, {} fail", .{
        checks.items.len, pass_count, warn_count, err_count,
    });

    return VerifyReport{
        .pass = pass,
        .checks = try checks.toOwnedSlice(),
        .errors = try errors.toOwnedSlice(),
        .warnings = try warnings.toOwnedSlice(),
        .summary = try summary_buf.toOwnedSlice(),
    };
}

/// Check that each module directory contains the required 6 files.
fn checkModuleIntegrity(allocator: std.mem.Allocator, project_dir: []const u8) !CheckResult {
    const required_files = [_][]const u8{ "model.zig", "persistence.zig", "service.zig", "api.zig", "module.zig", "root.zig" };

    var modules_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const modules_path = try std.fmt.bufPrint(&modules_path_buf, "{s}/src/modules", .{project_dir});

    var dir = std.fs.openDirAbsolute(modules_path, .{ .iterate = true }) catch {
        return CheckResult{
            .name = "module_integrity",
            .status = .fail,
            .details = "src/modules directory not found",
        };
    };
    defer dir.close();

    var missing = std.ArrayList(u8).init(allocator);
    errdefer missing.deinit();
    var module_count: usize = 0;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        module_count += 1;

        for (required_files) |req_file| {
            var file_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}/{s}", .{ entry.name, req_file });
            dir.access(file_path, .{}) catch {
                try missing.writer().print("{s}/{s} ", .{ entry.name, req_file });
            };
        }
    }

    if (missing.items.len > 0) {
        return CheckResult{
            .name = "module_integrity",
            .status = .fail,
            .details = try missing.toOwnedSlice(),
        };
    }

    var details_buf = std.ArrayList(u8).init(allocator);
    try details_buf.writer().print("{} modules checked", .{module_count});

    return CheckResult{
        .name = "module_integrity",
        .status = .pass,
        .details = try details_buf.toOwnedSlice(),
    };
}

/// Scan all .zig files for @import("...") and check that referenced files exist.
fn checkImportConsistency(allocator: std.mem.Allocator, project_dir: []const u8) !CheckResult {
    var src_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const src_path = try std.fmt.bufPrint(&src_path_buf, "{s}/src", .{project_dir});

    var missing_imports = std.ArrayList([]const u8).init(allocator);
    errdefer missing_imports.deinit();

    // Walk src/ directory looking for .zig files
    try walkAndCheckImports(allocator, src_path, src_path, &missing_imports);

    if (missing_imports.items.len > 0) {
        var details_buf = std.ArrayList(u8).init(allocator);
        try details_buf.writer().print("Missing imports: ", .{});
        for (missing_imports.items) |m| {
            try details_buf.writer().print("{s} ", .{m});
        }
        return CheckResult{
            .name = "import_consistency",
            .status = .warn,
            .details = try details_buf.toOwnedSlice(),
        };
    }

    return CheckResult{
        .name = "import_consistency",
        .status = .pass,
        .details = "All imports resolved",
    };
}

fn walkAndCheckImports(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    current_path: []const u8,
    missing: *std.ArrayList([]const u8),
) !void {
    var dir = std.fs.openDirAbsolute(current_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ current_path, entry.name }) catch continue;

        if (entry.kind == .directory) {
            if (entry.name[0] == '.') continue; // skip dotdirs
            try walkAndCheckImports(allocator, base_path, full_path, missing);
            continue;
        }

        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        // Read file and scan for @import("...")
        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        defer file.close();
        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch continue;
        defer allocator.free(content);

        // Simple scan for @import("...")
        var i: usize = 0;
        while (i < content.len) {
            if (std.mem.indexOfPos(u8, content, i, "@import(\"")) |pos| {
                const start = pos + "@import(\"".len;
                if (std.mem.indexOfPos(u8, content, start, "\"")) |end| {
                    const import_name = content[start..end];
                    // Resolve relative to the file's directory
                    if (!std.mem.startsWith(u8, import_name, "std") and
                        !std.mem.startsWith(u8, import_name, "builtin"))
                    {
                        // Check if file exists relative to the importing file's dir
                        var dir_of_file_buf: [std.fs.max_path_bytes]u8 = undefined;
                        const dir_of_file = std.fs.path.dirname(full_path) orelse current_path;
                        var resolved_buf: [std.fs.max_path_bytes]u8 = undefined;
                        const resolved = std.fmt.bufPrint(&resolved_buf, "{s}/{s}", .{ dir_of_file, import_name }) catch {
                            i = end + 1;
                            continue;
                        };
                        std.fs.accessAbsolute(resolved, .{}) catch {
                            try missing.append(try allocator.dupe(u8, import_name));
                        };
                    }
                    i = end + 1;
                } else break;
            } else break;
        }
    }
}

/// Run `zig build` in the project directory and check exit code.
fn checkCompile(allocator: std.mem.Allocator, project_dir: []const u8) !CheckResult {
    const start_time = std.time.milliTimestamp();

    var argv = [_][]const u8{ "zig", "build" };
    var child = std.process.Child.init(&argv, allocator);
    child.cwd = project_dir;
    child.stderr_behavior = .pipe;
    child.stdout_behavior = .pipe;

    child.spawn() catch |err| {
        return CheckResult{
            .name = "compile",
            .status = .fail,
            .details = try std.fmt.allocPrint(allocator, "Failed to spawn zig build: {s}", .{@errorName(err)}),
        };
    };

    const result = child.wait() catch |err| {
        return CheckResult{
            .name = "compile",
            .status = .fail,
            .details = try std.fmt.allocPrint(allocator, "Failed to wait for zig build: {s}", .{@errorName(err)}),
        };
    };

    const elapsed = std.time.milliTimestamp() - start_time;

    const stderr = child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024) catch "";
    defer allocator.free(stderr);

    switch (result) {
        .exited => |code| {
            if (code == 0) {
                return CheckResult{
                    .name = "compile",
                    .status = .pass,
                    .duration_ms = @intCast(elapsed),
                };
            } else {
                // Extract first error line
                var first_line: []const u8 = stderr;
                if (std.mem.indexOf(u8, stderr, "\n")) |nl| {
                    first_line = stderr[0..nl];
                }
                return CheckResult{
                    .name = "compile",
                    .status = .fail,
                    .details = try allocator.dupe(u8, first_line),
                    .duration_ms = @intCast(elapsed),
                };
            }
        },
        else => {
            return CheckResult{
                .name = "compile",
                .status = .fail,
                .details = "zig build terminated abnormally",
                .duration_ms = @intCast(elapsed),
            };
        },
    }
}

// ── Tests ──

test "checkModuleIntegrity detects missing files" {
    // Create a temp dir with one module missing root.zig
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create src/modules/testmod/ with only model.zig
    try tmp.dir.makePath("src/modules/testmod");
    const f = try tmp.dir.createFile("src/modules/testmod/model.zig", .{});
    f.close();

    const result = try checkModuleIntegrity(std.testing.allocator, tmp_path);
    try std.testing.expect(result.status == .fail);
    try std.testing.expect(result.details != null);
    try std.testing.expect(std.mem.indexOf(u8, result.details.?, "testmod/persistence.zig") != null);
}

test "checkModuleIntegrity passes when all files present" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("src/modules/testmod");
    const required = [_][]const u8{ "model.zig", "persistence.zig", "service.zig", "api.zig", "module.zig", "root.zig" };
    for (required) |name| {
        var path_buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "src/modules/testmod/{s}", .{name});
        const f = try tmp.dir.createFile(path, .{});
        f.close();
    }

    const result = try checkModuleIntegrity(std.testing.allocator, tmp_path);
    try std.testing.expect(result.status == .pass);
}

test "checkImportConsistency finds missing import" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("src");
    const f = try tmp.dir.createFile("src/main.zig", .{});
    try f.writeAll("const x = @import(\"nonexistent.zig\");");
    f.close();

    const result = try checkImportConsistency(std.testing.allocator, tmp_path);
    try std.testing.expect(result.status == .warn);
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -20`
Expected: All verify tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/verify.zig
git commit -m "feat(verify): add project verification module (compile, integrity, imports)"
```

---

### Task 7: Wire `verify` Command into `main.zig` + MCP

**Files:**
- Modify: `src/main.zig`
- Modify: `src/mcp_server.zig`

- [ ] **Step 1: Add `verify` to Command enum in main.zig**

```zig
const Command = enum {
    new, module, event, api, orm, generate, scaffold, add,
    migration, health, config, @"test", plugin, life, upgrade,
    mcp, verify, help, version,
};
```

- [ ] **Step 2: Add verify dispatch in `runCommand`**

```zig
.verify => try cmdVerify(allocator, cmd_args),
```

- [ ] **Step 3: Add verify to `parseCommand`**

```zig
if (std.mem.eql(u8, cmd, "verify")) return .verify;
```

- [ ] **Step 4: Add `cmdVerify` function**

```zig
const verify_mod = @import("verify.zig");

fn cmdVerify(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const project_dir = if (args.len > 0) args[0] else ".";
    const report = try verify_mod.verifyProject(allocator, project_dir);
    defer {
        for (report.checks) |c| {
            if (c.details) |d| allocator.free(d);
        }
        allocator.free(report.checks);
        for (report.errors) |e| allocator.free(e);
        allocator.free(report.errors);
        for (report.warnings) |w| allocator.free(w);
        allocator.free(report.warnings);
        allocator.free(report.summary);
    }

    // Print JSON report to stdout
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try std.json.stringify(.{
        .pass = report.pass,
        .summary = report.summary,
    }, .{}, buf.writer());
    std.io.getStdOut().writer().print("{s}\n", .{buf.items}) catch {};
}
```

- [ ] **Step 5: Wire `callVerify` in mcp_server.zig**

Replace the stub `callVerify`:

```zig
fn callVerify(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (args == null) return try jsonError(allocator, "Missing arguments");
    const a = args.?.object;
    const project_dir = if (a.get("project_dir")) |v| v.string else ".";

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("zmodu");
    try argv.append("verify");
    try argv.append(project_dir);

    return runSubprocess(allocator, argv.items);
}
```

- [ ] **Step 6: Run tests + manual test**

```bash
cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -5
./zig-out/bin/zmodu verify shopdemo 2>&1
```
Expected: Tests pass, verify outputs JSON report for shopdemo.

- [ ] **Step 7: Commit**

```bash
git add src/main.zig src/mcp_server.zig
git commit -m "feat(verify): wire verify command into CLI and MCP"
```

---

## Phase 3: Incremental Generation

### Task 8: SQL Diff Engine (`src/sql_diff.zig`)

**Files:**
- Create: `src/sql_diff.zig`
- Test: embedded `test` blocks

- [ ] **Step 1: Write SQL diff engine with tests**

```zig
// src/sql_diff.zig
const std = @import("std");
const main_mod = @import("main.zig");

pub const ChangeType = enum { added, removed, modified };

pub const ColumnChangeType = enum { added, removed, type_changed };

pub const ColumnChange = struct {
    column_name: []const u8,
    change_type: ColumnChangeType,
    old_type: ?[]const u8 = null,
    new_type: ?[]const u8 = null,
};

pub const TableDiff = struct {
    table_name: []const u8,
    change_type: ChangeType,
    column_changes: []ColumnChange = &.{},
};

/// Compare two sets of TableDefs and produce a list of diffs.
/// Caller owns the returned slice.
pub fn diffTables(allocator: std.mem.Allocator, old_tables: []const main_mod.TableDef, new_tables: []const main_mod.TableDef) ![]TableDiff {
    var diffs = std.ArrayList(TableDiff).init(allocator);
    errdefer diffs.deinit();

    // Build lookup maps
    var old_map = std.StringHashMap(*const main_mod.TableDef).init(allocator);
    defer old_map.deinit();
    for (old_tables) |*t| {
        try old_map.put(t.name, t);
    }

    var new_map = std.StringHashMap(*const main_mod.TableDef).init(allocator);
    defer new_map.deinit();
    for (new_tables) |*t| {
        try new_map.put(t.name, t);
    }

    // Find added and modified tables
    for (new_tables) |*new_t| {
        if (old_map.get(new_t.name)) |old_t| {
            // Table exists in both — check for column changes
            const changes = try diffColumns(allocator, old_t.columns, new_t.columns);
            if (changes.len > 0) {
                try diffs.append(.{
                    .table_name = new_t.name,
                    .change_type = .modified,
                    .column_changes = changes,
                });
            }
        } else {
            // New table
            try diffs.append(.{
                .table_name = new_t.name,
                .change_type = .added,
            });
        }
    }

    // Find removed tables
    for (old_tables) |*old_t| {
        if (new_map.get(old_t.name) == null) {
            try diffs.append(.{
                .table_name = old_t.name,
                .change_type = .removed,
            });
        }
    }

    return diffs.toOwnedSlice();
}

fn diffColumns(allocator: std.mem.Allocator, old_cols: []const main_mod.ColumnDef, new_cols: []const main_mod.ColumnDef) ![]ColumnChange {
    var changes = std.ArrayList(ColumnChange).init(allocator);
    errdefer changes.deinit();

    var old_col_map = std.StringHashMap(*const main_mod.ColumnDef).init(allocator);
    defer old_col_map.deinit();
    for (old_cols) |*c| {
        try old_col_map.put(c.name, c);
    }

    var new_col_map = std.StringHashMap(*const main_mod.ColumnDef).init(allocator);
    defer new_col_map.deinit();
    for (new_cols) |*c| {
        try new_col_map.put(c.name, c);
    }

    // Added or type-changed columns
    for (new_cols) |*new_c| {
        if (old_col_map.get(new_c.name)) |old_c| {
            if (old_c.col_type != new_c.col_type) {
                try changes.append(.{
                    .column_name = new_c.name,
                    .change_type = .type_changed,
                    .old_type = @tagName(old_c.col_type),
                    .new_type = @tagName(new_c.col_type),
                });
            }
        } else {
            try changes.append(.{
                .column_name = new_c.name,
                .change_type = .added,
                .new_type = @tagName(new_c.col_type),
            });
        }
    }

    // Removed columns
    for (old_cols) |*old_c| {
        if (new_col_map.get(old_c.name) == null) {
            try changes.append(.{
                .column_name = old_c.name,
                .change_type = .removed,
                .old_type = @tagName(old_c.col_type),
            });
        }
    }

    return changes.toOwnedSlice();
}

/// Convenience: parse two SQL files and diff them.
pub fn diffSqlFiles(allocator: std.mem.Allocator, old_sql: []const u8, new_sql: []const u8) ![]TableDiff {
    const old_tables = try main_mod.parseSqlSchema(allocator, old_sql);
    defer allocator.free(old_tables);
    const new_tables = try main_mod.parseSqlSchema(allocator, new_sql);
    defer allocator.free(new_tables);
    return diffTables(allocator, old_tables, new_tables);
}

// ── Tests ──

test "diffTables detects added table" {
    const allocator = std.testing.allocator;
    const old_tables = [_]main_mod.TableDef{};
    const new_tables = [_]main_mod.TableDef{.{
        .name = "users",
        .columns = &[_]main_mod.ColumnDef{.{
            .name = "id",
            .col_type = .int,
            .nullable = false,
            .is_primary_key = true,
            .is_unique = false,
            .has_default = false,
            .comment = null,
        }},
        .foreign_keys = &.{},
    }};

    const diffs = try diffTables(allocator, &old_tables, &new_tables);
    defer allocator.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expect(diffs[0].change_type == .added);
    try std.testing.expectEqualStrings("users", diffs[0].table_name);
}

test "diffTables detects removed table" {
    const allocator = std.testing.allocator;
    const old_tables = [_]main_mod.TableDef{.{
        .name = "old_table",
        .columns = &.{},
        .foreign_keys = &.{},
    }};
    const new_tables = [_]main_mod.TableDef{};

    const diffs = try diffTables(allocator, &old_tables, &new_tables);
    defer allocator.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expect(diffs[0].change_type == .removed);
}

test "diffTables detects added column" {
    const allocator = std.testing.allocator;
    const old_tables = [_]main_mod.TableDef{.{
        .name = "users",
        .columns = &[_]main_mod.ColumnDef{.{
            .name = "id", .col_type = .int, .nullable = false,
            .is_primary_key = true, .is_unique = false, .has_default = false, .comment = null,
        }},
        .foreign_keys = &.{},
    }};
    const new_tables = [_]main_mod.TableDef{.{
        .name = "users",
        .columns = &[_]main_mod.ColumnDef{
            .{ .name = "id", .col_type = .int, .nullable = false,
               .is_primary_key = true, .is_unique = false, .has_default = false, .comment = null },
            .{ .name = "email", .col_type = .string, .nullable = true,
               .is_primary_key = false, .is_unique = false, .has_default = false, .comment = null },
        },
        .foreign_keys = &.{},
    }};

    const diffs = try diffTables(allocator, &old_tables, &new_tables);
    defer {
        for (diffs) |d| allocator.free(d.column_changes);
        allocator.free(diffs);
    }
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expect(diffs[0].change_type == .modified);
    try std.testing.expectEqual(@as(usize, 1), diffs[0].column_changes.len);
    try std.testing.expect(diffs[0].column_changes[0].change_type == .added);
    try std.testing.expectEqualStrings("email", diffs[0].column_changes[0].column_name);
}

test "diffTables detects type change" {
    const allocator = std.testing.allocator;
    const old_tables = [_]main_mod.TableDef{.{
        .name = "t",
        .columns = &[_]main_mod.ColumnDef{.{
            .name = "val", .col_type = .int, .nullable = false,
            .is_primary_key = false, .is_unique = false, .has_default = false, .comment = null,
        }},
        .foreign_keys = &.{},
    }};
    const new_tables = [_]main_mod.TableDef{.{
        .name = "t",
        .columns = &[_]main_mod.ColumnDef{.{
            .name = "val", .col_type = .string, .nullable = false,
            .is_primary_key = false, .is_unique = false, .has_default = false, .comment = null,
        }},
        .foreign_keys = &.{},
    }};

    const diffs = try diffTables(allocator, &old_tables, &new_tables);
    defer {
        for (diffs) |d| allocator.free(d.column_changes);
        allocator.free(diffs);
    }
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expect(diffs[0].column_changes[0].change_type == .type_changed);
}

test "diffTables no changes produces empty diff" {
    const allocator = std.testing.allocator;
    const cols = [_]main_mod.ColumnDef{.{
        .name = "id", .col_type = .int, .nullable = false,
        .is_primary_key = true, .is_unique = false, .has_default = false, .comment = null,
    }};
    const tables = [_]main_mod.TableDef{.{
        .name = "users",
        .columns = &cols,
        .foreign_keys = &.{},
    }};

    const diffs = try diffTables(allocator, &tables, &tables);
    defer allocator.free(diffs);
    try std.testing.expectEqual(@as(usize, 0), diffs.len);
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -20`
Expected: All diff tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/sql_diff.zig
git commit -m "feat(diff): add SQL table diff engine with column-level change detection"
```

---

### Task 9: Hash Tracking (`src/incremental.zig`)

**Files:**
- Create: `src/incremental.zig`
- Test: embedded `test` blocks

- [ ] **Step 1: Write incremental module with hash tracking**

```zig
// src/incremental.zig
const std = @import("std");

pub const HashEntry = struct {
    path: []const u8,
    hash: [64]u8, // hex-encoded SHA256
};

pub const HashManifest = struct {
    generated_at: []const u8,
    zmodu_version: []const u8,
    files: std.StringHashMap([64]u8),

    pub fn deinit(self: *HashManifest) void {
        self.files.deinit();
    }
};

const HASH_FILE_NAME = ".zmodu/generated_hashes.json";

/// Compute SHA256 hex digest of content.
pub fn sha256Hex(content: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{s}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;
    return hex;
}

/// Load the hash manifest from a project directory.
/// Returns null if the file doesn't exist.
pub fn loadManifest(allocator: std.mem.Allocator, project_dir: []const u8) ?HashManifest {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ project_dir, HASH_FILE_NAME }) catch return null;

    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();
    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(content);

    return parseManifest(allocator, content) catch null;
}

fn parseManifest(allocator: std.mem.Allocator, json_content: []const u8) !HashManifest {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const generated_at = root.get("generated_at").?.string;
    const zmodu_version = root.get("zmodu_version").?.string;
    const files_obj = root.get("files").?.object;

    var files = std.StringHashMap([64]u8).init(allocator);
    var it = files_obj.iterator();
    while (it.next()) |entry| {
        const hash_str = entry.value_ptr.*.string;
        if (hash_str.len == 64) {
            var hash: [64]u8 = undefined;
            @memcpy(&hash, hash_str[0..64]);
            try files.put(entry.key_ptr.*, hash);
        }
    }

    return HashManifest{
        .generated_at = try allocator.dupe(u8, generated_at),
        .zmodu_version = try allocator.dupe(u8, zmodu_version),
        .files = files,
    };
}

/// Save a hash manifest to the project's .zmodu/generated_hashes.json.
pub fn saveManifest(allocator: std.mem.Allocator, project_dir: []const u8, entries: []const HashEntry, version: []const u8) !void {
    // Ensure .zmodu/ dir exists
    var dotmodu_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dotmodu_path = try std.fmt.bufPrint(&dotmodu_buf, "{s}/.zmodu", .{project_dir});
    std.fs.makeDirAbsolute(dotmodu_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ project_dir, HASH_FILE_NAME });

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    const writer = buf.writer();

    try writer.print("{{\n  \"generated_at\": \"{s}\",\n  \"zmodu_version\": \"{s}\",\n  \"files\": {{\n", .{
        "2026-01-01T00:00:00Z", // placeholder — real impl gets current time
        version,
    });
    for (entries, 0..) |entry, i| {
        try writer.print("    \"{s}\": \"{s}\"", .{ entry.path, &entry.hash });
        if (i < entries.len - 1) try writer.writeByte(',');
        try writer.writeByte('\n');
    }
    try writer.writeAll("  }\n}\n");

    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(buf.items);
}

/// Check if a file has been modified since last generation.
/// Returns true if the file matches the manifest hash (not modified).
pub fn isUnchanged(project_dir: []const u8, relative_path: []const u8, manifest: *const HashManifest) bool {
    const stored_hash = manifest.files.get(relative_path) orelse return false;

    var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ project_dir, relative_path }) catch return false;

    const file = std.fs.openFileAbsolute(full_path, .{}) catch return false;
    defer file.close();
    const content = file.readToEndAlloc(std.heap.page_allocator, 10 * 1024 * 1024) catch return false;
    defer std.heap.page_allocator.free(content);

    const current_hash = sha256Hex(content);
    return std.mem.eql(u8, &stored_hash, &current_hash);
}

// ── Tests ──

test "sha256Hex produces consistent 64-char hex" {
    const hash = sha256Hex("hello");
    try std.testing.expectEqual(@as(usize, 64), hash.len);
    // Same input → same hash
    const hash2 = sha256Hex("hello");
    try std.testing.expectEqualStrings(&hash, &hash2);
    // Different input → different hash
    const hash3 = sha256Hex("world");
    try std.testing.expect(!std.mem.eql(u8, &hash, &hash3));
}

test "saveManifest and loadManifest roundtrip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const entries = [_]HashEntry{
        .{ .path = "src/modules/user/model.zig", .hash = sha256Hex("content1") },
        .{ .path = "src/modules/user/api.zig", .hash = sha256Hex("content2") },
    };

    try saveManifest(std.testing.allocator, tmp_path, &entries, "0.14.9");

    var manifest = loadManifest(std.testing.allocator, tmp_path) orelse {
        try std.testing.expect(false); // should not be null
        return;
    };
    defer manifest.deinit();

    try std.testing.expectEqualStrings("0.14.9", manifest.zmodu_version);
    try std.testing.expect(manifest.files.count() == 2);

    const h1 = manifest.files.get("src/modules/user/model.zig").?;
    try std.testing.expectEqualStrings(&entries[0].hash, &h1);
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -20`
Expected: All hash tracking tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/incremental.zig
git commit -m "feat(incremental): add SHA256 hash tracking for generated file manifest"
```

---

### Task 10: Wire `diff` Command + Incremental `scaffold --diff` into `main.zig` + MCP

**Files:**
- Modify: `src/main.zig`
- Modify: `src/mcp_server.zig`

- [ ] **Step 1: Add `diff` to Command enum in main.zig**

```zig
const Command = enum {
    new, module, event, api, orm, generate, scaffold, add,
    migration, health, config, @"test", plugin, life, upgrade,
    mcp, verify, diff, help, version,
};
```

- [ ] **Step 2: Add diff dispatch in `runCommand`**

```zig
.diff => try cmdDiff(allocator, cmd_args),
```

- [ ] **Step 3: Add diff to `parseCommand`**

```zig
if (std.mem.eql(u8, cmd, "diff")) return .diff;
```

- [ ] **Step 4: Add `cmdDiff` function**

```zig
const sql_diff = @import("sql_diff.zig");

fn cmdDiff(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.log.err("Usage: zmodu diff <old.sql> <new.sql>", .{});
        return error.CliUsage;
    }
    const old_path = args[0];
    const new_path = args[1];

    const old_sql = try std.fs.cwd().readFileAlloc(allocator, old_path, 10 * 1024 * 1024);
    defer allocator.free(old_sql);
    const new_sql = try std.fs.cwd().readFileAlloc(allocator, new_path, 10 * 1024 * 1024);
    defer allocator.free(new_sql);

    const old_tables = try parseSqlSchema(allocator, old_sql);
    defer allocator.free(old_tables);
    const new_tables = try parseSqlSchema(allocator, new_sql);
    defer allocator.free(new_tables);

    const diffs = try sql_diff.diffTables(allocator, old_tables, new_tables);
    defer {
        for (diffs) |d| allocator.free(d.column_changes);
        allocator.free(diffs);
    }

    // Output as JSON
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try std.json.stringify(.{ .changed_tables = diffs.len, .diffs = diffs }, .{}, buf.writer());
    std.io.getStdOut().writer().print("{s}\n", .{buf.items}) catch {};
}
```

- [ ] **Step 5: Add hash saving to `cmdScaffold`**

At the end of `cmdScaffold` (after all files are written), add hash manifest saving:

```zig
const incremental = @import("incremental.zig");

// At the end of cmdScaffold, after writing all module files:
// Save hash manifest for incremental generation
var hash_entries = std.ArrayList(incremental.HashEntry).init(allocator);
defer hash_entries.deinit();
// Walk all generated .zig files and compute hashes
// (fill in with actual generated file paths)
try incremental.saveManifest(allocator, project_dir, hash_entries.items, "0.14.9");
```

> **NOTE:** The exact integration point depends on how `cmdScaffold` tracks generated files. The simplest approach: after `writeModuleFiles` writes each file, also record its path+hash. This requires modifying `writeModuleFiles` to return the list of written files, or walking the output directory after generation.

- [ ] **Step 6: Wire `callDiff` in mcp_server.zig**

Replace the stub `callDiff`:

```zig
fn callDiff(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (args == null) return try jsonError(allocator, "Missing arguments");
    const a = args.?.object;
    const old_sql = a.get("old_sql") orelse return try jsonError(allocator, "Missing old_sql");
    const new_sql = a.get("new_sql") orelse return try jsonError(allocator, "Missing new_sql");

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("zmodu");
    try argv.append("diff");
    try argv.append(old_sql.string);
    try argv.append(new_sql.string);

    return runSubprocess(allocator, argv.items);
}
```

- [ ] **Step 7: Run tests + manual test**

```bash
cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1 | tail -5
./zig-out/bin/zmodu diff src/shopdemo/init.sql src/shopdemo/init.sql 2>&1
```
Expected: Tests pass, self-diff shows 0 changes.

- [ ] **Step 8: Commit**

```bash
git add src/main.zig src/mcp_server.zig
git commit -m "feat(diff): wire diff command into CLI and MCP, add hash saving to scaffold"
```

---

## Phase 4: Documentation Cleanup

### Task 11: Update Documentation

**Files:**
- Modify: `docs/ZMODU-FIRST-PRINCIPLE.md`
- Modify: `shopdemo/AGENTS.md`
- Modify: `docs/AI-DEVELOP-PROMPT.md`
- Modify: `docs/AI-MIGRATION-PROMPT.md`

- [ ] **Step 1: Update ZMODU-FIRST-PRINCIPLE.md**

Read the file, then:
1. Replace all references to `ext/` files and `service_ext.zig` / `api_ext.zig` with "AI directly modifies generated files"
2. Add a new section: "## MCP Integration" explaining how AI agents call zmodu via MCP
3. Update the "File Boundary" section to reflect the current model
4. Add `zmodu mcp`, `zmodu verify`, `zmodu diff` to the command reference

- [ ] **Step 2: Update shopdemo/AGENTS.md**

1. Remove `service_ext.zig` and `api_ext.zig` from "Safe to edit" list
2. Add MCP workflow section: how to configure and use zmodu as an MCP server
3. Add `zmodu verify` to the development workflow

- [ ] **Step 3: Update docs/AI-DEVELOP-PROMPT.md**

1. Add MCP-based workflow alternative (before the existing CLI-based workflow)
2. Add `zmodu verify` step after scaffold
3. Add `zmodu diff` for incremental updates

- [ ] **Step 4: Update docs/AI-MIGRATION-PROMPT.md**

1. Add MCP call examples for each migration phase

- [ ] **Step 5: Commit**

```bash
git add docs/ZMODU-FIRST-PRINCIPLE.md shopdemo/AGENTS.md docs/AI-DEVELOP-PROMPT.md docs/AI-MIGRATION-PROMPT.md
git commit -m "docs: update file boundary model, add MCP workflow documentation"
```

---

## Final Verification

### Task 12: End-to-End Verification

- [ ] **Step 1: Run all tests**

```bash
cd /Users/n0x/w4_proj/zig_ws/zmodu && zig build test 2>&1
```
Expected: All tests pass (existing 22 + new mcp_types + mcp_server + verify + sql_diff + incremental tests).

- [ ] **Step 2: Build release binary**

```bash
zig build -Doptimize=ReleaseSafe
```
Expected: Builds without errors.

- [ ] **Step 3: MCP end-to-end test**

```bash
# Test the full MCP workflow
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./zig-out/bin/zmodu mcp
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./zig-out/bin/zmodu mcp
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"zmodu_version","arguments":{}}}' | ./zig-out/bin/zmodu mcp
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"zmodu_verify","arguments":{"project_dir":"shopdemo"}}}' | ./zig-out/bin/zmodu mcp
```

- [ ] **Step 4: Verify end-to-end scaffold via MCP**

```bash
mkdir -p /tmp/zmodu-e2e
echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"zmodu_scaffold","arguments":{"sql_path":"src/shopdemo/init.sql","output_dir":"/tmp/zmodu-e2e"}}}' | ./zig-out/bin/zmodu mcp
echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"zmodu_verify","arguments":{"project_dir":"/tmp/zmodu-e2e"}}}' | ./zig-out/bin/zmodu mcp
```

- [ ] **Step 5: Diff self-test**

```bash
./zig-out/bin/zmodu diff src/shopdemo/init.sql src/shopdemo/init.sql
```
Expected: 0 changes.

- [ ] **Step 6: Cleanup**

```bash
rm -rf /tmp/zmodu-e2e /tmp/zmodu-mcp-test
```
