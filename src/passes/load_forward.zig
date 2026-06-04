//! A `load` that observes a memory state in which a prior `store` wrote the
//! same address at the same width is unioned with the stored value.
//!
//! Forwarding only ever unions a load with a value, so the ordered store
//! chain it walks stays intact, and it forwards only to a value with a
//! concrete width (equal to the load).

const std = @import("std");
const Oir = @import("../Oir.zig");
const alias = @import("../Oir/alias.zig");

const Class = Oir.Class;

pub fn run(oir: *Oir) !bool {
    const gpa = oir.allocator;

    var actions: std.ArrayList([2]Class.Index) = .empty;
    defer actions.deinit(gpa);

    for (oir.getNodes(), 0..) |node, i| {
        if (node.tag != .load) continue;
        const load_class = oir.findClass(@enumFromInt(i));
        const l = node.data.load; // ops = (mem, addr)
        if (forwardOf(oir, l.ops[0], l.ops[1], l.bits)) |val| {
            try actions.append(gpa, .{ load_class, val });
        }
    }

    var changed = false;
    for (actions.items) |a| {
        if (try oir.@"union"(a[0], a[1])) changed = true;
    }
    if (changed) try oir.rebuild();
    return changed;
}

fn forwardOf(oir: *const Oir, mem: Class.Index, addr: Class.Index, bits: u16) ?Class.Index {
    var cur = mem;
    var guard: u32 = 0;
    while (guard < 4096) : (guard += 1) {
        const store = storeOf(oir, cur) orelse return null;
        const s = store.data.store; // ops = (prev, addr, value)
        switch (alias.aliasRel(oir, addr, bits, s.ops[1], s.bits)) {
            .must_exact => {
                // Only forward if we know the concrete-width of the load.
                if (oir.typeOfOpt(s.ops[2])) |w| {
                    if (w == bits) return s.ops[2];
                }
                return null;
            },
            .no_alias => cur = s.ops[0],
            .unknown => return null,
        }
    }
    return null;
}

fn storeOf(oir: *const Oir, class: Class.Index) ?Oir.Node {
    const leader = oir.union_find.find(class);
    const c = oir.classes.get(leader) orelse return null;
    for (c.bag.items) |ni| {
        const node = oir.getNode(ni);
        if (node.tag == .store) return node;
    }
    return null;
}
