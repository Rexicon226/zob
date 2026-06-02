//! Loop simplifications.
//!
//! Invariant-slot elimation. If a loop-carried slot's next-iteration value is
//! the same e-class as its loop argument, the slot never changes across the loop,
//! so the loop's output for that slot equals its initial value. We union
//! `project(theta, i)` with `init_i`.
//!
//! This is sound regardless of trip count. The slot holds `init_i` on every
//! iteration and at exit. (If the loop never terminates the result is never
//! observed, so the rewrite is vacuously fine.) Its value is decoupling post-loop
//! uses from the loop.
//!
//! For instance, the memory slot of a store-free loop becomes the pre-loop
//! memory state again, which lets store-to-load forwarding reach across the loop.

const std = @import("std");
const Oir = @import("../Oir.zig");

pub fn run(oir: *Oir) !bool {
    for (oir.getNodes(), 0..) |node, i| {
        if (node.tag != .project) continue;
        const proj = node.data.project;

        const tuple = oir.union_find.find(proj.tuple);
        const class = oir.classes.get(tuple) orelse continue;

        // The projected tuple must be a loop.
        const theta = for (class.bag.items) |node_idx| {
            const candidate = oir.getNode(node_idx);
            if (candidate.tag == .theta) break candidate;
        } else continue;

        const loop = theta.data.loop;
        if (proj.index >= loop.count) continue;

        // A slot is invariant when next_i and arg_i are the same e-class.
        const arg = oir.union_find.find(loop.args(oir)[proj.index]);
        const next = oir.union_find.find(loop.nexts(oir)[proj.index]);
        if (arg != next) continue;

        const init = loop.inits(oir)[proj.index];
        const proj_class = oir.findClass(@enumFromInt(i));
        if (try oir.@"union"(proj_class, init)) {
            try oir.rebuild();
            return true;
        }
    }
    return false;
}
