const std = @import("std");
const Oir = @import("../Oir.zig");
const eval = @import("eval.zig");

const Node = Oir.Node;
const Class = Oir.Class;
const assert = std.debug.assert;

/// Iterates through all nodes in the E-Graph, checking if it's possible to evaluate them now.
///
/// If a node is found with "comptime-known" children, it's evaluated and the new
/// "comptime-known" result is added to that node's class.
pub fn run(oir: *Oir) !bool {
    // A buffer of constant nodes found in operand classes.
    var constants: std.ArrayList(Node.Index) = .empty;
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
            .shr,
            .cmp_eq,
            .cmp_gt,
            .cmp_lt,
            .@"and",
            => {
                // The class has already been solved for a constant, no need to do anything else!
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

                if (eval.binOp(node.tag, lhs_value, rhs_value)) |value| {
                    const new_class = try oir.add(.{
                        .tag = .constant,
                        .data = .{ .constant = value },
                    });
                    _ = try oir.@"union"(new_class, class_idx);
                    try oir.rebuild();

                    // We can't continue this iteration since the rebuild could have modified
                    // the `nodes` list.
                    return true;
                }
            },

            .gamma => {
                // Already resolved to its chosen arm.
                if (oir.classContains(class_idx, .constant) != null) continue;

                const pred, const then_class, const else_class = node.data.tri_op;
                if (oir.classContains(pred, .constant)) |const_idx| {
                    const value = oir.getNode(const_idx).data.constant;
                    const chosen = if (value != 0) then_class else else_class;
                    if (try oir.@"union"(class_idx, chosen)) {
                        try oir.rebuild();
                        return true;
                    }
                }
            },

            // No fold rule for loops yet.
            .theta => {},
            .loopvar => {}, // a leaf loop-carried reference

            .constant => {}, // already folded!
            .project => {}, // function arguments, nothing to fold
            .load => {}, // TODO: GVN load elision
            .store => {}, // ^
            .start => {},
            .ret => {}, // volatile, handled above
        }
    }

    return false;
}
