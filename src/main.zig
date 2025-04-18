const std = @import("std");
const builtin = @import("builtin");
const Ir = @import("Ir.zig");
const Trace = @import("Trace.zig");
const Oir = @import("Oir.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 100 }){};
    defer _ = gpa.deinit();

    const allocator = switch (builtin.mode) {
        .Debug => gpa.allocator(),
        else => std.heap.smp_allocator,
    };
    defer log_scopes.deinit(allocator);

    const stdout = std.io.getStdOut().writer();
    var output_graph: bool = false;
    var input_path: ?[]const u8 = null;
    var use_builder: bool = false;
    var enable_tracing: bool = false;

    var iter = try std.process.argsWithAllocator(allocator);
    _ = iter.skip();
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--debug-log")) {
            try log_scopes.append(
                allocator,
                iter.next() orelse @panic("expected scope after --debug-log"),
            );
        } else if (std.mem.eql(u8, arg, "--output-graph")) {
            output_graph = true;
        } else if (std.mem.eql(u8, arg, "--builder")) {
            use_builder = true;
        } else if (std.mem.eql(u8, arg, "--trace")) {
            enable_tracing = true;
        } else {
            if (input_path != null) @panic("two input files");
            input_path = arg;
        }
    }

    var ir = if (!use_builder) ir: {
        if (input_path == null) @panic("expected input path");
        const input = try std.fs.cwd().readFileAlloc(allocator, input_path.?, 1 * 1024 * 1024);
        defer allocator.free(input);

        // parse the input IR
        break :ir try Ir.Parser.parse(allocator, input);
    } else ir: {
        // NOTE: just random testing stuff
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

        var prev_add = try block.addBinOp(
            .add,
            .{ .value = 0 },
            .{ .value = 1 },
        );
        for (2..500) |i| {
            prev_add = try block.addBinOp(
                .add,
                .{ .index = prev_add },
                .{ .value = @intCast(i) },
            );
        }

        _ = try block.addUnOp(.ret, .{ .index = prev_add });

        break :ir try builder.toIr(&block);
    };
    defer ir.deinit(allocator);

    try stdout.writeAll("unstructured IR:\n");
    try ir.dump(stdout);
    try stdout.writeAll("end IR\n");

    // create the Oir from the IR.
    var oir = try Ir.Constructor.extract(ir, allocator);
    defer oir.deinit();

    try stdout.writeAll("unoptimized OIR:\n");
    try oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    if (enable_tracing) try oir.trace.enable("trace.json");

    var start = try std.time.Timer.start();

    // run optimization passes on the OIR
    try oir.optimize(.saturate, output_graph);

    const end = start.lap();
    std.debug.print("took: {}\n", .{std.fmt.fmtDuration(end)});

    if (output_graph) try oir.dump("graphs/oir.dot");

    var recv = try oir.extract(.simple_latency);
    defer recv.deinit(allocator);

    if (output_graph) try recv.dump("graphs/recv.dot");

    try stdout.writeAll("recv:\n");
    try recv.print(stdout);
    try stdout.writeAll("end recv\n");
}

pub const std_options: std.Options = .{
    .logFn = log,
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
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
