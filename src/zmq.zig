const std = @import("std");
pub const c = @cImport(@cInclude("zmq.h"));

// TODO:
// - look into a better mechanism than zmq_errno -- seriously, having to call that sucks!

fn unexpectedError(e: c_int) noreturn {
    std.log.err("unknown error {d}, '{s}'", .{ e, c.zmq_strerror(e) });
    @panic("bug: unexpected zmq error");
}

pub const Context = opaque {
    /// zmq_ctx_new
    pub fn init() error{SystemResources}!*Context {
        return if (c.zmq_ctx_new()) |ctx|
            @ptrCast(ctx)
        else switch (c.zmq_errno()) {
            c.EMFILE => error.SystemResources,
            else => |unex| unexpectedError(unex),
        };
    }

    /// zmq_ctx_shutdown
    pub fn deinit(ctx: *Context) void {
        if (c.zmq_ctx_shutdown(ctx) != 0) unreachable; // user error: invalid context
    }

    /// zmq_socket
    pub fn socket(ctx: *Context, _type: Socket.Type) error{ SystemResources, Terminated, IllegalValue }!*Socket {
        return if (c.zmq_socket(ctx, @intFromEnum(_type))) |s|
            @ptrCast(s)
        else switch (c.zmq_errno()) {
            c.EFAULT => unreachable, // user error: invalid context
            c.EINVAL => error.IllegalValue,
            c.EMFILE => error.SystemResources,
            c.ETERM => error.Terminated,
            else => |unex| unexpectedError(unex),
        };
    }
};

