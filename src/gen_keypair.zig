const std = @import("std");
const zmq = @import("zmq");

pub fn main() !void {
    var seed: [std.crypto.dh.X25519.seed_length]u8 = undefined;
    std.crypto.random.bytes(&seed);
    const kp = try std.crypto.dh.X25519.KeyPair.create(seed);

    var secret_buf: [zmq.z85.encodedLen(std.crypto.dh.X25519.secret_length)]u8 = undefined;
    zmq.z85.encode(&secret_buf, &kp.secret_key);

    var public_buf: [zmq.z85.encodedLen(std.crypto.dh.X25519.public_length)]u8 = undefined;
    zmq.z85.encode(&public_buf, &kp.public_key);

    try std.io.getStdOut().writer().print("secret: {s}\npublic: {s}\n", .{
        secret_buf[0 .. secret_buf.len - 1],
        public_buf[0 .. public_buf.len - 1],
    });
}
