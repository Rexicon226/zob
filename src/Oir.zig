//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,

nodes: std.ArrayListUnmanaged(Node),

/// Represents the list of all E-Classes in the graph.
///
/// Each E-Class contains a bundle of nodes which are equivalent to each other.
classes: std.AutoHashMapUnmanaged(Class.Index, Class),

/// A map relating nodes to the classes they are in. Used as a fast way to determine
/// what "parent" class a node is in.
node_to_class: std.HashMapUnmanaged(
    Node.Index,
    Class.Index,
    NodeContext,
    std.hash_map.default_max_load_percentage,
),

union_find: UnionFind,

/// A list of pending `Pair`s which have made the E-Graph unclean. This is a part of incremental
/// rebuilding and lets the graph process faster. `add` and `union` dirty the graph, marking `clean`
/// as false, and then `rebuild` will iterate through the pending items to analyze and mark `clean`
/// as true.
pending: std.ArrayListUnmanaged(Pair),

/// Indicates whether or not reading type operations are allowed on the E-Graph.
///
/// Mutating operations set this to `false`, and `rebuild` will set it back to `true`.
clean: bool,

const UnionFind = struct {
    parents: std.ArrayListUnmanaged(Class.Index) = .{},

    fn makeSet(f: *UnionFind, gpa: std.mem.Allocator) !Class.Index {
        const id: Class.Index = @enumFromInt(f.parents.items.len);
        try f.parents.append(gpa, id);
        return id;
    }

    fn parent(f: *const UnionFind, idx: Class.Index) Class.Index {
        return f.parents.items[@intFromEnum(idx)];
    }

    fn find(f: *const UnionFind, idx: Class.Index) Class.Index {
        var current = idx;
        while (current != f.parent(current)) {
            current = f.parent(current);
        }
        return current;
    }

    /// Same thing as `find` but performs path-compression.
    fn findMutable(f: *UnionFind, idx: Class.Index) Class.Index {
        var current = idx;
        while (current != f.parent(current)) {
            const grandparent = f.parent(f.parent(current));
            f.parents.items[@intFromEnum(idx)] = grandparent;
            current = grandparent;
        }
        return current;
    }

    fn @"union"(f: *UnionFind, a: Class.Index, b: Class.Index) Class.Index {
        f.parents.items[@intFromEnum(b)] = a;
        return a;
    }

    fn clone(f: *UnionFind, allocator: std.mem.Allocator) !UnionFind {
        return .{ .parents = try f.parents.clone(allocator) };
    }

    fn deinit(f: *UnionFind, gpa: std.mem.Allocator) void {
        f.parents.deinit(gpa);
    }
};

