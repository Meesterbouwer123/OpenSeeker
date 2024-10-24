const std = @import("std");
const zmq = @import("zmq.zig");
const wire = @import("wire.zig");
const sqlite = @import("sqlite");

pub fn main() !void {
    const ctx = try zmq.Context.init();
    defer ctx.deinit();

    if (std.os.argv.len < 5) {
        std.log.info("args: <announce endpoint> <collect endpoint> <api endpoint> <control endpoint>", .{});
        return error.TooFewArguments;
    }

    const announce = try ctx.socket(.rep);
    defer announce.close();
    try announce.bind(std.os.argv[1]);

    const collect = try ctx.socket(.pull);
    defer collect.close();
    try collect.bind(std.os.argv[2]);

    const api = try ctx.socket(.rep);
    defer api.close();
    try api.bind(std.os.argv[3]);

    const control = try ctx.socket(.rep);
    defer control.close();
    try control.bind(std.os.argv[4]);

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "openseeker_manager.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    try db.exec(
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
