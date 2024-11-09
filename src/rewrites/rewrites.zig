//! A file containing rewrite implementations

/// (mul ?x 2) -> (shl ?x 1)
pub fn mulRewriteLhs(
    oir: *Oir,
    node_idx: Node.Index,
) Oir.Rewrite.Error!void {
    const node = oir.getNode(node_idx);
    assert(node.tag == .mul);

    const lhs_idx = node.out.items[0];
    const rhs_idx = node.out.items[1];
    const rhs = oir.getClass(rhs_idx);

    // the rhs class is supposed to contain a constant which we'll
    // log2 to get the shift amount

    const constant_idx: Node.Index = idx: for (rhs.bag.items) |sub_node_idx| {
        const sub_node = oir.getNode(sub_node_idx);
        if (sub_node.tag == .constant) break :idx sub_node_idx;
    } else @panic("something went wrong...");
    const constant_value = oir.getNode(constant_idx).data.constant;
    const shift_value = std.math.log2_int(u32, @intCast(constant_value));

    // create the two new nodes, the "shl" and the value we'll be shifting by
    const shl_idx = try oir.add(.{ .tag = .shl });
    const shift_idx = try oir.add(.{
        .tag = .constant,
        .data = .{ .constant = shift_value },
    });

    // create the relationship between the "shl" and the value node
    const shl_node = &oir.nodes.items[@intFromEnum(shl_idx)];
    try shl_node.out.append(oir.allocator, try oir.findClass(shift_idx));

    // create the relationship betwen the "shl" and the previous ?x node
    try shl_node.out.append(oir.allocator, lhs_idx);

    // finally, union the two classes
    const root_class_idx = try oir.findClass(node_idx);
    const shl_class_idx = try oir.findClass(shl_idx);
    try oir.@"union"(root_class_idx, shl_class_idx);
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

        // TODO: parse s-exprs at comptime in order to not parse them each time here
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
                        return gop.value_ptr.* == (oir.findClass(node_idx));
                    } else {
                        // make sure to remember for further matches
                        gop.value_ptr.* = oir.findClass(node_idx);
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

const std = @import("std");
const Oir = @import("../Oir.zig");
const Node = Oir.Node;
const Class = Oir.Class;
const SExpr = @import("SEcpr.zig");
const assert = std.debug.assert;
