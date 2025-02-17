const std = @import("std");
const zig = @import("zig");
const builtin = @import("builtin");
const build_options = @import("build_options");

const process = std.process;
const fs = std.fs;
const Directory = std.Build.Cache.Directory;
const Package = zig.Package;
const Compilation = zig.Compilation;
const introspect = zig.introspect;
const Zcu = zig.Zcu;
const Liveness = zig.Liveness;

const thread_stack_size = 32 << 20;

pub fn run(input_path: []const u8) !void {
    // We can't perfectly duplicate the memory mangement in the Zig compiler,
    // so we're gonna settle for just leaking a bit of memory.
    const gpa = std.heap.smp_allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var global_cache_directory: Directory = l: {
        const p = try introspect.resolveGlobalCacheDir(arena);
        break :l .{
            .handle = try fs.cwd().makeOpenPath(p, .{}),
            .path = p,
        };
    };
    defer global_cache_directory.handle.close();

    const zig_lib_directory: Directory = .{
        .path = build_options.zig_lib_dir,
        .handle = fs.cwd().openDir(build_options.zig_lib_dir, .{}) catch |err| {
            fatal(
                "unable to open zig lib directory from 'zig-lib-dir' argument: '{s}': {s}",
                .{ build_options.zig_lib_dir, @errorName(err) },
            );
        },
    };

    std.debug.print("lib path: {}\n", .{zig_lib_directory});

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{
        .allocator = arena,
        .n_jobs = @min(@max(std.Thread.getCpuCount() catch 1, 1), std.math.maxInt(Zcu.PerThread.IdBacking)),
        .track_ids = true,
        .stack_size = thread_stack_size,
    });
    defer thread_pool.deinit();

    const config: Compilation.Config = .{
        .have_zcu = true,
        .output_mode = .Obj,
        .link_mode = .static,
        .link_libc = false,
        .link_libcpp = false,
        .link_libunwind = false,
        .any_c_source_files = false,
        .any_unwind_tables = false,
        .any_non_single_threaded = false,
        .any_error_tracing = false,
        .any_sanitize_thread = false,
        .any_fuzz = false,
        .pie = false,
        .use_llvm = false,
        .use_lib_llvm = false,
        .use_lld = false,
        .c_frontend = .aro,
        .lto = .none,
        .wasi_exec_model = .command,
        .import_memory = false,
        .export_memory = false,
        .shared_memory = false,
        .is_test = false,
        .debug_format = .strip,
        .root_optimize_mode = .Debug,
        .root_strip = true,
        .root_error_tracing = false,
        .dll_export_fns = false,
        .rdynamic = false,
        .san_cov_trace_pc_guard = false,
    };

    const mod = try Package.Module.create(arena, .{
        .global_cache_directory = global_cache_directory,
        .fully_qualified_name = "test",
        .paths = .{
            .root = .{
                .root_dir = std.Build.Cache.Directory.cwd(),
                .sub_path = fs.path.dirname(input_path) orelse "",
            },
            .root_src_path = input_path,
        },
        .global = config,
        .cc_argv = &.{},
        .inherited = .{
            .resolved_target = .{
                .result = builtin.target,
                .is_native_os = true,
                .is_native_abi = true,
            },
        },
        .parent = null,
        .builtin_mod = null,
        .builtin_modules = null,
    });

    const self_exe_path = try introspect.findZigExePath(arena);
    const comp = try Compilation.create(gpa, arena, .{
        .zig_lib_directory = zig_lib_directory,
        .local_cache_directory = global_cache_directory,
        .global_cache_directory = global_cache_directory,
        .root_name = "test",
        .root_mod = mod,
        .main_mod = mod,
        .config = config,
        .emit_bin = null,
        .emit_h = null,
        .self_exe_path = self_exe_path,
        .thread_pool = &thread_pool,
    });
    defer comp.destroy();

    const root_prog_node = std.Progress.start(.{});
    defer root_prog_node.end();

    updateModule(comp, .auto, root_prog_node) catch |err| switch (err) {
        error.SemanticAnalyzeFail => {
            process.exit(1);
        },
        else => |e| return e,
    };

    const zcu = comp.zcu.?;
    const ip = &zcu.intern_pool;

    for (zcu.all_exports.items) |exprt| {
        std.debug.print("status: {} {}\n", .{ exprt.status, exprt.exported });

        const exported = exprt.exported;
        const index = switch (exported) {
            .uav => |idx| idx,
            .nav => |nav_index| idx: {
                const nav_val = zcu.navValue(nav_index);
                break :idx nav_val.toIntern();
            },
        };

        const pt: Zcu.PerThread = .activate(zcu, .main);
        defer pt.deactivate();

        var air = try pt.analyzeFnBodyInner(index);
        defer air.deinit(arena);

        var liveness = try Liveness.analyze(arena, air, ip);
        defer liveness.deinit(arena);

        zig.print_air.dump(pt, air, liveness);
    }
}

fn updateModule(comp: *Compilation, color: std.zig.Color, prog_node: std.Progress.Node) !void {
    try comp.update(prog_node);

    var errors = try comp.getAllErrorsAlloc();
    defer errors.deinit(comp.gpa);

    if (errors.errorMessageCount() > 0) {
        errors.renderToStdErr(color.renderOptions());
        return error.SemanticAnalyzeFail;
    }
}

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    process.exit(1);
}
