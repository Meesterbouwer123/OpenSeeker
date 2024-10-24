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
    api_curve_privkey: ?[]const u8 = null,
    query_curve_allowed_pubkey: ?[]const u8 = null,

    control_curve_admin_pubkey: ?[]const u8 = null,
    // maybe we want an array of allowed public keys? or we just use a token... but that provides
    // fewer guarantees
    control_curve_allowed_pubkey: ?[]const u8 = null,
};

pub const State = struct {
    config: Config,
    ctx: *zmq.Context,
    announce: *zmq.Socket,
    announce_thread: std.Thread,
    collect: *zmq.Socket,
    collect_thread: std.Thread,
    api: *zmq.Socket,
    api_thread: std.Thread,
    db: sqlite.Db,

    pub fn init(state: *State, config_buf: []const u8) !void {
        const config = try conf.parse(Config, config_buf);

        const ctx = try zmq.Context.init();
        errdefer ctx.deinit();

        const announce = try ctx.socket(.rep);
        errdefer announce.close();
        try announce.bind(std.os.argv[1]);

        const collect = try ctx.socket(.pull);
        errdefer collect.close();
        try collect.bind(std.os.argv[2]);

        const api = try ctx.socket(.rep);
        errdefer api.close();
        try api.bind(std.os.argv[3]);

        const zt_file_name = try std.heap.c_allocator.dupeZ(u8, config.db_path);
        defer std.heap.c_allocator.free(zt_file_name);

        var db = try sqlite.Db.init(.{
            .mode = sqlite.Db.Mode{ .File = zt_file_name },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .MultiThread,
        });
        errdefer db.deinit();

        state.* = .{
            .config = config,
            .ctx = ctx,
            .announce = announce,
            .announce_thread = undefined,
            .collect = collect,
            .collect_thread = undefined,
            .api = api,
            .api_thread = undefined,
            .db = db,
        };
        errdefer state.* = undefined;

        state.announce_thread = try std.Thread.spawn(
            .{ .stack_size = 1 << 20, .allocator = std.heap.c_allocator },
            announceWorker,
            .{state},
        );
        errdefer state.announce_thread.detach(); // thread will terminate on its own due to error.Terminated

        state.announce_thread = try std.Thread.spawn(
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
        state.announce.close();

        state.ctx.deinit();
        // threads should get error.Terminated right about now
        state.join();
        state.db.deinit();
        state.* = undefined;
    }

    pub fn join(state: *State) void {
        state.announce_thread.join();
        state.collect_thread.join();
        state.api_thread.join();
    }


    fn announceWorker(state: *State) void {
        _ = state;
    }

    fn collectWorker(state: *State) void {
        _ = state;
    }

    fn apiWorker(state: *State) void {
        _ = state;
    }

    pub fn initDb(state: *State) !void {
        // we use execDynamic here because the query is too long to validate at compile time
        try state.db.execDynamic(
            \\PRAGMA schema.user_version = 0;
            \\PRAGMA foreign_keys = ON;
            \\
            \\CREATE TABLE IF NOT EXISTS excluded (
            \\    prefix UINT32 NOT NULL,
            \\    msbs UINT8 NOT NULL,
            \\    reason TEXT,
            \\    PRIMARY KEY(prefix, msbs)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS pending_discovery (
            \\    prefix UINT32 NOT NULL,
            \\    msbs UINT8 NOT NULL,
            \\    priority INTEGER,
            \\    PRIMARY KEY(prefix, msbs)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS pending_ping (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    priority INTEGER,
            \\    PRIMARY KEY(ip, port)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS pending_legacy (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    priority INTEGER,
            \\    PRIMARY KEY(ip, port)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS pending_join (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    priority INTEGER,
            \\    PRIMARY KEY(prefix, msbs)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS servers (
            \\    ip UINT32 NOT NULL,
            \\    port UINT6 NOT NULL,
            \\    PRIMARY KEY(ip, port)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS discoveries (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            \\
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS favicons (
            \\    data: BLOB PRIMARY KEY,
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS failed_pings (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port),
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS successful_pings (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            \\    enforces_secure_chat BOOL NOT NULL,
            \\    prevents_chat_reports BOOL NOT NULL,
            \\    version_name TEXT,
            \\    version_protocol INTEGER NOT NULL,
            \\    favicon_id INTEGER,
            \\    max_players INTEGER,
            \\    current_players INTEGER,
            // because the description can contain arbitrary json, we save arbitrary json that we can
            // render, except when it's just text.
            \\    description_json TEXT,
            \\    description_text TEXT,
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port),
            \\    FOREIGN KEY (favicon_id) REFERENCES favicons(_rowid_),
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS failed_legacy_pings (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port),
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS successful_legacy_pings (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            \\    max_players INTEGER,
            \\    current_players INTEGER,
            \\    description_json TEXT,
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS failed_joins (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port),
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS successful_joins (
            \\    ip UINT32 NOT NULL,
            \\    port UINT16 NOT NULL,
            \\    timestamp UINT NOT NULL,
            // TODO: which information can be gained from joining?
            \\    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS players (
            \\    uuid BINARY(128) PRIMARY KEY,
            \\    name CHARACTER(16) NOT NULL
            \\) STRICT;
            \\
            \\CREATE TABLE IF NOT EXISTS ping_players (
            \\    ping_id INTEGER,
            \\    player_uuid INTEGER,
            \\    PRIMARY KEY (ping_id, player_uuid),
            \\    FOREIGN KEY (ping_id) REFERENCES successful_pings(_rowid_),
            \\    FOREIGN KEY (player_uuid) REFERENCES players(uuid),
            \\) STRICT;
            \\
            \\PRAGMA integrity_check;
        , .{}, .{});
    }
};

pub fn main() !void {
    if (std.os.argv.len < 2) {
        std.debug.print("{s} <config file>", .{std.os.argv[0]});
        return error.TooFewArguments;
    }

    const config_buf = try std.fs.cwd().readFileAlloc(std.heap.c_allocator, std.mem.span(std.os.argv[1]), 10 << 20);
    defer std.heap.c_allocator.free(config_buf);

    var s: State = undefined;
    try s.init(config_buf);
    defer s.deinit();
    try s.initDb();

}
