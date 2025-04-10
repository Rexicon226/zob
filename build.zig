const std = @import("std");
const cases = @import("test/cases.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compiler = b.addExecutable(.{
        .name = "compiler",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    const zob_mod = b.addModule("zob", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib.zig"),
    });

    b.installArtifact(compiler);

    const run = b.step("run", "Run the compiler");
    const run_artifact = b.addRunArtifact(compiler);
    run.dependOn(&run_artifact.step);
    if (b.args) |args| run_artifact.addArgs(args);

    const test_runner = b.addExecutable(.{
        .root_source_file = b.path("test/test_runner.zig"),
        .name = "test_runner",
        .target = target,
        .optimize = optimize,
    });
    test_runner.root_module.addImport("zob", zob_mod);

    const test_step = b.step("test", "Run the tests");

    const test_lib = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(test_lib).step);

    const single = b.option(
        bool,
        "single",
        "Runs a singular test provided in the args",
    ) orelse false;
    if (single) {
        const run_test = b.addRunArtifact(test_runner);
        if (b.args) |args| run_test.addArgs(args);
        test_step.dependOn(&run_test.step);
    } else {
        const test_case = b.step("test-cases", "Runs IR case tests");
        try cases.addCases(b, test_case, "rewrite", test_runner);
        try cases.addCases(b, test_case, "oir", test_runner);
        test_step.dependOn(test_case);
    }
}
