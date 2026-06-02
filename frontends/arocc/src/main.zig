const std = @import("std");
const aro = @import("aro");
const zob = @import("zob");
const builtin = @import("builtin");

const cli = @import("cli.zig");
const CodeGen = @import("CodeGen.zig");

pub const std_options: std.Options = .{
    .log_level = .err,
};

const Cmd = struct {
    file_path: ?[]const u8,
    graphs: ?[]const u8,

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

    var driver: aro.Driver = .{
        .comp = &comp,
        .diagnostics = &diagnostics,
    };
    defer driver.deinit();

    const source = try comp.addSourceFromPath(input);
    try driver.inputs.append(gpa, source);
    std.debug.assert(driver.inputs.items.len == 1);

    const builtin_macros = try comp.generateBuiltinMacros(.include_system_defines);

    var pp = try aro.Preprocessor.init(&comp, .{ .base_file = source.id });
    defer pp.deinit();
    try pp.preprocessSources(.{ .main = source, .builtin = builtin_macros });

    var tree = try pp.parse();
    defer tree.deinit();

    var oir: zob.Oir = .init(gpa);
    defer oir.deinit();

    var cg = try CodeGen.init(&oir, gpa, &tree);
    defer cg.deinit(gpa);

    const recvs = try cg.build(io, cmd.graphs);
    defer {
        for (recvs) |*recv| recv.deinit(gpa);
        gpa.free(recvs);
    }

    try zob.rv64.generate(recvs, cg.fn_names.items, gpa, stdout_w);
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}
