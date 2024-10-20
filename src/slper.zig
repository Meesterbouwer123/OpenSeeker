const std = @import("std");
const c = @cImport(@cInclude("zmq.h"));

const ventilator_connect_address = "tcp://127.0.0.1:31001";

pub fn main() !void {
    const ctx = c.zmq_ctx_new() orelse @panic("oom");
    defer _ = c.zmq_ctx_shutdown(ctx);

    const ventilator = c.zmq_socket(ctx, c.ZMQ_PULL);
    defer _ = c.zmq_close(ventilator);

    if (c.zmq_connect(ventilator, ventilator_connect_address) != 0) return error.ConnectFailed;

    while (true) {
        var buf: [4 + 2 + 8]u8 = undefined;
        const n = c.zmq_recv(ventilator, &buf, buf.len, 0);
        if (n != buf.len) return error.SkillIssue;

        const ip = std.mem.readInt(u32, buf[0..4], .little);
        _ = ip; // autofix
        const port = std.mem.readInt(u16, buf[4..][0..2], .little);
        const timestamp = std.mem.readInt(u64, buf[4 + 2..][0..8], .little);

        std.debug.print("received {d}.{d}.{d}.{d}:{d}, found at {d}\n", .{buf[3], buf[2], buf[1], buf[0], port, timestamp});
    }
}
