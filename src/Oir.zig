//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,
ir: IR,
ir_to_node: std.AutoHashMapUnmanaged(IR.Inst.Index, Node.Index) = .{},

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

        pub fn isCommutative(tag: Tag) bool {
            return switch (tag) {
                .add,
                .mul,
                => true,
                .div_trunc,
                .div_exact,
                .shl,
                => false,
                else => false, // not a node that can have this property
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

pub fn fromIr(ir: IR, allocator: std.mem.Allocator) !Oir {
    var oir: Oir = .{
        .ir = ir,
        .allocator = allocator,
    };

    const tags = ir.instructions.items(.tag);
    const data = ir.instructions.items(.data);

    for (tags, data, 0..) |tag, payload, i| {
        log.debug("tag: {s} : {s}", .{ @tagName(tag), @tagName(payload) });

        const inst: IR.Inst.Index = @enumFromInt(i);
        switch (tag) {
            .arg => {
                const node: Node = .{ .tag = .arg };
                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            .ret => {
                var node: Node = .{ .tag = .ret };

                const op = payload.un_op;
                const op_idx = oir.resolveNode(op).?;
                const class_idx = try oir.findClass(op_idx);
                try node.out.append(allocator, class_idx);

                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            .mul => {
                var node: Node = .{ .tag = .mul };

                const bin_op = payload.bin_op;
                inline for (.{ bin_op.lhs, bin_op.rhs }) |idx| {
                    const node_idx = oir.resolveNode(idx).?;
                    const class_idx = try oir.findClass(node_idx);
                    try node.out.append(allocator, class_idx);
                }

                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            .constant => {
                var node: Node = .{ .tag = .constant };
                node.data = .{ .constant = payload.value };
                const idx = try oir.add(node);
                try oir.ir_to_node.put(allocator, inst, idx);
            },
            else => std.debug.panic("TODO: find {s}", .{@tagName(tag)}),
        }
    }

    return oir;
}

const Rewrite = struct {
    const Error = error{
        OutOfMemory,
        ClassNotFound,
        Overflow,
        InvalidCharacter,
    };

    /// The S-Expr that we're trying to match for.
    pattern: []const u8,
    /// If a match was found, we're going to call `func` on the root index
    /// being the first argument.
    func: *const fn (*Oir, Node.Index) Error!void,
};

/// This is the main POI. This function will apply the given rewrite to
/// its E-Graph, ensuring that it remains equivalent and consistent.
/// A major benifit of E-Graphs is that rewriting never removes information
/// only provides peepholes for discovering new optimization paths. This means
/// the order of application should never matter.
///
/// There are a few ways we can go about this, including
/// purposefully not rebuilding the graph until a certain batch of rewrites
/// is applied, however we're not going to do that here. That requires us to enforce
/// application order of batches of rewrites in order to not miss. We force rebuilds
/// before and after the rewrite to be safe.
///
/// Strategy:
///     - Iterate through every node, trying to match this node as the "root" of the expression
///       we're given. When we find a matching e-match, we apply the rewrite to it and union
///       the E-Graph. This is important, since we need to maintain equivalance throughout the
///       optimization process.
///
/// TODO: compute whether a specific rewrite will require a rebuild before/after application
pub fn applyRewrite(oir: *Oir, rewrite: Rewrite) !void {
    const allocator = oir.allocator;

    // TODO: parse sexprs at comptime in order to not parse them each time here
    var parser: SExpr.Parser = .{ .buffer = rewrite.pattern };
    const expr = try parser.parse(allocator);
    defer expr.deinit(allocator);

    const found_matches = try oir.search(expr);
    defer allocator.free(found_matches);

    for (found_matches) |found_match| {
        log.debug("matched {} for {s}", .{ found_match, rewrite.pattern });
        try rewrite.func(oir, found_match);
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

            // we're faced with an interesting problem now. commutative patterns!
            // they require us to check all the permutations of the children
            // since there's no well-defined rhs and lhs.
            //
            // here's an example to make this easier to understand:
            // root_node is 2 * x
            // the pattern wants (mul ?x 2)
            // the optimization we're going for here is to rewrite (mul ?x 2) -> (shl ?x 1)
            //
            // does this mean we need to miss out because it doesn't match? well no, since
            // the pattern is still valid.

            // so how do we do it?
            // for commutative tags, both equivalence classes of the root_node
            // are allowed to match with both sub-expressions of the pattern.
            if (pattern.tag.isCommutative()) {
                // are we the first class in the node's out bag?
                var is_first: bool = true;
                // has a class before us already matched with the first sub_pattern of the expression?
                var matched_first: bool = false;

                for (root_node.out.items) |class_idx| {
                    // class_idx will be either %0 or %1,
                    // and since the pattern is commutative, it can match with either
                    // ?x or ?y *assuming* that it's the first class.
                    //
                    // if we're the second class, that means the first class
                    // *must* have matched with something, and we no longer have
                    // to check both ?x and ?y, only the *other* one.
                    //
                    // better explained, %0 == ?y means %1 *must* == ?x, or it fails.

                    // we order the one that can still be matched first
                    const sub_patterns = if (is_first) list else &.{
                        list[@intFromBool(matched_first)],
                        list[@intFromBool(!matched_first)],
                    };

                    for (sub_patterns, 0..) |sub_pattern, i| {
                        // if we've already matched the first sub_pattern,
                        // we don't want to pollute the second pattern's bindings
                        if (is_first and matched_first) continue;

                        const result = try oir.matchClass(class_idx, sub_pattern, bindings);
                        if (is_first) {
                            // this is the first go, we still have a chance to match with the second pattern
                            if (i == 0) {
                                // if we matched, then we matched. the second run will tell.
                                matched_first = result;
                                continue;
                            }
                            // if we matched the first one, great, we can continue to the second class.
                            // otherwise, there's no way to get a match anymore.
                            if (!matched_first and !result) {
                                return false;
                            }
                        } else {
                            // we weren't the first class. it doesn't matter the result of the
                            // first class, since this will make an invalid expression.
                            // the ordering above ensures that we've checked the one possible option here.
                            //
                            // TODO: we are assuming that there are only two arguments, but that is fine for now
                            assert(i == 0);
                            return result;
                        }
                        is_first = false;
                    }
                    return true;
                }
                return false;
            }
            // otherwise, we can check them in order, because as a nice implementation detail
            // i've made it so that the out array list contains the lhs first, then the rhs.
            else {
                @panic("TODO");
            }
        },
    }
}

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

const Oir = @This();
const IR = @import("Ir.zig");
const SExpr = @import("SExpr.zig");
const std = @import("std");

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
