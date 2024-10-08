const std = @import("std");
const IR = @import("Ir.zig");
const Oir = @import("Oir.zig");
const rewrites = @import("rewrites.zig");
const print_oir = @import("print_oir.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder: IR.Builder = .{
        .allocator = allocator,
        .instructions = .{},
    };
    defer builder.deinit();
    const stdout = std.io.getStdOut().writer();

    // in this example we're trying to trigger the (mul ?x 2) -> (shl ?x 1) rewrite

    // %0 = arg(0)
    // %1 = const(2)
    // %2 = mul(%0, %1)
    // %3 = ret(%2)

    const arg1 = try builder.addNone(.arg);
    const arg2 = try builder.addConstant(2);
    const result = try builder.addBinOp(.mul, arg1, arg2);
    _ = try builder.addUnOp(.ret, result);

    const ir = builder.toIr();

    // print the "before", unoptimized IR
    try stdout.writeAll("\nunoptimized IR:\n");
    try ir.dump(stdout);

    var oir = try Oir.fromIr(ir, allocator);
    defer oir.deinit();

    // apply the rewrite
    try oir.applyRewrite(.{ .pattern = "(mul ?x 2)", .rewrite = rewrites.mulRewriteLhs });

    // output IR
    var optimized_ir = try oir.extract();
    defer optimized_ir.deinit(allocator);

    // dump to a graphviz file
    const graphviz_file = try std.fs.cwd().createFile("out.dot", .{});
    defer graphviz_file.close();

    try print_oir.dumpGraphViz(&oir, graphviz_file.writer());

    // dump the optimized IR to stdout
    try stdout.writeAll("\noptimized IR:\n");
    try optimized_ir.dump(stdout);
}
