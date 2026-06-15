// Incremental Generation — SHA256 hash tracking for generated file manifest
const std = @import("std");
const Io = std.Io;

pub const HASH_FILE_NAME = ".zmodu/generated_hashes.json";

/// Compute SHA256 hex digest of content.
pub fn sha256Hex(content: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;
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
