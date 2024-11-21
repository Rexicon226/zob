//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,

/// Represents the list of all E-Classes in the graph.
///
/// Each E-Class contains a bundle of nodes which are equivalent to each other.
classes: std.AutoHashMapUnmanaged(Class.Index, Class) = .{},

/// TODO: silly hack for now, when node_to_class matches, we run into an issue where
/// we can't deinit the node in a clean way. just throwing it in here for now to not leak,
/// but we really should use the more DOD design of having an arraylist of nodes.
discarded_nodes: std.ArrayListUnmanaged(Node) = .{},

/// A map relating nodes to the classes they are in. Used as a fast way to determine
/// what "parent" class a node is in.
node_to_class: std.HashMapUnmanaged(
    Node,
    Class.Index,
    NodeContext,
    std.hash_map.default_max_load_percentage,
) = .{},

find: Find = .{},

/// A list of pending `Pair`s which have made the E-Graph unclean. This is a part of incremental
/// rebuilding and lets the graph process faster. `add` and `union` dirty the graph, marking `clean`
/// as false, and then `rebuild` will iterate through the pending items to analyze and mark `clean`
/// as true.
pending: std.ArrayListUnmanaged(Pair) = .{},

/// Indicates whether or not reading type operations are allowed on the E-Graph.
///
/// Mutating operations set this to `false`, and `rebuild` will set it back to `true`.
clean: bool = false,

const Find = struct {
    parents: std.ArrayListUnmanaged(Class.Index) = .{},

    fn makeSet(f: *Find, gpa: std.mem.Allocator) !Class.Index {
        const id: Class.Index = @enumFromInt(f.parents.items.len);
        try f.parents.append(gpa, id);
        return id;
    }

    fn parent(f: *Find, idx: Class.Index) Class.Index {
        return f.parents.items[@intFromEnum(idx)];
    }

    fn find(f: *Find, idx: Class.Index) Class.Index {
        var current = idx;
        while (current != f.parent(idx)) {
            current = f.parent(idx);
        }
        return current;
    }

    fn @"union"(f: *Find, a: Class.Index, b: Class.Index) Class.Index {
        f.parents.items[@intFromEnum(b)] = a;
        return a;
    }

    fn deinit(f: *Find, gpa: std.mem.Allocator) void {
        f.parents.deinit(gpa);
    }
};

pub const NodeContext = struct {
    pub fn hash(_: NodeContext, node: Node) u64 {
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&node.tag));
        std.hash.autoHash(&hasher, node.data);
        std.hash.autoHash(&hasher, node.out.items.len);
        for (node.out.items) |idx| {
            std.hash.autoHash(&hasher, idx);
        }

        return hasher.final();
    }

    pub fn eql(_: NodeContext, a: Node, b: Node) bool {
        if (a.tag != b.tag) return false;
        if (std.meta.activeTag(a.data) != std.meta.activeTag(b.data)) return false;
        // b.data would also be `constant` because of the above check
        if (a.data == .constant) {
            assert(a.out.items.len == 0 and b.out.items.len == 0);
            return a.data.constant == b.data.constant;
        }
        if (a.out.items.len != b.out.items.len) return false;

        std.sort.heap(Class.Index, a.out.items, {}, lessThanClass);
        std.sort.heap(Class.Index, b.out.items, {}, lessThanClass);

        for (a.out.items, b.out.items) |a_class, b_class| {
            if (a_class != b_class) return false;
        }

        return true;
    }

    fn lessThanClass(_: void, a: Class.Index, b: Class.Index) bool {
        return @intFromEnum(a) < @intFromEnum(b);
    }
};

