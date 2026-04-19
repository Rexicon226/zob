const std = @import("std");
const aro = @import("aro");
const zob = @import("zob");
const builtin = @import("builtin");

const CodeGen = @import("CodeGen.zig");

pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

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

    var macro_buffer: std.ArrayList(u8) = .empty;
    defer macro_buffer.deinit(gpa);

    var null_writer: std.Io.Writer.Discarding = .init(&.{});
    if (try driver.parseArgs(&null_writer.writer, &macro_buffer, args)) std.process.abort();

    std.debug.assert(driver.inputs.items.len == 1);
    const source = driver.inputs.items[0];

    const builtin_macros = try comp.generateBuiltinMacros(.include_system_defines);

    var pp = try aro.Preprocessor.init(&comp, .{ .base_file = source.id });
    defer pp.deinit();
    try pp.preprocessSources(.{
        .main = source,
        .builtin = builtin_macros,
    });

    var tree = try pp.parse();
    defer tree.deinit();

    var oir: zob.Oir = .init(gpa);
    defer oir.deinit();

    var cg = try CodeGen.init(&oir, gpa, &tree);
    defer cg.deinit(gpa);

    var recv = try cg.build(io);
    defer recv.deinit(gpa);

    try zob.rv64.generate(&recv, io);
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print(fmt ++ "\n", args) catch @panic("failed to print the stderr");
    std.posix.abort();
}
