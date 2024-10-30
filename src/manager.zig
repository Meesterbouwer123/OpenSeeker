const std = @import("std");
const zmq = @import("zmq.zig");
const wire = @import("wire.zig");
const conf = @import("conf.zig");
const sqlite = @import("sqlite");

const Config = struct {
    db_path: []const u8 = "openseeker_manager.sqlite3",

    /// The announcement REP endpoint, where discoveries and pingers announce themselves.
    announce: []const u8 = "tcp://127.0.0.1:35001",

    /// The collection PULL endpoint, where discoveries and pingers send statuses.
    collect: []const u8 = "tcp://127.0.0.1:35002",

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

    const log = std.log.scoped(.announce);

    fn sendHosts(announce: *Announce, iter: anytype, alist: *std.ArrayListUnmanaged(wire.Host), rheader: wire.SlpResponseHeader, options: zmq.Socket.SendRecvOptions) !void {
        while (try iter.next(.{})) |host| {
            try alist.append(std.heap.c_allocator, host);
        }

        const buf = try alist.toOwnedSlice(std.heap.c_allocator);
        errdefer std.heap.c_allocator.free(buf);
        try wire.send(rheader, announce.socket, .{ .sndmore = true });

        var m = try zmq.Message.initOwned(std.mem.sliceAsBytes(buf), wire.wireFree, null);
        try m.send(announce.socket, options);
    }

    fn handleSlpRequest(announce: *Announce, hosts_to_legacy: anytype, hosts_to_slp: anytype, hosts_to_join: anytype) !void {
        const slp_req = try wire.recv(wire.SlpRequest, announce.socket, .{});

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

    pub fn handleDiscoveryRequest(announce: *Announce, get_discovery: anytype, excluded_ranges: anytype, finish_discovery: anytype) !void {
        const discovery_request = try wire.recv(wire.DiscoveryRequest, announce.socket, .{});

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
        try announce.socket.send(std.mem.sliceAsBytes(excluded), .{ .sndmore = true });
    }

    pub fn worker(state: *State) void {
        var get_discovery = state.db.prepare(@embedFile("sql/get_discovery.sql")) catch @panic("bruh");
        var finish_discovery = state.db.prepare(@embedFile("sql/finish_discovery.sql")) catch @panic("bruh");
        var get_legacy = state.db.prepare(@embedFile("sql/get_legacy.sql")) catch @panic("bruh");
        var get_ping = state.db.prepare(@embedFile("sql/get_ping.sql")) catch @panic("bruh");
        var get_join = state.db.prepare(@embedFile("sql/get_join.sql")) catch @panic("bruh");
        var excluded_ranges = state.db.prepare(@embedFile("sql/excluded_ranges.sql")) catch @panic("bruh");

        while (true) {
            get_discovery.reset();
            get_legacy.reset();
            get_ping.reset();
            get_join.reset();
            excluded_ranges.reset();

            discard: {
                const nb_discarded = state.announce.socket.discardRemainingFrames(.{}) catch |err| {
                    if (err == error.NotSocket) return;
                    log.warn("discarding: {s}", .{@errorName(err)});
                    break :discard;
                };
                if (nb_discarded != 0) log.warn("{d} frames discarded", .{nb_discarded});
            }

            const header = wire.recv(wire.AnnounceHeader, state.announce.socket, .{}) catch |err| switch (err) {
                error.NotSocket => return,
                error.Terminated => return,
                else => {
                    log.warn("header recv error {s}", .{@errorName(err)});
                    continue;
                },
            };

            if (header.version != .latest) {
                log.warn("incorrect version {d}", .{@intFromEnum(header.version)});
                continue;
            }

            const res = switch (header.kind) {
                .slp => state.announce.handleSlpRequest(&get_legacy, &get_ping, &get_join),
                .discovery => state.announce.handleDiscoveryRequest(&get_discovery, &excluded_ranges, &finish_discovery),

                _ => |k| {
                    log.warn("incorrect kind {d}", .{@intFromEnum(k)});
                    wire.send({}, state.announce.socket, .{}) catch {};
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

    const log = std.log.scoped(.collect);

    fn handleDiscovery(collect: *Collect, new_discovery: anytype) !void {
        const discovered_host = try wire.recv(wire.Host, collect.Socket, .{});
        try new_discovery.exec(.{}, .{
            .ip = discovered_host.ip,
            .port = discovered_host.port,
            .timestamp = try std.time.timestamp(),
            .priority = 10,
        });
    }

    fn handleLegacySuccess(collect: *Collect, success_legacy: anytype) !void {
        const discovered_host = try wire.recv(wire.Host, collect.socket, .{});
        const h = try wire.recv(wire.LegacySuccessHeader, collect.socket, .{});

        var m = zmq.Message.init();
        try m.recv(collect.socket, .{});
        defer m.deinit();

        try success_legacy.exec(.{}, .{
            .ip = discovered_host.ip,
            .port = discovered_host.port,
            .timestamp = try std.time.timestamp(),
            .max_players = h.max_players,
            .current_players = h.current_players,
            .motd = m.data(),
        });
    }

    fn handlePingSuccess(collect: *Collect, success_legacy: anytype) !void {
        const discovered_host = try wire.recv(wire.Host, collect.socket, .{});
        const h = try wire.recv(wire.PingSuccessHeader, collect.socket, .{});

        var m = zmq.Message.init();
        try m.recv(collect.socket, .{});
        defer m.deinit();

        try success_legacy.exec(.{}, .{
            .ip = discovered_host.ip,
            .port = discovered_host.port,
            .timestamp = try std.time.timestamp(),
            .max_players = h.max_players,
            .current_players = h.current_players,
            .motd = m.data(),
        });
    }

    fn handleFailure(collect: *Collect, failure: anytype) !void {
        const host = try wire.recv(wire.Host, collect.socket, .{});

        try failure.exec(.{}, .{
            .ip = host.ip,
            .port = host.port,
            .timestamp = try std.time.timestamp(),
        });
    }

    pub fn worker(state: *State) void {
        var new_discovery = state.db.prepare(@embedFile("sql/new_discovery.sql")) catch @panic("bruh");
        var success_legacy = state.db.prepare(@embedFile("sql/success_legacy.sql")) catch @panic("bruh");
        var failure_legacy = state.db.prepare(@embedFile("sql/failure_legacy.sql")) catch @panic("bruh");
        var success_ping = state.db.prepare(@embedFile("sql/success_ping.sql")) catch @panic("bruh");
        var failure_ping = state.db.prepare(@embedFile("sql/failure_ping.sql")) catch @panic("bruh");
        var success_join = state.db.prepare(@embedFile("sql/success_join.sql")) catch @panic("bruh");
        var failure_join = state.db.prepare(@embedFile("sql/failure_join.sql")) catch @panic("bruh");
        var favicon = state.db.prepare(@embedFile("sql/favicon.sql")) catch @panic("bruh");

        while (true) {
            new_discovery.reset();
            success_legacy.reset();
            failure_legacy.reset();
            success_ping.reset();
            failure_ping.reset();
            success_join.reset();
            failure_join.reset();
            favicon.reset();

            discard: {
                const nb_discarded = state.collect.socket.discardRemainingFrames(.{}) catch |err| {
                    if (err == error.NotSocket) return;
                    log.warn("discarding: {s}", .{@errorName(err)});
                    break :discard;
                };
                if (nb_discarded != 0) log.warn("{d} frames discarded", .{nb_discarded});
            }

            const header = wire.recv(wire.StatusHeader, state.collect.socket, .{}) catch continue;

            if (header.version != .latest) {
                log.warn("incorrect version {d}", .{@intFromEnum(header.version)});
                continue;
            }

            const res = switch (header.kind) {
                .discovery => handleDiscovery(&state.collect, &new_discovery),

                .legacy_success => handleLegacySuccess(&state.collect, &success_legacy),
                .legacy_failure => handleFailure(&state.collect, &failure_legacy),

                .ping_success => handlePingSuccess(&state.collect, &ping_success),
                .ping_failure => handleFailure(&state.collect, &failure_ping),

                .join_success => handleJoinSuccess(&state.collect, &join_success),
                .join_failure => handleFailure(&state.collect, &failure_join),

                _ => |k| {
                    log.warn("incorrect kind {d}", .{@intFromEnum(k)});
                    wire.send({}, state.collect.socket, .{}) catch {};
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

pub const Api = struct {
    socket: *zmq.Socket,
    thread: std.Thread,

    const log = std.log.scoped(.api);

    pub fn worker(state: *State) void {
        _ = state; // autofix

    }
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
        state.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer state.* = undefined;
        errdefer state.arena.deinit();

        const config = try conf.parse(Config, config_buf);

        const ctx = try zmq.Context.init();
        errdefer ctx.deinit();

        const announce = try ctx.socket(.rep);
        errdefer announce.close();
        try announce.bind(config.announce, state.arena.allocator());

        const collect = try ctx.socket(.pull);
        errdefer collect.close();
        try collect.bind(config.collect, state.arena.allocator());

        const api = try ctx.socket(.rep);
        errdefer api.close();

        if (config.api_curve_secret_key) |secret| {
            {
                const server: c_int = 1;
                try api.setOption(.curve_server, &server, @sizeOf(c_int));
            }
            try api.setOption(.curve_secretkey, secret.ptr, secret.len);
        }

        try api.bind(config.api, state.arena.allocator());

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
        state.announce = .{
            .socket = announce,
            .thread = undefined,
        };
        state.collect = .{
            .socket = collect,
            .thread = undefined,
        };
        state.api = .{
            .socket = api,
            .thread = undefined,
        };

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
        state.api.close();
        state.collect.close();
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
        state.collect_thread.join();
        state.api_thread.join();
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