pub const Node = struct {
    tag: Tag,
    data: Data = .none,

    /// Nodes only have edges to Classes.
    out: std.ArrayListUnmanaged(Class.Index) = .{},

    pub const Tag = enum(u8) {
        arg,
        add,
        sub,
        mul,
        shl,
        shr,
        div_trunc,
        div_exact,
        ret,
        constant,
        load,
        store,

        /// Returns the number of arguments that are other nodes.
        /// Does not include constants,
        pub fn numNodeArgs(tag: Tag) u32 {
            return switch (tag) {
                .arg,
                .constant,
                => 0,
                .ret,
                .load,
                => 1,
                .add,
                .sub,
                .mul,
                .shl,
                .shr,
                .div_trunc,
                .div_exact,
                .store,
                => 2,
            };
        }

        pub fn isVolatile(tag: Tag) bool {
            return switch (tag) {
                .arg,
                .ret,
                => true,
                else => false,
            };
        }

        /// TODO: is this function needed? are there any absorbing node
        // types other than constant?
        pub fn isAbsorbing(tag: Tag) bool {
            return switch (tag) {
                .constant => true,
                else => false,
            };
        }
    };

    const Data = union(enum) {
        none: void,
        constant: i64,
    };
};

const Pair = struct { Node, Class.Index };

/// A Class contains an N amount of Nodes as children.
pub const Class = struct {
    index: Index,
    bag: std.ArrayListUnmanaged(Node) = .{},
    parents: std.ArrayListUnmanaged(Pair) = .{},

    pub const Index = enum(u32) {
        _,

        pub fn format(
            idx: Index,
            comptime fmt: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            assert(fmt.len == 0);
            try writer.print("%{d}", .{@intFromEnum(idx)});
        }
    };

    /// Creates a new node and adds it to the class.
    ///
    /// NOTE: shouldn't be called inside of optimization passes.
    /// unions are required.
    fn addNode(class: *Class, oir: *Oir, node: Node) !void {
        try class.bag.append(oir.allocator, node);
    }
};

pub const CostStrategy = enum {
    /// A super basic cost strategy that simply looks at the number of child nodes
    /// a particular node has to determine its cost.
    num_nodes,
};

/// Takes in an `IR`, meant to represent a basic version of Zig's AIR
/// and does some basic analysis to convert it to an Oir. Since AIR is
/// a linear graph, each new node has its own class.
///
/// TODO: run a rebuild of the graph at the end of constructing the Oir
/// to remove things such as duplicate constants which wouldn't be caught.
pub fn fromIr(ir: IR, allocator: std.mem.Allocator) !Oir {
    var oir: Oir = .{ .allocator = allocator };

    const tags = ir.instructions.items(.tag);
    const data = ir.instructions.items(.data);

    var ir_to_class: std.AutoHashMapUnmanaged(IR.Inst.Index, Class.Index) = .{};
    defer ir_to_class.deinit(allocator);

    for (tags, data, 0..) |tag, payload, i| {
        log.debug("tag: {s} : {s}", .{ @tagName(tag), @tagName(payload) });

        // TODO: unify the two Tag enums
        const convert_tag: Oir.Node.Tag = switch (tag) {
            .ret => .ret,
            .mul => .mul,
            .arg => .arg,
            .shl => .shl,
            .add => .add,
            .sub => .sub,
            .div_exact => .div_exact,
            .div_trunc => .div_trunc,
            .load => .load,
            .store => .store,
        };

        const inst: IR.Inst.Index = @enumFromInt(i);
        switch (tag.numNodeArgs()) {
            1 => {
                var node: Node = .{ .tag = convert_tag };

                const op = payload.un_op;
                switch (op) {
                    .index => |index| {
                        const class_idx = ir_to_class.get(index).?;
                        try node.out.append(allocator, class_idx);

                        const idx = try oir.add(node);
                        try ir_to_class.put(allocator, inst, idx);
                    },
                    .value => |value| {
                        // materialize the implicit constant node
                        const const_node: Node = .{
                            .tag = .constant,
                            .data = .{ .constant = value },
                        };
                        const const_idx = try oir.add(const_node);
                        try node.out.append(allocator, const_idx);
                        const idx = try oir.add(node);
                        try ir_to_class.put(allocator, inst, idx);
                    },
                }
            },
            2,
            => {
                var node: Node = .{ .tag = convert_tag };

                const bin_op = payload.bin_op;
                inline for (.{ bin_op.lhs, bin_op.rhs }) |operand| {
                    switch (operand) {
                        .index => |index| {
                            const class_idx = ir_to_class.get(index).?;
                            try node.out.append(allocator, class_idx);
                        },
                        .value => |value| {
                            // materialize the implicit constant node
                            const const_node: Node = .{
                                .tag = .constant,
                                .data = .{ .constant = value },
                            };
                            const const_idx = try oir.add(const_node);
                            try node.out.append(allocator, const_idx);
                        },
                    }
                }

                const idx = try oir.add(node);
                try ir_to_class.put(allocator, inst, idx);
            },
            0,
            => {
                const node: Node = .{
                    .tag = convert_tag,
                    .data = .{ .constant = payload.un_op.value },
                };
                const idx = try oir.add(node);
                try ir_to_class.put(allocator, inst, idx);
            },
            else => std.debug.panic("TODO: find {s}", .{@tagName(tag)}),
        }
    }

    return oir;
}

