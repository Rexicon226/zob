//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,

/// Represents the list of all E-Nodes in the graph.
nodes: std.ArrayListUnmanaged(Node) = .{},

/// Represents the list of all E-Classes in the graph.
///
/// Each E-Class contains a bundle of nodes which are equivalent to each other.
classes: std.ArrayListUnmanaged(Class) = .{},

/// A map relating nodes to the classes they are in. Used as a fast way to determine
/// what "parent" class a node is in.
node_to_class: std.AutoHashMapUnmanaged(Node.Index, Class.Index) = .{},

pub const Node = struct {
    tag: Tag,
    data: Data = .none,

    /// Nodes only have edges to Classes.
    out: std.ArrayListUnmanaged(Class.Index) = .{},

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

    pub const Tag = enum(u8) {
        arg,
        add,
        sub,
        mul,
        shl,
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

/// A Class contains an N amount of Nodes as children.
pub const Class = struct {
    bag: std.ArrayListUnmanaged(Node.Index) = .{},

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
    fn addNode(class: *Class, oir: *Oir, node: Node) !void {
        const new_idx: Node.Index = @enumFromInt(oir.nodes.items.len);
        try oir.nodes.append(oir.allocator, node);
        try class.bag.append(oir.allocator, new_idx);
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
        var buffer: std.ArrayListUnmanaged(Node.Index) = .{};
        defer buffer.deinit(oir.allocator);

        var did_something: bool = false;
        for (oir.classes.items, 0..) |*class, class_idx| {
            // the class has already been solved for a constant, no need to do anything else!
            if (oir.classContains(@enumFromInt(class_idx), .constant) != null) continue;

            for (class.bag.items) |node_idx| {
                defer buffer.clearRetainingCapacity();

                const node = oir.getNode(node_idx);

                for (node.out.items) |child_idx| {
                    if (oir.classContains(child_idx, .constant)) |constant_idx| {
                        try buffer.append(oir.allocator, constant_idx);
                    }
                }

                // all nodes are constants
                if (buffer.items.len == node.tag.numNodeArgs() and
                    !node.tag.isVolatile())
                {
                    did_something = true;

                    switch (node.tag) {
                        .add,
                        .mul,
                        => {
                            const lhs, const rhs = buffer.items[0..2].*;
                            const lhs_value = oir.getNode(lhs).data.constant;
                            const rhs_value = oir.getNode(rhs).data.constant;

                            const result = switch (node.tag) {
                                .add => lhs_value + rhs_value,
                                .mul => lhs_value * rhs_value,
                                else => unreachable,
                            };
                            try class.addNode(oir, .{
                                .tag = .constant,
                                .data = .{ .constant = result },
                            });
                        },
                        else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
                    }
                }
            }
        }

        return did_something;
    }

    /// Replaces trivially expensive operations with cheaper equivalents.
    fn strengthReduce(oir: *Oir) !bool {
        for (oir.nodes.items, 0..) |node, node_idx| {
            if (node.tag.isVolatile()) continue;

            switch (node.tag) {
                .mul => {
                    // metadata for the pass
                    const Meta = struct {
                        value: u64,
                        other_class: Class.Index,
                    };
                    var meta: ?Meta = null;

                    for (node.out.items, 0..) |class_idx, i| {
                        if (oir.classContains(class_idx, .constant)) |value_idx| {
                            const value: u64 = @intCast(oir.getNode(value_idx).data.constant);
                            if (std.math.isPowerOfTwo(value)) {
                                meta = .{
                                    .value = value,
                                    .other_class = node.out.items[i ^ 1], // trick to get the other one
                                };
                            }
                        }
                    }

                    const mul_class_idx = oir.findClass(@enumFromInt(node_idx));

                    // TODO: to avoid infinite loops, just check if a "shl" node already exists in the class
                    // this isn't a very good solution since there could be multiple non-identical shl in the class.
                    // node tagging maybe?

                    for (oir.getClass(mul_class_idx).bag.items) |mul_node_idx| {
                        const mul_node = oir.getNode(mul_node_idx);
                        if (mul_node.tag == .shl) return false;
                    }

                    if (meta) |resolved_meta| {
                        const value = resolved_meta.value;
                        const new_value = std.math.log2_int(u64, value);

                        // create the (shl ?x @log2($)) node instead of the mul class
                        const shift_value_idx = try oir.add(.{
                            .tag = .constant,
                            .data = .{ .constant = @intCast(new_value) },
                        });

                        var new_node: Node = .{ .tag = .shl };
                        try new_node.out.append(oir.allocator, resolved_meta.other_class);
                        try new_node.out.append(oir.allocator, shift_value_idx);

                        const class_ptr = oir.getClassPtr(mul_class_idx);
                        try class_ptr.addNode(oir, new_node);

                        return true;
                    }
                },
                else => {},
            }
        }

        return false;
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
            while (true) {
                var new_change: bool = false;
                inline for (passes) |pass| {
                    if (try pass(oir)) new_change = true;
                }
                if (!new_change) break;
            }
        },
    }
}

/// Adds an ENode to the EGraph, giving the node its own class.
/// Returns the EClass index the ENode was placed in.
pub fn add(oir: *Oir, node: Node) !Class.Index {
    const node_idx = try oir.addNode(node);

    var class: Class = .{};
    try class.bag.append(oir.allocator, node_idx);

    const class_idx: Class.Index = @enumFromInt(oir.classes.items.len);
    try oir.classes.append(oir.allocator, class);

    // store this relationship in node_to_class
    try oir.node_to_class.put(oir.allocator, node_idx, class_idx);

    return class_idx;
}

/// An internal function to simplify adding nodes to the Oir.
///
/// It should be used carefully as it invalidates the equality invariance of the graph.
/// You need to either rebuild the graph, or this is for an extracted Oir which does not
/// hold any invariance.
fn addNode(oir: *Oir, node: Node) !Node.Index {
    const node_idx: Node.Index = @enumFromInt(oir.nodes.items.len);
    try oir.nodes.append(oir.allocator, node);
    return node_idx;
}

/// Performs the "union" operation on the graph.
///
/// This can be thought of as "merging" two classes. When they were
/// proven to be equivalent.
pub fn @"union"(oir: *Oir, a_idx: Class.Index, b_idx: Class.Index) !void {
    if (a_idx != b_idx) {
        log.debug("union class {} -> {}", .{ a_idx, b_idx });

        const class_a = oir.getClassPtr(a_idx);
        const class_b = oir.getClassPtr(b_idx);

        // Replace all connections to class_b with class_a
        for (oir.nodes.items) |*node| {
            for (node.out.items) |*node_class_idx| {
                if (node_class_idx.* == b_idx) {
                    node_class_idx.* = a_idx;
                }
            }
        }

        // Move all nodes inside of class_b into class_a
        for (class_b.bag.items) |node_id| {
            try class_a.bag.append(oir.allocator, node_id);

            // TODO: if a node in the bag references class_b here, we need to change the reference to class_a
        }
        class_b.bag.clearRetainingCapacity();
    }
}

pub fn deinit(oir: *Oir) void {
    const allocator = oir.allocator;
    oir.node_to_class.deinit(allocator);

    for (oir.nodes.items) |*node| {
        node.out.deinit(allocator);
    }
    oir.nodes.deinit(allocator);

    for (oir.classes.items) |*class| {
        class.bag.deinit(allocator);
    }
    oir.classes.deinit(allocator);
}

/// Returns the `Class.Index` that the provided `idx` is in.
pub fn findClass(oir: *Oir, idx: Node.Index) Class.Index {
    return oir.node_to_class.get(idx).?;
}

pub fn getNode(oir: *Oir, idx: Node.Index) Node {
    return oir.nodes.items[@intFromEnum(idx)];
}

/// Returns a pointer to the node. Only valid until a new node is added
/// to the graph.
pub fn getNodePtr(oir: *Oir, idx: Node.Index) *Node {
    return &oir.nodes.items[@intFromEnum(idx)];
}

pub fn getClass(oir: *Oir, idx: Class.Index) Class {
    return oir.classes.items[@intFromEnum(idx)];
}

/// Returns a pointer to the class. Only valid until a new class is added
/// to the graph.
pub fn getClassPtr(oir: *Oir, idx: Class.Index) *Class {
    return &oir.classes.items[@intFromEnum(idx)];
}

/// Checks if a class contains a constant equivalence node, and returns it.
/// Otherwise returns `null`.
///
/// Can only return absorbing element types such as `constant`.
pub fn classContains(oir: *Oir, idx: Class.Index, comptime tag: Node.Tag) ?Node.Index {
    comptime assert(tag.isAbsorbing());

    const class = oir.getClass(idx);
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);

        // Since the node is aborbing, we can return early as no other
        // instances of it are allowed in the same class.
        if (node.tag == tag) return node_idx;
    }

    return null;
}

const Oir = @This();
const IR = @import("Ir.zig");
const std = @import("std");

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