pub const Socket = opaque {
    pub const Type = enum(c_int) {
        pair = 0,
        @"pub" = 1,
        sub = 2,
        req = 3,
        rep = 4,
        dealer = 5,
        router = 6,
        pull = 7,
        push = 8,
        xpub = 9,
        xsub = 10,
        stream = 11,

        // draft
        server = 12,
        client = 13,
        radio = 14,
        dish = 15,
        gather = 16,
        scatter = 17,
        dgram = 18,
        peer = 19,
        channel = 20,
        _,
    };

    pub const Option = enum(c_int) {
        affinity = 4,
        routing_id = 5,
        subscribe = 6,
        unsubscribe = 7,
        rate = 8,
        recovery_ivl = 9,
        sndbuf = 11,
        rcvbuf = 12,
        rcvmore = 13,
        fd = 14,
        events = 15,
        type = 16,
        linger = 17,
        reconnect_ivl = 18,
        backlog = 19,
        reconnect_ivl_max = 21,
        maxmsgsize = 22,
        sndhwm = 23,
        rcvhwm = 24,
        multicast_hops = 25,
        rcvtimeo = 27,
        sndtimeo = 28,
        last_endpoint = 32,
        router_mandatory = 33,
        tcp_keepalive = 34,
        tcp_keepalive_cnt = 35,
        tcp_keepalive_idle = 36,
        tcp_keepalive_intvl = 37,
        immediate = 39,
        xpub_verbose = 40,
        router_raw = 41,
        ipv6 = 42,
        mechanism = 43,
        plain_server = 44,
        plain_username = 45,
        plain_password = 46,
        curve_server = 47,
        curve_publickey = 48,
        curve_secretkey = 49,
        curve_serverkey = 50,
        probe_router = 51,
        req_correlate = 52,
        req_relaxed = 53,
        conflate = 54,
        zap_domain = 55,
        router_handover = 56,
        tos = 57,
        connect_routing_id = 61,
        gssapi_server = 62,
        gssapi_principal = 63,
        gssapi_service_principal = 64,
        gssapi_plaintext = 65,
        handshake_ivl = 66,
        socks_proxy = 68,
        xpub_nodrop = 69,
        blocky = 70,
        xpub_manual = 71,
        xpub_welcome_msg = 72,
        stream_notify = 73,
        invert_matching = 74,
        heartbeat_ivl = 75,
        heartbeat_ttl = 76,
        heartbeat_timeout = 77,
        xpub_verboser = 78,
        connect_timeout = 79,
        tcp_maxrt = 80,
        thread_safe = 81,
        multicast_maxtpdu = 84,
        vmci_buffer_size = 85,
        vmci_buffer_min_size = 86,
        vmci_buffer_max_size = 87,
        vmci_connect_timeout = 88,
        use_fd = 89,
        gssapi_principal_nametype = 90,
        gssapi_service_principal_nametype = 91,
        bindtodevice = 92,

        // draft
        zap_enforce_domain = 93,
        loopback_fastpath = 94,
        metadata = 95,
        multicast_loop = 96,
        router_notify = 97,
        xpub_manual_last_value = 98,
        socks_username = 99,
        socks_password = 100,
        in_batch_size = 101,
        out_batch_size = 102,
        wss_key_pem = 103,
        wss_cert_pem = 104,
        wss_trust_pem = 105,
        wss_hostname = 106,
        wss_trust_system = 107,
        only_first_subscribe = 108,
        reconnect_stop = 109,
        hello_msg = 110,
        disconnect_msg = 111,
        priority = 112,
        busy_poll = 113,
        hiccup_msg = 114,
        xsub_verbose_unsubscribe = 115,
        topics_count = 116,
        norm_mode = 117,
        norm_unicast_nack = 118,
        norm_buffer_size = 119,
        norm_segment_size = 120,
        norm_block_size = 121,
        norm_num_parity = 122,
        norm_num_autoparity = 123,
        norm_push = 124,
        _,
    };

    pub const Property = extern struct {
        str: [*:0]const u8,

        pub const socket_type = .{ .str = "Socket-Type" };
        pub const routing_id = .{ .str = "Routing-Id" };
        pub const user_id = .{ .str = "User-Id" };
    };

    pub const SendRecvOptions = packed struct(c_int) {
        dontwait: bool = false,
        sndmore: bool = false,
        _pad: @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(c_int) - 2 } }) = 0,
    };

    /// zmq_close
    pub fn close(sock: *Socket) void {
        if (c.zmq_close(sock) != 0) unreachable; // user error: sock was null
    }

    // recurses to eintr loop
    /// zmq_setsockopt
    pub fn setOption(sock: *Socket, opt: Option, value: ?*const anyopaque, len: usize) error{ IllegalValue, Terminated }!void {
        if (c.zmq_setsockopt(sock, @intFromEnum(opt), value, len) != 0) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EINVAL => error.IllegalValue,
            c.ETERM => error.Terminated,
            c.EINTR => @call(.always_tail, setOption, .{ sock, opt, value, len }),
            else => |unex| unexpectedError(unex),
        };
    }

    // recurses to eintr loop
    /// zmq_setsockopt
    pub fn getOption(sock: *Socket, opt: Option, value: ?*anyopaque, len: usize) error{ IllegalValue, Terminated }!void {
        if (c.zmq_getsockopt(sock, @intFromEnum(opt), value, len) != 0) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EINVAL => error.IllegalValue,
            c.ETERM => error.Terminated,
            c.EINTR => @call(.always_tail, getOption, .{ sock, opt, value, len }),
            else => |unex| unexpectedError(unex),
        };
    }

    // recurses to eintr loop
    /// zmq_send
    pub fn send(sock: *Socket, b: []const u8, options: SendRecvOptions) error{ WouldBlock, SocketTypeNotForSending, MultipartNotAllowed, IllegalState, Terminated, NotRoutable }!void {
        if (c.zmq_send(sock, b.ptr, b.len, @bitCast(options)) != b.len) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EAGAIN => error.WouldBlock,
            c.ENOTSUP => error.SocketTypeNotForSending,
            c.EINVAL => error.MultipartNotAllowed,
            c.EFSM => error.IllegalState,
            c.ETERM => error.Terminated,
            c.EHOSTUNREACH => error.NotRoutable,
            c.EINTR => @call(.always_tail, send, .{ sock, b, options }),
            else => |unex| unexpectedError(unex),
        };
    }

    // recurses to eintr loop
    /// zmq_recv
    pub fn recv(sock: *Socket, b: []u8, options: SendRecvOptions) error{ WouldBlock, SocketTypeNotForReceiving, IllegalState, Terminated }!usize {
        const res = c.zmq_recv(sock, b.ptr, b.len, @bitCast(options));
        return if (res >= 0) @intCast(res) else switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null.
            c.EAGAIN => error.WouldBlock,
            c.ENOTSUP => error.SocketTypeNotForReceiving,
            c.EFSM => error.IllegalState,
            c.ETERM => error.Terminated,
            c.EINTR => recv(sock, b, options),
            else => |unex| unexpectedError(unex),
        };
    }

    /// wraps recv with checking for the correct len
    pub fn recvExact(sock: *Socket, b: []u8, options: SendRecvOptions) error{ WouldBlock, SocketTypeNotForReceiving, IllegalState, Terminated, Truncated, NotEnoughData }!void {
        const n = try sock.recv(b, options);
        if (n == b.len) {
            @branchHint(.likely);
            return;
        } else if (n < b.len) {
            @branchHint(.unlikely);
            return error.NotEnoughData;
        } else if (n > b.len) {
            @branchHint(.unlikely);
            return error.Truncated;
        }
        unreachable;
    }

    /// zmq_bind
    pub fn bindZ(sock: *Socket, endpoint: [*:0]const u8) error{ InvalidValue, UnsupportedProtocol, IncompatibleProtocol, AddressInUse, AddressNotAvailable, NonexistantInterface, Terminated, NoIoThread }!void {
        if (c.zmq_bind(sock, endpoint) != 0) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EINVAL => error.InvalidValue,
            c.EPROTONOSUPPORT => error.UnsupportedProtocol,
            c.ENOCOMPATPROTO => error.IncompatibleProtocol,
            c.EADDRINUSE => error.AddressInUse,
            c.EADDRNOTAVAIL => error.AddressNotAvailable,
            c.ENODEV => error.NonexistantInterface,
            c.EMTHREAD => error.NoIoThread,
            c.ETERM => error.Terminated,
            else => |unex| unexpectedError(unex),
        };
    }

    pub fn bind(sock: *Socket, endpoint: []const u8, allocator: std.mem.Allocator) error{ OutOfMemory, InvalidValue, UnsupportedProtocol, IncompatibleProtocol, AddressInUse, AddressNotAvailable, NonexistantInterface, Terminated, NoIoThread }!void {
        const formatted_endpoint = try allocator.dupeZ(u8, endpoint);
        defer allocator.free(formatted_endpoint);
        return bindZ(sock, formatted_endpoint);
    }

    /// zmq_connect
    pub fn connectZ(sock: *Socket, endpoint: [*:0]const u8) error{ InvalidValue, UnsupportedProtocol, IncompatibleProtocol, Terminated, NoIoThread }!void {
        if (c.zmq_connect(sock, endpoint) != 0) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EINVAL => error.InvalidValue,
            c.EPROTONOSUPPORT => error.UnsupportedProtocol,
            c.ENOCOMPATPROTO => error.IncompatibleProtocol,
            c.EMTHREAD => error.NoIoThread,
            c.ETERM => error.Terminated,
            else => |unex| unexpectedError(unex),
        };
    }

    pub fn connect(sock: *Socket, endpoint: []const u8, allocator: std.mem.Allocator) error{ OutOfMemory, InvalidValue, UnsupportedProtocol, IncompatibleProtocol, Terminated, NoIoThread }!void {
        const formatted_endpoint = try allocator.dupeZ(u8, endpoint);
        defer allocator.free(formatted_endpoint);
        return connectZ(sock, formatted_endpoint);
    }

    /// Returns the number of frames discarded.
    pub fn discardRemainingFrames(sock: *Socket, options: SendRecvOptions) !usize {
        var nb_discarded: usize = 0;
        var has_more: c_int = undefined;
        try sock.getOption(.rcvmore, &has_more, @sizeOf(c_int));
        while (has_more != 0) {
            var m = Message.init();
            defer m.deinit();
            try m.recv(sock, options);
            try sock.getOption(.rcvmore, &has_more, @sizeOf(c_int));
            nb_discarded += 1;
        }
        return nb_discarded;
    }
};

