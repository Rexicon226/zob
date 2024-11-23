const std = @import("std");
const tests = @import("test/tests.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compiler = b.addExecutable(.{
        .name = "compiler",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/compiler.zig"),
    });
    b.installArtifact(compiler);

    const run = b.step("run", "Run the compiler");
    const run_artifact = b.addRunArtifact(compiler);
    run.dependOn(&run_artifact.step);
    if (b.args) |args| run_artifact.addArgs(args);

    const test_exe = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/test.zig"),
    });

    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&b.addRunArtifact(test_exe).step);

    const test_case = b.step("test-cases", "Runs IR case tests");
    try tests.addCases(b, test_case, "mir", compiler);
    try tests.addCases(b, test_case, "rewrites", compiler);

    test_step.dependOn(test_case);
}
