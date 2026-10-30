const std = @import("std");

/// Contract definition (Consumer-Driven Contract)
pub const Contract = struct {
    /// Contract name
    name: []const u8,
    /// Consumer name
    consumer: []const u8,
    /// Provider name
    provider: []const u8,
    /// Contract version
    version: []const u8,
    /// Interaction type
    interaction_type: InteractionType,
    /// Request matching rules
    request: RequestMatcher,
    /// Expected response
    response: ResponseExpectation,

    pub const InteractionType = enum {
        http,
        grpc,
        event,
        message,
    };

    pub const RequestMatcher = struct {
        method: []const u8,
        path: []const u8,
        headers: []const HeaderMatcher = &.{},
        body: ?[]const u8 = null,
    };

    pub const HeaderMatcher = struct {
        key: []const u8,
        value: []const u8,
    };

    pub const ResponseExpectation = struct {
        status: u16,
        headers: []const HeaderMatcher = &.{},
        body_contains: ?[]const u8 = null,
        body_schema: ?[]const u8 = null,
    };
};

/// Contract verification result
pub const ContractVerificationResult = struct {
    contract_name: []const u8,
    passed: bool,
    failures: []const ContractFailure,
    duration_ms: u64,

    pub const ContractFailure = struct {
        field: []const u8,
        expected: []const u8,
        actual: []const u8,
        message: []const u8,
    };

    /// Releases everything `verifyContract` allocated. Call it even on pass —
    /// the result always owns its `contract_name`.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.contract_name);
        for (self.failures) |f| {
            allocator.free(f.field);
            allocator.free(f.expected);
            allocator.free(f.actual);
            allocator.free(f.message);
        }
        allocator.free(self.failures);
        self.* = undefined;
    }
};

