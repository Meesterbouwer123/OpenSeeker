const std = @import("std");

pub fn parse(comptime Config: type, buf: []const u8) !Config {
    var s: Config = .{};

    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeScalar(u8, line, ' ');
        const key = words.next().?;
        const value = words.rest();

        inline for(@typeInfo(Config).@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, key)) @field(s, field.name) = try parseValue(field.type, value);
        }
    }

    return s;
}

fn parseValue(comptime T: type, value: []const u8) !T {
     return switch (@typeInfo(T)) {
         .optional => |o| if (value.len == 0) null else parseValue(o.child, value),
         .int => try std.fmt.parseInt(T, value, 0),
         .float => try std.fmt.parseFloat(T, value),
         .pointer => |p| switch(p.size) {
             .Slice => switch (p.child) {
                 u8 => value,
                 else => error.Unsupported,
             },
             else => error.Unsupported,
         },
         else => error.Unsupported,
    };
}
