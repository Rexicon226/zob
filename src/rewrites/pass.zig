//! Contains the common rewrites pass. This pass will find basic patterns in
//! the graph, and convert them to another one. These rewrites won't always
//! be strict improvements in the graph, but they expose future passes to
//! find more advanced patterns.

const std = @import("std");
const SExpr = @import("SExpr.zig");
const Oir = @import("../Oir.zig");

const log = std.log.scoped(.@"pass/rewrite");

const Node = Oir.Node;
const Class = Oir.Class;
const assert = std.debug.assert;

const Rewrite = struct {
    name: []const u8,
    from: SExpr,
    to: SExpr,
};

const RewriteError = error{ OutOfMemory, InvalidCharacter, Overflow };

const RewriteResult = struct {
    root: Node.Index,
    rw: Rewrite,
    bindings: std.StringHashMapUnmanaged(Node.Index),

    fn deinit(result: *RewriteResult, gpa: std.mem.Allocator) void {
        result.bindings.deinit(gpa);
    }
};

const rewrites: []const Rewrite = blk: {
    const table: []const struct {
        name: []const u8,
        from: []const u8,
        to: []const u8,
    } = @import("table.zon");
    @setEvalBranchQuota(table.len * 20_000);
    var list: [table.len]Rewrite = undefined;
    for (&list, table) |*entry, op| {
        entry.* = Rewrite{
            .name = op.name,
            .from = SExpr.parse(op.from),
            .to = SExpr.parse(op.to),
        };
    }
    const copy = list;
    break :blk &copy;
};

pub fn run(oir: *Oir) !bool {
    const gpa = oir.allocator;

    var matches = std.ArrayList(RewriteResult).init(gpa);
    defer {
        for (matches.items) |*item| {
            item.deinit(gpa);
        }
        matches.deinit();
    }

    {
        const trace = oir.trace.start(@src(), "searching for matches", .{});
        defer trace.end();

        for (rewrites) |rewrite| {
            const from_matches = try search(oir, rewrite);
            defer gpa.free(from_matches);
            try matches.appendSlice(from_matches);
        }
    }

    const trace = oir.trace.start(@src(), "applying matches", .{});
    defer trace.end();
    for (matches.items) |*item| {
        log.debug(
            "applying {} -> {} to {}",
            .{ item.rw.from, item.rw.to, item.root },
        );
        if (try applyRewrite(oir, item.root, item.rw.to, &item.bindings)) {
            log.debug("change happened!", .{});
            return true;
        }
    }

    return false;
}

fn search(oir: *Oir, rewrite: Rewrite) RewriteError![]RewriteResult {
    const gpa = oir.allocator;
    var matches = std.ArrayList(RewriteResult).init(gpa);
    for (0..oir.nodes.items.len) |node_idx| {
        const node_index: Node.Index = @enumFromInt(node_idx);
        var bindings: std.StringHashMapUnmanaged(Node.Index) = .{};
        const matched = try match(oir, node_index, rewrite.from, &bindings);
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
            const operands = root_node.operands(oir);
            if (list.len != operands.len) return false;

            // now we're left with a list of expressions and a graph.
            // since the "out" field of the nodes is ordered from left to right, we're going to
            // iterate through it inline with the expression list, and just recursively match with match()
            for (operands, list) |sub_node_idx, expr| {
                if (!try matchClass(oir, sub_node_idx, expr, bindings)) {
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
        const is_match = try match(
            oir,
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

    var old = try oir.clone();

    const changed: bool = changed: {
        switch (to.data) {
            .list, .atom => {
                const new_node = try expressionToNode(oir, to, bindings);
                const new_class_idx = try oir.add(new_node);
                break :changed try oir.@"union"(root_class, new_class_idx);
            },
            .builtin => unreachable,
        }
    };

    if (changed) {
        old.deinit();
        return true;
    } else {
        // revert the oir back to its state before
        oir.deinit();
        oir.* = old;
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
            var node = Node.init(expr.tag, undefined);

            for (list, 0..) |item, i| {
                const sub_node = try expressionToNode(oir, item, bindings);
                const sub_class_idx = try oir.add(sub_node);
                node.mutableOperands(oir)[i] = sub_class_idx;
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
