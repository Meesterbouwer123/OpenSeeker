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

    const ventilator = b.addExecutable(.{
        .name = "ventilator",
        .root_source_file = b.path("src/ventilator.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });
    ventilator.addIncludePath(b.path("src"));
    ventilator.linkSystemLibrary("zmq");
    b.installArtifact(ventilator);

    const masscan_dispatcher = b.addExecutable(.{
        .name = "masscan_dispatcher",
        .root_source_file = b.path("src/masscan_dispatcher.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });
    masscan_dispatcher.addIncludePath(b.path("src"));
    masscan_dispatcher.addObject(list_parser);
    masscan_dispatcher.linkSystemLibrary("zmq");
    b.installArtifact(masscan_dispatcher);

    const slper = b.addExecutable(.{
        .name = "slper",
        .root_source_file = b.path("src/slper.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });
    slper.addIncludePath(b.path("src"));
    slper.linkSystemLibrary("zmq");
    b.installArtifact(slper);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(test_masscan_parser).step);
}
