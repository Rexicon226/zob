//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,

nodes: std.ArrayListUnmanaged(Node) = .{},

/// Represents the list of all E-Classes in the graph.
///
/// Each E-Class contains a bundle of nodes which are equivalent to each other.
classes: std.AutoHashMapUnmanaged(Class.Index, Class) = .{},

/// A map relating nodes to the classes they are in. Used as a fast way to determine
/// what "parent" class a node is in.
node_to_class: std.HashMapUnmanaged(
    Node.Index,
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

    fn parent(f: *const Find, idx: Class.Index) Class.Index {
        return f.parents.items[@intFromEnum(idx)];
    }

    fn find(f: *const Find, idx: Class.Index) Class.Index {
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
    oir: *const Oir,

    pub fn hash(ctx: NodeContext, node_idx: Node.Index) u64 {
        const node = ctx.oir.getNode(node_idx);
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&node.tag));
        std.hash.autoHash(&hasher, node.data);
        std.hash.autoHash(&hasher, node.out.items.len);
        for (node.out.items) |idx| {
            std.hash.autoHash(&hasher, idx);
        }

        return hasher.final();
    }

    pub fn eql(ctx: NodeContext, a_idx: Node.Index, b_idx: Node.Index) bool {
        const oir = ctx.oir;
        const a = oir.getNode(a_idx);
        const b = oir.getNode(b_idx);

        if (a.tag != b.tag) return false;
        if (std.meta.activeTag(a.data) != std.meta.activeTag(b.data)) return false;
        // b.data would also be `constant` because of the above check
        if (a.data == .constant) {
            assert(a.out.items.len == 0 and b.out.items.len == 0);
            return a.data.constant == b.data.constant;
        }
        if (a.out.items.len != b.out.items.len) return false;

        for (a.out.items, b.out.items) |a_class, b_class| {
            if (a_class != b_class) {
                return false;
            }
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

    pub const Index = enum(u32) {
        _,
    };

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

    pub fn clone(node: *const Node, allocator: std.mem.Allocator) !Node {
        return .{
            .tag = node.tag,
            .data = node.data,
            .out = try node.out.clone(allocator),
        };
    }
};

const Pair = struct { Node.Index, Class.Index };

/// A Class contains an N amount of Nodes as children.
pub const Class = struct {
    index: Index,
    bag: std.ArrayListUnmanaged(Node.Index) = .{},
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

    pub fn deinit(class: *Class, allocator: std.mem.Allocator) void {
        class.bag.deinit(allocator);
        class.parents.deinit(allocator);
    }
};

pub const CostStrategy = enum {
    /// A super basic cost strategy that simply looks at the number of child nodes
    /// a particular node has to determine its cost.
    simple_latency,
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

        var changed: bool = false;

        var copied_nodes = try oir.nodes.clone(oir.allocator);
        defer copied_nodes.deinit(oir.allocator);
        for (copied_nodes.items, 0..) |node, i| {
            const node_idx: Node.Index = @enumFromInt(i);
            const memo_class_idx = oir.node_to_class.getContext(node_idx, .{ .oir = oir }).?;
            const class_idx = oir.find.find(memo_class_idx);

            // the class has already been solved for a constant, no need to do anything else!
            if (oir.classContains(class_idx, .constant) != null) continue;

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
                        const lhs_value = oir.getNode(lhs).data.constant;
                        const rhs_value = oir.getNode(rhs).data.constant;

                        const result = switch (node.tag) {
                            .add => lhs_value + rhs_value,
                            .mul => lhs_value * rhs_value,
                            else => unreachable,
                        };

                        const new_class = try oir.add(.{
                            .tag = .constant,
                            .data = .{ .constant = result },
                        });
                        try oir.@"union"(new_class, class_idx);
                        try oir.rebuild();
                    },
                    else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
                }
            }
        }

        return changed;
    }

    const Rewrite = struct {
        name: []const u8,
        from: SExpr,
        to: SExpr,
    };

    const Parser = SExpr.Parser;
    const rewrites: []const Rewrite = &.{
        .{
            .name = "comm-mul",
            .from = Parser.parse("(mul ?x ?y)"),
            .to = Parser.parse("(mul ?y ?x)"),
        },
        .{
            .name = "mul-to-shl",
            .from = Parser.parse("(mul ?x @known_pow2(y))"),
            .to = Parser.parse("(shl ?x @log2(y))"),
        },
        .{
            .name = "zero-add",
            .from = Parser.parse("(add ?x 0)"),
            .to = Parser.parse("?x"),
        },
    };

    fn commonRewrites(oir: *Oir) !bool {
        const gpa = oir.allocator;

        var matches = std.ArrayList(RewriteResult).init(gpa);
        defer {
            for (matches.items) |*item| {
                item.deinit(gpa);
            }
            matches.deinit();
        }

        for (rewrites) |rewrite| {
            const from_matches = try oir.search(rewrite);
            defer gpa.free(from_matches);
            try matches.appendSlice(from_matches);
        }

        for (matches.items) |*item| {
            log.debug("applying {} to {}", .{ item.rw.to, item.root });
            try oir.applyRewrite(item.root, item.rw.to, &item.bindings);
        }

        return false;
    }
};

