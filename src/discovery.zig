const std = @import("std");
const zmq = @import("zmq");
const wire = @import("wire.zig");
const conf = @import("conf.zig");
const m = @import("masscan.zig");
const TempPath = @import("TempPath.zig");
const multipart = @import("multipart.zig");

const Config = struct {
    packets_per_sec: u32 = 1000,

    announce: []const u8 = "tcp://127.0.0.1:35001",
    announce_server_key: ?[]const u8 = null,

    collect: []const u8 = "tcp://127.0.0.1:35002",
    collect_server_key: ?[]const u8 = null,
};

var is_exiting: bool = false;
var failed: bool = true;
var previous_range = wire.Range.invalid;

pub fn main() !void {
    const config_buffer = if (std.os.argv.len < 2) "" else try std.fs.cwd().readFileAlloc(std.heap.c_allocator, std.mem.span(std.os.argv[1]), 1 << 20);
    defer std.heap.c_allocator.free(config_buffer);
    const config = try conf.parse(Config, config_buffer);

    var fifo_p = try TempPath.init();
    defer fifo_p.deinit();

    if (std.os.linux.mknodat(fifo_p.dir.fd, fifo_p.basename(), 0o600 | std.os.linux.S.IFIFO, 0) != 0) return error.MkfifoFailed;

    var exclude_p = try TempPath.init();
    defer exclude_p.deinit();

    const ctx = try zmq.Context.init();
    defer ctx.deinit();

    const announce = try ctx.socket(.req);
    defer announce.close();

    const collect = try ctx.socket(.push);
    defer collect.close();

    {
        var opt: c_int = 5000;
        try announce.setOption(.connect_timeout, &opt, @sizeOf(c_int));
        try announce.setOption(.rcvtimeo, &opt, @sizeOf(c_int));
        try announce.setOption(.sndtimeo, &opt, @sizeOf(c_int));
        try collect.setOption(.connect_timeout, &opt, @sizeOf(c_int));
        try collect.setOption(.rcvtimeo, &opt, @sizeOf(c_int));
        try collect.setOption(.sndtimeo, &opt, @sizeOf(c_int));
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    while (true) {
        _ = arena.reset(.{ .retain_with_limit = 8 << 20 });
        loopInner(
            config,
            announce,
            collect,
            &arena,
            &fifo_p,
            &exclude_p,
        ) catch |err| {
            std.log.scoped(.discovery).err("{} {?}", .{ err, @errorReturnTrace() });
            failed = true;
            // FIXME: error handling
        };
    }
}

fn loopInner(
    config: Config,
    announce: *zmq.Socket,
    collect: *zmq.Socket,
    arena: *std.heap.ArenaAllocator,
    fifo_p: *const TempPath,
    exclude_p: *const TempPath,
) !void {
    _ = collect; // autofix
    try wire.send(
        wire.AnnounceHeader{
            .kind = .discovery,
        },
        announce,
        .{ .sndmore = true },
    );
    try wire.send(
        wire.DiscoveryRequest{
            .flags = .{
                .is_first_request = !previous_range.isValid(),
                .failed = failed,
                .is_exiting = is_exiting,
            },
            .packets_per_sec = config.packets_per_sec,
            .previous_range = previous_range,
        },
        announce,
        .{},
    );
    const fm = try multipart.recv(announce, arena.allocator());
    defer multipart.deinit(fm, arena.allocator());

    if (fm.len != 3) return error.BadLength;

    const range_to_scan = try wire.recvMP(wire.Range, &fm[0]);
    if (!range_to_scan.isValid()) return error.InvalidRange;

    if (fm[1].len % @sizeOf(wire.Range) != 0) return error.InvalidExcludes;

    var args = std.ArrayList([]const u8).init(arena.allocator());
    defer args.deinit();

    try args.append("masscan");

    try args.appendSlice(&.{ "-oL", fifo_p.path() });

    var rate_buf: [32]u8 = undefined;
    const rate = rate_buf[0..std.fmt.formatIntBuf(&rate_buf, config.packets_per_sec, 10, .lower, .{})];

    try args.appendSlice(&.{ "--rate", rate });
    try args.appendSlice(&.{ "--excludefile", exclude_p.path() });

    var child = std.process.Child.init(args.items, arena.allocator());
    try child.spawn();
    defer _ = child.wait() catch {};

    const fp = m.h.fopen(fifo_p.path(), "rb") orelse return error.OpenFailed;
    defer _ = m.h.fclose(fp);

    const mlp = m.h.mlp_init(.{
        .type = m.h.MASSCAN_PARSER_SRC_FILEP,
        .v = .{ .fp = fp },
    }) orelse return error.MlpInitFailed;
    defer m.h.mlp_destroy(mlp);

    while (true) {
        var r: m.h.masscan_record = undefined;
        const res = m.h.mlp_next_record(mlp, &r);

        if (res == 0) break;
        if (res < 0) return error.ReadError;
        if (r.ip.version != 4 or r.is_open == 0) continue;
    }
}
