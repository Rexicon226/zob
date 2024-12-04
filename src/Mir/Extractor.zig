oir: *Oir,
mir: *Mir,
cost_strategy: Oir.CostStrategy,
virt_map: std.AutoHashMapUnmanaged(Register, VirtualRegister) = .{},

/// Describes cycles found in the OIR. EGraphs are allowed to have cycles,
/// they are not DAGs. However, it's impossible to extract a "best node"
/// from a cyclic class pattern so we must skip them. If after iterating through
/// all of the nodes in a class we can't find one that doesn't cycle, this means
/// the class itself cycles and the graph is unsolvable.
///
/// The key is a cyclic node index and the value is the index of the class
/// which references the class the node is in.
cycles: std.AutoHashMapUnmanaged(Node.Index, Class.Index) = .{},

/// Relates class indicies to the best node in them. Since the classes
/// are immutable after the OIR optimization passes, we can confidently
/// reuse the extraction. This amortization makes our extraction strategy
/// just barely usable.
memo: std.AutoHashMapUnmanaged(Class.Index, NodeCost) = .{},

const NodeCost = struct {
    u32,
    Node.Index,
};

/// Extracts the best pattern of Oir from the E-Graph given a cost model.
pub fn extract(e: *Extractor) !void {
    // First we need to find what the root class is. This will usually be the class containing a `ret`,
    // or something similar.
    const ret_node_idx = e.findLeafNode();

    assert(e.cycles.count() == 0); // don't run extract twice!
    try e.findCycles();

    // Walk from that return node and extract the best classes.
    _ = try e.extractNode(ret_node_idx);
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
) !Value {
    const oir = e.oir;
    const mir = e.mir;
    const node = oir.getNode(node_idx);

    switch (node.tag) {
        .arg => {
            const arg_reg: Register = bits.Registers.Integer.function_arg_regs[@intCast(node.data.constant)];
            const arg_value: Value = .{ .register = arg_reg };
            const gop = try e.virt_map.getOrPut(oir.allocator, arg_reg);
            const virt_reg: VirtualRegister = blk: {
                if (gop.found_existing) {
                    break :blk gop.value_ptr.*;
                } else {
                    const virt_reg: VirtualRegister = try mir.allocVirtualReg(.int);
                    gop.value_ptr.* = virt_reg;
                    break :blk virt_reg;
                }
            };
            const dst_value: Value = .{ .virtual = virt_reg };

            try mir.copyValue(dst_value, arg_value);

            return dst_value;
        },
        .ret => {
            const class_idx = node.data.un_op;

            const arg_idx = try e.getClass(class_idx);
            const arg_value = try e.getNode(arg_idx);

            try mir.copyValue(.{ .register = .a0 }, arg_value);

            _ = try mir.addUnOp(.{
                .tag = .pseudo_ret,
                .data = .{ .register = .a0 },
            });
            return .none;
        },
        // memory operations
        .load => {
            const class_idx = node.data.un_op;

            const arg_idx = try e.getClass(class_idx);
            const arg_value = try e.getNode(arg_idx);

            const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.int) };

            _ = try mir.addUnOp(.{
                .tag = .ld, // just assuming 8-bytes for now
                .data = .{ .un_op = .{
                    .dst = dst_value,
                    .src = arg_value,
                } },
            });

            return dst_value;
        },
        // non-commutative instructions
        .div_exact,
        .mul, // putting mul here for now even though it's commutative
        => {
            const rhs_class_idx, const lhs_class_idx = node.data.bin_op;

            const rhs_idx = try e.getClass(rhs_class_idx);
            const lhs_idx = try e.getClass(lhs_class_idx);

            var rhs_value = try e.getNode(rhs_idx);
            var lhs_value = try e.getNode(lhs_idx);

            const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.int) };

            const tag: Mir.Instruction.Tag = switch (node.tag) {
                .div_exact => .div,
                .mul => .mul,
                else => unreachable,
            };

            if (lhs_value == .immediate) {
                // we want the immediate value to be rhs, uh because it looks nice!
                std.mem.swap(Value, &rhs_value, &lhs_value);
            }

            _ = try mir.addUnOp(.{
                .tag = tag,
                .data = .{ .bin_op = .{
                    .rhs = rhs_value,
                    .lhs = lhs_value,
                    .dst = dst_value,
                } },
            });

            return dst_value;
        },

        // commutative instructions with immediate versions
        .add,
        .shl,
        .shr,
        => {
            const rhs_class_idx, const lhs_class_idx = node.data.bin_op;

            const rhs_idx = try e.getClass(rhs_class_idx);
            const lhs_idx = try e.getClass(lhs_class_idx);

            var rhs_value = try e.getNode(rhs_idx);
            var lhs_value = try e.getNode(lhs_idx);

            var tag: Mir.Instruction.Tag = switch (node.tag) {
                .add => .add,
                .shl => .sll,
                .shr => .srl,
                else => unreachable,
            };

            if (rhs_value == .immediate) {
                tag = tag.immediateVersion();
            } else if (lhs_value == .immediate) {
                // we want the immediate value to be rhs
                tag = tag.immediateVersion();
                std.mem.swap(Value, &rhs_value, &lhs_value);
            }

            const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.int) };

            _ = try mir.addUnOp(.{
                .tag = tag,
                .data = .{ .bin_op = .{
                    .rhs = rhs_value,
                    .lhs = lhs_value,
                    .dst = dst_value,
                } },
            });

            return dst_value;
        },
        .constant => {
            const value: Value = .{ .immediate = node.data.constant };
            return value;
        },
        else => std.debug.panic("TODO: mir extractNode {s}", .{@tagName(node.tag)}),
    }
}

