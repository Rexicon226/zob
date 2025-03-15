const std = @import("std");
const zob = @import("zob");
const TestInput = @import("cases.zig").TestInput;

const Ir = zob.Ir;
const Oir = zob.Oir;

pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 100 }){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const input_ir_path = args[1];

    const contents = try std.fs.cwd().readFileAlloc(gpa, input_ir_path, 100 * 1024);
    defer gpa.free(contents);

    var ir = try Ir.Parser.parse(gpa, contents);
    defer ir.deinit(gpa);

    var oir = try Ir.Constructor.extract(ir, gpa);
    defer oir.deinit();

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\nunoptimized OIR:\n");
    try oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    try oir.optimize(.saturate, false);

    var recv = try Oir.Extractor.extract(&oir, .simple_latency);
    defer recv.deinit(gpa);

    try stdout.writeAll("\nextracted OIR:\n");
    try stdout.print("{}", .{recv});
    try stdout.writeAll("end OIR\n");
}
