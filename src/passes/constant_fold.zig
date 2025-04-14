//! The Constant Folding pass

const std = @import("std");
const Oir = @import("../Oir.zig");

const Node = Oir.Node;
const assert = std.debug.assert;

/// Iterates through all nodes in the E-Graph, checking if it's possible to evaluate them now.
///
/// If a node is found with "comptime-known" children, it's evaluated and the new
/// "comptime-known" result is added to that node's class.
pub fn run(oir: *Oir) !bool {
    // A buffer of constant nodes found in operand classes.
    // Not a BoundedArray, since there are certain nodes that can have a variable
    // amount of operands.
    var constants: std.ArrayListUnmanaged(Node.Index) = .{};
    defer constants.deinit(oir.allocator);

    outer: for (oir.nodes.keys(), 0..) |node, i| {
        const node_idx: Node.Index = @enumFromInt(i);
        const class_idx = oir.findClass(node_idx);

        // If this node is volatile, we cannot fold it away.
        if (node.isVolatile()) continue;

        switch (node.tag) {
            .add,
            .sub,
            .mul,
            .div_exact,
            .div_trunc,
            .shl,
            .cmp_eq,
            .cmp_gt,
            => {
                // the class has already been solved for a constant, no need to do anything else!
                if (oir.classContains(class_idx, .constant) != null) continue;
                assert(node.tag != .constant);
                defer constants.clearRetainingCapacity();

                for (node.operands(oir)) |child_idx| {
                    if (oir.classContains(child_idx, .constant)) |constant| {
                        try constants.append(oir.allocator, constant);
                    } else continue :outer;
                }

                const lhs, const rhs = constants.items[0..2].*;
                const lhs_value = oir.getNode(lhs).data.constant;
                const rhs_value = oir.getNode(rhs).data.constant;

                const result = switch (node.tag) {
                    .add => lhs_value + rhs_value,
                    .sub => lhs_value - rhs_value,
                    .mul => lhs_value * rhs_value,
                    .div_exact => @divExact(lhs_value, rhs_value),
                    .div_trunc => @divTrunc(lhs_value, rhs_value),
                    .shl => lhs_value << @intCast(rhs_value),
                    .cmp_eq => @intFromBool(lhs_value == rhs_value),
                    .cmp_gt => @intFromBool(lhs_value > rhs_value),
                    else => unreachable,
                };

                const new_class = try oir.add(.{
                    .tag = .constant,
                    .data = .{ .constant = result },
                });
                _ = try oir.@"union"(new_class, class_idx);
                try oir.rebuild();

                // We can't continue this iteration since the rebuild could have modified
                // the `nodes` list.
                // TODO: figure out a better way to continue running, even after a rebuild
                // has affected the graph.
                return true;
            },
            .constant => {}, // already folded!
            .project => {}, // TODO
            .branch => {
                // We can fold away branches if we know what the predicate is.
                const predicate = node.data.bin_op[1];
                if (oir.classContains(predicate, .constant)) |idx| {
                    _ = idx;
                    // TODO: no clear way to extract this in a valid way yet
                    // const value = oir.getNode(idx).data.constant;
                    // assert(value == 0 or value == 1);

                    // var true_project: ?Oir.Class.Index = null;
                    // for (oir.nodes.keys(), 0..) |sub_node, j| {
                    //     if (sub_node.tag == .project) {
                    //         const project = sub_node.data.project;

                    //         if (project.tuple == class_idx and
                    //             // NOTE: project(0, ...) is the then case, and 1 is "true",
                    //             // so we are comparing inverse.
                    //             project.index != value)
                    //         {
                    //             true_project = oir.findClass(@enumFromInt(j));
                    //         }
                    //     }
                    // }

                    // if (true_project) |prt| {
                    //     for (oir.nodes.keys()) |sub_node| {
                    //         switch (sub_node.tag) {
                    //             .ret => {
                    //                 if (sub_node.data.bin_op[0] == prt) {
                    //                     const new_ret = try oir.add(.binOp(
                    //                         .ret,
                    //                         node.data.bin_op[0],
                    //                         sub_node.data.bin_op[1],
                    //                     ));
                    //                     try oir.exit_list.insert(oir.allocator, 0, new_ret);
                    //                     return false;
                    //                 }
                    //             },
                    //             else => {},
                    //         }
                    //     }
                    //     return false;
                    // } else return false;
                }
            },
            else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
        }
    }

    return false;
}
