//! A file containing rewrite implementations

/// (mul ?x 2) -> (shl ?x 1)
pub fn mulRewriteLhs(
    oir: *Oir,
    node_idx: Node.Index,
) Oir.Rewrite.Error!void {
    const node = oir.getNode(node_idx);
    assert(node.tag == .mul);

    const lhs_idx = node.out.items[0];
    const rhs_idx = node.out.items[1];
    const rhs = oir.getClass(rhs_idx);

    // the rhs class is supposed to contain a constant which we'll
    // log2 to get the shift amount

    const constant_idx: Node.Index = idx: for (rhs.bag.items) |sub_node_idx| {
        const sub_node = oir.getNode(sub_node_idx);
        if (sub_node.tag == .constant) break :idx sub_node_idx;
    } else @panic("something went wrong...");
    const constant_value = oir.getNode(constant_idx).data.constant;
    const shift_value = std.math.log2_int(u32, @intCast(constant_value));

    // create the two new nodes, the "shl" and the value we'll be shifting by
    const shl_idx = try oir.add(.{ .tag = .shl });
    const shift_idx = try oir.add(.{
        .tag = .constant,
        .data = .{ .constant = shift_value },
    });

    // create the relationship between the "shl" and the value node
    const shl_node = &oir.nodes.items[@intFromEnum(shl_idx)];
    try shl_node.out.append(oir.allocator, try oir.findClass(shift_idx));

    // create the relationship betwen the "shl" and the previous ?x node
    try shl_node.out.append(oir.allocator, lhs_idx);

    // finally, union the two classes
    const root_class_idx = try oir.findClass(node_idx);
    const shl_class_idx = try oir.findClass(shl_idx);
    try oir.@"union"(root_class_idx, shl_class_idx);
}

const std = @import("std");
const Oir = @import("Oir.zig");
const Node = Oir.Node;
const assert = std.debug.assert;
