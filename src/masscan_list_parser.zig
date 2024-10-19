const std = @import("std");
const m = @import("masscan.zig");

const ListParser = struct {
    src: m.SourceReader,
    buffered: std.io.BufferedReader(4096, m.SourceReader.Reader),

    pub fn init(source: m.h.masscan_parser_source) callconv(.C) ?*ListParser {
        const p = std.heap.c_allocator.create(ListParser) catch return null;
        p.src = .{ .source = source };
        p.buffered = std.io.bufferedReaderSize(4096, p.src.reader());
        return p;
    }

    pub fn destroy(lp: *ListParser) callconv(.C) void {
        std.heap.c_allocator.destroy(lp);
    }

    pub fn next(lp: *ListParser, r: *m.h.masscan_record) callconv(.C) c_int {
        var buf: [m.h.MASSCAN_LIST_PARSER_MAX_LINE_LEN]u8 = undefined;

        r.* = .{};

        while (true) {
            const line = lp.buffered.reader().readUntilDelimiter(&buf, '\n') catch |err| switch (err) {
                error.EndOfStream => return 0,
                else => return -1,
            };

            if (std.mem.startsWith(u8, line, "#")) {
                continue;
            }

            var iter = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

            const state = iter.next() orelse continue;

            if (std.mem.eql(u8, state, "open")) {
                r.is_open = 1;
            } else if (std.mem.eql(u8, state, "closed")) {
                r.is_open = 0;
            } else continue;

            const proto = iter.next() orelse continue;

            if (std.mem.eql(u8, proto, "tcp")) {
                r.ip_proto = 6;
            } else if (std.mem.eql(u8, proto, "udp")) {
                r.ip_proto = 17;
            } else continue;

            const port = iter.next() orelse continue;
            r.port = std.fmt.parseInt(c_ushort, port, 10) catch continue;

            const ip = iter.next() orelse continue;
            // TODO
            r.ip.version = 4;

            r.ip.v.ipv4 = parse: {
                var periods = std.mem.splitScalar(u8, ip, '.');
                const a: u32 = std.fmt.parseInt(u8, periods.first(), 10) catch continue;
                const b: u32 = std.fmt.parseInt(u8, periods.next() orelse continue, 10) catch continue;
                const c: u32 = std.fmt.parseInt(u8, periods.next() orelse continue, 10) catch continue;
                const d: u32 = std.fmt.parseInt(u8, periods.next() orelse continue, 10) catch continue;
                break :parse a << 24 | b << 16 | c << 8 | d;
            };

            const timestamp = iter.next() orelse continue;

            r.timestamp = std.fmt.parseInt(c_ulong, timestamp, 10) catch continue;

            break;
        }

        return 1;
    }
};

comptime {
    @export(&ListParser.init, .{ .name = "mlp_init" });
    @export(&ListParser.destroy, .{ .name = "mlp_destroy" });
    @export(&ListParser.next, .{ .name = "mlp_next_record" });
}