pub const NodeContext = struct {
    oir: *const Oir,

    pub fn hash(ctx: NodeContext, node_idx: Node.Index) u64 {
        const node = ctx.oir.getNode(node_idx);
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&node.tag));
        std.hash.autoHash(&hasher, std.meta.activeTag(node.data));
        for (node.operands()) |idx| std.hash.autoHash(&hasher, idx);

        const result = hasher.final();
        return result;
    }

    pub fn eql(ctx: NodeContext, a_idx: Node.Index, b_idx: Node.Index) bool {
        const oir = ctx.oir;
        const a = oir.getNode(a_idx);
        const b = oir.getNode(b_idx);

        if (a.tag != b.tag) return false;
        if (std.meta.activeTag(a.data) != std.meta.activeTag(b.data)) return false;
        // b.data would also be `constant` because of the above check
        if (a.data == .constant) {
            return a.data.constant == b.data.constant;
        }

        for (a.operands(), b.operands()) |a_class, b_class| {
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
        cmp_gt,

        ret,
        constant,

        load,
        store,

        gamma,

        /// Returns the number of arguments that are other nodes.
        /// Does not include constants,
        pub fn numNodeArgs(tag: Tag) ?u32 {
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
                .cmp_gt,
                => 2,
                .gamma,
                => null,
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

        fn dataType(tag: Tag) DataEnum {
            return switch (tag) {
                .arg,
                .constant,
                => .constant,
                .add,
                .sub,
                .mul,
                .shl,
                .shr,
                .div_trunc,
                .div_exact,
                .cmp_gt,
                => .bin_op,
                .ret,
                .load,
                .store,
                => .un_op,
                .gamma,
                => .gamma,
            };
        }
    };

    const DataEnum = enum {
        none,
        constant,
        bin_op,
        un_op,
        gamma,
    };

    const Data = union(DataEnum) {
        none: void,
        constant: i64,
        bin_op: [2]Class.Index,
        un_op: Class.Index,
        gamma: Gamma,

        const Gamma = struct {
            /// The predicate must evaluate to a integral within `0 <= v <= k`.
            predicate: Class.Index,
            /// Maps the operands of the gamma node to the entry values of the cases.
            /// This map is shared by all of the cases because `gamma` nodes are symetric.
            map: std.AutoHashMapUnmanaged(Class.Index, Class.Index),
            exit_values: std.ArrayListUnmanaged(Class.Index),

            pub fn deinit(gamma: *Gamma, allocator: std.mem.Allocator) void {
                gamma.map.deinit(allocator);
                gamma.exit_values.deinit(allocator);
            }
        };
    };

    /// Given a tag, returns a Node with the data union initalized
    /// to the correct tag, but with an undefined payload.
    ///
    /// Useful when mixing the same operations no matter the arity of the node.
    ///
    /// TODO: remove this function!
    fn new(tag: Tag) Node {
        switch (tag) {
            inline else => |t| {
                return .{
                    .tag = t,
                    .data = @unionInit(Data, @tagName(t.dataType()), undefined),
                };
            },
        }
    }

    pub fn operands(node: *const Node) []const Class.Index {
        return switch (node.data) {
            .none => &.{},
            .constant => &.{},
            .bin_op => |*bin_op| bin_op,
            .un_op => |*un_op| un_op[0..1],
            .gamma => |_| &.{},
        };
    }

    pub fn mutableOperands(node: *Node) []Class.Index {
        return switch (node.data) {
            .none => &.{},
            .constant => &.{},
            .bin_op => |*bin_op| bin_op,
            .un_op => |*un_op| un_op[0..1],
            .gamma => &.{}, // gamma nodes should never be mutated through this.
        };
    }

    pub fn format(
        node: Node,
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        comptime assert(fmt.len == 0);
        try writer.print("{s}(", .{@tagName(node.tag)});

        const inputs = node.operands();
        for (inputs, 0..) |op, i| {
            try writer.print("{}", .{op});
            if (i != inputs.len - 1) try writer.writeAll(", ");
        }

        switch (node.tag) {
            .constant,
            .arg,
            => try writer.print("{}", .{node.data.constant}),
            else => {},
        }

        try writer.writeAll(")");
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

    fn clone(class: *Class, allocator: std.mem.Allocator) !Class {
        return .{
            .index = class.index,
            .bag = try class.bag.clone(allocator),
            .parents = try class.parents.clone(allocator),
        };
    }

    pub fn deinit(class: *Class, allocator: std.mem.Allocator) void {
        class.bag.deinit(allocator);
        class.parents.deinit(allocator);
    }
};

const Passes = struct {
    const Error = error{ OutOfMemory, Overflow, InvalidCharacter };

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
            const class_idx = oir.union_find.find(memo_class_idx);

            // the class has already been solved for a constant, no need to do anything else!
            if (oir.classContains(class_idx, .constant) != null) continue;

            assert(node.tag != .constant);
            defer buffer.clearRetainingCapacity();

            for (node.operands()) |child_idx| {
                if (oir.classContains(child_idx, .constant)) |constant| {
                    try buffer.append(oir.allocator, constant);
                }
            }

            // all nodes are constants
            const num_nodes = node.tag.numNodeArgs() orelse continue;
            assert(buffer.items.len <= num_nodes);
            if (buffer.items.len == num_nodes and
                !node.tag.isVolatile())
            {
                changed = true;
                switch (node.tag) {
                    .add,
                    .sub,
                    .mul,
                    .div_exact,
                    .shl,
                    => {
                        const lhs, const rhs = buffer.items[0..2].*;
                        const lhs_value = oir.getNode(lhs).data.constant;
                        const rhs_value = oir.getNode(rhs).data.constant;

                        const result = switch (node.tag) {
                            .add => lhs_value + rhs_value,
                            .sub => lhs_value - rhs_value,
                            .mul => lhs_value * rhs_value,
                            .div_exact => @divExact(lhs_value, rhs_value),
                            .shl => lhs_value << @intCast(rhs_value),
                            else => unreachable,
                        };

                        const new_class = try oir.add(.{
                            .tag = .constant,
                            .data = .{ .constant = result },
                        });
                        _ = try oir.@"union"(new_class, class_idx);
                    },
                    else => std.debug.panic("TODO: constant fold {s}", .{@tagName(node.tag)}),
                }

                // rebuild afterwards, the add + union could have made it unclean
                if (!oir.clean) try oir.rebuild();
            }
        }

        return changed;
    }

    const Rewrite = struct {
        name: []const u8,
        from: SExpr,
        to: SExpr,
    };

    const rewrites: []const Rewrite = &.{
        .{
            .name = "comm-mul",
            .from = SExpr.parse("(mul ?x ?y)"),
            .to = SExpr.parse("(mul ?y ?x)"),
        },
        .{
            .name = "comm-add",
            .from = SExpr.parse("(add ?x ?y)"),
            .to = SExpr.parse("(add ?y ?x)"),
        },
        .{
            .name = "mul-to-shl",
            .from = SExpr.parse("(mul ?x @known_pow2(y))"),
            .to = SExpr.parse("(shl ?x @log2(y))"),
        },
        .{
            .name = "zero-add",
            .from = SExpr.parse("(add ?x 0)"),
            .to = SExpr.parse("?x"),
        },
        .{
            .name = "double",
            .from = SExpr.parse("(add ?x ?x)"),
            .to = SExpr.parse("(mul ?x 2)"),
        },
        .{
            .name = "zero-mul",
            .from = SExpr.parse("(mul ?x 0)"),
            .to = SExpr.parse("0"),
        },
        .{
            .name = "one-mul",
            .from = SExpr.parse("(mul ?x 1)"),
            .to = SExpr.parse("?x"),
        },
        .{
            .name = "one-div",
            .from = SExpr.parse("(div_exact ?x 1)"),
            .to = SExpr.parse("?x"),
        },
        .{
            .name = "associate-div-mul",
            .from = SExpr.parse("(div_exact (mul ?x ?y) ?z)"),
            .to = SExpr.parse("(mul ?x (div_exact ?y ?z))"),
        },
        .{
            .name = "factor",
            .from = SExpr.parse("(add (mul ?x ?y) (mul ?x ?z))"),
            .to = SExpr.parse("(mul ?x (add ?y ?z))"),
        },
        .{
            .name = "factor-one",
            .from = SExpr.parse("(add ?x (mul ?x ?y))"),
            .to = SExpr.parse("(mul ?x (add 1 ?y))"),
        },
    };

    fn commonRewrites(oir: *Oir) !bool {
        const gpa = oir.allocator;

        var changed: bool = false;
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
            log.debug(
                "applying {} -> {} to {}",
                .{ item.rw.from, item.rw.to, item.root },
            );
            if (try oir.applyRewrite(
                item.root,
                item.rw.to,
                &item.bindings,
            )) {
                log.debug("change happened!", .{});
                changed = true;
            }
        }

        return changed;
    }
};