const Passes = struct {
    /// Iterates through all nodes in the E-Graph,
    /// checking if it's possible to evaluate them now.
    ///
    /// If a node is found with "comptime-known" children,
    /// it's evaluated and the new "comptime-known" result is added
    /// to that node's class.
    fn constantFold(oir: *Oir) !bool {
        var buffer: std.ArrayListUnmanaged(Node) = .{};
        defer buffer.deinit(oir.allocator);

        var changed: bool = false;

        var iterator = oir.classes.iterator();
        while (iterator.next()) |entry| {
            const class_idx = entry.key_ptr.*;
            const class = entry.value_ptr;

            // the class has already been solved for a constant, no need to do anything else!
            if (oir.classContains(class_idx, .constant) != null) continue;

            for (class.bag.items) |node| {
                assert(node.tag != .constant);
                defer buffer.clearRetainingCapacity();

                for (node.out.items) |child_idx| {
                    if (oir.classContains(child_idx, .constant)) |constant| {
                        try buffer.append(oir.allocator, constant);
                    }
                }

                // all nodes are constants
                assert(buffer.items.len <= node.tag.numNodeArgs());
                if (buffer.items.len == node.tag.numNodeArgs() and
                    !node.tag.isVolatile())
                {
                    changed = true;
                    switch (node.tag) {
                        .add,
                        .mul,
                        => {
                            const lhs, const rhs = buffer.items[0..2].*;
                            const lhs_value = lhs.data.constant;
                            const rhs_value = rhs.data.constant;

                            const result = switch (node.tag) {
                                .add => lhs_value + rhs_value,
                                .mul => lhs_value * rhs_value,
                                else => unreachable,
                            };

                            const new_class = try oir.add(.{
                                .tag = .constant,
                                .data = .{ .constant = result },
                            });
                            _ = try oir.@"union"(new_class, class_idx);
                            oir.rebuild();
                        },
                        else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
                    }
                }
            }
        }

        return changed;
    }

    /// Replaces trivially expensive operations with cheaper equivalents.
    fn strengthReduce(oir: *Oir) !bool {
        var changed: bool = false;

        var iterator = oir.classes.iterator();
        while (iterator.next()) |entry| {
            const class_idx = entry.key_ptr.*;
            const class = entry.value_ptr;
            for (class.bag.items) |node| {
                if (node.tag.isVolatile()) continue;

                switch (node.tag) {
                    .mul,
                    .div_exact,
                    => {
                        // metadata for the pass
                        const Meta = struct {
                            value: u64,
                            other_class: Class.Index,
                        };
                        var meta: ?Meta = null;

                        for (node.out.items, 0..) |sub_idx, i| {
                            if (oir.classContains(sub_idx, .constant)) |sub_node| {
                                const value: u64 = @intCast(sub_node.data.constant);
                                if (std.math.isPowerOfTwo(value)) {
                                    meta = .{
                                        .value = value,
                                        .other_class = node.out.items[i ^ 1], // trick to get the other one
                                    };
                                }
                            }
                        }

                        const rewritten_tag: Oir.Node.Tag = switch (node.tag) {
                            .mul => .shl,
                            .div_exact => .shr,
                            else => unreachable,
                        };

                        // TODO: to avoid infinite loops, just check if a "shl" node already exists in the class
                        // this isn't a very good solution since there could be multiple non-identical shl in the class.
                        // node tagging maybe?
                        var skip: bool = false;
                        for (class.bag.items) |sub_node| {
                            if (sub_node.tag == rewritten_tag) {
                                changed = false;
                                skip = true;
                            }
                        }
                        if (skip) continue;

                        if (meta) |resolved_meta| {
                            changed = true;
                            const value = resolved_meta.value;
                            const new_value = std.math.log2_int(u64, value);

                            // create the (shl ?x @log2($)) node instead of the mul class
                            const shift_value_idx = try oir.add(.{
                                .tag = .constant,
                                .data = .{ .constant = @intCast(new_value) },
                            });

                            var new_node: Node = .{ .tag = rewritten_tag };
                            try new_node.out.append(oir.allocator, resolved_meta.other_class);
                            try new_node.out.append(oir.allocator, shift_value_idx);

                            const new_class = try oir.add(new_node);
                            _ = try oir.@"union"(new_class, class_idx);
                        }
                    },
                    else => {},
                }
            }
        }

        return changed;
    }
};

