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

    outer: for (oir.nodes.items, 0..) |node, i| {
        const node_idx: Node.Index = @enumFromInt(i);
        const class_idx = oir.findClass(node_idx);

        // If this node is volatile, we cannot fold it away.
        if (node.isVolatile()) continue;

        // the class has already been solved for a constant, no need to do anything else!
        if (oir.classContains(class_idx, .constant) != null) continue;
        assert(node.tag != .constant);
        defer constants.clearRetainingCapacity();

        for (node.operands(oir)) |child_idx| {
            if (oir.classContains(child_idx, .constant)) |constant| {
                try constants.append(oir.allocator, constant);
            } else continue :outer;
        }

        switch (node.tag) {
            .add,
            .sub,
            .mul,
            .div_exact,
            .shl,
            => {
                const lhs, const rhs = constants.items[0..2].*;
                const lhs_value = oir.getNode(lhs).data.constant;
                const rhs_value = oir.getNode(rhs).data.constant;

                const result = switch (node.tag) {
                    .add => lhs_value + rhs_value,
                    .sub => lhs_value - rhs_value,
                    .mul => lhs_value * rhs_value,
                    .div_exact => @divExact(lhs_value, rhs_value),
                    .shl => lhs_value << @intCast(rhs_value),
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
            else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
        }
    }

    return false;
}
