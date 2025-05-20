const std = @import("std");
const aro = @import("aro");
const zob = @import("zob");
const builtin = @import("builtin");

const CodeGen = @import("CodeGen.zig");

pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();

    const args = try std.process.argsAlloc(arena);

    const stderr_file = std.io.getStdErr();
    var diagnostics: aro.Diagnostics = .{
        .output = .{ .to_file = .{
            .config = std.io.tty.detectConfig(stderr_file),
            .file = stderr_file,
        } },
    };

    var comp = try aro.Compilation.initDefault(gpa, &diagnostics, std.fs.cwd());
    defer comp.deinit();

    var driver: aro.Driver = .{
        .comp = &comp,
        .diagnostics = &diagnostics,
    };
    defer driver.deinit();

    var macro_buf = std.ArrayList(u8).init(gpa);
    defer macro_buf.deinit();

    std.debug.assert(!try driver.parseArgs(std.io.null_writer, macro_buf.writer(), args));
    std.debug.assert(driver.inputs.items.len == 1);
    const source = driver.inputs.items[0];

    const builtin_macros = try comp.generateBuiltinMacros(.include_system_defines, null);
    const user_macros = try comp.addSourceFromBuffer("<command line>", macro_buf.items);

    var pp = try aro.Preprocessor.initDefault(&comp);
    defer pp.deinit();

    try pp.preprocessSources(&.{ source, builtin_macros, user_macros });

    var tree = try pp.parse();
    defer tree.deinit();

    var oir: zob.Oir = .init(gpa);
    defer oir.deinit();

    var cg = try CodeGen.init(&oir, gpa, &tree);
    defer cg.deinit(gpa);

    var recv = try cg.build();
    defer recv.deinit(gpa);

    try zob.p2.generate(&recv);
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print(fmt ++ "\n", args) catch @panic("failed to print the stderr");
    std.posix.abort();
}
