// Incremental Generation — SHA256 hash tracking for generated file manifest
const std = @import("std");
const Io = std.Io;

pub const HASH_FILE_NAME = ".zmodu/generated_hashes.json";

pub const HashEntry = struct {
    path: []const u8,
    hash: [64]u8,
};

/// Compute SHA256 hex digest of content.
pub fn sha256Hex(content: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});
    var hex: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex[i * 2] = hex_chars[byte >> 4];
        hex[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return hex;
}

/// Check if a file matches its stored hash in the manifest.
/// Returns true if unchanged (hash matches), false if modified or not in manifest.
pub fn isUnchanged(io: Io, project_dir: []const u8, relative_path: []const u8, manifest_files: *const std.StringHashMap([64]u8)) bool {
    const stored_hash = manifest_files.get(relative_path) orelse return false;

    var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ project_dir, relative_path }) catch return false;

    const content = Io.Dir.cwd().readFileAlloc(io, full_path, std.heap.page_allocator, Io.Limit.limited(10 * 1024 * 1024)) catch return false;
    defer std.heap.page_allocator.free(content);

    const current_hash = sha256Hex(content);
    return std.mem.eql(u8, &stored_hash, &current_hash);
}

/// Save a hash manifest to the project's .zmodu/generated_hashes.json.
pub fn saveManifest(allocator: std.mem.Allocator, io: Io, project_dir: []const u8, entries: []const HashEntry, version: []const u8) !void {
    // Ensure .zmodu/ dir exists
    var dotmodu_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dotmodu_path = try std.fmt.bufPrint(&dotmodu_buf, "{s}/.zmodu", .{project_dir});
    Io.Dir.cwd().createDirPath(io, dotmodu_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ project_dir, HASH_FILE_NAME });
    defer allocator.free(path);

    // Build JSON manually
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\n  \"generated_at\": \"2026-01-01T00:00:00Z\",\n  \"zmodu_version\": \"");
    try buf.appendSlice(allocator, version);
    try buf.appendSlice(allocator, "\",\n  \"files\": {\n");
    for (entries, 0..) |entry, i| {
        try buf.appendSlice(allocator, "    \"");
        try buf.appendSlice(allocator, entry.path);
        try buf.appendSlice(allocator, "\": \"");
        try buf.appendSlice(allocator, &entry.hash);
        try buf.appendSlice(allocator, "\"");
        if (i < entries.len - 1) try buf.appendSlice(allocator, ",");
        try buf.appendSlice(allocator, "\n");
    }
    try buf.appendSlice(allocator, "  }\n}\n");

    const file = try Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, buf.items);
}

// ── Tests ──

test "sha256Hex produces consistent 64-char hex" {
    const hash = sha256Hex("hello");
    try std.testing.expectEqual(@as(usize, 64), hash.len);
    const hash2 = sha256Hex("hello");
    try std.testing.expectEqualStrings(&hash, &hash2);
    const hash3 = sha256Hex("world");
    try std.testing.expect(!std.mem.eql(u8, &hash, &hash3));
}

test "sha256Hex different inputs produce different hashes" {
    const a = sha256Hex("aaa");
    const b = sha256Hex("bbb");
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
}