const passes = &.{
    Passes.constantFold,
    Passes.strengthReduce,
};

pub fn optimize(oir: *Oir, mode: enum {
    /// Optimize until running all passes creates no new changes.
    /// NOTE: likely will be very slow for any large input
    saturate,
}) !void {
    switch (mode) {
        .saturate => {
            oir.rebuild();
            while (true) {
                var new_change: bool = false;
                inline for (passes) |pass| {
                    if (try pass(oir)) new_change = true;

                    // TODO: in theory we don't actually need to rebuild after every pass
                    // maybe we should look into rebuilding on demand?
                    if (!oir.clean) oir.rebuild();
                }
                if (!new_change) break;
            }
        },
    }
}

/// Reference becomes invalid when new classes are adedd to the graph.
fn getClassPtr(oir: *Oir, idx: Class.Index) *Class {
    const found = oir.find.find(idx);
    return oir.classes.getPtr(found).?;
}

/// Adds an ENode to the EGraph, giving the node its own class.
/// Returns the EClass index the ENode was placed in.
pub fn add(oir: *Oir, node: Node) !Class.Index {
    log.debug("adding node {s}", .{@tagName(node.tag)});
    const class_idx = try oir.addInternal(node);
    return oir.find.find(class_idx);
}

/// An internal function to simplify adding nodes to the Oir.
///
/// It should be used carefully as it invalidates the equality invariance of the graph.
fn addInternal(oir: *Oir, node: Node) !Class.Index {
    if (oir.node_to_class.get(node)) |class_idx| {
        try oir.discarded_nodes.append(oir.allocator, node);
        return class_idx;
    } else {
        const id = try oir.makeClass(node);
        oir.clean = false;
        return id;
    }
}

fn makeClass(oir: *Oir, node: Node) !Class.Index {
    const id = try oir.find.makeSet(oir.allocator);
    log.debug("adding to {}", .{id});

    var class: Class = .{
        .index = id,
        .bag = .{},
    };
    try class.bag.append(oir.allocator, node);

    for (node.out.items) |child| {
        const class_ptr = oir.getClassPtr(child);
        try class_ptr.parents.append(oir.allocator, .{ node, id });
    }

    try oir.classes.put(oir.allocator, id, class);
    try oir.node_to_class.putNoClobber(oir.allocator, node, id);

    return id;
}

