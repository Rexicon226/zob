//! Super basic Oir extractor implementation.

const std = @import("std");
const Oir = @import("../Oir.zig");
const cost = @import("../cost.zig");
const extraction = @import("extraction.zig");
const alias = @import("alias.zig");

const Class = Oir.Class;
const Node = Oir.Node;
const SimpleExtractor = @This();
const Recursive = extraction.Recursive;

const log = std.log.scoped(.simple_extractor);
const assert = std.debug.assert;

oir: *const Oir,

/// The chosen lowest-cost node for each canonical class.
best_node: std.AutoHashMapUnmanaged(Class.Index, Node.Index),
map: std.AutoHashMapUnmanaged(Class.Index, Class.Index),
dead_slots: std.AutoHashMapUnmanaged(u32, void),

/// Sentinel cost for a class that has no finite-cost (acyclic) extraction yet.
const infinite = std.math.maxInt(u32);

/// Extracts the best program, producing one `Recursive` per function in
/// `oir.exit_list`.
pub fn extract(oir: *const Oir) ![]Recursive {
    var e: SimpleExtractor = .{
        .oir = oir,
        .best_node = .{},
        .map = .{},
        .dead_slots = try alias.deadSlots(oir, oir.allocator),
    };
    defer e.deinit();

    try e.computeBestNodes();

    var list: std.ArrayList(Recursive) = .empty;
    errdefer {
        for (list.items) |*recv| recv.deinit(oir.allocator);
        list.deinit(oir.allocator);
    }

    for (oir.exit_list.items) |exit| {
        const exit_class = oir.union_find.find(exit);
        _ = e.best_node.get(exit_class) orelse continue;

        var recv: Recursive = .{};
        e.map.clearRetainingCapacity();
        const idx = try e.extractClass(exit, &recv);
        try recv.exit_list.append(oir.allocator, idx);
        try list.append(oir.allocator, recv);
    }

    return list.toOwnedSlice(oir.allocator);
}

/// Computes the best (lowest-cost) node for every class via Bellman-Ford style
/// fixpoint.
///
/// E-graphs may contain cycles (e.g. store-to-load forwarding unions a load with
/// the stored value, while the load still references the store). A class only
/// ever receives a finite cost through a node whose childre are *all* finite, so
/// cyclic nodes are skipped automatically as long as the class has an acyclic
/// alternative (such as a `constant`). Since every node with operands has a
/// non-zero base cost, the chosen subgraph is well-founded and therefore acyclic.
fn computeBestNodes(e: *SimpleExtractor) !void {
    const oir = e.oir;
    const gpa = oir.allocator;

    var best_cost: std.AutoHashMapUnmanaged(Class.Index, u32) = .{};
    defer best_cost.deinit(gpa);

    var changed: bool = true;
    while (changed) {
        changed = false;

        var iter = oir.classes.iterator();
        while (iter.next()) |entry| {
            const class_idx = entry.key_ptr.*;
            const class = entry.value_ptr.*;

            for (class.bag.items) |node_idx| {
                const node = oir.getNode(node_idx);

                var total: u32 = cost.getCost(node.tag);
                for (node.operands(oir)) |child| {
                    const child_cost = best_cost.get(oir.union_find.find(child)) orelse infinite;
                    if (child_cost == infinite) {
                        total = infinite;
                        break;
                    }
                    total += child_cost;
                }
                if (total == infinite) continue;

                // We always prefer a non-load instruction to a load one.
                const cur_node = e.best_node.get(class_idx);
                const cur_cost = best_cost.get(class_idx) orelse infinite;
                const new_is_load = node.tag == .load;
                const better = better: {
                    const cb = cur_node orelse break :better true;
                    const cur_is_load = oir.getNode(cb).tag == .load;
                    if (cur_is_load != new_is_load) break :better !new_is_load;
                    break :better total < cur_cost;
                };
                if (better) {
                    try best_cost.put(gpa, class_idx, total);
                    try e.best_node.put(gpa, class_idx, node_idx);
                    changed = true;
                }
            }
        }
    }
}

