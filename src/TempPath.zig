const std = @import("std");
const TempPath = @This();

buf: [std.fs.max_path_bytes]u8,
dir: std.fs.Dir,
basename_idx: usize,

pub fn init() !TempPath {
    var tp: TempPath = undefined;
    const p = std.posix.getenv("TMPDIR") orelse std.posix.getenv("TEMP") orelse ".";
    if (p.len >= tp.buf.len - 34) return error.PathTooLong;

    tp.dir = try std.fs.cwd().openDir(p, .{});

    @memcpy(tp.buf[0..p.len], p);
    tp.buf[p.len] = std.fs.path.sep;
    tp.basename_idx = p.len + 1;

    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    const name = std.fmt.bytesToHex(&bytes, .lower);
    @memcpy(tp.buf[tp.basename_idx..][0..name.len], &name);
    tp.buf[p.len + 33] = 0;
    return tp;
}

pub fn deinit(tp: *TempPath) void {
    tp.dir.deleteTree(tp.basename()) catch {};
    tp.dir.close();
}

pub fn path(tp: *const TempPath) [:0]const u8 {
    return @ptrCast(tp.buf[0 .. tp.basename_idx + 33]);
}

pub fn dirname(tp: *const TempPath) []const u8 {
    return tp.buf[0..tp.basename_idx];
}

pub fn basename(tp: *const TempPath) [:0]const u8 {
    return @ptrCast(tp.buf[tp.basename_idx..][0..32]);
}