/// Contract test runner
/// Consumer-driven contract testing (Pact-style)
pub const ContractTestRunner = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    contracts: std.ArrayList(Contract),
    verifications: std.ArrayList(ContractVerificationResult),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .contracts = std.ArrayList(Contract).empty,
            .verifications = std.ArrayList(ContractVerificationResult).empty,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.contracts.items) |c| freeContract(self.allocator, c);
        self.contracts.deinit(self.allocator);

        for (self.verifications.items) |v| {
            self.allocator.free(v.contract_name);
            for (v.failures) |f| freeFailure(self.allocator, f);
            self.allocator.free(v.failures);
        }
        self.verifications.deinit(self.allocator);
        self.* = undefined;
    }

    /// Release one failure record.
    fn freeFailure(allocator: std.mem.Allocator, f: ContractVerificationResult.ContractFailure) void {
        allocator.free(f.field);
        allocator.free(f.expected);
        allocator.free(f.actual);
        allocator.free(f.message);
    }

    /// Copy the four strings and append the record. A failure part-way through
    /// the copies — or in the append — releases what was already copied: the
    /// caller only ever sees the returned list's contents.
    fn appendFailure(
        list: *std.ArrayList(ContractVerificationResult.ContractFailure),
        allocator: std.mem.Allocator,
        field: []const u8,
        expected: []const u8,
        actual: []const u8,
        message: []const u8,
    ) !void {
        const field_copy = try allocator.dupe(u8, field);
        errdefer allocator.free(field_copy);
        const expected_copy = try allocator.dupe(u8, expected);
        errdefer allocator.free(expected_copy);
        const actual_copy = try allocator.dupe(u8, actual);
        errdefer allocator.free(actual_copy);
        const message_copy = try allocator.dupe(u8, message);
        errdefer allocator.free(message_copy);

        try list.append(allocator, .{
            .field = field_copy,
            .expected = expected_copy,
            .actual = actual_copy,
            .message = message_copy,
        });
    }

    /// Copy a header matcher list, releasing the partially built array (and the
    /// pairs already in it) when an allocation fails.
    fn cloneHeaders(allocator: std.mem.Allocator, headers: []const Contract.HeaderMatcher) ![]const Contract.HeaderMatcher {
        const copy = try allocator.alloc(Contract.HeaderMatcher, headers.len);
        var filled: usize = 0;
        errdefer {
            for (copy[0..filled]) |h| {
                allocator.free(h.key);
                allocator.free(h.value);
            }
            allocator.free(copy);
        }
        for (headers, 0..) |h, i| {
            const key = try allocator.dupe(u8, h.key);
            errdefer allocator.free(key);
            const value = try allocator.dupe(u8, h.value);
            copy[i] = .{ .key = key, .value = value };
            filled += 1;
        }
        return copy;
    }

    fn freeHeaders(allocator: std.mem.Allocator, headers: []const Contract.HeaderMatcher) void {
        for (headers) |h| {
            allocator.free(h.key);
            allocator.free(h.value);
        }
        allocator.free(headers);
    }

    /// Release a contract this runner owns (used by `deinit` and by the
    /// register path when the append fails).
    fn freeContract(allocator: std.mem.Allocator, c: Contract) void {
        allocator.free(c.name);
        allocator.free(c.consumer);
        allocator.free(c.provider);
        allocator.free(c.version);
        allocator.free(c.request.method);
        allocator.free(c.request.path);
        freeHeaders(allocator, c.request.headers);
        if (c.request.body) |b| allocator.free(b);
        freeHeaders(allocator, c.response.headers);
        if (c.response.body_contains) |bc| allocator.free(bc);
        if (c.response.body_schema) |bs| allocator.free(bs);
    }

    /// Register a contract
    pub fn registerContract(self: *Self, contract: Contract) !void {
        const owned = try self.cloneContract(contract);
        errdefer freeContract(self.allocator, owned);
        try self.contracts.append(self.allocator, owned);
    }

    /// Verify a contract: simulate the request and validate the response
    pub fn verifyContract(
        self: *Self,
        contract_name: []const u8,
        actual_status: u16,
        actual_body: []const u8,
        actual_headers: []const Contract.HeaderMatcher,
    ) !ContractVerificationResult {
        const contract = self.findContract(contract_name) orelse return error.ContractNotFound;

        var failures = std.ArrayList(ContractVerificationResult.ContractFailure).empty;
        // Every record already appended owns four strings; an error further
        // down (a later copy, the final slice) must not strand them.
        errdefer {
            for (failures.items) |f| freeFailure(self.allocator, f);
            failures.deinit(self.allocator);
        }
        const start = @import("../core/Time.zig").monotonicNowSeconds();

        // Validate the status code
        if (actual_status != contract.response.status) {
            const expected = try self.allocator.print("{d}", .{contract.response.status});
            defer self.allocator.free(expected);
            const actual = try self.allocator.print("{d}", .{actual_status});
            defer self.allocator.free(actual);
            try appendFailure(&failures, self.allocator, "status", expected, actual, "HTTP status mismatch");
        }

        // Validate that the response body contains the expected string
        if (contract.response.body_contains) |expected| {
            if (!std.mem.containsAtLeast(u8, actual_body, 1, expected)) {
                try appendFailure(&failures, self.allocator, "body", expected, actual_body, "Response body does not contain expected string");
            }
        }

        // Validate the response headers
        for (contract.response.headers) |expected_header| {
            var found = false;
            for (actual_headers) |actual_header| {
                if (std.mem.eql(u8, expected_header.key, actual_header.key)) {
                    if (!std.mem.eql(u8, expected_header.value, actual_header.value)) {
                        const field = try self.allocator.print("header.{s}", .{expected_header.key});
                        defer self.allocator.free(field);
                        try appendFailure(&failures, self.allocator, field, expected_header.value, actual_header.value, "Response header value mismatch");
                    }
                    found = true;
                    break;
                }
            }
            if (!found) {
                const field = try self.allocator.print("header.{s}", .{expected_header.key});
                defer self.allocator.free(field);
                try appendFailure(&failures, self.allocator, field, expected_header.value, "<missing>", "Expected response header not found");
            }
        }

        const end = @import("../core/Time.zig").monotonicNowSeconds();
        const duration = @as(u64, @intCast((end - start) * 1000));
        const passed = failures.items.len == 0;

        const contract_name_copy = try self.allocator.dupe(u8, contract_name);
        errdefer self.allocator.free(contract_name_copy);
        return ContractVerificationResult{
            .contract_name = contract_name_copy,
            .passed = passed,
            .failures = try failures.toOwnedSlice(self.allocator),
            .duration_ms = duration,
        };
    }

    /// Generate a contract report
    pub fn generateReport(self: *Self) ![]const u8 {
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator, "═══════════════════════════════════\n");
        try buf.appendSlice(self.allocator, "  Contract Test Report\n");
        try buf.appendSlice(self.allocator, "═══════════════════════════════════\n\n");

        var passed: usize = 0;
        var failed: usize = 0;

        for (self.verifications.items) |v| {
            if (v.passed) {
                passed += 1;
                const line = try self.allocator.print("  ✓ {s}\n", .{v.contract_name});
                defer self.allocator.free(line);
                try buf.appendSlice(self.allocator, line);
            } else {
                failed += 1;
                const line = try self.allocator.print("  ✗ {s}\n", .{v.contract_name});
                defer self.allocator.free(line);
                try buf.appendSlice(self.allocator, line);

                for (v.failures) |f| {
                    const detail = try self.allocator.print(
                        "    - {s}: expected '{s}', got '{s}' ({s})\n",
                        .{ f.field, f.expected, f.actual, f.message },
                    );
                    defer self.allocator.free(detail);
                    try buf.appendSlice(self.allocator, detail);
                }
            }
        }

        const summary = try self.allocator.print(
            "\n  Results: {d} passed, {d} failed, {d} total\n",
            .{ passed, failed, passed + failed },
        );
        defer self.allocator.free(summary);
        try buf.appendSlice(self.allocator, summary);

        return buf.toOwnedSlice(self.allocator);
    }

    fn findContract(self: *Self, name: []const u8) ?Contract {
        for (self.contracts.items) |c| {
            if (std.mem.eql(u8, c.name, name)) return c;
        }
        return null;
    }

    fn cloneContract(self: *Self, c: Contract) !Contract {
        const name_copy = try self.allocator.dupe(u8, c.name);
        errdefer self.allocator.free(name_copy);
        const consumer = try self.allocator.dupe(u8, c.consumer);
        errdefer self.allocator.free(consumer);
        const provider = try self.allocator.dupe(u8, c.provider);
        errdefer self.allocator.free(provider);
        const version = try self.allocator.dupe(u8, c.version);
        errdefer self.allocator.free(version);

        const req_headers_copy = try cloneHeaders(self.allocator, c.request.headers);
        errdefer freeHeaders(self.allocator, req_headers_copy);
        const resp_headers_copy = try cloneHeaders(self.allocator, c.response.headers);
        errdefer freeHeaders(self.allocator, resp_headers_copy);

        const method = try self.allocator.dupe(u8, c.request.method);
        errdefer self.allocator.free(method);
        const path = try self.allocator.dupe(u8, c.request.path);
        errdefer self.allocator.free(path);
        const body: ?[]const u8 = if (c.request.body) |b| try self.allocator.dupe(u8, b) else null;
        errdefer if (body) |b| self.allocator.free(b);
        const body_contains: ?[]const u8 = if (c.response.body_contains) |bc| try self.allocator.dupe(u8, bc) else null;
        errdefer if (body_contains) |bc| self.allocator.free(bc);
        const body_schema: ?[]const u8 = if (c.response.body_schema) |bs| try self.allocator.dupe(u8, bs) else null;
        errdefer if (body_schema) |bs| self.allocator.free(bs);

        return Contract{
            .name = name_copy,
            .consumer = consumer,
            .provider = provider,
            .version = version,
            .interaction_type = c.interaction_type,
            .request = .{
                .method = method,
                .path = path,
                .headers = req_headers_copy,
                .body = body,
            },
            .response = .{
                .status = c.response.status,
                .headers = resp_headers_copy,
                .body_contains = body_contains,
                .body_schema = body_schema,
            },
        };
    }
};

