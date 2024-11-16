const std = @import("std");

fn obj(b: *std.Build, path: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const o = b.addObject(.{
        .name = std.fs.path.stem(std.fs.path.basename(path)),
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    o.addIncludePath(b.path("src"));
    return o;
}

fn linkZmq(b: *std.Build, exe: anytype, target: std.Build.ResolvedTarget) void {
    if (!b.systemIntegrationOption("zmq", .{})) {
        const dep = b.lazyDependency(
            "libzmq",
            .{
                .target = target,
                .release = true,
                .curve = true,
                .sodium = true,
                .shared = false,
            },
        ) orelse return;
        exe.linkLibrary(dep.artifact("zmq"));
    } else {
        if (@hasDecl(@TypeOf(exe.*), "linkSystemLibrary2")) {
            exe.linkSystemLibrary2("zmq", .{});
        } else {
            exe.linkSystemLibrary("zmq", .{});
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const llvm = b.option(bool, "llvm", "use llvm (debug false)") orelse (optimize != .Debug);

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const list_parser = obj(b, "src/masscan_list_parser.zig", target, optimize);

    // const masscan_parser_static = b.addStaticLibrary(.{
    //     .name = "masscan_parser",
    //     .target = target,
    //     .optimize = optimize,
    //     .link_libc = true,
    // });

    // masscan_parser_static.addObject(list_parser);

    // const masscan_parser_shared = b.addSharedLibrary(.{
    //     .name = "masscan_parser",
    //     .target = target,
    //     .optimize = optimize,
    //     .link_libc = true,
    // });
    // masscan_parser_shared.addObject(list_parser);

    const zlzmq = b.dependency("zlzmq", .{}).module("zlzmq");
    linkZmq(b, zlzmq, target);

    const test_masscan_parser = b.addTest(.{
        .name = "test_masscan_parser",
        .root_source_file = b.path("src/test_masscan_parser.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .use_lld = llvm,
        .use_llvm = llvm,
    });
    test_masscan_parser.addIncludePath(b.path("src"));
    test_masscan_parser.addObject(list_parser);

    const discovery = b.addExecutable(.{
        .name = "discovery",
        .root_source_file = b.path("src/discovery.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    discovery.addIncludePath(b.path("src"));
    discovery.root_module.addImport("zmq", zlzmq);
    linkZmq(b, discovery, target);

    const openseekerctl = b.addExecutable(.{
        .name = "openseekerctl",
        .root_source_file = b.path("src/openseekerctl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    openseekerctl.addIncludePath(b.path("src"));
    openseekerctl.root_module.addImport("zmq", zlzmq);
    linkZmq(b, openseekerctl, target);

    const manager = b.addExecutable(.{
        .name = "manager",
        .root_source_file = b.path("src/manager.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .use_lld = llvm,
        .use_llvm = llvm,
    });
    manager.root_module.addImport("zmq", zlzmq);
    linkZmq(b, manager, target);
    manager.root_module.addImport("sqlite", sqlite.module("sqlite"));
    manager.linkLibrary(sqlite.artifact("sqlite"));

    const gen_keypair = b.addExecutable(.{
        .name = "gen_keypair",
        .root_source_file = b.path("src/gen_keypair.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .use_lld = llvm,
        .use_llvm = llvm,
    });
    gen_keypair.root_module.addImport("zmq", zlzmq);
    linkZmq(b, gen_keypair, target);

    b.installArtifact(discovery);
    b.installArtifact(openseekerctl);
    b.installArtifact(manager);
    b.installArtifact(gen_keypair);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(test_masscan_parser).step);
}
