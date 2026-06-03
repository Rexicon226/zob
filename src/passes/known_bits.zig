const std = @import("std");
const Oir = @import("../Oir.zig");
const analysis = @import("../Oir/analysis.zig");

const KnownBits = analysis.KnownBits;
const Class = Oir.Class;

const Action = union(enum) {
    to_const: struct { class: Class.Index, value: i64 },
    to_operand: struct { class: Class.Index, operand: Class.Index },
};

pub fn run(oir: *Oir) !bool {
    const gpa = oir.allocator;

    var facts = try analysis.analyze(oir, gpa);
    defer facts.deinit(gpa);

    var actions: std.ArrayList(Action) = .empty;
    defer actions.deinit(gpa);

    var iter = oir.classes.iterator();
    while (iter.next()) |entry| {
        const leader = entry.key_ptr.*;
        const f = facts.get(leader) orelse KnownBits.top;
        if (f.isBottom()) continue;
        if (oir.getClassType(leader) != .data) continue;
        if (oir.classContains(leader, .constant) != null) continue;

        if (f.isFullyKnown()) {
            try actions.append(gpa, .{ .to_const = .{ .class = leader, .value = f.value() } });
            continue;
        }

        for (entry.value_ptr.bag.items) |node_idx| {
            const node = oir.getNode(node_idx);
            const operand = switch (node.tag) {
                .@"and" => redundantAnd(oir, &facts, node.data.bin_op),
                .@"or" => redundantOr(oir, &facts, node.data.bin_op),
                else => continue,
            } orelse continue;
            try actions.append(gpa, .{ .to_operand = .{ .class = leader, .operand = operand } });
            break;
        }
    }

    var changed = false;
    for (actions.items) |action| {
        switch (action) {
            .to_const => |a| {
                const c = try oir.add(.constant(a.value));
                if (try oir.@"union"(oir.union_find.find(a.class), c)) changed = true;
            },
            .to_operand => |a| {
                if (try oir.@"union"(oir.union_find.find(a.class), oir.union_find.find(a.operand)))
                    changed = true;
            },
        }
    }
    if (!oir.clean) try oir.rebuild();
    return changed;
}

/// `(and a b)` equals one operand when every bit of the other operand could
/// possibly set 1 is already known 1 in it. Returns the surviving operand class,
/// if any.
fn redundantAnd(oir: *const Oir, facts: *const analysis.Facts, ops: [2]Class.Index) ?Class.Index {
    const a = facts.get(oir.union_find.find(ops[0])) orelse KnownBits.top;
    const b = facts.get(oir.union_find.find(ops[1])) orelse KnownBits.top;
    // a & b == a iff every possibly-1 bit of a is known 1 in b.
    if ((~a.zeros & ~b.ones) == 0) return ops[0];
    if ((~b.zeros & ~a.ones) == 0) return ops[1];
    return null;
}

fn redundantOr(oir: *const Oir, facts: *const analysis.Facts, ops: [2]Class.Index) ?Class.Index {
    const a = facts.get(oir.union_find.find(ops[0])) orelse KnownBits.top;
    const b = facts.get(oir.union_find.find(ops[1])) orelse KnownBits.top;
    // a | b == a iff every possibly-1 bit of b is already known 1 in a.
    if ((~b.zeros & ~a.ones) == 0) return ops[0];
    if ((~a.zeros & ~b.ones) == 0) return ops[1];
    return null;
}
