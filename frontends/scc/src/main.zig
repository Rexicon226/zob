const std = @import("std");
const zob = @import("zob");
const builtin = @import("builtin");

const Ast = @import("Ast.zig");
const CodeGen = @import("CodeGen.zig");

pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var input_path: ?[]const u8 = null;
    for (init.minimal.args.vector[1..]) |arg| {
        if (input_path != null) @panic("two file inputs");
        input_path = std.mem.span(arg);
    }

    if (input_path == null) @panic("no file provided");

    const source = try std.Io.Dir.cwd().readFileAllocOptions(io, input_path.?, gpa, .unlimited, .of(u8), 0);
    defer gpa.free(source);

    var ast = try Ast.parse(gpa, source, input_path.?);
    defer ast.deinit(gpa);

    if (ast.errors.len != 0) {
        const stderr = try io.lockStderr(&.{}, null);
        defer io.unlockStderr();
        const terminal = stderr.terminal();

        for (ast.errors) |err| try err.render(ast, terminal);
        try terminal.writer.print("failed with {d} error(s)\n", .{ast.errors.len});

        std.process.abort();
    }

    var oir: zob.Oir = .init(gpa);
    defer oir.deinit();

    var cg: CodeGen = try .init(&oir, gpa, &ast);
    defer cg.deinit(gpa);

    var recv = try cg.build(io);
    defer recv.deinit(gpa);
}

test {
    _ = std.testing.refAllDecls(Ast);
    _ = std.testing.refAllDecls(CodeGen);
}