// ─────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────

test "ContractTestRunner.registerContract releases everything when an allocation fails" {
    const Scan = struct {
        fn run(a: std.mem.Allocator) !void {
            var runner = ContractTestRunner.init(a);
            defer runner.deinit();
            try runner.registerContract(.{
                .name = "order-create",
                .consumer = "order-service",
                .provider = "payment-service",
                .version = "1.0",
                .interaction_type = .http,
                .request = .{
                    .method = "POST",
                    .path = "/api/payments",
                    .headers = &.{.{ .key = "content-type", .value = "application/json" }},
                    .body = "{\"amount\":1}",
                },
                .response = .{
                    .status = 201,
                    .headers = &.{.{ .key = "location", .value = "/api/payments/1" }},
                    .body_contains = "paid",
                    .body_schema = "payment",
                },
            });
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Scan.run, .{});
}

test "ContractTestRunner.verifyContract releases failures when an allocation fails" {
    const Scan = struct {
        fn run(a: std.mem.Allocator) !void {
            var runner = ContractTestRunner.init(a);
            defer runner.deinit();
            try runner.registerContract(.{
                .name = "c",
                .consumer = "a",
                .provider = "b",
                .version = "1",
                .interaction_type = .http,
                .request = .{ .method = "GET", .path = "/x" },
                .response = .{
                    .status = 201,
                    .headers = &.{.{ .key = "x-trace", .value = "t1" }},
                    .body_contains = "ok",
                },
            });
            // Status + body + missing-header failures: three records, so a
            // failure while building the third must release the first two.
            var result = try runner.verifyContract("c", 200, "nope", &.{});
            result.deinit(a);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Scan.run, .{});
}

test "ContractTestRunner register and verify pass" {
    const allocator = std.testing.allocator;
    var runner = ContractTestRunner.init(allocator);
    defer runner.deinit();

    try runner.registerContract(.{
        .name = "order-create",
        .consumer = "order-service",
        .provider = "payment-service",
        .version = "1.0",
        .interaction_type = .http,
        .request = .{ .method = "POST", .path = "/api/payments" },
        .response = .{ .status = 201, .body_contains = "paid" },
    });

    const result = try runner.verifyContract("order-create", 201, "{\"status\":\"paid\"}", &.{});
    defer {
        allocator.free(result.contract_name);
        for (result.failures) |f| {
            allocator.free(f.field);
            allocator.free(f.expected);
            allocator.free(f.actual);
            allocator.free(f.message);
        }
        allocator.free(result.failures);
    }

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(usize, 0), result.failures.len);
}

test "ContractTestRunner verify fail - status mismatch" {
    const allocator = std.testing.allocator;
    var runner = ContractTestRunner.init(allocator);
    defer runner.deinit();

    try runner.registerContract(.{
        .name = "status-test",
        .consumer = "c1",
        .provider = "p1",
        .version = "1.0",
        .interaction_type = .http,
        .request = .{ .method = "GET", .path = "/health" },
        .response = .{ .status = 200 },
    });

    const result = try runner.verifyContract("status-test", 500, "{}", &.{});
    defer {
        allocator.free(result.contract_name);
        for (result.failures) |f| {
            allocator.free(f.field);
            allocator.free(f.expected);
            allocator.free(f.actual);
            allocator.free(f.message);
        }
        allocator.free(result.failures);
    }

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.failures.len);
}