const passes = &.{
    Passes.constantFold,
    Passes.commonRewrites,
};

pub fn optimize(oir: *Oir, mode: enum {
    /// Optimize until running all passes creates no new changes.
    /// NOTE: likely will be very slow for any large input
    saturate,
}) !void {
    switch (mode) {
        .saturate => {
            try oir.rebuild();
            assert(oir.clean);
            while (true) {
                var new_change: bool = false;
                inline for (passes) |pass| {
                    if (try pass(oir)) new_change = true;

                    // TODO: in theory we don't actually need to rebuild after every pass
                    // maybe we should look into rebuilding on-demand?
                    if (!oir.clean) try oir.rebuild();
                }
                if (!new_change) break;
            }
        },
    }
}

const RewriteError = error{ OutOfMemory, InvalidCharacter, Overflow };

const RewriteResult = struct {
    root: Node.Index,
    rw: Passes.Rewrite,
    bindings: std.StringHashMapUnmanaged(Node.Index),

    fn deinit(result: *RewriteResult, gpa: std.mem.Allocator) void {
        result.bindings.deinit(gpa);
    }
};

fn search(
    oir: *Oir,
    rewrite: Passes.Rewrite,
) RewriteError![]RewriteResult {
    const gpa = oir.allocator;
    var matches = std.ArrayList(RewriteResult).init(gpa);
    for (0..oir.nodes.items.len) |node_idx| {
        const node_index: Node.Index = @enumFromInt(node_idx);

        var bindings: std.StringHashMapUnmanaged(Node.Index) = .{};
        const matched = try oir.match(node_index, rewrite.from, &bindings);
        if (matched) try matches.append(.{
            .root = node_index,
            .rw = rewrite,
            .bindings = bindings,
        }) else bindings.deinit(gpa);
    }
    return matches.toOwnedSlice();
}

fn match(
    oir: *Oir,
    node_idx: Node.Index,
    from: SExpr,
    bindings: *std.StringHashMapUnmanaged(Node.Index),
) RewriteError!bool {
    const allocator = oir.allocator;
    const root_node = oir.getNode(node_idx);

    switch (from.data) {
        .list => |list| {
            assert(list.len != 0); // there shouldn't be any empty lists
            // we cant immediately tell that it isn't equal if the tags don't match.
            // i.e, root_node is a (mul 10 20), and the pattern wants (div_exact ?x ?y)
            // as you can see, they could never match.
            if (root_node.tag != from.tag) return false;
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
                    return gop.value_ptr.* == node_idx;
                } else {
                    // make sure to remember for further matches
                    gop.value_ptr.* = node_idx;
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
        .builtin => |builtin| {
            const tag = builtin.tag;
            const param = builtin.expr;
            if (tag.location() != .src) @panic("called dst builtin in matching");

            switch (tag) {
                .known_pow2 => {
                    const class_idx = oir.findClass(node_idx);
                    if (oir.classContains(class_idx, .constant)) |constant_idx| {
                        const constant_node = oir.getNode(constant_idx);
                        const value = constant_node.data.constant;
                        if (value > 0 and std.math.isPowerOfTwo(value)) {
                            try bindings.put(allocator, param, constant_idx);
                            return true;
                        }
                    }
                    return false;
                },
                else => unreachable,
            }
        },
    }
}

/// Given an class index, returns whether any nodes in it match the given pattern.
fn matchClass(
    oir: *Oir,
    class_idx: Class.Index,
    sub_pattern: SExpr,
    bindings: *std.StringHashMapUnmanaged(Node.Index),
) RewriteError!bool {
    const class = oir.getClassPtr(class_idx);
    for (class.bag.items) |sub_node_idx| {
        const is_match = try oir.match(
            sub_node_idx,
            sub_pattern,
            bindings,
        );
        if (is_match) return true;
    }
    return false;
}

fn applyRewrite(
    oir: *Oir,
    root_node_idx: Node.Index,
    to: SExpr,
    bindings: *const std.StringHashMapUnmanaged(Node.Index),
) !void {
    const allocator = oir.allocator;
    const root_class = oir.findClass(root_node_idx);

    switch (to.data) {
        .list => |list| {
            var new_node: Node = .{
                .tag = to.tag,
                .out = .{},
            };

            for (list) |sub_expr| {
                const new_sub_node = try oir.expressionToNode(sub_expr, bindings);
                const sub_class_idx = try oir.add(new_sub_node);
                try new_node.out.append(allocator, sub_class_idx);
            }

            const new_class_idx = try oir.add(new_node);
            try oir.@"union"(root_class, new_class_idx);
        },
        .atom => {
            const new_node = try oir.expressionToNode(to, bindings);
            const new_class_idx = try oir.add(new_node);
            try oir.@"union"(root_class, new_class_idx);
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(to.data)}),
    }
}

