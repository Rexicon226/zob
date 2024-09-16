const std = @import("std");
const IR = @import("Ir.zig");
const Oir = @import("Oir.zig");
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

    // in this example we're trying to trigger the (mul ?x 2) -> (shl ?x 1) rewrite

    // %0 = arg(0)
    // %1 = const(10)
    // %2 = mul(%0, %1)
    // %3 = ret(%2)

    const arg1 = try builder.addNone(.arg);
    const arg2 = try builder.addConstant(2);
    const result = try builder.addBinOp(.mul, arg1, arg2);
    _ = try builder.addUnOp(.ret, result);

    const ir = builder.toIr();
    var oir = try Oir.fromIr(ir, allocator);
    defer oir.deinit();

    // apply the rewrite
    try oir.applyRewrite(.{ .pattern = "(mul ?x ?y)", .func = mulRewrite });

    // dump to a graphviz file
    const graphviz_file = try std.fs.cwd().createFile("out.dot", .{});
    defer graphviz_file.close();

    try print_oir.dumpGraphViz(&oir, graphviz_file.writer());
}

// TODO: damn, this is ugly.
fn mulRewrite(oir: *Oir, node_idx: Oir.Node.Index) !void {
    const node = oir.getNode(node_idx);

    const lhs_class_idx = node.out.items[0];
    const rhs_class_idx = node.out.items[1];

    const lhs_class = oir.getClass(lhs_class_idx);
    const rhs_class = oir.getClass(rhs_class_idx);
    var meta: ?struct { i64, Oir.Class.Index } = null;

    inline for (.{ lhs_class, rhs_class }, 0..) |class, i| {
        for (class.bag.items) |child_idx| {
            const child = oir.getNode(child_idx);
            if (child.tag != .constant) continue;
            const val = child.data.constant;
            if (val <= 0) continue; // todo this
            if (std.math.isPowerOfTwo(@as(u32, @intCast(val)))) {
                // given the equality invariance, all other nodes in this class
                // must equal to this value, hence we can assume that we've found the constant
                meta = .{ val, .{ lhs_class_idx, rhs_class_idx }[(i + 1) & 1] };
                break;
            }
        }
        if (meta != null) break; // we only want to find one constant
    }
    if (meta == null) {
        // we never found a viable constant node
        return;
    }

    const val, const other_class = meta.?;

    const shift_node_id = try oir.add(.{
        .tag = .shl,
        .data = .none,
    });

    const shift_amount_id = try oir.add(.{
        .tag = .constant,
        .data = .{ .constant = std.math.log2(@as(u32, @intCast(val))) },
    });
    const shift_class_id = try oir.findClass(shift_amount_id);
    const shift_node = &oir.nodes.items[@intFromEnum(shift_node_id)];
    try shift_node.out.append(oir.allocator, other_class);
    try shift_node.out.append(oir.allocator, shift_class_id);

    const old_class_id = try oir.findClass(node_idx);
    const new_class_id = try oir.findClass(shift_node_id);

    try oir.@"union"(old_class_id, new_class_id);
}
