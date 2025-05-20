const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const aro = b.dependency("aro", .{
        .target = target,
        .optimize = optimize,
    });

    const main = b.addModule("arocc", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    main.addImport("aro", aro.module("aro"));

    const exe = b.addExecutable(.{
        .name = "arocc",
        .root_module = main,
    });
    b.installArtifact(exe);
}
