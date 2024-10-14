//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,
ir: IR,
ir_to_node: std.AutoHashMapUnmanaged(IR.Inst.Index, Node.Index) = .{},

cost_strat: CostStrategy = .num_nodes,

nodes: std.ArrayListUnmanaged(Node) = .{},
classes: std.ArrayListUnmanaged(Class) = .{},

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
};

pub const CostStrategy = enum {
    /// A super basic cost strategy that simply looks at the number of child nodes
    /// a particular node has to determine its cost.
    num_nodes,
};

pub fn fromIr(ir: IR, allocator: std.mem.Allocator) !Oir {
    var oir: Oir = .{
        .ir = ir,
        .allocator = allocator,
    };

    const tags = ir.instructions.items(.tag);
    const data = ir.instructions.items(.data);

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
            .constant => .constant,
            .load => .load,
            .store => .store,
        };

        const inst: IR.Inst.Index = @enumFromInt(i);
        switch (tag.numNodeArgs()) {
            1 => {
                var node: Node = .{ .tag = convert_tag };

                const op = payload.un_op;
                const op_idx = oir.resolveNode(op).?;
                const class_idx = try oir.findClass(op_idx);
                try node.out.append(allocator, class_idx);

                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            2,
            => {
                var node: Node = .{ .tag = convert_tag };

                const bin_op = payload.bin_op;
                inline for (.{ bin_op.lhs, bin_op.rhs }) |idx| {
                    const node_idx = oir.resolveNode(idx).?;
                    const class_idx = try oir.findClass(node_idx);
                    try node.out.append(allocator, class_idx);
                }

                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            0,
            => {
                const node: Node = .{
                    .tag = convert_tag,
                    .data = .{ .constant = payload.value },
                };
                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            else => std.debug.panic("TODO: find {s}", .{@tagName(tag)}),
        }
    }

    return oir;
}

pub const Rewrite = struct {
    pub const Error = error{
        OutOfMemory,
        ClassNotFound,
        Overflow,
        InvalidCharacter,
    };

    /// The S-Expr that we're trying to match for.
    pattern: []const u8,
    /// A rewrite function that's given the root index of the matched rewrite.
    rewrite: *const fn (*Oir, Node.Index) Error!void,

    pub fn applyRewrite(oir: *Oir, rewrite: Rewrite) !void {
        const allocator = oir.allocator;

        // TODO: parse sexprs at comptime in order to not parse them each time here
        var parser: SExpr.Parser = .{ .buffer = rewrite.pattern };
        const match_expr = try parser.parse(allocator);
        defer match_expr.deinit(allocator);

        const found_matches = try oir.search(match_expr);
        defer allocator.free(found_matches);

        for (found_matches) |node_idx| {
            try rewrite.rewrite(oir, node_idx);
        }
    }

    /// Searches through all nodes in the E-Graph, trying to match it to the provided pattern.
    fn search(oir: *Oir, pattern: SExpr) ![]const Node.Index {
        const allocator = oir.allocator;
        // contains the root nodes of all of the matches we got
        var matches = std.ArrayList(Node.Index).init(allocator);
        for (0..oir.nodes.items.len) |node_idx| {
            const node_index: Node.Index = @enumFromInt(node_idx);

            // matching requires us to prove equality between identifiers of the same name
            // so something like (div_exact ?x ?x), needs us to prove that ?x and ?x are the same
            // given an div_exact root node.
            // We rely on the idea of graph equality and uniqueness.
            // If they are in the same class they must be equal.
            var bindings: std.StringHashMapUnmanaged(Class.Index) = .{};
            defer bindings.deinit(allocator);

            const matched = try oir.match(node_index, pattern, &bindings);
            if (matched) {
                try matches.append(node_index);
            }
        }
        return matches.toOwnedSlice();
    }

    /// Given a root node index, returns whether it E-Matches the given pattern.
    fn match(
        oir: *Oir,
        node_idx: Node.Index,
        pattern: SExpr,
        bindings: *std.StringHashMapUnmanaged(Class.Index),
    ) Rewrite.Error!bool {
        const allocator = oir.allocator;
        const root_node = oir.getNode(node_idx);

        switch (pattern.data) {
            .atom => |constant| {
                // is this an identifier?
                if (constant[0] == '?') {
                    const identifier = constant[1..];
                    const gop = try bindings.getOrPut(allocator, identifier);
                    if (gop.found_existing) {
                        // we've already found this! is it the same as we found before?
                        // NOTE: you may think the order in which we match identifiers
                        // matters. fortunately, it doesn't! if "x" was found first,
                        // and was equal to 10, it doesn't matter if another "x" was
                        // found equal to 20. they would never match.

                        // if both nodes are in the same class, they *must* be equal.
                        // this is one of the reasons why we need to rebuild before
                        // doing rewrites, to allow checks like this.
                        return gop.value_ptr.* == (try oir.findClass(node_idx));
                    } else {
                        // make sure to remember for further matches
                        gop.value_ptr.* = try oir.findClass(node_idx);
                        // we haven't seen this class yet. it's a match, since unique identifiers
                        // could mean anything.
                        return true;
                    }
                } else {
                    // must be a number
                    if (root_node.tag != .constant) return false;

                    const value = root_node.data.constant;
                    const parsed_value = try std.fmt.parseInt(i64, constant, 10);

                    return value == parsed_value;
                }
            },
            .list => |list| {
                assert(list.len != 0); // there shouldn't be any empty lists
                // we cant immediately tell that it isn't equal if the tags don't match.
                // i.e, root_node is a (mul 10 20), and the pattern wants (div_exact ?x ?y)
                // as you can see, they could never match.
                if (root_node.tag != pattern.tag) return false;
                // if the amount of children isn't equal, they couldn't match.
                // i.e root_node is a (mul 10 20), and the pattern wants (abs ?x)
                // this is more of a sanity check, since the tag check above would probably
                // remove all cases of this.
                if (list.len != root_node.out.items.len) return false;

                // now we're left with a list of expressions and a graph.
                // since the "out" field of the nodes is ordered from left to right, we're going to
                // iterate through it inline with the expression list, and just recursively match with match()
                for (root_node.out.items, list) |sub_node_idx, expr| {
                    if (!try oir.matchClass(sub_node_idx, expr, bindings)) {
                        return false;
                    }
                }
                return true;
            },
        }
    }

    /// Given an class index, returns whether any nodes in it match the given pattern.
    fn matchClass(
        oir: *Oir,
        class_idx: Class.Index,
        sub_pattern: SExpr,
        bindings: *std.StringHashMapUnmanaged(Class.Index),
    ) Rewrite.Error!bool {
        const class = oir.getClass(class_idx);
        var found_match: bool = false;
        for (class.bag.items) |sub_node_idx| {
            const is_match = try oir.match(
                sub_node_idx,
                sub_pattern,
                bindings,
            );
            if (!found_match) found_match = is_match;
        }
        return found_match;
    }
};

const Optimizations = struct {
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
            if (oir.classContainsConstant(@enumFromInt(class_idx)) != null) continue;

            for (class.bag.items) |node_idx| {
                defer buffer.clearRetainingCapacity();

                const node = oir.getNode(node_idx);
                for (node.out.items) |child_idx| {
                    if (oir.classContainsConstant(child_idx)) |constant_idx| {
                        try buffer.append(oir.allocator, constant_idx);
                    }
                }

                // all nodes are constants
                if (buffer.items.len == node.tag.numNodeArgs()) {
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
                            const result_node = try oir.add(.{
                                .tag = .constant,
                                .data = .{ .constant = result },
                            });

                            try class.bag.append(oir.allocator, result_node);
                        },
                        // `ret` is a special case where it could be pointing at constant nodes,
                        // but there isn't any optimization we can do.
                        // TODO: make a "isVolatile" function and check for it here, make sure
                        // we can actually remove "node".
                        .ret => {
                            did_something = false;
                        },
                        else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
                    }
                }
            }
        }

        return did_something;
    }

    /// Replaces trivially expensive operations with cheaper equivalents.
    fn strengthReduce(oir: *Oir) !bool {}
};

