const std = @import("std");
const zmq = @import("zmq");
const wire = @import("wire.zig");
const conf = @import("conf.zig");
const sqlite = @import("sqlite");

const MultipartMessage = std.ArrayListUnmanaged(zmq.Message);

pub fn recvAll(s: *zmq.Socket, ally: std.mem.Allocator) !MultipartMessage {
    var fm: MultipartMessage = .{};
    errdefer deinitAll(&fm, ally);

    var more = true;
    while (more) {
        var m = try fm.addOne(ally);
        errdefer _ = fm.pop();

        m.* = zmq.Message.init();
        errdefer m.deinit();

        try m.recv(s, .{});
        more = m.hasMore();
    }
    return fm;
}

pub fn deinitAll(m: *MultipartMessage, ally: std.mem.Allocator) void {
    for (m.items) |*ms| ms.deinit();
    m.deinit(ally);
}

const Config = struct {
    db_path: []const u8 = "openseeker_manager.sqlite3",

    /// The announcement REP endpoint, where discoveries and pingers announce themselves.
    announce: []const u8 = "tcp://127.0.0.1:35001",
    announce_curve_secret_key: ?[]const u8 = null,

    /// The collection PULL endpoint, where discoveries and pingers send statuses.
    collect: []const u8 = "tcp://127.0.0.1:35002",
    collect_curve_secret_key: ?[]const u8 = null,

    /// The api REP endpoint, where clients can send queries, and where administrators and users can manipulate the database (query format: TBD).
    api: []const u8 = "tcp://127.0.0.1:35003",
    api_curve_secret_key: ?[]const u8 = null,

    query_curve_allowed_public_key: ?[]const u8 = null,

    control_curve_admin_public_key: ?[]const u8 = null,
    // maybe we want an array of allowed public keys? or we just use a token... but that provides
    // fewer guarantees
    control_curve_allowed_public_key: ?[]const u8 = null,
};