fn getNode(e: *Extractor, node: Node.Index) error{OutOfMemory}!Value {
    return e.extractNode(node);
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

    if (e.memo.get(class_idx)) |entry| return entry;

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
            try e.memo.putNoClobber(oir.allocator, class_idx, entry);
            return entry;
        },
    }
}

fn findCycles(e: *Extractor) !void {
    const oir = e.oir;
    const allocator = oir.allocator;

    const Color = enum {
        white,
        gray,
        black,
    };

    var stack = try std.ArrayList(struct { bool, Class.Index })
        .initCapacity(allocator, oir.classes.size);
    defer stack.deinit();

    var color = std.AutoHashMap(Class.Index, Color).init(allocator);
    defer color.deinit();

    {
        var iter = oir.classes.valueIterator();
        while (iter.next()) |class| {
            stack.appendAssumeCapacity(.{ true, class.index });
            try color.put(class.index, .white);
        }
    }

    var cycles: std.AutoHashMapUnmanaged(Node.Index, Class.Index) = .{};
    while (stack.popOrNull()) |entry| {
        const enter, const id = entry;
        if (enter) {
            color.getPtr(id).?.* = .gray;
            try stack.append(.{ false, id });

            const class_ptr = oir.getClassPtr(id);
            for (class_ptr.bag.items) |node_idx| {
                const node = oir.getNode(node_idx);
                for (node.operands()) |child| {
                    const child_color = color.get(child).?;
                    switch (child_color) {
                        .white => try stack.append(.{ true, child }),
                        .gray => try cycles.put(allocator, node_idx, id),
                        .black => {},
                    }
                }
            }
        } else {
            color.getPtr(id).?.* = .black;
        }
    }

    // We found some cycles!
    // if (cycles.count() > 0) {
    //     var iter = cycles.iterator();
    //     while (iter.next()) |entry| {
    //         std.debug.print("{} cycles with {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    //     }
    // }

    e.cycles = cycles;
}
pub fn deinit(e: *Extractor) void {
    const allocator = e.oir.allocator;
    e.virt_map.deinit(allocator);
    e.memo.deinit(allocator);
    e.cycles.deinit(allocator);
}

const std = @import("std");
const Oir = @import("../Oir.zig");
const Mir = @import("../Mir.zig");
const bits = @import("../bits.zig");
const cost = @import("../cost.zig");

const Register = bits.Register;
const VirtualRegister = bits.VirtualRegister;
const Class = Oir.Class;
const Node = Oir.Node;
const Value = Mir.Value;
const Extractor = @This();

const log = std.log.scoped(.extractor);
const assert = std.debug.assert;
