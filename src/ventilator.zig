const std = @import("std");
const zmq = @cImport(@cInclude("zmq.h"));

const masscan_bind_address = "tcp://*:31000";
const slper_bind_address = "tcp://*:31001";

pub fn main() !void {
    const ctx = zmq.zmq_ctx_new() orelse @panic("oom");
    defer _ = zmq.zmq_ctx_shutdown(ctx);

    const masscan = zmq.zmq_socket(ctx, zmq.ZMQ_PULL) orelse @panic("oom");
    defer _ = zmq.zmq_close(masscan);

    const slper = zmq.zmq_socket(ctx, zmq.ZMQ_PUSH);
    defer _ = zmq.zmq_close(slper);

    if (zmq.zmq_bind(masscan, masscan_bind_address) != 0) return error.BindFailed;
    if (zmq.zmq_bind(slper, slper_bind_address) != 0) return error.BindFailed;

    _ = zmq.zmq_proxy(masscan, slper, null);
    if (zmq.zmq_errno() == zmq.EINTR) return;
    return error.ProxyFailed;
}
