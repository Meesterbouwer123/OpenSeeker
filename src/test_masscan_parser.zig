const std = @import("std");
const m = @import("masscan.zig");

test "parse a simple list file" {
    const f = try std.fs.cwd().openFile("test/simple.list", .{ .mode = .read_only });
    defer f.close();

    const mlp = m.h.mlp_init(.{
        .type = m.h.MASSCAN_PARSER_SRC_FD,
        .v = .{ .fd = f.handle },
    }) orelse return error.OutOfMemory;
    defer m.h.mlp_destroy(mlp);

    var r: m.h.masscan_record = undefined;

    try std.testing.expectEqual(@as(c_int, 1), m.h.mlp_next_record(mlp, &r));
    try std.testing.expectEqual(r.is_open, 1);
    try std.testing.expectEqual(r.ip_proto, 6);
    try std.testing.expectEqual(r.port, 25565);
    try std.testing.expectEqual(r.ip.v.ipv4, 0x08080808);
    try std.testing.expectEqual(r.timestamp, 1729350268);

    try std.testing.expectEqual(@as(c_int, 1), m.h.mlp_next_record(mlp, &r));
    try std.testing.expectEqual(r.is_open, 1);
    try std.testing.expectEqual(r.ip_proto, 6);
    try std.testing.expectEqual(r.port, 25565);
    try std.testing.expectEqual(r.ip.v.ipv4, 0x01010101);
    try std.testing.expectEqual(r.timestamp, 1729350268);

    try std.testing.expectEqual(@as(c_int, 1), m.h.mlp_next_record(mlp, &r));
    try std.testing.expectEqual(r.is_open, 1);
    try std.testing.expectEqual(r.ip_proto, 6);
    try std.testing.expectEqual(r.port, 25565);
    try std.testing.expectEqual(r.ip.v.ipv4, 0x8efab96e);
    try std.testing.expectEqual(r.timestamp, 1729350268);

    try std.testing.expectEqual(@as(c_int, 1), m.h.mlp_next_record(mlp, &r));
    try std.testing.expectEqual(r.is_open, 1);
    try std.testing.expectEqual(r.ip_proto, 6);
    try std.testing.expectEqual(r.port, 25565);
    try std.testing.expectEqual(r.ip.v.ipv4, 0xcaa57cb6);
    try std.testing.expectEqual(r.timestamp, 1729350268);

    try std.testing.expectEqual(@as(c_int, 0), m.h.mlp_next_record(mlp, &r));
}
