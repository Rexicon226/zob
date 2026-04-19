const std = @import("std");
const Oir = @import("../Oir.zig");

const Node = Oir.Node;
const Class = Oir.Class;
const assert = std.debug.assert;

/// Iterates through all nodes in the E-Graph, checking if it's possible to evaluate them now.
///
/// If a node is found with "comptime-known" children, it's evaluated and the new
/// "comptime-known" result is added to that node's class.
pub fn run(oir: *Oir) !bool {
    // A buffer of constant nodes found in operand classes.
    var constants: std.ArrayListUnmanaged(Node.Index) = .empty;
    defer constants.deinit(oir.allocator);

    var branch_projects: std.AutoHashMapUnmanaged(Class.Index, ProjectPair) = .{};
    defer branch_projects.deinit(oir.allocator);

    // Collect branch -> project mappings for the branch folding.
    for (oir.nodes.keys(), 0..) |node, i| {
        if (node.tag == .project and node.data.project.type == .ctrl) {
            const project = node.data.project;
            const tuple_class = oir.union_find.find(project.tuple);

            const gop = try branch_projects.getOrPut(oir.allocator, tuple_class);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{ .then_project = null, .else_project = null };
            }

            const project_class = oir.findClass(@enumFromInt(i));
            if (project.index == 0) {
                gop.value_ptr.then_project = project_class;
            } else if (project.index == 1) {
                gop.value_ptr.else_project = project_class;
            }
        }
    }

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

                const result: ?i64 = switch (node.tag) {
                    .add => lhs_value +% rhs_value,
                    .sub => lhs_value -% rhs_value,
                    .mul => lhs_value *% rhs_value,
                    .div_exact => if (rhs_value != 0) @divExact(lhs_value, rhs_value) else null,
                    .div_trunc => if (rhs_value != 0) @divTrunc(lhs_value, rhs_value) else null,
                    .shl => if (rhs_value >= 0 and rhs_value < 64)
                        lhs_value << @intCast(rhs_value)
                    else
                        null,
                    .shr => if (rhs_value >= 0 and rhs_value < 64)
                        lhs_value >> @intCast(rhs_value)
                    else
                        null,
                    .cmp_eq => @intFromBool(lhs_value == rhs_value),
                    .cmp_gt => @intFromBool(lhs_value > rhs_value),
                    .@"and" => lhs_value & rhs_value,
                    else => unreachable,
                };

                if (result) |value| {
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

            .branch => {
                const input_ctrl = node.data.bin_op[0];
                const predicate_class = node.data.bin_op[1];

                if (oir.classContains(predicate_class, .constant)) |const_idx| {
                    const value = oir.getNode(const_idx).data.constant;
                    const branch_class = class_idx;

                    if (branch_projects.get(branch_class)) |projects| {
                        const taken_is_then = (value != 0);

                        const taken_project = if (taken_is_then)
                            projects.then_project
                        else
                            projects.else_project;

                        const not_taken_project = if (taken_is_then)
                            projects.else_project
                        else
                            projects.then_project;

                        if (not_taken_project) |dead_class| {
                            if (try foldDeadControl(oir, dead_class)) {
                                try oir.rebuild();
                                return true;
                            }
                        }

                        if (taken_project) |taken_class| {
                            const canonical_taken = oir.union_find.find(taken_class);
                            if (oir.classes.get(canonical_taken)) |taken_class_data| {
                                for (taken_class_data.parents.items) |parent_pair| {
                                    const parent_node_idx, const parent_class_idx = parent_pair;
                                    const parent_node = oir.getNode(parent_node_idx);

                                    const new_node = try rewriteControlInput(
                                        parent_node,
                                        canonical_taken,
                                        input_ctrl,
                                        oir,
                                    );

                                    if (new_node) |rewritten| {
                                        const new_class = try oir.add(rewritten);
                                        if (try oir.@"union"(new_class, parent_class_idx)) {
                                            try oir.rebuild();
                                            return true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            },

            .region => {
                const span = node.data.list;
                const inputs: []const u32 = oir.extra.items[span.start..span.end];

                if (inputs.len == 0) {
                    if (try foldDeadControl(oir, class_idx)) {
                        try oir.rebuild();
                        return true;
                    }
                } else if (inputs.len == 1) {
                    const single_input: Class.Index = @enumFromInt(inputs[0]);
                    if (try oir.@"union"(class_idx, single_input)) {
                        try oir.rebuild();
                        return true;
                    }
                } else {
                    var live_inputs: std.ArrayListUnmanaged(Class.Index) = .empty;
                    defer live_inputs.deinit(oir.allocator);

                    for (inputs) |input| {
                        const input_class: Class.Index = @enumFromInt(input);
                        if (oir.classContains(input_class, .dead) == null) {
                            try live_inputs.append(oir.allocator, input_class);
                        }
                    }

                    if (live_inputs.items.len < inputs.len) {
                        if (live_inputs.items.len == 0) {
                            if (try foldDeadControl(oir, class_idx)) {
                                try oir.rebuild();
                                return true;
                            }
                        } else if (live_inputs.items.len == 1) {
                            if (try oir.@"union"(class_idx, live_inputs.items[0])) {
                                try oir.rebuild();
                                return true;
                            }
                        } else {
                            const new_span = try oir.listToSpan(live_inputs.items);
                            const new_region = try oir.add(.region(new_span));
                            if (try oir.@"union"(class_idx, new_region)) {
                                try oir.rebuild();
                                return true;
                            }
                        }
                    }
                }
            },

            .ret => {
                const ctrl = node.data.bin_op[0];
                if (oir.classContains(ctrl, .dead) != null) {
                    for (oir.exit_list.items, 0..) |exit, idx| {
                        if (oir.union_find.find(exit) == class_idx) {
                            _ = oir.exit_list.swapRemove(idx);
                            return true;
                        }
                    }
                }
            },

            .constant => {}, // already folded!
            .project => {}, // handled via branch folding
            .load => {}, // TODO: GVN load elision
            .store => {}, // ^
            .start => {},
            .dead => {},
        }
    }

    return false;
}

const ProjectPair = struct {
    then_project: ?Class.Index,
    else_project: ?Class.Index,
};

fn foldDeadControl(oir: *Oir, ctrl_class: Class.Index) !bool {
    const canonical_class = oir.union_find.find(ctrl_class);
    if (oir.classes.get(canonical_class)) |class| {
        for (class.bag.items) |node_idx| {
            if (oir.getNode(node_idx).tag == .dead) {
                return false; // already dead
            }
        }
    }

    const dead_class = try oir.add(.{ .tag = .dead, .data = .none });
    return try oir.@"union"(ctrl_class, dead_class);
}

fn rewriteControlInput(
    node: Node,
    old_ctrl: Class.Index,
    new_ctrl: Class.Index,
    oir: *const Oir,
) !?Node {
    switch (node.tag) {
        .ret => {
            if (oir.union_find.find(node.data.bin_op[0]) == old_ctrl) {
                return Node.binOp(.ret, new_ctrl, node.data.bin_op[1]);
            }
        },
        .branch => {
            if (oir.union_find.find(node.data.bin_op[0]) == old_ctrl) {
                return Node.binOp(.branch, new_ctrl, node.data.bin_op[1]);
            }
        },
        .store => {
            if (oir.union_find.find(node.data.bin_op[0]) == old_ctrl) {
                return Node.binOp(.store, new_ctrl, node.data.bin_op[1]);
            }
        },
        .region => {},
        else => {},
    }
    return null;
}
