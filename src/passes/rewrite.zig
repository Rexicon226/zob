//! Contains the common rewrites pass. This pass will find basic patterns in
//! the graph, and convert them to another one. These rewrites won't always
//! be strict improvements in the graph, but they expose future passes to
//! find more advanced patterns.

const std = @import("std");
const SExpr = @import("rewrite/SExpr.zig");
const Oir = @import("../Oir.zig");
const machine = @import("rewrite/machine.zig");

const log = std.log.scoped(.rewrite);

const Node = Oir.Node;
const Class = Oir.Class;

pub const Rewrite = struct {
    name: []const u8,
    from: SExpr,
    to: SExpr,
};

pub const MultiRewrite = struct {
    name: []const u8,
    from: []const MultiPattern,
};

pub const MultiPattern = struct {
    atom: []const u8,
    pattern: SExpr,
};

pub const Result = struct {
    bindings: Bindings,
    class: Class.Index,
    pattern: SExpr,

    pub const Bindings = std.StringHashMapUnmanaged(Class.Index);
    pub const Error = error{ OutOfMemory, InvalidCharacter, Overflow };

    fn deinit(result: *const Result, gpa: std.mem.Allocator) void {
        var copy = result.*;
        copy.bindings.deinit(gpa);
    }
};

const rewrites: []const Rewrite = blk: {
    const table: []const struct {
        name: []const u8,
        from: []const u8,
        to: []const u8,
    } = @import("rewrite/table.zon");
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
    var matches: std.ArrayList(Result) = .empty;
    defer {
        for (matches.items) |*m| m.deinit(oir.allocator);
        matches.deinit(oir.allocator);
    }

    {
        const trace = oir.trace.start(@src(), "searching", .{});
        defer trace.end();

        for (rewrites) |rewrite| {
            try machine.search(oir, .{
                .from = rewrite.from,
                .to = rewrite.to,
                .name = rewrite.name,
            }, &matches);
        }
    }

    {
        const trace = oir.trace.start(@src(), "applying matches", .{});
        defer trace.end();

        return try applyMatches(
            oir,
            matches.items,
        );
    }
}

fn applyMatches(oir: *Oir, matches: []const Result) !bool {
    var ids: std.ArrayList(Class.Index) = .empty;
    defer ids.deinit(oir.allocator);

    var changed: bool = false;
    for (matches) |m| {
        ids.clearRetainingCapacity();

        for (m.pattern.nodes) |entry| {
            const id = switch (entry) {
                .atom => |v| m.bindings.get(v).?,
                .constant => |c| try oir.add(.constant(c)),
                .node => |n| b: {
                    var new = switch (n.tag) {
                        inline else => |t| Node.init(t, undefined),
                    };
                    for (new.mutableOperands(oir), n.list) |*op, child| {
                        op.* = ids.items[@intFromEnum(child)];
                    }
                    break :b try oir.add(new);
                },
                .builtin => |b| b: {
                    if (b.tag.location() != .dst)
                        @panic("have non-dst builtin in destination pattern");

                    switch (b.tag) {
                        .log2 => {
                            // We can't actually rebuild the graph here, a batch of
                            // matches may have added nodes whose pending merges
                            // would trip a duplicate-node assertion.
                            //
                            // Instead, kinda sketchy, but we can technically
                            // just access the class as we've already proven that
                            // there must be a constant node in this class.
                            const idx = m.bindings.get(b.expr).?;
                            const value = constInClass(oir, idx) orelse
                                @panic("@log2 binding isn't a power of two?");
                            if (value < 1) @panic("how do we handle @log2 of a negative?");
                            const log_value = std.math.log2_int(u64, @intCast(value));
                            break :b try oir.add(.constant(log_value));
                        },
                        else => unreachable,
                    }
                },
            };

            try ids.append(oir.allocator, id);
        }

        const last = ids.getLast();
        if (try oir.@"union"(m.class, last)) changed = true;
    }
    return changed;
}

