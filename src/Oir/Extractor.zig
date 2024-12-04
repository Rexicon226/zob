oir: *const Oir,
allocator: std.mem.Allocator,

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
cost_memo: std.AutoHashMapUnmanaged(Class.Index, NodeCost) = .{},
cost_strategy: CostStrategy,

const NodeCost = struct {
    u32,
    Node.Index,
};

/// A form of OIR where nodes reference other nodes.
pub const Recursive = struct {
    nodes: std.ArrayListUnmanaged(Node) = .{},

    pub fn getNode(r: *Recursive, idx: Class.Index) Node {
        return r.nodes.items[@intFromEnum(idx)];
    }

    fn addNode(r: *Recursive, allocator: std.mem.Allocator, node: Node) !Class.Index {
        const idx: Class.Index = @enumFromInt(r.nodes.items.len);
        try r.nodes.append(allocator, node);
        return idx;
    }

    pub fn dump(recv: *Recursive, name: []const u8) !void {
        const graphviz_file = try std.fs.cwd().createFile(name, .{});
        defer graphviz_file.close();
        try print_oir.dumpRecvGraph(recv, graphviz_file.writer());
    }

    pub fn deinit(r: *Recursive, allocator: std.mem.Allocator) void {
        r.nodes.deinit(allocator);
    }
};

pub const CostStrategy = enum {
    /// A super basic cost strategy that simply looks at the number of child nodes
    /// a particular node has to determine its cost.
    simple_latency,
};

/// Extracts the best pattern of Oir from the E-Graph given a cost model.
pub fn extract(oir: *const Oir, cost_strategy: CostStrategy) !Recursive {
    var e: Extractor = .{
        .oir = oir,
        .allocator = oir.allocator,
        .cost_strategy = cost_strategy,
        .cycles = try oir.findCycles(),
    };
    defer e.deinit();

    log.debug("cycles found: {}", .{e.cycles.count()});

    // First we need to find what the root class is. This will usually be the class containing a `ret`,
    // or something similar.
    const ret_node_idx = e.findLeafNode();

    var recv: Recursive = .{};
    _ = try e.extractNode(ret_node_idx, &recv);

    return recv;
}

/// TODO: don't just search for a `ret` node, there can be multiple
fn findLeafNode(e: *Extractor) Node.Index {
    const oir = e.oir;
    const ret_node_idx: Node.Index = idx: {
        var class_iter = oir.classes.valueIterator();
        while (class_iter.next()) |class| {
            for (class.bag.items) |node_idx| {
                const node = oir.getNode(node_idx);
                if (node.tag == .ret) break :idx node_idx;
            }
        }
        @panic("no ret node found!");
    };

    return ret_node_idx;
}

/// Given a `Node`, walk the edges of that node to find the optimal
/// linear nodes to make up the graph. Converts the normal "node-class" relationship
/// into a "node-node" one, where the child node is extracted from its class using
/// the given cost model.
fn extractNode(
    e: *Extractor,
    node_idx: Node.Index,
    recv: *Recursive,
) !Class.Index {
    const oir = e.oir;
    const allocator = e.allocator;
    const node = oir.getNode(node_idx);

    switch (node.tag) {
        .ret => {
            const operand_idx = node.data.un_op;
            const arg_node_idx = try e.getClass(operand_idx);
            const arg_class_idx = try e.getNode(arg_node_idx, recv);

            const ret_node: Node = .{
                .tag = .ret,
                .data = .{ .un_op = arg_class_idx },
            };

            return recv.addNode(allocator, ret_node);
        },
        .arg,
        .constant,
        => return recv.addNode(allocator, node),

        .add,
        .sub,
        .shl,
        .div_exact,
        .mul,
        => {
            const rhs_class_idx, const lhs_class_idx = node.data.bin_op;
            const rhs_idx = try e.getClass(rhs_class_idx);
            const lhs_idx = try e.getClass(lhs_class_idx);

            const new_rhs_idx = try e.getNode(rhs_idx, recv);
            const new_lhs_idx = try e.getNode(lhs_idx, recv);

            const new_node: Node = .{
                .tag = node.tag,
                .data = .{ .bin_op = .{ new_rhs_idx, new_lhs_idx } },
            };

            return recv.addNode(allocator, new_node);
        },
        else => std.debug.panic("TODO: mir extractNode {s}", .{@tagName(node.tag)}),
    }
}

fn getNode(e: *Extractor, node: Node.Index, recv: *Recursive) error{OutOfMemory}!Class.Index {
    return try e.extractNode(node, recv);
}

fn getClass(e: *Extractor, class_idx: Class.Index) !Node.Index {
    _, const best_node = try e.extractClass(class_idx);

    log.debug("best node for class {} is {s}", .{
        class_idx,
        @tagName(e.oir.getNode(best_node).tag),
    });

    return best_node;
}

/// Given a class, extract the "best" node from it.
fn extractClass(e: *Extractor, class_idx: Class.Index) !NodeCost {
    const oir = e.oir;
    const class = oir.classes.get(class_idx).?;
    assert(class.bag.items.len > 0);

    if (e.cost_memo.get(class_idx)) |entry| return entry;

    switch (e.cost_strategy) {
        .simple_latency => {
            var best_cost: u32 = std.math.maxInt(u32);
            var best_node: Node.Index = class.bag.items[0];

            for (class.bag.items) |node_idx| {
                // the node is known to cycle, we must skip it.
                if (e.cycles.get(node_idx) != null) continue;

                const node = oir.getNode(node_idx);

                const base_cost = cost.getCost(node.tag);
                var child_cost: u32 = 0;
                for (node.operands()) |sub_class_idx| {
                    assert(sub_class_idx != class_idx);

                    const extracted_cost, _ = try e.extractClass(sub_class_idx);
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
        },
    }
}

pub fn deinit(e: *Extractor) void {
    const allocator = e.oir.allocator;
    e.cost_memo.deinit(allocator);
    e.cycles.deinit(allocator);
}

const std = @import("std");
const Oir = @import("../Oir.zig");
const bits = @import("../bits.zig");
const cost = @import("../cost.zig");
const print_oir = @import("print_oir.zig");

const Class = Oir.Class;
const Node = Oir.Node;
const Extractor = @This();

const log = std.log.scoped(.extractor);
const assert = std.debug.assert;