pub const Announce = struct {
    socket: *zmq.Socket,
    thread: std.Thread,
    arena: std.heap.ArenaAllocator,

    const log = std.log.scoped(.announce);

    fn sendHosts(
        announce: *Announce,
        iter: *sqlite.Iterator(wire.Host),
        alist: *std.ArrayListUnmanaged(wire.Host),
        rheader: wire.SlpResponseHeader,
        options: zmq.Socket.SendRecvOptions,
    ) !void {
        while (try iter.next(.{})) |host| {
            try alist.append(std.heap.c_allocator, host);
        }

        const buf = try alist.toOwnedSlice(std.heap.c_allocator);
        errdefer std.heap.c_allocator.free(buf);
        try wire.send(rheader, announce.socket, .{ .sndmore = true });

        var m = try zmq.Message.initOwned(std.mem.sliceAsBytes(buf), wire.wireFree, null);
        try m.send(announce.socket, options);
    }

    fn handleSlpRequest(
        announce: *Announce,
        slp_req_m: *zmq.Message,
        hosts_to_legacy: *sqlite.DynamicStatement,
        hosts_to_slp: *sqlite.DynamicStatement,
        hosts_to_join: *sqlite.DynamicStatement,
    ) !void {
        const slp_req = try wire.recvMP(wire.SlpRequest, slp_req_m);

        if (slp_req.preferred_bucket_size < 3) {
            const host = try hosts_to_legacy.one(wire.Host, .{}, .{ .limit = 1 });
            const rheader: wire.SlpResponseHeader = .{ .task = .legacy };

            try wire.send(rheader, announce.socket, .{ .sndmore = true });
            try wire.send(host, announce.socket, .{});
        } else {
            const nb_hosts_per_bucket = slp_req.preferred_bucket_size;

            var alist: std.ArrayListUnmanaged(wire.Host) = .{};
            defer alist.deinit(std.heap.c_allocator);

            {
                try alist.ensureUnusedCapacity(std.heap.c_allocator, nb_hosts_per_bucket);
                var legacy_iter = try hosts_to_legacy.iterator(wire.Host, .{ .limit = nb_hosts_per_bucket });
                try announce.sendHosts(&legacy_iter, &alist, .{ .task = .legacy }, .{ .sndmore = true });
            }

            {
                try alist.ensureUnusedCapacity(std.heap.c_allocator, nb_hosts_per_bucket);
                var slp_iter = try hosts_to_slp.iterator(wire.Host, .{ .limit = nb_hosts_per_bucket });
                try announce.sendHosts(&slp_iter, &alist, .{ .task = .slp }, .{ .sndmore = true });
            }

            {
                try alist.ensureUnusedCapacity(std.heap.c_allocator, nb_hosts_per_bucket);
                var join_iter = try hosts_to_join.iterator(wire.Host, .{ .limit = nb_hosts_per_bucket });
                try announce.sendHosts(&join_iter, &alist, .{ .task = .join }, .{});
            }
        }
    }

    pub fn handleDiscoveryRequest(
        announce: *Announce,
        dis_req: *zmq.Message,
        get_discovery: *sqlite.DynamicStatement,
        excluded_ranges: *sqlite.DynamicStatement,
        finish_discovery: *sqlite.DynamicStatement,
    ) !void {
        const discovery_request = try wire.recvMP(wire.DiscoveryRequest, dis_req);

        if (!discovery_request.flags.is_first_request) {
            try finish_discovery.exec(
                .{},
                .{
                    .prefix = discovery_request.previous_range.prefix,
                    .msbs = discovery_request.previous_range.msbs,
                },
            );
        }

        const new_range = try get_discovery.one(wire.Range, .{}, .{ .limit = 1 });

        var alist: std.ArrayListUnmanaged(wire.Range) = .{};
        defer alist.deinit(std.heap.c_allocator);

        {
            const range_to_search: wire.Range = if (discovery_request.flags.is_first_request)
                .{ .prefix = wire.Ip{ .i = 0 }, .msbs = 0 }
            else
                .{
                    .prefix = discovery_request.previous_range.prefix,
                    .msbs = discovery_request.previous_range.msbs,
                };
            var exclude_iter = try excluded_ranges.iterator(
                wire.Range,
                range_to_search,
            );

            while (try exclude_iter.next(.{})) |range| {
                try alist.append(std.heap.c_allocator, range);
            }
        }

        const excluded = try alist.toOwnedSlice(std.heap.c_allocator);

        try announce.socket.send(std.mem.asBytes(&new_range), .{ .sndmore = true });
        var m = try zmq.Message.initOwned(std.mem.sliceAsBytes(excluded), wire.wireFree, null);
        try m.send(announce.socket, .{});
    }

    pub fn worker(state: *State) void {
        const announce = &state.announce;
        var get_discovery = state.db.prepareDynamic(@embedFile("sql/get_discovery.sql")) catch @panic("bruh");
        var finish_discovery = state.db.prepareDynamic(@embedFile("sql/finish_discovery.sql")) catch @panic("bruh");
        var get_legacy = state.db.prepareDynamic(@embedFile("sql/get_legacy.sql")) catch @panic("bruh");
        var get_ping = state.db.prepareDynamic(@embedFile("sql/get_ping.sql")) catch @panic("bruh");
        var get_join = state.db.prepareDynamic(@embedFile("sql/get_join.sql")) catch @panic("bruh");
        var excluded_ranges = state.db.prepareDynamic(@embedFile("sql/excluded_ranges.sql")) catch @panic("bruh");

        while (true) {
            get_discovery.reset();
            get_legacy.reset();
            get_ping.reset();
            get_join.reset();
            excluded_ranges.reset();
            _ = announce.arena.reset(.{ .retain_with_limit = 4 << 20 });

            var fm = recvAll(announce.socket, announce.arena.allocator()) catch |err| switch (err) {
                error.NotSocket => return,
                error.Terminated => return,
                else => {
                    log.warn("recv error {s}", .{@errorName(err)});
                    continue;
                },
            };
            defer deinitAll(&fm, announce.arena.allocator());

            if (fm.items.len != 2) {
                log.warn("discarded {d} messages", .{fm.items.len});
                continue;
            }

            const header = wire.recvMP(wire.AnnounceHeader, &fm.items[0]) catch continue;

            if (header.version != .latest) {
                log.warn("incorrect version {d}", .{@intFromEnum(header.version)});
                continue;
            }

            const res = switch (header.kind) {
                .slp => announce.handleSlpRequest(&fm.items[1], &get_legacy, &get_ping, &get_join),
                .discovery => announce.handleDiscoveryRequest(&fm.items[1], &get_discovery, &excluded_ranges, &finish_discovery),

                _ => |k| {
                    log.warn("incorrect kind {d}", .{@intFromEnum(k)});
                    wire.send({}, announce.socket, .{}) catch {};
                    continue;
                },
            };
            res catch |err| switch (err) {
                error.Terminated => return,
                else => {
                    log.warn("handling error {s}", .{@errorName(err)});
                    continue;
                },
            };
        }
    }
};