fn constInClass(oir: *Oir, idx: Class.Index) ?i64 {
    for ([_]Class.Index{ oir.union_find.find(idx), idx }) |c| {
        const class = oir.classes.get(c) orelse continue;
        for (class.bag.items) |node_idx| {
            const node = oir.getNode(node_idx);
            if (node.tag == .constant) return node.data.constant.val;
        }
    }
    return null;
}

fn testSearch(oir: *const Oir, comptime buffer: []const u8, num_matches: u64) !void {
    std.debug.assert(oir.clean); // must be clean before searching

    const apply = SExpr.parse("?x");
    const pattern = SExpr.parse(buffer);

    var matches: std.ArrayList(Result) = .{};
    defer {
        for (matches.items) |*m| m.deinit(oir.allocator);
        matches.deinit(oir.allocator);
    }
    try machine.search(oir, .{
        .from = pattern,
        .to = apply,
        .name = "test",
    }, &matches);

    try std.testing.expectEqual(num_matches, matches.items.len);
}

test "basic match" {
    const allocator = std.testing.allocator;
    var oir: Oir = .init(allocator);
    defer oir.deinit();

    // (add (mul 10 20) 30)
    _ = try oir.add(try .create(.start, &oir, &.{}));
    const a = try oir.add(.init(.constant, 10));
    const b = try oir.add(.init(.constant, 20));
    const mul = try oir.add(.binOp(.mul, a, b));
    const c = try oir.add(.init(.constant, 30));
    _ = try oir.add(.binOp(.add, mul, c));
    try oir.rebuild();

    try testSearch(&oir, "(mul 10 20)", 1);
    try testSearch(&oir, "(mul ?x 20)", 1);
    try testSearch(&oir, "(add ?x ?x)", 0);
    try testSearch(&oir, "(add 10 20)", 0);
    try testSearch(&oir, "(add ?x ?y)", 1);
    try testSearch(&oir, "(add (mul 10 20) 30)", 1);
}

test "builtin function match" {
    const allocator = std.testing.allocator;
    var oir: Oir = .init(allocator);
    defer oir.deinit();

    // (mul 37 16)
    _ = try oir.add(try .create(.start, &oir, &.{}));
    const a = try oir.add(.init(.constant, 37));
    const b = try oir.add(.init(.constant, 16));
    _ = try oir.add(.binOp(.mul, a, b));
    try oir.rebuild();

    try testSearch(&oir, "(mul ?x @known_pow2(?y))", 1);
    try testSearch(&oir, "(add ?x @known_pow2(?y))", 0);
}

test "negative known_pow2" {
    const allocator = std.testing.allocator;
    var oir: Oir = .init(allocator);
    defer oir.deinit();

    // (mul 5 -2)
    _ = try oir.add(try .create(.start, &oir, &.{}));
    const a = try oir.add(.init(.constant, 5));
    const b = try oir.add(.init(.constant, -2));
    _ = try oir.add(.binOp(.mul, a, b));
    try oir.rebuild();

    try testSearch(&oir, "(mul ?x @known_pow2(?y))", 0);
}

// test "basic multi-pattern match" {
//     const allocator = std.testing.allocator;
//     var oir: Oir = .init(allocator, &trace);
//     defer oir.deinit();

//     // (add (mul 10 20) 30)
//     _ = try oir.add(try .create(.start, &oir, &.{}));
//     const a = try oir.add(.init(.constant, 10));
//     const b = try oir.add(.init(.constant, 20));
//     const add = try oir.add(.binOp(.mul, a, b));
//     const c = try oir.add(.init(.constant, 30));
//     _ = try oir.add(.binOp(.add, add, c));
//     try oir.rebuild();

//     try machine.multiSearch(&oir, .{
//         .from = &.{
//             .{
//                 .atom = "?x",
//                 .pattern = SExpr.parse("(mul 10 20)"),
//             },
//             .{
//                 .atom = "?y",
//                 .pattern = SExpr.parse("(add ?a 30)"),
//             },
//         },
//         .name = "test",
//     });
//     // defer {
//     //     for (matches) |*m| m.deinit(oir.allocator);
//     //     oir.allocator.free(matches);
//     // }

//     // std.debug.print("n matches: {}\n", .{matches.len});
// }
