//! Super basic Oir extractor implementation.

const std = @import("std");
const Oir = @import("../Oir.zig");
const cost = @import("../cost.zig");
const extraction = @import("extraction.zig");

const Class = Oir.Class;
const Node = Oir.Node;
const SimpleExtractor = @This();
const Recursive = extraction.Recursive;

const log = std.log.scoped(.simple_extractor);
const assert = std.debug.assert;

oir: *const Oir,

/// Describes cycles found in the OIR. EGraphs are allowed to have cycles,
/// they are not DAGs. However, it's impossible to extract a "best node"
/// from a cyclic class pattern so we must skip them. If after iterating through
/// all of the nodes in a class we can't find one that doesn't cycle, this means
/// the class itself cycles and the graph is unsolvable.
///
/// The key is a cyclic node index and the value is the index of the class
/// which references the class the node is in.
cycles: std.AutoHashMapUnmanaged(Node.Index, Class.Index),

/// Relates class indicies to the best node in them. Since the classes
/// are immutable after the OIR optimization passes, we can confidently
/// reuse the extraction. This amortization makes our extraction strategy
/// just barely usable.
cost_memo: std.AutoHashMapUnmanaged(Class.Index, NodeCost),

start_class: ?Class.Index,

best_node: std.AutoHashMapUnmanaged(Class.Index, Node.Index),
map: std.AutoHashMapUnmanaged(Class.Index, Class.Index),

exit_list: std.ArrayListUnmanaged(Class.Index),

const NodeCost = struct {
    u32,
    Node.Index,
};

/// Extracts the best pattern of Oir from the E-Graph given a cost model.
pub fn extract(oir: *const Oir) !Recursive {
    var e: SimpleExtractor = .{
        .oir = oir,
        .cycles = try oir.findCycles(),
        .cost_memo = .empty,
        .best_node = .{},
        .map = .{},
        .exit_list = .{},
        .start_class = null,
    };
    defer e.deinit();

    log.debug("cycles found: {}", .{e.cycles.count()});

    {
        var iter = oir.classes.valueIterator();
        while (iter.next()) |class| {
            const best_node = try e.getBestNode(class.index);
            try e.best_node.put(oir.allocator, class.index, best_node);
        }
    }

    var recv: Recursive = .{};
    for (oir.exit_list.items) |exit| {
        _ = try e.extractClass(exit, &recv);
    }
    recv.exit_list = try e.exit_list.clone(oir.allocator);

    return recv;
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
            if (e.start_class != null) @panic("found two start nodes?");
            e.start_class = idx;
            try e.map.put(gpa, class_idx, idx);
            return idx;
        },
        .project => {
            const project = best_node.data.project;

            const tuple = try e.extractClass(project.tuple, recv);

            const new_node: Node = .project(project.index, tuple, project.type);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .load => {
            const un_op = best_node.data.un_op;

            const operand = try e.extractClass(un_op, recv);

            const new_node: Node = .{
                .tag = best_node.tag,
                .data = .{ .un_op = operand },
            };
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            return new_node_idx;
        },
        .ret,
        .branch,
        .cmp_gt,
        .add,
        .sub,
        .shl,
        .shr,
        => {
            const bin_op = best_node.data.bin_op;

            const lhs = try e.extractClass(bin_op[0], recv);
            const rhs = try e.extractClass(bin_op[1], recv);

            const new_node: Node = .binOp(best_node.tag, lhs, rhs);
            const new_node_idx = try recv.addNode(gpa, new_node);
            try e.map.put(gpa, class_idx, new_node_idx);
            switch (best_node.tag) {
                .ret => try e.exit_list.append(gpa, new_node_idx),
                else => {},
            }
            return new_node_idx;
        },
        .constant => {
            const idx = try recv.addNode(gpa, best_node);
            try e.map.put(gpa, class_idx, idx);
            return idx;
        },
        .dead => unreachable,
        else => std.debug.panic("TODO: extractClass {s}\n", .{@tagName(best_node.tag)}),
    }
}

fn getBestNode(e: *SimpleExtractor, class_idx: Class.Index) !Node.Index {
    _, const best_node = try e.extractBestNode(class_idx);

    log.debug("best node for class {} is {s}", .{
        class_idx,
        @tagName(e.oir.getNode(best_node).tag),
    });

    return best_node;
}

/// Given a class, extract the "best" node from it.
fn extractBestNode(e: *SimpleExtractor, class_idx: Class.Index) !NodeCost {
    const oir = e.oir;
    const class = oir.classes.get(class_idx).?;
    assert(class.bag.items.len > 0);

    if (e.cost_memo.get(class_idx)) |entry| return entry;

    var best_cost: u32 = std.math.maxInt(u32);
    var best_node: Node.Index = class.bag.items[0];

    for (class.bag.items) |node_idx| {
        // the node is known to cycle, we must skip it.
        if (e.cycles.get(node_idx) != null) continue;

        const node = oir.getNode(node_idx);

        const base_cost = cost.getCost(node.tag);
        var child_cost: u32 = 0;
        for (node.operands(oir)) |sub_class_idx| {
            assert(sub_class_idx != class_idx); // checked for cycles above

            const extracted_cost, _ = try e.extractBestNode(sub_class_idx);
            child_cost += extracted_cost;
        }

        const node_cost = base_cost + child_cost;

        if (node_cost < best_cost) {
            best_cost = node_cost;
            best_node = node_idx;
        }
    }
    if (best_cost == std.math.maxInt(u32)) {
        std.debug.panic("extracted cyclic terms, no best node could be found! {}", .{class_idx});
    }

    const entry: NodeCost = .{ best_cost, best_node };
    try e.cost_memo.putNoClobber(oir.allocator, class_idx, entry);
    return entry;
}

pub fn deinit(e: *SimpleExtractor) void {
    const allocator = e.oir.allocator;
    e.cost_memo.deinit(allocator);
    e.cycles.deinit(allocator);
    e.best_node.deinit(allocator);
    e.map.deinit(allocator);
    e.exit_list.deinit(allocator);
}