fn expressionToNode(
    oir: *Oir,
    expr: SExpr,
    bindings: *const std.StringHashMapUnmanaged(Node.Index),
) !Node {
    switch (expr.data) {
        .atom => |atom| {
            var node: Node = .{
                .tag = .constant,
                .out = .{},
            };

            if (atom[0] == '?') {
                const ident = atom[1..];
                const from_idx = bindings.get(ident).?;
                const from_node = oir.getNode(from_idx);
                node = try from_node.clone(oir.allocator);
            } else {
                const number = try std.fmt.parseInt(i64, atom, 10);
                node = .{
                    .tag = .constant,
                    .data = .{ .constant = number },
                };
            }

            return node;
        },
        .builtin => |builtin| {
            const tag = builtin.tag;
            const param = builtin.expr;
            if (tag.location() != .dst) @panic("called src builtin in applying");

            switch (tag) {
                .log2 => {
                    const constant_idx = bindings.get(param).?;
                    const constant_node = oir.getNode(constant_idx);
                    assert(constant_node.tag == .constant);

                    const value = constant_node.data.constant;
                    if (value < 1) @panic("how do we handle @log2 of a negative?");

                    const log_value = std.math.log2_int(u64, @intCast(value));
                    const new_node: Node = .{
                        .tag = .constant,
                        .data = .{ .constant = log_value },
                    };
                    return new_node;
                },
                else => unreachable,
            }
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(expr.data)}),
    }
}

/// Reference becomes invalid when new classes are adedd to the graph.
fn getClassPtr(oir: *Oir, idx: Class.Index) *Class {
    const found = oir.find.find(idx);
    return oir.classes.getPtr(found).?;
}

fn findClass(oir: *Oir, node_idx: Node.Index) Class.Index {
    const memo_idx = oir.node_to_class.getContext(
        node_idx,
        .{ .oir = oir },
    ).?;
    return oir.find.find(memo_idx);
}

pub fn getNode(oir: *const Oir, idx: Node.Index) Node {
    return oir.nodes.items[@intFromEnum(idx)];
}

/// Adds an ENode to the EGraph, giving the node its own class.
/// Returns the EClass index the ENode was placed in.
pub fn add(oir: *Oir, node: Node) !Class.Index {
    log.debug("adding node {s}", .{@tagName(node.tag)});

    const node_idx: Node.Index = @enumFromInt(oir.nodes.items.len);
    try oir.nodes.append(oir.allocator, node);

    const class_idx = try oir.addInternal(node_idx);
    return oir.find.find(class_idx);
}

/// An internal function to simplify adding nodes to the Oir.
///
/// It should be used carefully as it invalidates the equality invariance of the graph.
fn addInternal(oir: *Oir, node: Node.Index) !Class.Index {
    if (oir.node_to_class.getContext(
        node,
        .{ .oir = oir },
    )) |class_idx| {
        return class_idx;
    } else {
        const id = try oir.makeClass(node);
        oir.clean = false;
        return id;
    }
}