pub const Collect = struct {
    socket: *zmq.Socket,
    thread: std.Thread,
    arena: std.heap.ArenaAllocator,

    const log = std.log.scoped(.collect);

    fn handleDiscovery(rest: []zmq.Message, new_discovery: *sqlite.DynamicStatement) !void {
        if (rest.len != 1) return error.InvalidNbFrames;
        const discovered_host = try wire.recvMP(wire.Host, &rest[0]);
        try new_discovery.exec(.{}, .{
            .ip = discovered_host.ip,
            .port = discovered_host.port,
            .timestamp = std.time.timestamp(),
            .priority = 10,
        });
    }

    fn handleLegacySuccess(rest: []zmq.Message, success_legacy: *sqlite.DynamicStatement) !void {
        if (rest.len != 3) return error.InvalidNbFrames;
        const host = try wire.recvMP(wire.Host, &rest[0]);
        const h = try wire.recvMP(wire.LegacySuccessHeader, &rest[1]);

        try success_legacy.exec(.{}, .{
            .ip = host.ip,
            .port = host.port,
            .timestamp = std.time.timestamp(),
            .max_players = h.max_players,
            .current_players = h.current_players,
            .motd = rest[3].data(),
        });
    }

    fn handleLegacyFailure(rest: []zmq.Message, failure_legacy: *sqlite.DynamicStatement) !void {
        if (rest.len != 1) return error.InvalidNbFrames;
        const host = try wire.recvMP(wire.Host, &rest[0]);
        try failure_legacy.exec(.{}, .{
            .ip = host.ip,
            .port = host.port,
            .timestamp = std.time.timestamp(),
        });
    }

    fn handlePingSuccess(rest: []zmq.Message, success_ping: *sqlite.DynamicStatement, favicon: *sqlite.DynamicStatement) !void {
        if (rest.len < 3 or rest.len > 4) return error.InvalidNbFrames;
        const host = try wire.recvMP(wire.Host, &rest[0]);
        const h = try wire.recvMP(wire.PingSuccessHeader, &rest[1]);

        var favicon_id: ?u64 = null;
        if (rest.len == 4) {
            favicon_id = try favicon.one(u64, .{}, .{ .d = rest[3].data() });
        }

        try success_ping.exec(.{}, .{
            .ip = host.ip,
            .port = host.port,
            .timestamp = std.time.timestamp(),
            .max_players = h.max_players,
            .current_players = h.current_players,
            .motd = rest[2].data(),
            .favicon_id = favicon_id,
        });
    }

    fn handlePingFailure(rest: []zmq.Message, failure_ping: *sqlite.DynamicStatement) !void {
        if (rest.len != 1) return error.InvalidNbFrames;
        const host = try wire.recvMP(wire.Host, &rest[0]);
        try failure_ping.exec(.{}, .{
            .ip = host.ip,
            .port = host.port,
            .timestamp = std.time.timestamp(),
        });
    }

    fn handleJoinSuccess(rest: []zmq.Message, success_join: *sqlite.DynamicStatement) !void {
        _ = rest; // autofix
        _ = success_join; // autofix
        return error.Unimplemented;
    }

    fn handleJoinFailure(rest: []zmq.Message, success_join: *sqlite.DynamicStatement) !void {
        _ = rest; // autofix
        _ = success_join; // autofix
        // const host = try wire.recv(wire.Host, state.collect.socket, .{});
        // var reason = zmq.Message.init();
        // defer reason.deinit();
        // reason.recv(state.collect.socket, .{});
        // try std.heap.c_allocator.dupeZ(u8, reason);
        // try failure_ping.exec(.{}, .{
        // .ip = host.ip,
        // .port = host.port,
        // .timestamp = std.time.timestamp(),
        // .reason = reason.data(),
        // });
        return error.Unimplemented;
    }

    pub fn worker(state: *State) void {
        const collect = &state.collect;
        var new_discovery = state.db.prepareDynamic(@embedFile("sql/new_discovery.sql")) catch @panic("bruh");
        var success_legacy = state.db.prepareDynamic(@embedFile("sql/success_legacy.sql")) catch @panic("bruh");
        var failure_legacy = state.db.prepareDynamic(@embedFile("sql/failure_legacy.sql")) catch @panic("bruh");
        var success_ping = state.db.prepareDynamic(@embedFile("sql/success_ping.sql")) catch @panic("bruh");
        var failure_ping = state.db.prepareDynamic(@embedFile("sql/failure_ping.sql")) catch @panic("bruh");
        var success_join = state.db.prepareDynamic(@embedFile("sql/success_join.sql")) catch @panic("bruh");
        var failure_join = state.db.prepareDynamic(@embedFile("sql/failure_join.sql")) catch @panic("bruh");
        var favicon = state.db.prepareDynamic(@embedFile("sql/favicon.sql")) catch @panic("bruh");

        while (true) {
            new_discovery.reset();
            success_legacy.reset();
            failure_legacy.reset();
            success_ping.reset();
            failure_ping.reset();
            success_join.reset();
            failure_join.reset();
            favicon.reset();
            _ = collect.arena.reset(.{ .retain_with_limit = 4 << 20 });

            var fm = recvAll(collect.socket, collect.arena.allocator()) catch |err| switch (err) {
                error.NotSocket => return,
                error.Terminated => return,
                else => {
                    log.warn("recv error {s}", .{@errorName(err)});
                    continue;
                },
            };
            defer deinitAll(&fm, collect.arena.allocator());

            if (fm.items.len < 2) {
                log.warn("discarded {d} messages", .{fm.items.len});
                continue;
            }

            const header = wire.recvMP(wire.StatusHeader, &fm.items[0]) catch continue;

            if (header.version != .latest) {
                log.warn("incorrect version {d}", .{@intFromEnum(header.version)});
                continue;
            }

            const rest = fm.items[1..];
            const res = switch (header.kind) {
                .discovery => handleDiscovery(rest, &new_discovery),

                .legacy_success => handleLegacySuccess(rest, &success_legacy),
                .legacy_failure => handleLegacyFailure(rest, &failure_legacy),

                .ping_success => handlePingSuccess(rest, &success_ping, &favicon),
                .ping_failure => handlePingFailure(rest, &failure_ping),

                .join_success => handleJoinSuccess(rest, &success_join),
                .join_failure => handleJoinFailure(rest, &failure_join),

                _ => |k| {
                    log.warn("incorrect kind {d}", .{@intFromEnum(k)});
                    wire.send({}, collect.socket, .{}) catch {};
                    continue;
                },
            };
            res catch |err| switch (err) {
                else => {
                    log.warn("handling error {s}", .{@errorName(err)});
                    continue;
                },
            };
        }
    }
};