const Pass = struct {
    name: []const u8,
    func: *const fn (oir: *Oir) Passes.Error!bool,
};
const passes: []const Pass = &.{
    .{ .name = "constant-fold", .func = Passes.constantFold },
    .{ .name = "common-rewrites", .func = Passes.commonRewrites },
};

pub fn optimize(
    oir: *Oir,
    mode: enum {
        /// Optimize until running all passes creates no new changes.
        /// NOTE: likely will be very slow for any large input
        saturate,
    },
    /// Prints dumps a graphviz of the current OIR state after each pass iteration.
    output_graph: bool,
) !void {
    switch (mode) {
        .saturate => {
            try oir.rebuild();
            assert(oir.clean);

            var i: u32 = 0;
            while (true) {
                var new_change: bool = false;
                inline for (passes) |pass| {
                    if (output_graph) {
                        const name = try std.fmt.allocPrint(
                            oir.allocator,
                            "graphs/pre_{s}_{}.dot",
                            .{ pass.name, i },
                        );
                        defer oir.allocator.free(name);
                        try oir.dump(name);
                    }

                    if (try pass.func(oir)) new_change = true;
                    // TODO: in theory we don't actually need to rebuild after every pass
                    // maybe we should look into rebuilding on-demand?
                    if (!oir.clean) try oir.rebuild();
                }

                i += 1;
                if (!new_change) break;
            }
        },
    }
}

