const std = @import("std");
pub const h = @cImport({
    @cInclude("masscan.h");
    @cInclude("masscan_list_parser.h");
    @cInclude("masscan_binary_parser.h");
});

pub const SourceReader = struct {
    source: h.masscan_parser_source,

    pub const ReadError = std.fs.File.ReadError;
    pub const Reader = std.io.Reader(*SourceReader, ReadError, read);

    fn read(sr: *SourceReader, buf: []u8) ReadError!usize {
        return switch (sr.source.type) {
            h.MASSCAN_PARSER_SRC_FD => try (std.fs.File{ .handle = sr.source.v.fd }).read(buf),
            else => unreachable,
        };
    }

    pub fn reader(sr: *SourceReader) Reader {
        return .{
            .context = sr,
        };
    }
};
