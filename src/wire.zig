const std = @import("std");
const zmq = @import("zmq.zig");

comptime {
    if (@import("builtin").cpu.arch.endian() != .little) @compileError("little endian is required for now");
}

pub fn wireFree(p: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
    std.c.free(p);
}

/// If `v` is a pointer, `send` takes ownership of it.
pub fn send(v: anytype, sock: *zmq.Socket, options: zmq.Socket.SendRecvOptions) !void {
    const T = @TypeOf(v);
    const ti = @typeInfo(T);
    if (ti == .pointer) {
        std.debug.assert(ti.pointer.size == .One);
        var m = try zmq.Message.initOwned(std.mem.asBytes(v), wireFree, null);

        try m.send(sock, options);
    } else {
        try sock.send(&std.mem.toBytes(v), options);
    }
}

pub fn recv(comptime T: type, sock: *zmq.Socket, options: zmq.Socket.SendRecvOptions) !T {
    var v: T = undefined;
    try sock.recvExact(std.mem.asBytes(&v), options);
    return v;
}

pub const Ip = packed union {
    i: u32,
    b: packed struct(u32) {
        d: u8,
        c: u8,
        b: u8,
        a: u8,
    },

    // pub const BaseType = u32;

    // pub fn bindField(self: Ip, _: std.mem.Allocator) !BaseType {
    //     return self.i;
    // }

    // pub fn readField(_: std.mem.Allocator, value: BaseType) !Ip {
    //     return .{ .i = value };
    // }

    pub fn fromString(str: []const u8) error{IllegalIp}!Ip {
        var periods = std.mem.splitScalar(u8, str, '.');
        const x = std.fmt.parseInt(u8, periods.first(), 10) catch return error.IllegalIp;
        const y = std.fmt.parseInt(u8, periods.next() orelse return error.IllegalIp, 10) catch return error.IllegalIp;
        const z = std.fmt.parseInt(u8, periods.next() orelse return error.IllegalIp, 10) catch return error.IllegalIp;
        const w = std.fmt.parseInt(u8, periods.next() orelse return error.IllegalIp, 10) catch return error.IllegalIp;
        return .{ .b = .{
            .a = x,
            .b = y,
            .c = z,
            .d = w,
        } };
    }

    pub fn format(v: Ip, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{[a]d}.{[b]d}.{[c]d}.{[d]d}", v.b);
    }
};

pub const Host = extern struct {
    ip: Ip align(1),
    port: u16 align(1),

    pub fn fromString(str: []const u8) error{ IllegalIp, IllegalPort, MissingPort }!Host {
        const colon_idx = std.mem.indexOfScalar(u8, str, ':') orelse return error.MissingPort;
        return .{
            .ip = try Ip.fromString(str[0..colon_idx]),
            .port = std.fmt.parseInt(u16, str[colon_idx + 1 ..], 10) catch return error.IllegalPort,
        };
    }

    pub fn format(v: Host, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{d}", .{ v.ip, v.port });
    }
};

pub const Range = extern struct {
    prefix: Ip align(1),
    mask: u8,

    pub fn isValid(r: Range) bool {
        return r.mask <= 32;
    }

    pub fn fromString(str: []const u8) error{ IllegalIp, IllegalMask, MissingMask }!Host {
        const slash_idx = std.mem.indexOfScalar(u8, str, '/') orelse return error.MissingMask;
        return .{
            .ip = try Ip.fromString(str[0..slash_idx]),
            .port = std.fmt.parseInt(u16, str[slash_idx + 1 ..], 10) catch return error.IllegalMask,
        };
    }

    pub fn format(v: Range, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}/{d}", .{ v.ip, v.mask });
    }
};

pub const DiscoveryRequest = extern struct {
    flags: packed struct {
        padding: u7 = 0,
        is_first_request: bool,
    },
    packets_per_sec: u32 align(1),
    previous_range: Range,
    previous_duration_ms: u32 align(1),
};

pub const SlpRequest = extern struct {
    preferred_bucket_size: u32 align(1),
};

pub const SlpResponseHeader = extern struct {
    pub const Task = enum(u8) {
        slp = 's',
        legacy = 'l',
        join = 'j',
        _,
    };

    task: Task,
};

pub const AnnounceHeader = extern struct {
    pub const Version = enum(u8) {
        latest = '1',
        _,
    };
    pub const Kind = enum(u8) {
        slp = 's',
        discovery = 'd',
        _,
    };

    version: Version,
    kind: Kind,
};

pub const ApiHeader = extern struct {
    pub const Version = enum(u8) {
        latest = '1',
        _,
    };

    pub const Kind = enum(u8) {
        enqueue_range = 'r',
        remove_range = 'R',

        enqueue_slp = 's',
        remove_slp = 'S',

        enqueue_legacy = 'l',
        remove_legacy = 'L',

        enqueue_join = 'j',
        remove_join = 'J',

        enqueue_pubkey = 'p',
        remove_pubkey = 'P',

        add_exclude = 'e',
        remove_exclude = 'E',

        query = 'q',
        _,
    };

    version: Version,
    kind: Kind,
};

test "send a host" {
    const ctx = try zmq.Context.init();
    defer ctx.deinit();

    const a = try ctx.socket(.pair);
    defer a.close();
    try a.bind("inproc://Host");

    const b = try ctx.socket(.pair);
    defer b.close();
    try b.connect("inproc://Host");

    const h: Host = .{
        .ip = .{ .i = 0x01020304 },
        .port = 6969,
    };
    try send(h, a, .{});
    const n = try recv(Host, b, .{});
    try std.testing.expectEqualSlices(u8, &std.mem.toBytes(h), &std.mem.toBytes(n));
}

test {
    std.testing.refAllDecls(Ip);
    std.testing.refAllDecls(Host);
    std.testing.refAllDecls(Range);
    std.testing.refAllDecls(DiscoveryRequest);
    std.testing.refAllDecls(SlpRequest);
}