pub fn dump(oir: *Oir, name: []const u8) !void {
    const graphviz_file = try std.fs.cwd().createFile(name, .{});
    defer graphviz_file.close();
    try print_oir.dumpOirGraph(oir, graphviz_file.writer());
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
            if (list.len != root_node.operands().len) return false;

            // now we're left with a list of expressions and a graph.
            // since the "out" field of the nodes is ordered from left to right, we're going to
            // iterate through it inline with the expression list, and just recursively match with match()
            for (root_node.operands(), list) |sub_node_idx, expr| {
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

/// Given the root node index and an expression to which it should be set,
/// we generate a class that represents the expression and then union it to
/// the class which the root node index is in.
///
/// Returns whether a union happened, indicated if a change happened.
fn applyRewrite(
    oir: *Oir,
    root_node_idx: Node.Index,
    to: SExpr,
    bindings: *const std.StringHashMapUnmanaged(Node.Index),
) !bool {
    const root_class = oir.findClass(root_node_idx);

    var cloned = try oir.clone();

    const changed: bool = changed: {
        switch (to.data) {
            .list => |list| {
                var new_node = Node.new(to.tag);

                for (list, 0..) |sub_expr, i| {
                    const new_sub_node = try oir.expressionToNode(sub_expr, bindings);
                    const sub_class_idx = try oir.add(new_sub_node);
                    new_node.mutableOperands()[i] = sub_class_idx;
                }

                const new_class_idx = try oir.add(new_node);
                break :changed try oir.@"union"(root_class, new_class_idx);
            },
            .atom => {
                const new_node = try oir.expressionToNode(to, bindings);
                const new_class_idx = try oir.add(new_node);
                break :changed try oir.@"union"(root_class, new_class_idx);
            },
            else => std.debug.panic("TODO: {s}", .{@tagName(to.data)}),
        }
    };

    if (changed) {
        cloned.deinit();
        return true;
    } else {
        // revert the oir back to its state before
        oir.deinit();
        oir.* = cloned;
        return false;
    }
}

fn expressionToNode(
    oir: *Oir,
    expr: SExpr,
    bindings: *const std.StringHashMapUnmanaged(Node.Index),
) !Node {
    switch (expr.data) {
        .list => |list| {
            var node = Node.new(expr.tag);

            for (list, 0..) |item, i| {
                const sub_node = try oir.expressionToNode(item, bindings);
                const sub_class_idx = try oir.add(sub_node);
                node.mutableOperands()[i] = sub_class_idx;
            }

            return node;
        },
        .atom => |atom| {
            return node: {
                if (atom[0] == '?') {
                    const ident = atom[1..];
                    const from_idx = bindings.get(ident).?;
                    break :node oir.getNode(from_idx);
                } else {
                    const number = try std.fmt.parseInt(i64, atom, 10);
                    break :node .{
                        .tag = .constant,
                        .data = .{ .constant = number },
                    };
                }
            };
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
    }
}

fn clone(oir: *Oir) !Oir {
    const gpa = oir.allocator;
    return .{
        .allocator = gpa,
        .nodes = try oir.nodes.clone(gpa),
        .classes = classes: {
            const cloned = try oir.classes.clone(gpa);
            var iter = cloned.valueIterator();
            while (iter.next()) |value| {
                value.* = try value.clone(gpa);
            }
            break :classes cloned;
        },
        .node_to_class = try oir.node_to_class.cloneContext(gpa, @as(NodeContext, .{ .oir = oir })),
        .clean = oir.clean,
        .pending = try oir.pending.clone(gpa),
        .union_find = try oir.union_find.clone(gpa),
    };
}

/// Reference becomes invalid when new classes are added to the graph.
pub fn getClassPtr(oir: *Oir, idx: Class.Index) *Class {
    const found = oir.union_find.findMutable(idx);
    return oir.classes.getPtr(found).?;
}

pub fn getClass(oir: *const Oir, idx: Class.Index) Class {
    const found = oir.union_find.find(idx);
    return oir.classes.get(found).?;
}

fn findClass(oir: *const Oir, node_idx: Node.Index) Class.Index {
    const memo_idx = oir.node_to_class.getContext(
        node_idx,
        .{ .oir = oir },
    ).?;
    return oir.union_find.find(memo_idx);
}

pub fn getNode(oir: *const Oir, idx: Node.Index) Node {
    return oir.nodes.items[@intFromEnum(idx)];
}

/// Reference becomes invalid when new nodes are added to the graph.
fn getNodePtr(oir: *const Oir, idx: Node.Index) *Node {
    return &oir.nodes.items[@intFromEnum(idx)];
}

/// Adds an ENode to the EGraph, giving the node its own class.
/// Returns the EClass index the ENode was placed in.
pub fn add(oir: *Oir, node: Node) !Class.Index {
    const node_idx: Node.Index = @enumFromInt(oir.nodes.items.len);
    try oir.nodes.append(oir.allocator, node);

    log.debug("adding node {} {}", .{ node, node_idx });

    const class_idx = try oir.addInternal(node_idx);
    return oir.union_find.find(class_idx);
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
    const id = try oir.union_find.makeSet(oir.allocator);
    log.debug("adding {} to {}", .{ node_idx, id });

    var class: Class = .{
        .index = id,
        .bag = .{},
    };

    try class.bag.append(oir.allocator, node_idx);

    const node = oir.getNode(node_idx);
    for (node.operands()) |child| {
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
pub fn @"union"(oir: *Oir, a_idx: Class.Index, b_idx: Class.Index) !bool {
    oir.clean = false;
    var a = oir.union_find.findMutable(a_idx);
    var b = oir.union_find.findMutable(b_idx);
    if (a == b) return false;

    const a_parents = oir.classes.get(a).?.parents.items.len;
    const b_parents = oir.classes.get(b).?.parents.items.len;

    if (a_parents < b_parents) {
        std.mem.swap(Class.Index, &a, &b);
    }

    log.debug("union on {} -> {}", .{ b, a });

    // make `a` the leader class
    _ = oir.union_find.@"union"(a, b);

    var b_class = oir.classes.fetchRemove(b).?.value;
    defer b_class.deinit(oir.allocator);

    const a_class = oir.classes.getPtr(a).?;
    assert(a == a_class.index);

    try oir.pending.appendSlice(oir.allocator, b_class.parents.items);
    try a_class.bag.appendSlice(oir.allocator, b_class.bag.items);
    try a_class.parents.appendSlice(oir.allocator, b_class.parents.items);

    return true;
}

/// Performs a rebuild of the E-Graph to ensure that invariances are met.
///
/// This looks over hashes of the nodes and merges duplicate nodes.
/// We can hash based on the class indices themselves, as they don't change during the
/// rebuild.
pub fn rebuild(oir: *Oir) !void {
    log.debug("rebuilding", .{});

    while (oir.pending.popOrNull()) |pair| {
        const node_idx, const class_idx = pair;

        // before modifying the node in-place, we must remove it from the hashmap
        // in order to not get a stale hash.
        assert(oir.node_to_class.removeContext(node_idx, .{ .oir = oir }));

        const node = oir.getNodePtr(node_idx);
        for (node.mutableOperands()) |*id| {
            const found_idx = oir.union_find.findMutable(id.*);
            id.* = found_idx;
        }

        try oir.node_to_class.putNoClobberContext(
            oir.allocator,
            node_idx,
            class_idx,
            .{ .oir = oir },
        );
    }

    var iter = oir.classes.iterator();
    while (iter.next()) |entry| {
        for (entry.value_ptr.bag.items) |node_idx| {
            assert(oir.node_to_class.removeContext(node_idx, .{ .oir = oir }));

            const node = oir.getNodePtr(node_idx);
            for (node.mutableOperands()) |*child| {
                child.* = oir.union_find.findMutable(child.*);
            }

            // place the newly changed node back on the map
            try oir.node_to_class.putNoClobberContext(
                oir.allocator,
                node_idx,
                entry.key_ptr.*,
                .{ .oir = oir },
            );
        }
    }

    try oir.verifyNodes();
    assert(oir.pending.items.len == 0);
    oir.clean = true;
}

pub fn findCycles(oir: *const Oir) !std.AutoHashMapUnmanaged(Node.Index, Class.Index) {
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

    var iter = oir.classes.valueIterator();
    while (iter.next()) |class| {
        stack.appendAssumeCapacity(.{ true, class.index });
        try color.put(class.index, .white);
    }

    var cycles: std.AutoHashMapUnmanaged(Node.Index, Class.Index) = .{};
    while (stack.popOrNull()) |entry| {
        const enter, const id = entry;
        if (enter) {
            color.getPtr(id).?.* = .gray;
            try stack.append(.{ false, id });

            const class_ptr = oir.getClass(id);
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
        } else color.getPtr(id).?.* = .black;
    }

    return cycles;
}

fn verifyNodes(oir: *Oir) !void {
    var temporary: std.HashMapUnmanaged(
        Node.Index,
        Class.Index,
        NodeContext,
        std.hash_map.default_max_load_percentage,
    ) = .{};
    defer temporary.deinit(oir.allocator);

    var iter = oir.classes.iterator();
    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const class = entry.value_ptr.*;
        for (class.bag.items) |node| {
            const gop = try temporary.getOrPutContext(
                oir.allocator,
                node,
                .{ .oir = oir },
            );
            if (gop.found_existing) {
                const found_id = oir.union_find.find(id);
                const found_old = oir.union_find.find(gop.value_ptr.*);
                if (found_id != found_id) {
                    std.debug.panic(
                        "found unexpected equivalence for {}\n{any}\nvs\n{any}",
                        .{
                            node,
                            oir.getClassPtr(found_id).bag.items,
                            oir.getClassPtr(found_old).bag.items,
                        },
                    );
                }
            } else gop.value_ptr.* = id;
        }
    }

    var temp_iter = temporary.iterator();
    while (temp_iter.next()) |entry| {
        const e = entry.value_ptr.*;
        assert(e == oir.union_find.find(e));
    }
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
        switch (node.data) {
            .gamma => |*gamma| gamma.deinit(allocator),
            else => {},
        }
    }
    oir.nodes.deinit(allocator);

    oir.union_find.deinit(allocator);
    oir.pending.deinit(allocator);
}

/// Checks if a class contains a constant equivalence node, and returns it.
/// Otherwise returns `null`.
///
/// Can only return absorbing element types such as `constant`.
pub fn classContains(oir: *Oir, idx: Class.Index, comptime tag: Node.Tag) ?Node.Index {
    comptime assert(tag.isAbsorbing());
    assert(oir.clean);

    const class = oir.classes.get(idx) orelse return null;
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
const print_oir = @import("Oir/print_oir.zig");
const SExpr = @import("rewrites/SExpr.zig");
pub const Extractor = @import("Oir/Extractor.zig");

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
