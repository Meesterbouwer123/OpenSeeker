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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const linkage = b.option(std.builtin.LinkMode, "linkage", "How to link, defaults to dynamic") orelse .dynamic;

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

    const test_masscan_parser = b.addTest(.{
        .name = "test_masscan_parser",
        .root_source_file = b.path("src/test_masscan_parser.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_masscan_parser.addIncludePath(b.path("src"));
    test_masscan_parser.addObject(list_parser);

    const discovery = b.addExecutable(.{
        .name = "discovery",
        .root_source_file = b.path("src/discovery.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });
    discovery.addIncludePath(b.path("src"));
    discovery.linkSystemLibrary("zmq");

    const manager = b.addExecutable(.{
        .name = "manager",
        .root_source_file = b.path("src/manager.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });
    manager.linkSystemLibrary("zmq");
    manager.root_module.addImport("sqlite", sqlite.module("sqlite"));
    manager.linkLibrary(sqlite.artifact("sqlite"));

    const gen_keypair = b.addExecutable(.{
        .name = "gen_keypair",
        .root_source_file = b.path("src/gen_keypair.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });
    gen_keypair.linkSystemLibrary("zmq");

    b.installArtifact(discovery);
    b.installArtifact(manager);
    b.installArtifact(gen_keypair);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(test_masscan_parser).step);
}
