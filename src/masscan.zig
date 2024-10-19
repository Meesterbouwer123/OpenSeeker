const std = @import("std");
pub const h = @cImport({
    @cInclude("masscan.h");
    @cInclude("masscan_list_parser.h");
    @cInclude("masscan_binary_parser.h");
});

pub const SourceReader = struct {
    source: h.masscan_parser_source,

    pub const ReadError = std.fs.File.ReadError || error{CError};
    pub const Reader = std.io.Reader(*SourceReader, ReadError, read);

    fn read(sr: *SourceReader, buf: []u8) ReadError!usize {
        return switch (sr.source.type) {
            h.MASSCAN_PARSER_SRC_FILEP => {
                const n = h.fread(buf.ptr, 1, buf.len, sr.source.v.fp);
                // TODO: translate errno
                if (n != buf.len and h.ferror(sr.source.v.fp) != 0) return error.CError;
                return n;
            },
            h.MASSCAN_PARSER_SRC_MEMORY => {
                const to_copy = @min(buf.len, sr.source.v.mem.len);
                @memcpy(buf[0..to_copy], sr.source.v.mem.ptr[0..to_copy]);
                sr.source.v.mem.ptr += to_copy;
                return to_copy;
            },
            else => unreachable,
        };
    }

    pub fn reader(sr: *SourceReader) Reader {
        return .{
            .context = sr,
        };
    }
};

test "read from memory" {
    const memory = "meow meow";
    var rd = SourceReader{
        .source = .{ .type = h.MASSCAN_PARSER_SRC_MEMORY, .v = .{
            .mem = .{ .ptr = @ptrCast(memory.ptr), .len = memory.len },
        } },
    };

    var tmp: [9]u8 = undefined;
    try rd.reader().readNoEof(&tmp);
    try std.testing.expectEqualStrings(memory, &tmp);
}