const passes = &.{
    Optimizations.constantFold,
};

pub fn optimize(oir: *Oir, mode: enum {
    /// Optimize until running all passes creates no new changes.
    /// NOTE: likely will be very slow for any large input
    saturate,
}) !void {
    _ = mode;

    while (true) {
        var new_change: bool = false;

        inline for (passes) |pass| {
            if (try pass(oir)) new_change = true;
        }

        if (!new_change) break;
    }
}

/// Extracts the best pattern of IR from the E-Graph given a cost model.
pub fn extract(oir: *Oir) !IR {
    // First we need to find what the root class is. This will usually be the class containing a `ret`,
    // or something similar.

    // TODO: don't just search for a `ret` node,
    // instead compute the mathemtical leaves of the graph

    const ret_node_idx: Node.Index = idx: for (oir.classes.items) |class| {
        for (class.bag.items) |node_idx| {
            const node = oir.getNode(node_idx);
            if (node.tag == .ret) break :idx node_idx;
        }
    } else @panic("no ret in extract() input IR");

    // walk back up and find the best node from each class
    var ir_builder: IR.Builder = .{
        .allocator = oir.allocator,
        .instructions = .{},
    };
    _ = try oir.extractNode(ret_node_idx, &ir_builder);
    return ir_builder.toIr();
}

