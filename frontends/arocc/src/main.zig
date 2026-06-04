const std = @import("std");
const aro = @import("aro");
const zob = @import("zob");
const builtin = @import("builtin");

const build_options = @import("build_options");

const cli = @import("cli.zig");
const CodeGen = @import("CodeGen.zig");

pub const std_options: std.Options = .{
    .log_level = .err,
};

const Cmd = struct {
    file_path: ?[]const u8,
    graphs: ?[]const u8,
    verbose_oir: bool,

    const cmd_info: cli.CommandInfo(Cmd) = .{
        .help = .{
            .short = "C11 Compiler",
            .long = null,
        },
        .sub = .{
            .file_path = .{
                .kind = .positional,
                .name_override = "path",
                .alias = .none,
                .default_value = null,
                .config = .string,
                .help = "input '.c' path",
            },
            .graphs = .{
                .kind = .named,
                .name_override = "graph-path",
                .alias = .none,
                .default_value = null,
                .config = .string,
                .help = "if specified, graphviz outputs are written to the provided directory",
            },
            .verbose_oir = .{
                .kind = .named,
                .name_override = "verbose-oir",
                .alias = .none,
                .default_value = false,
                .config = {},
                .help = "prints the unoptimized and saturated OIR state to stderr",
            },
        },
    };
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var args_iter = try init.minimal.args.iterateAllocator(gpa);
    defer args_iter.deinit();
    _ = args_iter.skip();

    const no_color = no_color: {
        const value = init.environ_map.get("NO_COLOR") orelse break :no_color false;
        break :no_color !std.ascii.eqlIgnoreCase(value, "false");
    };
    const clicolor_force = clicolor_force: {
        const value = init.environ_map.get("CLICOLOR_FORCE") orelse break :clicolor_force false;
        break :clicolor_force !std.ascii.eqlIgnoreCase(value, "false");
    };

    var stdout = std.Io.File.stdout();
    defer stdout.close(io);

    var stdout_writer = stdout.writer(io, &.{});
    const stdout_w = &stdout_writer.interface;

    const terminal: std.Io.Terminal = .{
        .writer = stdout_w,
        .mode = try .detect(io, stdout, no_color, clicolor_force),
    };

    const Parser = cli.Parser(Cmd, Cmd.cmd_info);
    const cmd = try Parser.parse(
        gpa,
        "cc",
        terminal,
        &args_iter,
    ) orelse return;
    defer Parser.free(gpa, cmd);

    const input = cmd.file_path orelse
        fail("expected input file path", .{});

    const stderr = try io.lockStderr(&.{}, null);
    var diagnostics: aro.Diagnostics = .{
        .output = .{ .to_writer = stderr.terminal() },
    };

    var comp = try aro.Compilation.init(.{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .diagnostics = &diagnostics,
        .environ_map = init.environ_map,
    });
    defer comp.deinit();
    comp.target = .{
        .cpu = .{
            .arch = .riscv64,
            .model = .generic(.riscv64),
            .features = .empty,
        },
        .vendor = .unknown,
        .os = .{
            .tag = .linux,
            .version_range = .default(.riscv64, .linux, .musl),
        },
        .abi = .musl,
        .ofmt = .elf,
    };

    var driver: aro.Driver = .{
        .comp = &comp,
        .diagnostics = &diagnostics,
        .resource_dir = build_options.resource_dir,
    };
    defer driver.deinit();

    const source = try comp.addSourceFromPath(input);
    try driver.inputs.append(gpa, source);

    var toolchain: aro.Toolchain = .{ .driver = &driver };
    defer toolchain.deinit();
    try toolchain.discover();
    try toolchain.defineSystemIncludes();
    try comp.initSearchPath(driver.includes.items, false);

    // Parse header files.
    const builtin_macros = try comp.generateBuiltinMacros(.include_system_defines);
    var pp = try aro.Preprocessor.init(&comp, .{ .base_file = source.id });
    defer pp.deinit();
    pp.preprocessSources(.{ .main = source, .builtin = builtin_macros }) catch |err| switch (err) {
        error.FatalError => std.process.exit(1), // already printed the msg to stderr
        else => |e| return e,
    };

    var tree = try pp.parse();
    defer tree.deinit();

    // Construction the Oir of the translation unit.
    var oir: zob.Oir = .init(gpa, .default(io));
    defer oir.deinit();

    var cg = try CodeGen.init(&oir, gpa, &tree, &comp);
    defer cg.deinit(gpa);

    const recvs = r: {
        const t = oir.trace.start(@src(), "construction", .{});
        defer t.end();
        break :r try cg.build(io, .{ .graphs = cmd.graphs, .verbose_oir = cmd.verbose_oir });
    };
    defer {
        for (recvs) |*recv| recv.deinit(gpa);
        gpa.free(recvs);
    }

    {
        const t = oir.trace.start(@src(), "codegen", .{});
        defer t.end();

        // Codegen it into assembly.
        try zob.rv64.generate(
            recvs,
            cg.fn_names.items,
            cg.global_defs.items,
            gpa,
            stdout_w,
        );
    }
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}