/// Performs the "union" operation on the graph.
///
/// Returns whether a union needs to happen. `true` is they are already equivalent
///
/// This can be thought of as "merging" two classes. When they were
/// proven to be equivalent.
pub fn @"union"(oir: *Oir, a_idx: Class.Index, b_idx: Class.Index) !bool {
    oir.clean = false;
    var a = oir.find.find(a_idx);
    var b = oir.find.find(b_idx);
    if (a == b) return false;

    const a_parents = oir.classes.get(a).?.parents.items.len;
    const b_parents = oir.classes.get(b).?.parents.items.len;

    if (a_parents < b_parents) {
        std.mem.swap(Class.Index, &a, &b);
    }

    log.debug("union on {} -> {}", .{ b, a });

    _ = oir.find.@"union"(a, b);

    assert(a != b);
    var b_class = oir.classes.fetchRemove(b).?.value;
    defer {
        b_class.bag.deinit(oir.allocator);
        b_class.parents.deinit(oir.allocator);
    }

    const a_class = oir.classes.getPtr(a).?;
    assert(a == a_class.index);

    try oir.pending.appendSlice(oir.allocator, b_class.parents.items);
    try a_class.bag.appendSlice(oir.allocator, b_class.bag.items);
    try a_class.parents.appendSlice(oir.allocator, b_class.parents.items);

    return true;
}

/// Performs a rebuild of the E-Graph to ensure that the invariances are met.
///
/// Currently this looks over hashes of the nodes and merges duplicate nodes.
/// We can hash based on the class indices themselves, as they don't change during the
/// rebuild.
pub fn rebuild(oir: *Oir) void {
    // the simplest version for now will just be iterating through the nodes
    // inside of a class, and finding duplicate nodes inside of them and deleting those.
    // TODO: later we need to perform unions on classes that are proven duplicate.

    log.debug("rebuilding", .{});

    while (oir.pending.popOrNull()) |pair| {
        const node, const class_idx = pair;
        std.debug.print("node: {}, class_idx: {}\n", .{ node, class_idx });
    }

    var iter = oir.classes.valueIterator();
    while (iter.next()) |class| {
        for (class.bag.items) |node| {
            for (node.out.items) |*child| {
                child.* = oir.find.find(child.*);
            }
        }
    }

    oir.clean = true;
}

pub fn deinit(oir: *Oir) void {
    const allocator = oir.allocator;

    {
        var iter = oir.classes.valueIterator();
        while (iter.next()) |class| {
            class.parents.deinit(allocator);
            class.bag.deinit(allocator);
        }
        oir.classes.deinit(allocator);
    }

    {
        var iter = oir.node_to_class.keyIterator();
        while (iter.next()) |node| {
            node.out.deinit(allocator);
        }

        oir.node_to_class.deinit(allocator);
    }

    oir.find.deinit(allocator);
    for (oir.discarded_nodes.items) |*node| {
        node.out.deinit(allocator);
    }
    oir.discarded_nodes.deinit(allocator);
    oir.pending.deinit(allocator);
}

/// Checks if a class contains a constant equivalence node, and returns it.
/// Otherwise returns `null`.
///
/// Can only return absorbing element types such as `constant`.
pub fn classContains(oir: *Oir, idx: Class.Index, comptime tag: Node.Tag) ?Node {
    comptime assert(tag.isAbsorbing());
    assert(oir.clean);

    const class = oir.classes.get(idx).?;
    for (class.bag.items) |node| {
        // Since the node is aborbing, we can return early as no other
        // instances of it are allowed in the same class.
        if (node.tag == tag) return node;
    }

    return null;
}

const Oir = @This();
const IR = @import("Ir.zig");
const std = @import("std");

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
