const std = @import("std");
const Ir = @import("Ir.zig");
const Mir = @import("Mir.zig");
const Oir = @import("Oir.zig");
const print_oir = @import("print_oir.zig");

pub const std_options: std.Options = .{
    .logFn = log,
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Hide debug messages unless:
    // * logging enabled with `-Dlog`.
    // * the --debug-log arg for the scope has been provided
    if (@intFromEnum(level) > @intFromEnum(std.options.log_level) or
        @intFromEnum(level) > @intFromEnum(std.log.Level.info))
    {
        const scope_name = @tagName(scope);
        for (log_scopes.items) |log_scope| {
            if (std.mem.eql(u8, log_scope, scope_name))
                break;
        } else return;
    }

    const prefix1 = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    // Print the message to stderr, silently ignoring any errors
    std.debug.print(prefix1 ++ prefix2 ++ format ++ "\n", args);
}

var log_scopes: std.ArrayListUnmanaged([]const u8) = .{};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 100 }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    defer log_scopes.deinit(allocator);

    var output_graph: bool = false;
    var input_path: ?[]const u8 = null;

    var iter = try std.process.argsWithAllocator(allocator);
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--debug-log")) {
            try log_scopes.append(
                allocator,
                iter.next() orelse @panic("expected scope after --debug-log"),
            );
        } else if (std.mem.eql(u8, arg, "--output-graph")) {
            output_graph = true;
        } else {
            input_path = arg;
        }
    }
    if (input_path == null) @panic("expected input path");

    const input = try std.fs.cwd().readFileAlloc(allocator, input_path.?, 1 * 1024 * 1024);
    defer allocator.free(input);

    // parse the input IR
    var ir = try Ir.Parser.parse(allocator, input);
    defer ir.deinit(allocator);

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("input IR:\n");
    try ir.dump(stdout);
    try stdout.writeAll("end IR\n");

    // create the Oir from the IR.
    var oir = try Oir.fromIr(ir, allocator);
    defer oir.deinit();

    // run optimization passes on the OIR
    try oir.optimize(.saturate);

    // dump to a graphviz file
    if (output_graph) {
        const graphviz_file = try std.fs.cwd().createFile("out.dot", .{});
        defer graphviz_file.close();
        try print_oir.dumpGraphViz(&oir, graphviz_file.writer());
    }

    var mir: Mir = .{ .gpa = allocator };
    defer mir.deinit();

    // extract the best OIR solution into our MIR
    var extractor: Mir.Extractor = .{
        .cost_strategy = .num_nodes,
        .oir = &oir,
        .mir = &mir,
    };
    try extractor.extract();
    defer extractor.deinit();

    try mir.run();
}
