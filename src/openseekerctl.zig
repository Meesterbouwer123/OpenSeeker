const std = @import("std");
const zmq = @import("zmq");
const wire = @import("wire.zig");

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{.scope = .wire_send, .level = .info},
    },
};

pub fn main() !void {
    const args = std.os.argv;
    if (args.len < 2) {
        std.log.err("{s} <API socket> [server public key] [own secret key]", .{args[0]});
        return;
    }

    const ctx = try zmq.Context.init();
    defer ctx.deinit();

    const api_req = try ctx.socket(.req);
    defer api_req.close();

    const interactive = std.io.getStdIn().isTty();

    if (args.len > 2) {
        const server_key_len = std.mem.len(args[2]);
        if (server_key_len != 40) return error.InvalidServerKey;
        try api_req.setOption(.curve_serverkey, args[2], server_key_len);
        if (args.len > 3) {
            const client_key_len = std.mem.len(args[3]);
            if (client_key_len != 40) return error.InvalidSecretKey;
            try api_req.setOption(.curve_secretkey, args[3], client_key_len);
            {
                var public_buf: [40:0]u8 = undefined;
                try zmq.curve.public(&public_buf, @ptrCast(args[3][0..41]));
                try api_req.setOption(.curve_publickey, &public_buf, 40);
            }
        } else {
            var public_buf: [40:0]u8 = undefined;
            var secret_buf: [40:0]u8 = undefined;
            try zmq.curve.keypair(&public_buf, &secret_buf);
            try api_req.setOption(.curve_publickey, &public_buf, 40);
            try api_req.setOption(.curve_secretkey, &secret_buf, 40);
        }
    }

    try api_req.connectZ(args[1]);

    const stdin = std.io.getStdIn();

    const stdout = std.io.getStdOut();
    var buf_stdout = std.io.bufferedWriter(stdout.writer());
    defer buf_stdout.flush() catch {};
    const out = buf_stdout.writer();

    const help =
        \\commands:
        \\discover <range> <prio>
        \\discover_remove <range>
        \\exclude <range>
        \\unexclude <range>
        \\authorize <public key>
        \\revoke <public key>
        \\---
        \\
    ;

    while (true) {
        if (interactive) try out.writeAll(">");
        try buf_stdout.flush();

        var buf: [4096]u8 = undefined;
        const line = stdin.reader().readUntilDelimiter(&buf, '\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (std.mem.eql(u8, line, "exit")) break;
        var iter = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

        const command = iter.next() orelse {
            try out.writeAll("no command\n");
            continue;
        };

        if (std.mem.eql(u8, command, "help")) {
            try out.writeAll(help);
            continue;
        } else if (std.mem.eql(u8, command, "discover")) {
            const arg = iter.next() orelse {
                try out.writeAll("specify range\n");
                continue;
            };
            const arg2 = iter.next() orelse {
                try out.writeAll("specify prio\n");
                continue;
            };
            const range = try wire.Range.fromString(arg);
            const prio = try std.fmt.parseInt(u8, arg2, 0);
            try wire.send(wire.ApiHeader{ .kind = .enqueue_range }, api_req, .{ .sndmore = true });
            try wire.send(range, api_req, .{ .sndmore = true });
            try wire.send(prio, api_req, .{});
        } else if (std.mem.eql(u8, command, "discover_remove")) {
            const arg = iter.next() orelse {
                try out.writeAll("specify range\n");
                continue;
            };
            const range = try wire.Range.fromString(arg);
            try wire.send(wire.ApiHeader{ .kind = .remove_range }, api_req, .{ .sndmore = true });
            try wire.send(range, api_req, .{});
        } else if (std.mem.eql(u8, command, "exclude")) {
            const arg = iter.next() orelse {
                try out.writeAll("specify range\n");
                continue;
            };
            const range = try wire.Range.fromString(arg);
            try wire.send(wire.ApiHeader{ .kind = .exclude_range }, api_req, .{ .sndmore = true });
            try wire.send(range, api_req, .{});
        } else if (std.mem.eql(u8, command, "unexclude")) {
            const arg = iter.next() orelse {
                try out.writeAll("specify range\n");
                continue;
            };
            const range = try wire.Range.fromString(arg);
            try wire.send(wire.ApiHeader{ .kind = .unexclude_range }, api_req, .{ .sndmore = true });
            try wire.send(range, api_req, .{});
        } else if (std.mem.eql(u8, command, "authorize")) {
            const arg = iter.next() orelse {
                try out.writeAll("specify z85-encoded public key\n");
                continue;
            };
            if (arg.len != zmq.z85.encodedLen(32) - 1) {
                try out.writeAll("specify z85-encoded public key\n");
                continue;
            }

            try wire.send(wire.ApiHeader{ .kind = .authorize_public_key }, api_req, .{ .sndmore = true });
            const zt = try std.heap.c_allocator.dupeZ(u8, arg);
            var m = try zmq.Message.initOwned(zt.ptr[0 .. zt.len + 1], wire.wireFree, null);
            try m.send(api_req, .{});
        } else if (std.mem.eql(u8, command, "revoke")) {
            const arg = iter.next() orelse {
                try out.writeAll("specify z85-encoded public key\n");
                continue;
            };
            if (arg.len != zmq.z85.encodedLen(32) - 1) {
                try out.writeAll("specify z85-encoded public key\n");
                continue;
            }

            try wire.send(wire.ApiHeader{ .kind = .remove_public_key }, api_req, .{ .sndmore = true });
            const zt = try std.heap.c_allocator.dupeZ(u8, arg);
            var m = try zmq.Message.initOwned(zt.ptr[0 .. zt.len + 1], wire.wireFree, null);
            try m.send(api_req, .{});
        } else {
            try out.writeAll("invalid command\n");
            continue;
        }

        while (true) {
            var reply = zmq.Message.init();
            defer reply.deinit();
            try reply.recv(api_req, .{});
            if (interactive) try out.writeAll("<");
            try out.print("{s}\n", .{reply.data()});
            if (!reply.hasMore()) break;
        }
    }
    if (interactive) try out.writeByte('\n');
    try buf_stdout.flush();
}
