const std = @import("std");
const zmq = @import("zmq");

pub fn main() !void {
    var secret_buf: [40:0]u8 = undefined;
    var public_buf: [40:0]u8 = undefined;
    try zmq.curve.keypair(&public_buf, &secret_buf);

    try std.io.getStdOut().writer().print("secret: {s}\npublic: {s}\n", .{
        secret_buf[0 .. secret_buf.len - 1],
        public_buf[0 .. public_buf.len - 1],
    });
}