pub const Api = struct {
    socket: *zmq.Socket,
    thread: std.Thread,
    arena: std.heap.ArenaAllocator,

    const log = std.log.scoped(.api);

    pub fn worker(state: *State) void {
        const api = &state.api;

        var enqueue_range = state.db.prepareDynamic(@embedFile("sql/enqueue_range.sql")) catch @panic("bruh");
        var remove_range = state.db.prepareDynamic(@embedFile("sql/remove_range.sql")) catch @panic("bruh");
        var authorize_public_key = state.db.prepareDynamic(@embedFile("sql/authorize_public_key.sql")) catch @panic("bruh");
        var remove_public_key = state.db.prepareDynamic(@embedFile("sql/remove_public_key.sql")) catch @panic("bruh");
        var exclude_range = state.db.prepareDynamic(@embedFile("sql/exclude_range.sql")) catch @panic("bruh");
        var unexclude_range = state.db.prepareDynamic(@embedFile("sql/unexclude_range.sql")) catch @panic("bruh");

        while (true) {
            enqueue_range.reset();
            remove_range.reset();
            authorize_public_key.reset();
            remove_public_key.reset();
            exclude_range.reset();
            unexclude_range.reset();
            _ = api.arena.reset(.{ .retain_with_limit = 4 << 20 });

            var fm = recvAll(api.socket, api.arena.allocator()) catch continue;
            defer deinitAll(&fm, api.arena.allocator());

            if (fm.items.len < 4 or fm.items.len > 4 or fm.items[1].len() != 0) {
                log.err("bruh, {d}", .{fm.items.len});
            }

            const h = wire.recvMP(wire.ApiHeader, &fm.items[2]) catch continue;
            if (h.version != .latest) continue;

            if (h.kind == .query) {
                log.err("query asynchronously and authorize here", .{});
                fm.items[0].send(api.socket, .{.sndmore = true}) catch continue;
                wire.send({}, api.socket, .{.sndmore = true}) catch continue;
                wire.send({}, api.socket, .{}) catch continue;
                continue;
            }

            if (state.config.control_curve_admin_public_key != null) @panic("authenticate");

            fm.items[0].send(api.socket, .{.sndmore = true}) catch continue;
            wire.send({}, api.socket, .{.sndmore = true}) catch continue;

            const res = switch (h.kind) {
                .enqueue_range => api.handleEnqueue(&fm.items[3], &enqueue_range),
                .remove_range => api.handleRemove(&fm.items[3], &remove_range),

                .authorize_public_key => api.handleAuthorize(&fm.items[3], &authorize_public_key),
                .remove_public_key => api.handleUnauthorize(&fm.items[3], &remove_public_key),

                .exclude_range => api.handleExclude(&fm.items[3], &exclude_range),
                .unexclude_range => api.handleUnexclude(&fm.items[3], &unexclude_range),

                else => |k| {
                    log.warn("incorrect kind {d}", .{@intFromEnum(k)});
                    wire.send({}, api.socket, .{}) catch {};
                    continue;
                },
            };

            res catch |err| {
                log.err("skill issue {}", .{err});
                wire.send({}, api.socket, .{}) catch {};
                continue;
            };
        }
    }

    fn handleEnqueue(
        api: *Api,
        host_m: *zmq.Message,
        enqueue: *sqlite.DynamicStatement,
    ) !void {
        const r = try wire.recvMP(wire.Range, host_m);
        const res = enqueue.exec(.{}, .{
            .prefix = r.prefix.i,
            .msbs = r.msbs,
        });
        if (res) {
            try api.socket.send("OK", .{});
        } else |err| {
            try api.socket.send(@errorName(err), .{});
        }
    }

    const handleRemove = handleEnqueue;

    fn handleAuthorize(
        api: *Api,
        key_m: *zmq.Message,
        authorize: *sqlite.DynamicStatement,
    ) !void {
        const key_s = key_m.data();
        if (key_s.len != zmq.z85.encodedLen(32) or key_s[key_s.len - 1] != 0) return error.NotKey;
        var buf: [32]u8 = undefined;
        try zmq.z85.decode(&buf, @ptrCast(key_s.ptr));
        const res = authorize.exec(.{}, .{
            .public_key = &buf,
        });
        if (res) {
            try api.socket.send("OK", .{});
        } else |err| {
            try api.socket.send(@errorName(err), .{});
        }
    }

    const handleUnauthorize = handleAuthorize;

    const handleExclude = handleEnqueue;
    const handleUnexclude = handleEnqueue;
};

