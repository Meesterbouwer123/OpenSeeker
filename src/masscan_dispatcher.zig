const std = @import("std");
const c = @cImport(@cInclude("zmq.h"));
const m = @import("masscan.zig");

const ventilator_connect_address = "tcp://127.0.0.1:31000";

pub fn main() !void {
    var fifo_buf: [32 + 5:0]u8 = undefined;
    {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        const fifoname = std.fmt.bytesToHex(&bytes, .lower);
        @memcpy(fifo_buf[0..5], "/tmp/");
        @memcpy(fifo_buf[5..][0..32], &fifoname);
        fifo_buf[fifo_buf.len] = 0;
    }
    const fifopath = fifo_buf[0..32 + 5];
    const fifoname = fifopath[5..];

    var tmp = try std.fs.openDirAbsolute("/tmp", .{});
    defer tmp.close();

    if (std.os.linux.mknodat(tmp.fd, fifoname, 0o600 | std.os.linux.S.IFIFO, 0) != 0) return error.MkfifoFailed;
    defer _ = std.os.linux.unlinkat(tmp.fd, fifoname, 0);


    var args = std.ArrayList([]const u8).init(std.heap.c_allocator);
    defer args.deinit();

    try args.append("masscan");

    for (std.os.argv[1..]) |arg| {
        try args.append(std.mem.span(arg));
    }
    try args.appendSlice(&.{"-oL", fifopath});

    var child = std.process.Child.init(args.items, std.heap.c_allocator);
    try child.spawn();
    defer _ = child.wait() catch {};

    const fp = m.h.fopen(fifopath, "rb") orelse return error.OpenFailed;
    defer _ = m.h.fclose(fp);

    const mlp = m.h.mlp_init(.{
        .type = m.h.MASSCAN_PARSER_SRC_FILEP,
        .v = .{ .fp = fp },
    }) orelse return error.MlpInitFailed;
    defer m.h.mlp_destroy(mlp);

    const ctx = c.zmq_ctx_new() orelse return error.OutOfMemory;
    defer _ = c.zmq_ctx_shutdown(ctx);

    const ventilator = c.zmq_socket(ctx, c.ZMQ_PUSH) orelse return error.OutOfMemory;
    defer _ = c.zmq_close(ventilator);

    if (c.zmq_connect(ventilator, ventilator_connect_address) != 0) return error.ConnectFailed;

    while (true) {
        var r: m.h.masscan_record = undefined;
        const res = m.h.mlp_next_record(mlp, &r);

        if (res == 0) break;
        if (res < 0) return error.ReadError;
        if (r.ip.version != 4 or r.is_open == 0) continue;

        var buf: [4 + 2 + 8]u8 = undefined;
        std.mem.writeInt(u32, buf[0..4], r.ip.v.ipv4, .little);
        std.mem.writeInt(u16, buf[4..][0..2], r.port, .little);
        std.mem.writeInt(u64, buf[4 + 2..][0..8], r.timestamp, .little);
        std.debug.print("read {d}.{d}.{d}.{d}:{d}, found at {d}\n", .{buf[3], buf[2], buf[1], buf[0], r.port, r.timestamp});
        if (c.zmq_send(ventilator, &buf, buf.len, 0) != buf.len) return error.SendFailed;
    }
}
