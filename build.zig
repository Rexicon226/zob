const std = @import("std");

const frontends = .{
    .{ "scc", "C" },
    .{ "arocc", "C-aro" },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_z3 = b.option(bool, "use_z3", "Use Z3 as the MILP solver for Oir extraction") orelse false;
    const filters = b.option([]const []const u8, "filter", "Filter test cases");
    const trace = b.option(bool, "trace", "Enable tracing output to trace.json") orelse false;

    var options = b.addOptions();
    options.addOption(bool, "has_z3", use_z3);
    options.addOption(bool, "enable_trace", trace);

    const zob_mod = b.addModule("zob", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib.zig"),
    });
    zob_mod.addOptions("build_options", options);

    const test_lib = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .filters = filters orelse &.{},
    });
    test_lib.root_module.addOptions("build_options", options);

    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&b.addRunArtifact(test_lib).step);

    if (use_z3) {
        const z3 = b.lazyDependency("z3", .{ .target = target, .optimize = optimize }) orelse return;
        const z3_mod = z3.module("z3_bindings");
        zob_mod.addImport("z3", z3_mod);
        test_lib.root_module.addImport("z3", z3_mod);
    }

    const test_frontends = b.step("test-frontends", "Runs frontend tests");
    if (filters == null) test_step.dependOn(test_frontends);

    inline for (frontends) |frontend| {
        const name, const lang = frontend;

        const step = b.step(name, lang ++ " language compiler");
        const dep = b.dependency(name, .{
            .target = target,
            .optimize = optimize,
        });

        const artifact = dep.artifact(name);
        artifact.root_module.addImport("zob", zob_mod);
        b.installArtifact(artifact);

        const run = b.addRunArtifact(artifact);
        if (b.args) |args| run.addArgs(args);
        step.dependOn(&run.step);

        const test_exe = b.addTest(.{
            .name = name,
            .root_module = dep.module(name),
        });
        test_frontends.dependOn(&b.addRunArtifact(test_exe).step);
    }
}
