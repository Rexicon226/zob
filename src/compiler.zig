const std = @import("std");
const Ir = @import("Ir.zig");
const Mir = @import("Mir.zig");
const Oir = @import("Oir.zig");

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

    const stdout = std.io.getStdOut().writer();

    const input = try std.fs.cwd().readFileAlloc(allocator, input_path.?, 1 * 1024 * 1024);
    defer allocator.free(input);

    // parse the input IR
    // var ir = try Ir.Parser.parse(allocator, input);
    // defer ir.deinit(allocator);

    var builder: Ir.Builder = .{
        .allocator = allocator,
        .instructions = .{},
    };
    defer builder.deinit();

    var block: Ir.Builder.Block = .{
        .instructions = .{},
        .parent = &builder,
    };
    defer block.deinit();

    const arg1 = try block.addConstant(.arg, 0);
    const arg2 = try block.addConstant(.arg, 1);

    {
        var child_block: Ir.Builder.Block = .{
            .instructions = .{},
            .parent = &builder,
        };
        const child_index = try block.addNone(.dead);

        const compare_index = try child_block.addBinOp(
            .cmp_gt,
            .{ .index = arg1 },
            .{ .index = arg2 },
        );

        var then_case: Ir.Builder.Block = .{
            .instructions = .{},
            .parent = &builder,
        };
        _ = try then_case.addBinOp(.br, .{ .index = child_index }, .{ .value = 0 });

        var else_case: Ir.Builder.Block = .{
            .instructions = .{},
            .parent = &builder,
        };
        _ = try else_case.addBinOp(.br, .{ .index = child_index }, .{ .value = 0 });

        _ = try child_block.addInst(.{
            .tag = .cond_br,
            .data = .{
                .cond_br = .{
                    .pred = compare_index,
                    .then = try then_case.instructions.toOwnedSlice(allocator),
                    .@"else" = try else_case.instructions.toOwnedSlice(allocator),
                },
            },
        });

        try builder.setBlock(child_index, &child_block);
        _ = try block.addUnOp(.ret, .{ .index = child_index });
    }

    var ir = try builder.toIr(&block);
    defer ir.deinit(allocator);

    try stdout.writeAll("input IR:\n");
    try ir.dump(stdout);
    try stdout.writeAll("end IR\n");

    // // create the Oir from the IR.
    // var oir = try Oir.fromIr(ir, allocator);
    // defer oir.deinit();

    // // run optimization passes on the OIR
    // try oir.optimize(.saturate, output_graph);

    // var recv = try Oir.Extractor.extract(&oir, .simple_latency);
    // defer recv.deinit(allocator);

    // try recv.dump("graphs/test_recv.dot");

    // var mir: Mir = .{ .gpa = allocator };
    // defer mir.deinit();

    // // extract the best OIR solution into our MIR
    // var extractor: Mir.Extractor = .{
    //     .cost_strategy = .simple_latency,
    //     .oir = &oir,
    //     .mir = &mir,
    // };
    // try extractor.extract();
    // defer extractor.deinit();

    // try mir.run();
}
