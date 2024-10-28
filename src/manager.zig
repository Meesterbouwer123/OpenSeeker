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

    pub fn handleDiscoveryRequest(announce: *Announce, subnets_to_scan: anytype, excluded_hosts: anytype) !void {
        _ = subnets_to_scan; // autofix
        _ = excluded_hosts; // autofix
        const discovery_request = try wire.recv(wire.DiscoveryRequest, announce.socket, .{});

        _ = discovery_request; // autofix

    }

    pub fn worker(announce: *Announce) void {
        const state: *State = @fieldParentPtr("announce", announce);
        var hosts_to_legacy = state.db.prepare("SELECT ip, port FROM pending_legacy ORDER BY priority DESC LIMIT ?") catch @panic("bruh");
        var hosts_to_slp = state.db.prepare("SELECT ip, port FROM pending_ping ORDER BY priority DESC LIMIT ?") catch @panic("bruh");
        var hosts_to_join = state.db.prepare("SELECT ip, port FROM pending_join ORDER BY priority DESC LIMIT ?") catch @panic("bruh");
        var subnets_to_scan = state.db.prepare("SELECT prefix, msbs FROM pending_discovery ORDER BY priority DESC LIMIT ?") catch @panic("bruh");
        var excluded_hosts = state.db.prepare(
            \\SELECT excluded.prefix, excluded.msbs
            \\FROM excluded
            \\WHERE EXISTS (
            \\    SELECT 1
            \\    FROM pending_legacy
            \\    WHERE excluded.prefix = pending_legacy.ip
            \\) OR EXISTS (
            \\    SELECT 1
            \\    FROM pending_ping
            \\    WHERE excluded.prefix = pending_legacy.ip
            \\) OR EXISTS (
            \\    SELECT 1
            \\    FROM pending_
            \\    WHERE excluded.prefix = pending_legacy.ip
            \\)
        ) catch @panic("bruh");

        while (true) {
            hosts_to_legacy.reset();
            hosts_to_slp.reset();
            hosts_to_join.reset();
            subnets_to_scan.reset();
            excluded_hosts.reset();

            discard: {
                const nb_discarded = announce.socket.discardRemainingFrames(.{}) catch |err| {
                    log.warn("discarding: {s}", .{@errorName(err)});
                    break :discard;
                };
                if (nb_discarded != 0) log.warn("{d} frames discarded", .{nb_discarded});
            }

            const header = wire.recv(wire.AnnounceHeader, announce.socket, .{}) catch |err| switch (err) {
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
                .slp => handleSlpRequest(announce, &hosts_to_legacy, &hosts_to_slp, &hosts_to_join),
                .discovery => handleDiscoveryRequest(announce, &subnets_to_scan, &excluded_hosts),

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

pub const State = struct {
    config: Config,
    ctx: *zmq.Context,
    db: sqlite.Db,

    announce: Announce,

    collect: *zmq.Socket,
    collect_thread: std.Thread,

    api: *zmq.Socket,
    api_thread: std.Thread,

    arena: std.heap.ArenaAllocator,

    pub const setup_sql =
        \\PRAGMA user_version = 0;
        \\PRAGMA foreign_keys = ON;
        \\
        \\CREATE TABLE IF NOT EXISTS excluded (
        \\    prefix INT NOT NULL CHECK(prefix >= 0 AND prefix < 1 << 32 AND prefix & (0xffffffff >> msbs) == 0),
        \\    msbs INT NOT NULL CHECK(msbs >= 0 AND msbs <= 32),
        \\    reason TEXT,
        \\    PRIMARY KEY(prefix, msbs)
        \\) STRICT;
        \\
        \\CREATE INDEX IF NOT EXISTS idx_excluded_msbs ON excluded (msbs);
        \\
        \\CREATE TABLE IF NOT EXISTS pending_discovery (
        \\    prefix INT NOT NULL CHECK(prefix >= 0 AND prefix < 1 << 32 AND prefix & (0xffffffff >> msbs) == 0),
        \\    msbs INT NOT NULL CHECK(msbs >= 0 AND msbs <= 32),
        \\    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
        \\    PRIMARY KEY(prefix, msbs)
        \\) STRICT;
        \\
        \\CREATE INDEX IF NOT EXISTS idx_pending_discovery_priority ON pending_discovery (priority DESC);
        \\
        \\CREATE TABLE IF NOT EXISTS pending_ping (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
        \\    PRIMARY KEY(ip, port)
        \\) STRICT;
        \\
        \\CREATE INDEX IF NOT EXISTS idx_pending_ping_priority ON pending_ping (priority DESC);
        \\
        \\CREATE TABLE IF NOT EXISTS pending_legacy (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
        \\    PRIMARY KEY(ip, port)
        \\) STRICT;
        \\
        \\CREATE INDEX IF NOT EXISTS idx_pending_legacy_priority ON pending_legacy (priority DESC);
        \\
        \\CREATE TABLE IF NOT EXISTS pending_join (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
        \\    PRIMARY KEY(ip, port)
        \\) STRICT;
        \\
        \\CREATE INDEX IF NOT EXISTS idx_pending_join_priority ON pending_join (priority DESC);
        \\
        \\CREATE TABLE IF NOT EXISTS servers (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    PRIMARY KEY(ip, port)
        \\) STRICT;
        \\
        \\
        \\CREATE TABLE IF NOT EXISTS discoveries (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        \\
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS favicons (
        \\    data BLOB PRIMARY KEY
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS failed_pings (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS successful_pings (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        \\    enforces_secure_chat INT,
        \\    prevents_chat_reports INT,
        \\    version_name TEXT,
        \\    version_protocol INT NOT NULL,
        \\    favicon_id INT,
        \\    max_players INT,
        \\    current_players INT,
        // because the description can contain arbitrary json, we save arbitrary json that we can
        // render, except when it's just text.
        \\    description_json TEXT,
        \\    description_text TEXT,
        \\    extra_json TEXT,
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port),
        \\    FOREIGN KEY (favicon_id) REFERENCES favicons(_rowid_)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS failed_legacy_pings (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS successful_legacy_pings (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        \\    max_players INT NOT NULL,
        \\    current_players INT NOT NULL,
        \\    description TEXT NOT NULL,
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS failed_joins (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS successful_joins (
        \\    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
        \\    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
        \\    timestamp INT NOT NULL,
        // TODO: which information can be gained from joining?
        \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS players (
        \\    uuid_low INT NOT NULL,
        \\    uuid_high INT NOT NULL,
        \\    name BLOB NOT NULL,
        \\   PRIMARY KEY (uuid_high, uuid_low)
        \\) STRICT;
        \\
        \\CREATE TABLE IF NOT EXISTS ping_players (
        \\    ping_id INT NOT NULL,
        \\    player_uuid INT NOT NULL,
        \\    PRIMARY KEY (ping_id, player_uuid),
        \\    FOREIGN KEY (ping_id) REFERENCES successful_pings(_rowid_),
        \\    FOREIGN KEY (player_uuid) REFERENCES players(uuid)
        \\) STRICT;
    ;

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
            setup_sql,
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
        state.collect = collect;
        state.api = api;

        state.announce.thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            Announce.worker,
            .{&state.announce},
        );
        errdefer state.announce.thread.detach(); // thread will terminate on its own due to error.Terminated

        state.api_thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            apiWorker,
            .{state},
        );
        errdefer state.api_thread.detach(); // thread will terminate on its own due to error.Terminated

        state.collect_thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            collectWorker,
            .{state},
        );
        errdefer state.collect_thread.detach(); // thread will terminate on its own due to error.Terminated
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

    fn collectWorker(state: *State) void {
        _ = state;
    }

    fn apiWorker(state: *State) void {
        _ = state;
    }
};

pub fn main() !void {
    try std.io.getStdOut().writeAll(State.setup_sql);

    const config_buf = if (std.os.argv.len < 2) "" else try std.fs.cwd().readFileAlloc(std.heap.c_allocator, std.mem.span(std.os.argv[1]), 10 << 20);
    defer std.heap.c_allocator.free(config_buf);

    var s: State = undefined;
    try s.init(config_buf);
    defer s.deinit();
}