pub const Message = extern struct {
    i: c.zmq_msg_t,

    pub const FreeFn = fn (data: ?*anyopaque, hint: ?*anyopaque) callconv(.C) void;

    pub fn init() Message {
        var m: Message = undefined;
        if (c.zmq_msg_init(&m.i) != 0) unreachable;
        return m;
    }

    pub fn initCapacity(cap: usize) error{OutOfMemory}!Message {
        var m: Message = undefined;
        if (c.zmq_msg_init_size(&m.i, cap) != 0) return switch (c.zmq_errno()) {
            c.ENOMEM => error.OutOfMemory,
            else => |unex| unexpectedError(unex),
        };
        return m;
    }

    pub fn initOwned(buf: []u8, freeFn: ?*const FreeFn, hint: ?*anyopaque) error{OutOfMemory}!Message {
        var m: Message = undefined;
        if (c.zmq_msg_init_data(&m.i, buf.ptr, buf.len, freeFn, hint) != 0) return switch (c.zmq_errno()) {
            c.ENOMEM => error.OutOfMemory,
            else => |unex| unexpectedError(unex),
        };
        return m;
    }

    pub fn initCopy(buf: []const u8) error{OutOfMemory}!Message {
        var m: Message = undefined;
        if (c.zmq_msg_init_buffer(&m.i, buf.ptr, buf.len) != 0) return switch (c.zmq_errno()) {
            c.ENOMEM => error.OutOfMemory,
            else => |unex| unexpectedError(unex),
        };
        return m;
    }

    pub fn data(m: *Message) []u8 {
        return m.dataPtr()[0..m.len()];
    }

    pub fn len(m: *Message) usize {
        return c.zmq_msg_size(&m.i);
    }

    pub fn dataPtr(m: *Message) [*]u8 {
        return @ptrCast(c.zmq_msg_data(&m.i));
    }

    pub fn deinit(m: *Message) void {
        if (c.zmq_msg_close(&m.i) != 0) unreachable;
    }

    // recurses to eintr loop
    /// zmq_msg_send
    pub fn send(m: *Message, sock: *Socket, options: Socket.SendRecvOptions) error{ WouldBlock, SocketTypeNotForSending, MultipartNotAllowed, IllegalState, Terminated, NotRoutable }!void {
        if (c.zmq_msg_send(&m.i, sock, @bitCast(options)) != 0) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EFAULT => unreachable, // user error: message was invalid
            c.EAGAIN => error.WouldBlock,
            c.ENOTSUP => error.SocketTypeNotForSending,
            c.EINVAL => error.MultipartNotAllowed,
            c.EFSM => error.IllegalState,
            c.ETERM => error.Terminated,
            c.EHOSTUNREACH => error.NotRoutable,
            c.EINTR => @call(.always_tail, send, .{ m, sock, options }),
            else => |unex| unexpectedError(unex),
        };
    }

    // recurses to eintr loop
    /// zmq_msg_recv
    pub fn recv(m: *Message, sock: *Socket, options: Socket.SendRecvOptions) error{ WouldBlock, SocketTypeNotForReceiving, IllegalState, Terminated }!void {
        if (c.zmq_msg_recv(&m.i, sock, @bitCast(options)) == 0) return switch (c.zmq_errno()) {
            c.ENOTSOCK => unreachable, // user error: sock was null
            c.EFAULT => unreachable, // user error: message was invalid
            c.EAGAIN => error.WouldBlock,
            c.ENOTSUP => error.SocketTypeNotForReceiving,
            c.EFSM => error.IllegalState,
            c.ETERM => error.Terminated,
            c.EINTR => @call(.always_tail, recv, .{ m, sock, options }),
            else => |unex| unexpectedError(unex),
        };
    }
};

pub const z85 = struct {
    /// Includes the null byte
    pub fn encodedLen(in: usize) usize {
        return in * 5 / 4 + 1;
    }

    pub fn decodedLen(in: usize) usize {
        return in * 8 / 10;
    }

    /// out must be at least `encodedLen(in.len)` long
    pub fn encode(noalias out: [*]u8, in: []const u8) void {
        _ = c.zmq_z85_encode(out, in.ptr, in.len);
    }

    /// out must be at least `decodedLen(in.len)` long
    pub fn decode(noalias out: [*]u8, in: [*:0]const u8) error{IllegalValue}!void {
        if (c.zmq_z85_decode(out, in) != out) return error.IllegalValue;
    }
};
