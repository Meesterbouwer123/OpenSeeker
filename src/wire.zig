const std = @import("std");
const zmq = @import("zmq.zig");

comptime {
    if (@import("builtin").cpu.arch.endian() != .little) @compileError("little endian is required for now");
}

pub fn wireFree(p: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
    std.c.free(p);
}

pub const Ip = packed union {
    i: u32,
    b: packed struct(u32) {
        d: u8,
        c: u8,
        b: u8,
        a: u8,
    },

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

    pub fn send(v: *const Host, sock: *zmq.Socket) !void {
        try sock.send(std.mem.asBytes(v), .{});
    }

    pub inline fn recv(sock: *zmq.Socket) !Host {
        var h: Host = undefined;
        const n = try sock.recv(std.mem.asBytes(&h), .{});
        if (n != @sizeOf(Host)) return error.BadMessageLength;
        return h;
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

    pub fn send(v: *const Range, sock: *zmq.Socket) !void {
        try sock.send(std.mem.asBytes(v), .{});
    }

    pub inline fn recv(sock: *zmq.Socket) !Range {
        var v: Range = undefined;
        const n = try sock.recv(&v, .{});
        if (n != @sizeOf(Range)) return error.BadMessageLength;
        return v;
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

    /// TAKES OWNERSHIP of `dr`. `dr` must be allocated with the c allocator.
    pub fn send(dr: *DiscoveryRequest, sock: *zmq.Socket) !void {
        try sock.send("1d", .{.sndmore = true});

        var m = try zmq.Message.initOwned(std.mem.asBytes(dr), wireFree, null);
        errdefer m.deinit();

        try m.send(sock, .{});
    }
};

pub const SlpRequest = extern struct {
    preferred_bucket_size: u32 align(1),

    /// TAKES OWNERSHIP of `dr`. `dr` must be allocated with the c allocator.
    pub fn send(sr: *SlpRequest, sock: *zmq.Socket) !void {
        try sock.send("1s", .{.sndmore = true});

        var m = try zmq.Message.initOwned(std.mem.asBytes(sr), wireFree, null);
        errdefer m.deinit();

        try m.send(sock, .{});
    }
};

pub const Request = struct {
    msg: zmq.Message,
    v: union(enum) {
        slp: *SlpRequest,
        discovery: *DiscoveryRequest,
    },

    pub fn deinit(r: *Request) void {
        r.msg.deinit();
        r.* = undefined;
    }

    /// Will be allocated with the C allocator.
    pub fn recv(sock: *zmq.Socket) !Request {
        var buf: [2]u8 = undefined;
        const n = try sock.recv(&buf, .{});
        if (n != buf.len) return error.BadMessageLength;

        if (buf[0] != '1') return error.IncompatibleVersion;

        const size: usize = switch(buf[1]) {
            'd' => @sizeOf(DiscoveryRequest),
            's' => @sizeOf(SlpRequest),
            else => return error.IllegalRequest,
        };

        var m = try zmq.Message.initCapacity(size);
        errdefer m.deinit();

        try m.recv(sock, .{});
        if (m.len() != size) return error.Bruh;

        return switch (buf[1]) {
            'd' => .{
                .msg = m,
                .v = .{ .discovery = @ptrCast(m.dataPtr())},
            },
            's' => .{
                .msg = m,
                .v = .{ .slp = @ptrCast(m.dataPtr())},
            },
            else => unreachable,
        };
    }
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
        .ip = .{.i = 0x01020304},
        .port = 6969,
    };
    try h.send(a);
    const n = try Host.recv(b);
    try std.testing.expectEqualSlices(u8, &std.mem.toBytes(h), &std.mem.toBytes(n));
}


test {
    std.testing.refAllDecls(Ip);
    std.testing.refAllDecls(Host);
    std.testing.refAllDecls(Range);
    std.testing.refAllDecls(DiscoveryRequest);
    std.testing.refAllDecls(SlpRequest);
    std.testing.refAllDecls(Request);
}