pub const State = struct {
    config: Config,
    ctx: *zmq.Context,
    db: sqlite.Db,

    announce: Announce,
    collect: Collect,
    api: Api,

    arena: std.heap.ArenaAllocator,

    pub fn init(state: *State, config_buf: []const u8) !void {
        state.* = undefined;
        errdefer state.* = undefined;

        state.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer state.arena.deinit();

        state.announce.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer state.announce.arena.deinit();

        state.collect.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer state.collect.arena.deinit();

        state.api.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer state.api.arena.deinit();

        const config = try conf.parse(Config, config_buf);

        const ctx = try zmq.Context.init();
        errdefer ctx.deinit();

        const announce = try ctx.socket(.rep);
        errdefer announce.close();
        {
            const zt_announce = try state.arena.allocator().dupeZ(u8, config.announce);
            defer state.arena.allocator().free(zt_announce);
            try announce.bindZ(zt_announce);
        }

        if (config.announce_curve_secret_key) |secret| {
            {
                const server: c_int = 1;
                try announce.setOption(.curve_server, &server, @sizeOf(c_int));
            }
            try announce.setOption(.curve_secretkey, secret.ptr, secret.len);
        }

        const collect = try ctx.socket(.pull);
        errdefer collect.close();

        if (config.collect_curve_secret_key) |secret| {
            {
                const server: c_int = 1;
                try collect.setOption(.curve_server, &server, @sizeOf(c_int));
            }
            try collect.setOption(.curve_secretkey, secret.ptr, secret.len);
        }

        {
            const zt_collect = try state.arena.allocator().dupeZ(u8, config.collect);
            defer state.arena.allocator().free(zt_collect);
            try collect.bindZ(zt_collect);
        }

        const api = try ctx.socket(.router);
        errdefer api.close();

        if (config.api_curve_secret_key) |secret| {
            {
                const server: c_int = 1;
                try api.setOption(.curve_server, &server, @sizeOf(c_int));
            }
            try api.setOption(.curve_secretkey, secret.ptr, secret.len);
        }

        {
            const zt_api = try state.arena.allocator().dupeZ(u8, config.api);
            defer state.arena.allocator().free(zt_api);
            try api.bindZ(zt_api);
        }

        const zt_file_name = try state.arena.allocator().dupeZ(u8, config.db_path);

        state.db = try sqlite.Db.init(.{
            .mode = .{ .File = zt_file_name },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .Serialized,
        });
        errdefer state.db.deinit();

        var diags: sqlite.Diagnostics = .{};
        state.db.execMulti(
            @embedFile("sql/first_run.sql"),
            .{ .diags = &diags },
        ) catch |e| {
            std.log.warn("{} {s}\n", .{ diags, @errorName(e) });
        };

        state.config = config;
        state.ctx = ctx;

        state.announce.socket = announce;
        state.collect.socket = collect;
        state.api.socket = api;

        state.announce.thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            Announce.worker,
            .{state},
        );
        errdefer state.announce.thread.detach(); // thread will terminate on its own due to error.Terminated

        state.api.thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            Api.worker,
            .{state},
        );
        errdefer state.api.thread.detach(); // thread will terminate on its own due to error.Terminated

        state.collect.thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            Collect.worker,
            .{state},
        );
        errdefer state.collect.thread.detach(); // thread will terminate on its own due to error.Terminated
    }

    pub fn deinit(state: *State) void {
        state.api.socket.close();
        state.collect.socket.close();
        state.announce.socket.close();

        state.ctx.deinit();
        // threads should get error.Terminated right about now
        state.join();
        state.db.deinit();
        state.arena.deinit();
        state.* = undefined;
    }

    pub fn join(state: *State) void {
        state.announce.thread.join();
        state.collect.thread.join();
        state.api.thread.join();
    }
};

pub fn main() !void {
    const config_buf = if (std.os.argv.len < 2) "" else try std.fs.cwd().readFileAlloc(std.heap.c_allocator, std.mem.span(std.os.argv[1]), 10 << 20);
    defer std.heap.c_allocator.free(config_buf);

    var s: State = undefined;
    try s.init(config_buf);
    defer s.deinit();
    s.join();
}
