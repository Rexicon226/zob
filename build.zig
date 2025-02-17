const std = @import("std");
const tests = @import("test/tests.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_dep = b.dependency("zig", .{});
    const write = b.addWriteFiles();
    _ = write.addCopyDirectory(zig_dep.path("."), "", .{});
    const root = write.addCopyFile(b.path("zig/root.zig"), "src/root.zig");
    const zig_mod = b.createModule(.{
        .root_source_file = root,
    });

    const aro_mod = b.createModule(.{
        .root_source_file = zig_dep.path("lib/compiler/aro/aro.zig"),
    });
    const aro_translate_c_mod = b.createModule(.{
        .root_source_file = zig_dep.path("lib/compiler/aro_translate_c.zig"),
    });

    aro_translate_c_mod.addImport("aro", aro_mod);
    zig_mod.addImport("aro", aro_mod);
    zig_mod.addImport("aro_translate_c", aro_translate_c_mod);

    {
        const options = b.addOptions();
        options.addOption([:0]const u8, "version", "0.14.0");
        options.addOption(bool, "have_llvm", false);
        options.addOption(bool, "enable_debug_extensions", false);
        options.addOption(bool, "enable_logging", false);
        options.addOption(bool, "enable_link_snapshots", false);
        options.addOption(bool, "enable_tracy", false);
        options.addOption(bool, "enable_tracy_callstack", false);
        options.addOption(bool, "enable_tracy_allocation", false);
        options.addOption(u32, "tracy_callstack_depth", 0);
        options.addOption(bool, "value_tracing", false);
        options.addOption(u32, "mem_leak_frames", 16);
        options.addOption(bool, "skip_non_native", true);
        options.addOption(bool, "llvm_has_m68k", false);
        options.addOption(bool, "llvm_has_csky", false);
        options.addOption(bool, "llvm_has_arc", false);
        options.addOption(bool, "llvm_has_xtensa", false);
        options.addOption(bool, "debug_gpa", false);
        options.addOption(enum { sema }, "dev", .sema);
        options.addOption(enum { direct, by_name }, "value_interpret_mode", .direct);

        const semver = try std.SemanticVersion.parse("0.14.0");
        options.addOption(std.SemanticVersion, "semver", semver);

        zig_mod.addOptions("build_options", options);
    }

    const compiler = b.addExecutable(.{
        .name = "compiler",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/compiler.zig"),
    });
    compiler.root_module.addImport("zig", zig_mod);

    const options = b.addOptions();
    options.addOptionPath("zig_lib_dir", zig_dep.path("lib"));
    compiler.root_module.addOptions("build_options", options);

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

    // const test_case = b.step("test-cases", "Runs IR case tests");
    // try tests.addCases(b, test_case, "mir", compiler);
    // try tests.addCases(b, test_case, "rewrites", compiler);
    // test_step.dependOn(test_case);
}