fn extractClass(e: *SimpleExtractor, class_idx: Class.Index, recv: *Recursive) !Class.Index {
    const oir = e.oir;
    const gpa = oir.allocator;

    if (e.map.get(class_idx)) |memo| return memo;

    const best_node_idx = e.best_node.get(e.oir.union_find.find(class_idx)).?;
    const best_node = oir.getNode(best_node_idx);

    switch (best_node.tag) {
        .start => {
            const new_node: Node = .{ .tag = .start, .data = .{ .list = .empty } };
            const idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, idx);
            return idx;
        },
        .project => {
            const project = best_node.data.project;

            const tuple = try e.extractClass(project.tuple, recv);

            const new_node: Node = .project(project.index, tuple, project.type, project.bits);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .store => {
            const ops = best_node.data.store.ops;

            if (alias.decompose(oir, ops[1]).base) |id| {
                if (e.dead_slots.contains(id)) {
                    const pred = try e.extractClass(ops[0], recv);
                    try e.map.put(gpa, class_idx, pred);
                    return pred;
                }
            }

            const mem_state = try e.extractClass(ops[0], recv);
            const address = try e.extractClass(ops[1], recv);
            const value = try e.extractClass(ops[2], recv);

            const new_node: Node = .store(mem_state, address, value, best_node.data.store.bits);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .ret => {
            const results = best_node.data.list.toSlice(oir);

            var extracted: std.ArrayList(Class.Index) = .empty;
            defer extracted.deinit(gpa);
            for (results) |result| {
                try extracted.append(gpa, try e.extractClass(@enumFromInt(result), recv));
            }

            const span = try recv.listToSpan(extracted.items, gpa);
            const new_node: Node = .ret(span);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .gamma => {
            const tri_op = best_node.data.tri_op;

            const pred = try e.extractClass(tri_op[0], recv);
            const then = try e.extractClass(tri_op[1], recv);
            const els = try e.extractClass(tri_op[2], recv);

            const new_node: Node = .gamma(pred, then, els);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .theta => {
            const loop = best_node.data.loop;

            var body: std.ArrayList(Class.Index) = .empty;
            defer body.deinit(gpa);
            for (loop.args(oir)) |c| try body.append(gpa, try e.extractClass(c, recv));
            for (loop.inits(oir)) |c| try body.append(gpa, try e.extractClass(c, recv));
            try body.append(gpa, try e.extractClass(loop.pred(oir), recv));
            for (loop.nexts(oir)) |c| try body.append(gpa, try e.extractClass(c, recv));

            const span = try recv.listToSpan(body.items, gpa);
            const new_node: Node = .theta(loop.id, loop.count, span);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .loopvar => {
            const lv = best_node.data.loopvar;
            const new_node_idx = try recv.addNode(gpa, .loopvar(lv.loop, lv.index, lv.bits));
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .lambda => {
            const lambda = best_node.data.lambda;

            var results: std.ArrayList(Class.Index) = .empty;
            defer results.deinit(gpa);
            for (lambda.results(oir)) |c| try results.append(gpa, try e.extractClass(c, recv));

            const span = try recv.listToSpan(results.items, gpa);
            const new_node_idx = try recv.addNode(gpa, .lambda(lambda.id, lambda.params, span));
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .param => {
            const p = best_node.data.param;
            const new_node_idx = try recv.addNode(gpa, .param(p.lambda, p.index, p.bits));
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .call => {
            const c = best_node.data.call;

            var body: std.ArrayList(Class.Index) = .empty;
            defer body.deinit(gpa);
            try body.append(gpa, try e.extractClass(c.mem(oir), recv));
            for (c.args(oir)) |a| try body.append(gpa, try e.extractClass(a, recv));

            const span = try recv.listToSpan(body.items, gpa);
            const new_node_idx = try recv.addNode(gpa, .call(c.callee, span));
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .cmp_eq,
        .cmp_gt,
        .cmp_lt,
        .cmp_ult,
        .cmp_ugt,
        .add,
        .sub,
        .mul,
        .@"and",
        .@"or",
        .shl,
        .shr,
        .sar,
        .div_trunc,
        .udiv,
        .div_exact,
        => {
            const bin_op = best_node.data.bin_op;

            const lhs = try e.extractClass(bin_op[0], recv);
            const rhs = try e.extractClass(bin_op[1], recv);

            const new_node: Node = .binOp(best_node.tag, lhs, rhs);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .trunc,
        .sext,
        .zext,
        => {
            const cast = best_node.data.cast;
            const operand = try e.extractClass(cast.operand, recv);
            const new_node: Node = switch (best_node.tag) {
                .trunc => .trunc(operand, cast.bits),
                .sext => .sext(operand, cast.bits),
                .zext => .zext(operand, cast.bits),
                else => unreachable,
            };
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .load => {
            const load = best_node.data.load;
            const mem_state = try e.extractClass(load.ops[0], recv);
            const address = try e.extractClass(load.ops[1], recv);
            const new_node: Node = .load(mem_state, address, load.bits);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .constant, .alloca => {
            const idx = try recv.addNode(gpa, best_node);
            try e.map.put(gpa, class_idx, idx);
            return idx;
        },
    }
}

pub fn deinit(e: *SimpleExtractor) void {
    const allocator = e.oir.allocator;
    e.best_node.deinit(allocator);
    e.map.deinit(allocator);
    e.dead_slots.deinit(allocator);
}