/// Given a node index, recursively resolves information from the graph
/// as needed to fill everything in. Returns an index into `insts` with the node.
fn extractNode(
    oir: *Oir,
    node_idx: Node.Index,
    builder: *IR.Builder,
) !IR.Inst.Index {
    const node = oir.getNode(node_idx);

    // TODO: unify the two Tag enums
    const convert_tag: IR.Inst.Tag = switch (node.tag) {
        .ret => .ret,
        .mul => .mul,
        .arg => .arg,
        .shl => .shl,
        .add => .add,
        .sub => .sub,
        .div_exact => .div_exact,
        .div_trunc => .div_trunc,
        .constant => .constant,
        .load => .load,
        .store => .store,
    };

    switch (node.tag.numNodeArgs()) {
        // Instructions with 1 argument
        1,
        => {
            assert(node.out.items.len == 1);
            const arg_class_idx = node.out.items[0];

            const arg_idx = oir.extractClass(arg_class_idx);
            const resolved_arg = try oir.extractNode(arg_idx, builder);

            return builder.addUnOp(convert_tag, resolved_arg);
        },
        // Instructions with 2 arguments
        2 => {
            assert(node.out.items.len == 2);

            const lhs_class_idx = node.out.items[0];
            const rhs_class_idx = node.out.items[1];

            const lhs_node_idx = oir.extractClass(lhs_class_idx);
            const rhs_node_idx = oir.extractClass(rhs_class_idx);

            const lhs_node = try oir.extractNode(lhs_node_idx, builder);
            const rhs_node = try oir.extractNode(rhs_node_idx, builder);

            return builder.addBinOp(convert_tag, lhs_node, rhs_node);
        },
        // Constants
        0,
        => {
            assert(node.out.items.len == 0);
            const value = node.data.constant;
            return builder.addConstant(convert_tag, value);
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(node.tag)}),
    }
}

/// Given a class, extract the "best" node from it.
fn extractClass(oir: *Oir, class_idx: Class.Index) Node.Index {
    // for now, just select the first node in the class bag
    const class = oir.getClass(class_idx);
    const index: usize = if (class.bag.items.len > 1) 1 else 0;
    return class.bag.items[index];
}

/// Adds an ENode to the EGraph, giving the node its own class.
pub fn add(oir: *Oir, node: Node) !Node.Index {
    const node_idx: Node.Index = @enumFromInt(oir.nodes.items.len);
    try oir.nodes.append(oir.allocator, node);

    var class: Class = .{};
    try class.bag.append(oir.allocator, node_idx);
    try oir.classes.append(oir.allocator, class);

    log.debug("birth node {}", .{node_idx});
    return node_idx;
}

pub fn @"union"(oir: *Oir, a_idx: Class.Index, b_idx: Class.Index) !void {
    if (a_idx != b_idx) {
        log.debug("unioning class {} -> {}", .{ a_idx, b_idx });

        const class_a = &oir.classes.items[@intFromEnum(a_idx)];
        const class_b = &oir.classes.items[@intFromEnum(b_idx)];

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
    oir.ir_to_node.deinit(allocator);
    oir.ir.instructions.deinit(allocator);

    for (oir.nodes.items) |*node| {
        node.out.deinit(allocator);
    }
    oir.nodes.deinit(allocator);

    for (oir.classes.items) |*class| {
        class.bag.deinit(allocator);
    }
    oir.classes.deinit(allocator);
}

fn resolveNode(oir: *Oir, idx: IR.Inst.Index) ?Node.Index {
    return oir.ir_to_node.get(idx);
}

/// Finds which class `idx` is in.
/// NOTE: very expensive, call this are rarely as possible.
/// TODO: improve via bimapping
pub fn findClass(oir: *Oir, idx: Node.Index) !Class.Index {
    for (oir.classes.items, 0..) |class, i| {
        for (class.bag.items) |node| {
            if (node == idx) return @enumFromInt(i);
        }
    }
    return error.ClassNotFound;
}

pub fn getNode(oir: *Oir, idx: Node.Index) Node {
    return oir.nodes.items[@intFromEnum(idx)];
}

pub fn getClass(oir: *Oir, idx: Class.Index) Class {
    return oir.classes.items[@intFromEnum(idx)];
}

/// Checks if a class contains a constant equivalence node, and returns it.
/// Otherwise returns `null`.
pub fn classContainsConstant(oir: *Oir, idx: Class.Index) ?Node.Index {
    const class = oir.getClass(idx);
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);

        // There should be at-most one constant node per
        // class. We can early return.

        if (node.tag == .constant) return node_idx;
    }

    return null;
}

const Oir = @This();
const IR = @import("Ir.zig");
const SExpr = @import("SExpr.zig");
const std = @import("std");

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
