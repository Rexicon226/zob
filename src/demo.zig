const std = @import("std");
const Ir = @import("Ir.zig");
const Mir = @import("Mir.zig");
const Oir = @import("Oir.zig");
const print_oir = @import("print_oir.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 100 }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder: Ir.Builder = .{
        .allocator = allocator,
        .instructions = .{},
    };
    defer builder.deinit();
    const stdout = std.io.getStdOut().writer();

    // meant to sort of look like AIR
    const input =
        \\%0 = arg(0)
        \\%1 = arg(1)
        \\%2 = ret(%1)
    ;

    // parse the input IR
    var ir = try Ir.Parser.parse(allocator, input);
    defer ir.deinit(allocator);

    try stdout.writeAll("\nunoptimized IR:\n");
    try ir.dump(stdout);
    try stdout.writeAll("\n");

    // create the Oir from the IR.
    var oir = try Oir.fromIr(ir, allocator);
    defer oir.deinit();

    // run optimization passes on the OIR
    try oir.optimize(.saturate);

    var mir: Mir = .{ .gpa = allocator };
    defer mir.deinit();

    // extract the best OIR solution into our MIR
    var extractor: Mir.Extractor = .{
        .cost_strategy = .num_nodes,
        .oir = &oir,
        .mir = &mir,
    };
    try extractor.extract();

    try mir.run();

    // dump to a graphviz file
    const graphviz_file = try std.fs.cwd().createFile("out.dot", .{});
    defer graphviz_file.close();
    try print_oir.dumpGraphViz(&oir, graphviz_file.writer());
}
