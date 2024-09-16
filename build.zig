const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const demo = b.addExecutable(.{
        .name = "demo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/demo.zig"),
    });
    b.installArtifact(demo);

    const run = b.step("run", "Run the demo");
    run.dependOn(&b.addRunArtifact(demo).step);

    const test_exe = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/test.zig"),
    });
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&b.addRunArtifact(test_exe).step);
}
