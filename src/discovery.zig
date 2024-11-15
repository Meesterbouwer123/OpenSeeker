const std = @import("std");
const zmq = @import("zmq");
const wire = @import("wire.zig");
const conf = @import("conf.zig");

const Config = struct {
    name: []const u8 = "test",
    othervalue: []const u8 = "idk",
};

pub fn main() !void {
    const ctx = try zmq.Context.init();
    defer ctx.deinit();

    // load config from arguments
    if (std.os.argv.len < 2) {
        std.log.info("Too few arguments, expected a config file.\n", .{});
        return error.TooFewArguments;
    }

    const config_buffer = try std.fs.cwd().readFileAlloc(std.heap.c_allocator, std.mem.span(std.os.argv[1]), 1 << 20); // I assume that the config file won't surpass 1 MB, if it does: blame me (Meesterbouwer123)
    defer std.heap.c_allocator.free(config_buffer);
    const config = try conf.parse(Config, config_buffer);

    std.debug.print("Got config: name={s}, othervalue={s}\n", .{ config.name, config.othervalue });
}
