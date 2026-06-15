// MCP Server — JSON-RPC 2.0 over stdio for Model Context Protocol
const std = @import("std");
const mcp_types = @import("mcp_types.zig");
const builtin = @import("builtin");

/// Start the MCP server loop on stdin/stdout.
/// Blocks until stdin is closed.
pub fn start(allocator: std.mem.Allocator) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var buf: [65536]u8 = undefined;

    while (true) {
        const line = stdin.readUntilDelimiter(&buf, '\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (line.len == 0) continue;

        const response = handleMessage(allocator, line) catch |err| {
            const resp = try mcp_types.errorResponse(allocator, null, -32603, @errorName(err));
            defer allocator.free(resp);
            try stdout.print("{s}\n", .{resp});
            continue;
        };
        defer allocator.free(response);
        if (response.len == 0) continue; // notification — no response
        try stdout.print("{s}\n", .{response});
    }
}

/// Parse a JSON-RPC request line and dispatch to the appropriate handler.
fn handleMessage(allocator: std.mem.Allocator, line: []const u8) ![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch {
        return mcp_types.errorResponse(allocator, null, -32700, "Parse error");
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const method = root.get("method") orelse return mcp_types.errorResponse(allocator, null, -32600, "Missing method");
    const method_str = method.string;
    const id_val = root.get("id");
    const id: ?i64 = if (id_val) |v| switch (v) {
        .integer => |i| i,
        else => null,
    } else null;

    if (std.mem.eql(u8, method_str, "initialize")) {
        return handleInitialize(allocator, id);
    } else if (std.mem.eql(u8, method_str, "tools/list")) {
        return handleToolsList(allocator, id);
    } else if (std.mem.eql(u8, method_str, "tools/call")) {
        const params = root.get("params");
        return handleToolsCall(allocator, id, params);
    } else if (std.mem.eql(u8, method_str, "notifications/initialized")) {
        if (id == null) return allocator.dupe(u8, "");
        return mcp_types.errorResponse(allocator, id, -32601, "Method not found");
    } else {
        return mcp_types.errorResponse(allocator, id, -32601, "Method not found");
    }
}

fn handleInitialize(allocator: std.mem.Allocator, id: ?i64) ![]const u8 {
    // Build capabilities response using ObjectMap
    var result = std.json.ObjectMap{};
    try result.put("protocolVersion", .{ .string = "2024-11-05" });
    var caps = std.json.ObjectMap{};
    try caps.put("tools", .{ .object = std.json.ObjectMap{} });
    try result.put("capabilities", .{ .object = caps });
    var server_info = std.json.ObjectMap{};
    try server_info.put("name", .{ .string = "zmodu" });
    try server_info.put("version", .{ .string = "0.14.9" });
    try result.put("serverInfo", .{ .object = server_info });

    return try buildResponse(allocator, id, .{ .object = result });
}

fn handleToolsList(allocator: std.mem.Allocator, id: ?i64) ![]const u8 {
    var tools = std.json.Array{};

    try tools.append(try makeToolSchema(allocator, "zmodu_scaffold", "Generate a full ZigModu project from SQL DDL", &.{
        .{ .name = "sql_path", .type = "string", .desc = "Path to SQL file" },
        .{ .name = "output_dir", .type = "string", .desc = "Output directory" },
        .{ .name = "orm_backend", .type = "string", .desc = "ORM backend: sqlx (default) or zent", .opt = true },
    }));
    try tools.append(try makeToolSchema(allocator, "zmodu_module", "Generate a single module skeleton", &.{
        .{ .name = "name", .type = "string", .desc = "Module name (snake_case)" },
        .{ .name = "output_dir", .type = "string", .desc = "Project root directory", .opt = true },
    }));
    try tools.append(try makeToolSchema(allocator, "zmodu_version", "Get zmodu version info", &.{}));
    try tools.append(try makeToolSchema(allocator, "zmodu_verify", "Verify a generated project compiles and has correct structure", &.{
        .{ .name = "project_dir", .type = "string", .desc = "Path to the project directory" },
    }));
    try tools.append(try makeToolSchema(allocator, "zmodu_diff", "Compare two SQL files and show table-level changes", &.{
        .{ .name = "old_sql", .type = "string", .desc = "Path to the old SQL file" },
        .{ .name = "new_sql", .type = "string", .desc = "Path to the new SQL file" },
    }));

    var result = std.json.ObjectMap{};
    try result.put("tools", .{ .array = tools });
    return try buildResponse(allocator, id, .{ .object = result });
}

fn handleToolsCall(allocator: std.mem.Allocator, id: ?i64, params: ?std.json.Value) ![]const u8 {
    if (params == null) return mcp_types.errorResponse(allocator, id, -32602, "Missing params");
    const p = params.?.object;
    const tool_name_val = p.get("name") orelse return mcp_types.errorResponse(allocator, id, -32602, "Missing tool name");
    const tool_name = tool_name_val.string;

    const result_text = if (std.mem.eql(u8, tool_name, "zmodu_version"))
        try callVersion(allocator)
    else if (std.mem.eql(u8, tool_name, "zmodu_scaffold"))
        try callStub(allocator, "scaffold not yet wired")
    else if (std.mem.eql(u8, tool_name, "zmodu_module"))
        try callStub(allocator, "module not yet wired")
    else if (std.mem.eql(u8, tool_name, "zmodu_verify"))
        try callStub(allocator, "verify not yet wired")
    else if (std.mem.eql(u8, tool_name, "zmodu_diff"))
        try callStub(allocator, "diff not yet wired")
    else
        return mcp_types.errorResponse(allocator, id, -32602, "Unknown tool");

    // Build MCP tool result: {content: [{type: "text", text: "..."}], isError: false}
    var content_item = std.json.ObjectMap{};
    try content_item.put("type", .{ .string = "text" });
    try content_item.put("text", .{ .string = result_text });

    var content_arr = std.json.Array{};
    try content_arr.append(.{ .object = content_item });

    var result = std.json.ObjectMap{};
    try result.put("content", .{ .array = content_arr });
    try result.put("isError", .{ .bool = false });

    return try buildResponse(allocator, id, .{ .object = result });
}

// ── Tool implementations ──

fn callVersion(allocator: std.mem.Allocator) ![]const u8 {
    var obj = std.json.ObjectMap{};
    try obj.put("version", .{ .string = "0.14.9" });
    try obj.put("zig_version", .{ .string = "0.17.0" });
    return try std.json.Stringify.valueAlloc(allocator, .{ .object = obj }, .{});
}

fn callStub(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    var obj = std.json.ObjectMap{};
    try obj.put("error", .{ .string = message });
    return try std.json.Stringify.valueAlloc(allocator, .{ .object = obj }, .{});
}

// ── Helpers ──

fn buildResponse(allocator: std.mem.Allocator, id: ?i64, result: std.json.Value) ![]const u8 {
    var resp = std.json.ObjectMap{};
    try resp.put("jsonrpc", .{ .string = "2.0" });
    if (id) |i| {
        try resp.put("id", .{ .integer = i });
    } else {
        try resp.put("id", .null);
    }
    try resp.put("result", result);
    return try std.json.Stringify.valueAlloc(allocator, .{ .object = resp }, .{});
}

const ParamDef = struct {
    name: []const u8,
    type: []const u8,
    desc: []const u8,
    opt: bool = false,
};

fn makeToolSchema(allocator: std.mem.Allocator, name: []const u8, description: []const u8, params: []const ParamDef) !std.json.Value {
    _ = allocator;
    var properties = std.json.ObjectMap{};
    var required_arr = std.json.Array{};

    for (params) |p| {
        var prop = std.json.ObjectMap{};
        try prop.put("type", .{ .string = p.type });
        try prop.put("description", .{ .string = p.desc });
        try properties.put(p.name, .{ .object = prop });
        if (!p.opt) {
            try required_arr.append(.{ .string = p.name });
        }
    }

    var schema = std.json.ObjectMap{};
    try schema.put("type", .{ .string = "object" });
    try schema.put("properties", .{ .object = properties });
    if (required_arr.items.len > 0) {
        try schema.put("required", .{ .array = required_arr });
    }

    var tool = std.json.ObjectMap{};
    try tool.put("name", .{ .string = name });
    try tool.put("description", .{ .string = description });
    try tool.put("inputSchema", .{ .object = schema });
    return .{ .object = tool };
}

// ── Tests ──

test "handleMessage returns error for invalid JSON" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "not json");
    defer allocator.free(resp);
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
    try std.testing.expect(std.mem.indexOf(u8, resp, "zmodu_verify") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "zmodu_diff") != null);
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

test "handleMessage handles notification (no id)" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
    defer allocator.free(resp);
    try std.testing.expectEqual(@as(usize, 0), resp.len);
}

test "handleMessage returns error for tools/call with unknown tool" {
    const allocator = std.testing.allocator;
    const resp = try handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"unknown_tool\",\"arguments\":{}}}");
    defer allocator.free(resp);
    try std.testing.expect(std.mem.indexOf(u8, resp, "Unknown tool") != null);
}
