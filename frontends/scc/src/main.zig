const std = @import("std");
const zob = @import("zob");
const builtin = @import("builtin");

const Ast = @import("Ast.zig");
const CodeGen = @import("CodeGen.zig");

pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    var input_path: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (input_path != null) @panic("two file inputs");
        input_path = arg;
    }

    if (input_path == null) @panic("no file provided");
    const source = try std.fs.cwd().readFileAllocOptions(
        allocator,
        input_path.?,
        10 * 1024 * 1024,
        null,
        .@"1",
        0,
    );
    defer allocator.free(source);

    var ast = try Ast.parse(allocator, source, input_path.?);
    defer ast.deinit(allocator);

    if (ast.errors.len != 0) {
        const stderr = std.io.getStdErr();
        for (ast.errors) |err| {
            try err.render(ast, stderr.writer());
        }
        fail("failed with {d} error(s)", .{ast.errors.len});
    }

    var oir: zob.Oir = .init(allocator);
    defer oir.deinit();

    var cg: CodeGen = try .init(&oir, allocator, &ast);
    defer cg.deinit(allocator);

    var recv = try cg.build();
    defer recv.deinit(allocator);
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print(fmt ++ "\n", args) catch @panic("failed to print the stderr");
    std.posix.abort();
}

test {
    _ = std.testing.refAllDecls(Ast);
    _ = std.testing.refAllDecls(CodeGen);
}