fn makeClass(oir: *Oir, node_idx: Node.Index) !Class.Index {
    const id = try oir.find.makeSet(oir.allocator);
    log.debug("adding to {}", .{id});

    var class: Class = .{
        .index = id,
        .bag = .{},
    };

    try class.bag.append(oir.allocator, node_idx);

    const node = oir.getNode(node_idx);
    for (node.out.items) |child| {
        const class_ptr = oir.getClassPtr(child);
        try class_ptr.parents.append(oir.allocator, .{ node_idx, id });
    }

    try oir.pending.append(oir.allocator, .{ node_idx, id });
    try oir.classes.put(oir.allocator, id, class);
    try oir.node_to_class.putNoClobberContext(oir.allocator, node_idx, id, .{ .oir = oir });

    return id;
}

/// Performs the "union" operation on the graph.
///
/// Returns whether a union needs to happen. `true` is they are already equivalent
///
/// This can be thought of as "merging" two classes. When they were
/// proven to be equivalent.
pub fn @"union"(oir: *Oir, a_idx: Class.Index, b_idx: Class.Index) !void {
    oir.clean = false;
    var a = oir.find.find(a_idx);
    var b = oir.find.find(b_idx);
    if (a == b) return;

    const a_parents = oir.classes.get(a).?.parents.items.len;
    const b_parents = oir.classes.get(b).?.parents.items.len;

    if (a_parents < b_parents) {
        std.mem.swap(Class.Index, &a, &b);
    }

    log.debug("union on {} -> {}", .{ b, a });

    _ = oir.find.@"union"(a, b);

    var b_class = oir.classes.fetchRemove(b).?.value;
    defer b_class.deinit(oir.allocator);

    const a_class = oir.classes.getPtr(a).?;
    assert(a == a_class.index);

    try oir.pending.appendSlice(oir.allocator, b_class.parents.items);
    try a_class.bag.appendSlice(oir.allocator, b_class.bag.items);
    try a_class.parents.appendSlice(oir.allocator, b_class.parents.items);
}

/// Performs a rebuild of the E-Graph to ensure that the invariances are met.
///
/// Currently this looks over hashes of the nodes and merges duplicate nodes.
/// We can hash based on the class indices themselves, as they don't change during the
/// rebuild.
pub fn rebuild(oir: *Oir) !void {
    log.debug("rebuilding", .{});

    while (oir.pending.popOrNull()) |pair| {
        const node_idx, const class_idx = pair;
        for (oir.getNode(node_idx).out.items) |*id| {
            id.* = oir.find.find(id.*);
        }
        const gop = try oir.node_to_class.getOrPutContext(
            oir.allocator,
            node_idx,
            .{ .oir = oir },
        );
        if (gop.found_existing) {
            const mem_class = gop.value_ptr.*;
            try oir.@"union"(mem_class, class_idx);
        }
        gop.value_ptr.* = class_idx;
    }

    var iter = oir.classes.valueIterator();
    while (iter.next()) |class| {
        for (class.bag.items) |node_idx| {
            const node = oir.getNode(node_idx);
            for (node.out.items) |*child| {
                child.* = oir.find.find(child.*);
            }
        }
    }

    assert(oir.pending.items.len == 0);
    oir.clean = true;
}

pub fn deinit(oir: *Oir) void {
    const allocator = oir.allocator;

    {
        var iter = oir.classes.valueIterator();
        while (iter.next()) |class| class.deinit(allocator);
        oir.classes.deinit(allocator);
    }

    oir.node_to_class.deinit(allocator);

    for (oir.nodes.items) |*node| {
        node.out.deinit(allocator);
    }
    oir.nodes.deinit(allocator);

    oir.find.deinit(allocator);
    oir.pending.deinit(allocator);
}

/// Checks if a class contains a constant equivalence node, and returns it.
/// Otherwise returns `null`.
///
/// Can only return absorbing element types such as `constant`.
pub fn classContains(oir: *Oir, idx: Class.Index, comptime tag: Node.Tag) ?Node.Index {
    comptime assert(tag.isAbsorbing());
    assert(oir.clean);

    const class = oir.classes.get(idx).?;
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        // Since the node is aborbing, we can return early as no other
        // instances of it are allowed in the same class.
        if (node.tag == tag) return node_idx;
    }

    return null;
}

const Oir = @This();
const std = @import("std");
const IR = @import("Ir.zig");
const SExpr = @import("rewrites/SExpr.zig");

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