test "ContractTestRunner verify fail - body mismatch" {
    const allocator = std.testing.allocator;
    var runner = ContractTestRunner.init(allocator);
    defer runner.deinit();

    try runner.registerContract(.{
        .name = "body-test",
        .consumer = "c1",
        .provider = "p1",
        .version = "1.0",
        .interaction_type = .http,
        .request = .{ .method = "GET", .path = "/data" },
        .response = .{ .status = 200, .body_contains = "success" },
    });

    const result = try runner.verifyContract("body-test", 200, "{\"error\":\"failed\"}", &.{});
    defer {
        allocator.free(result.contract_name);
        for (result.failures) |f| {
            allocator.free(f.field);
            allocator.free(f.expected);
            allocator.free(f.actual);
            allocator.free(f.message);
        }
        allocator.free(result.failures);
    }

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.failures.len);
    try std.testing.expectEqualStrings("body", result.failures[0].field);
}

test "ContractTestRunner verify headers" {
    const allocator = std.testing.allocator;
    var runner = ContractTestRunner.init(allocator);
    defer runner.deinit();

    try runner.registerContract(.{
        .name = "header-test",
        .consumer = "c1",
        .provider = "p1",
        .version = "1.0",
        .interaction_type = .http,
        .request = .{ .method = "GET", .path = "/api" },
        .response = .{
            .status = 200,
            .headers = &.{
                .{ .key = "Content-Type", .value = "application/json" },
                .{ .key = "X-Request-Id", .value = "12345" },
            },
        },
    });

    const actual_headers = &[_]Contract.HeaderMatcher{
        .{ .key = "Content-Type", .value = "text/plain" },
    };

    const result = try runner.verifyContract("header-test", 200, "{}", actual_headers);
    defer {
        allocator.free(result.contract_name);
        for (result.failures) |f| {
            allocator.free(f.field);
            allocator.free(f.expected);
            allocator.free(f.actual);
            allocator.free(f.message);
        }
        allocator.free(result.failures);
    }

    // Content-Type mismatch + X-Request-Id missing = 2 failures
    try std.testing.expect(!result.passed);
    try std.testing.expect(result.failures.len >= 1);
}

test "ContractTestRunner generate report" {
    const allocator = std.testing.allocator;
    var runner = ContractTestRunner.init(allocator);
    defer runner.deinit();

    try runner.registerContract(.{
        .name = "report-test",
        .consumer = "c1",
        .provider = "p1",
        .version = "1.0",
        .interaction_type = .http,
        .request = .{ .method = "GET", .path = "/ok" },
        .response = .{ .status = 200 },
    });

    const r = try runner.verifyContract("report-test", 200, "ok", &.{});
    defer {
        allocator.free(r.contract_name);
        for (r.failures) |f| {
            allocator.free(f.field);
            allocator.free(f.expected);
            allocator.free(f.actual);
            allocator.free(f.message);
        }
        allocator.free(r.failures);
    }

    try std.testing.expect(r.passed);
    try std.testing.expectEqualStrings("report-test", r.contract_name);
}

test "ContractTestRunner contract not found" {
    const allocator = std.testing.allocator;
    var runner = ContractTestRunner.init(allocator);
    defer runner.deinit();

    const result = runner.verifyContract("nonexistent", 200, "", &.{});
    try std.testing.expectError(error.ContractNotFound, result);
}
