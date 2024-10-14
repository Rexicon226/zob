const std = @import("std");
const Ir = @import("Ir.zig");
const Oir = @import("Oir.zig");
const rewrites = @import("rewrites.zig");
const print_oir = @import("print_oir.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder: Ir.Builder = .{
        .allocator = allocator,
        .instructions = .{},
    };
    defer builder.deinit();
    const stdout = std.io.getStdOut().writer();

    const input =
        \\%0 = constant(3)
        \\%1 = constant(4)
        \\%2 = add(%0, %1)
        \\%3 = mul(%1, %0)
        \\%4 = ret(%3)
    ;

    var ir = try Ir.Parser.parse(allocator, input);

    // print the "before", unoptimized IR
    try stdout.writeAll("\nunoptimized IR:\n");
    try ir.dump(stdout);
    try stdout.writeAll("\n");

    var oir = try Oir.fromIr(ir, allocator);
    defer oir.deinit();

    try oir.optimize(.saturate);

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
