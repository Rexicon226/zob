//! Describes an S-Expression used for describing graph rewrites.
//!
//! S-Expressions can contain three things:
//!
//! - An identifier. An identifier signifies a unique value.
//!   To denote an identifier, you would write any single letter, [a-zA-Z]
//!   prepended with a question mark (`?`). Given the law of equivalence that E-Graphs
//!   must maintain before commiting rewrites, identifiers with the same letter will
//!   be required to match.
//!   An example usage of this could be removing exact divisions of the same values.
//!   The expression for such a rewrite would look like, `(mul ?x ?x)`, and for the e-match
//!   to succeed, the optimizer would need to prove that both the RHS and the LHS of
//!   the nodes here are equivalent.
//!
//! - A constant. This is a numerical number, which requires the node intending to match the constraint
//!   to have been proven to be equivalent to this constant. These can be written in the Zig fashion of,
//!   0x10, 0b100, 0o10, or 10
//! TODO: these values can only be `i64` currently.
//!
//! - Other S-Expressions. S-expressions are intended to be nested, and matching will consider
//!   the absolute structure of the expression when pairing.

nodes: []const Entry,

pub const Entry = union(enum) {
    atom: []const u8,
    constant: i64,
    node: Node,
    builtin: BuiltinFn,

    pub const Node = struct {
        tag: NodeTag,
        list: []const Index,
    };

    const FormatCtx = struct {
        entry: Entry,
        expr: SExpr,
    };

    pub fn operands(e: Entry) []const Index {
        return switch (e) {
            .builtin, .atom, .constant => &.{},
            .node => |n| n.list,
        };
    }

    pub fn tag(e: Entry) NodeTag {
        return switch (e) {
            .atom => unreachable,
            .builtin => unreachable,
            .constant => .constant,
            .node => |n| n.tag,
        };
    }

    pub fn matches(e: Entry, n: Oir.Node, oir: *const Oir) bool {
        if (e == .builtin) {
            switch (e.builtin.tag) {
                .known_pow2 => {
                    if (n.tag != .constant) return false;
                    const value = n.data.constant;
                    if (value > 0 and std.math.isPowerOfTwo(value)) return true;
                    return false;
                },
                else => @panic("TODO"),
            }
        }
        if (n.tag != e.tag()) return false;
        if (n.operands(oir).len != e.operands().len) return false;
        if (n.tag == .constant and n.data.constant != e.constant) return false;
        return true;
    }

    pub fn map(
        e: Entry,
        allocator: std.mem.Allocator,
        m: *const std.AutoHashMapUnmanaged(Index, Index),
    ) !Entry {
        return switch (e) {
            .atom,
            .constant,
            .builtin,
            => e,
            .node => |n| n: {
                const new_operands = try allocator.dupe(Index, n.list);
                for (new_operands) |*op| op.* = m.get(op.*).?;
                break :n .{ .node = .{ .tag = n.tag, .list = new_operands } };
            },
        };
    }

    pub fn format2(
        ctx: FormatCtx,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (ctx.entry) {
            .atom => |atom| try writer.writeAll(atom),
            .constant => |constant| try writer.print("{}", .{constant}),
            .builtin => |b| try writer.print("@{s}({s})", .{ @tagName(b.tag), b.expr }),
            .node => |node| {
                try writer.print("({s}", .{@tagName(node.tag)});
                for (node.list) |index| {
                    try writer.print(
                        " {}",
                        .{ctx.expr.nodes[@intFromEnum(index)].fmt(ctx.expr)},
                    );
                }
                try writer.writeAll(")");
            },
        }
    }

    pub fn fmt(entry: Entry, expr: SExpr) std.fmt.Formatter(format2) {
        return .{ .data = .{
            .expr = expr,
            .entry = entry,
        } };
    }

    pub fn format(
        entry: Entry,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (entry) {
            .atom => |v| try writer.writeAll(v),
            .constant => |c| try writer.print("{}", .{c}),
            .builtin => |b| try writer.print("@{s}({s})", .{ @tagName(b.tag), b.expr }),
            .node => |list| {
                try writer.print("({s} ", .{@tagName(list.tag)});
                for (list.list, 0..) |child, i| {
                    try writer.print("%{d}", .{@intFromEnum(child)});
                    if (i != list.list.len - 1) try writer.writeAll(", ");
                }
                try writer.writeByte(')');
            },
        }
    }
};

pub const Index = enum(u32) {
    _,
};

const BuiltinFn = struct {
    tag: Tag,
    expr: []const u8,

    const Tag = enum {
        known_pow2,
        log2,

        pub fn location(tag: Tag) Location {
            return switch (tag) {
                .known_pow2 => .src,
                .log2 => .dst,
            };
        }
    };

    /// Describes where this builtin can be used.
    const Location = enum {
        /// This builtin can be used in the source expression, during matching.
        ///
        /// Its parameter is the name of the identifier that will be set in the bindings
        /// when it finds that node/constant.
        ///
        /// `(mul ?x @known_pow2(y))` will create bindings where `y` is the constant node
        /// that was proven to be a known power of two.
        src,
        /// This builtin can be used in the destination expression, during applying.
        ///
        /// Its parameter is a link to the name of the identifier that was found during matching.
        ///
        /// `(shl ?x @log2(y))` will search up for `y` in the bindings and take the log2 of
        /// the constant node that was found.
        dst,
    };
};

/// TODO: better error reporting!
pub const Parser = struct {
    nodes: []Entry = &.{},
    buffer: []const u8,
    index: u32 = 0,

    pub fn parseInternal(comptime parser: *Parser) Index {
        @setEvalBranchQuota(parser.buffer.len * 1_000);
        while (parser.index < parser.buffer.len) {
            const c = parser.eat();
            switch (c) {
                // the start of an expression. we're expecting to
                // have the expression tag next, i.e (mul ...
                '(' => {
                    const tag_start = parser.index;
                    // the space is what seperates the tag from the rest of the expression
                    try parser.eatUntilDelimiter(' ');
                    const tag_end = parser.index;
                    const tag_string = parser.buffer[tag_start..tag_end];
                    const tag = std.meta.stringToEnum(NodeTag, tag_string) orelse
                        @compileError("unknown tag");
                    // now there will be a list of parameters to this expression
                    // i.e (mul ?x ?y), where ?x and ?y are the parameters.
                    // these are delimited by the right paren.
                    var list: []const Index = &.{};
                    while (parser.peak() != ')') {
                        if (parser.index == parser.buffer.len) {
                            @compileError("no closing paren");
                        }
                        // this should only happen when an expression was parsed
                        // but a space wasn't provided after it. so, (mul ?x?y).
                        // the issue here is that identifiers are only allowed to
                        // have single letter names, so `?y?` would be in a second
                        // loop.
                        if (parser.peak() != ' ') {
                            @compileLog("no space after arg");
                        }
                        // eat the space before parsing the next expression
                        assert(parser.eat() == ' ');
                        const expr = parser.parseInternal();
                        list = list ++ .{expr};
                    }
                    // closing off the expression with a parenthesis
                    assert(parser.eat() == ')');
                    if (list.len == 0) {
                        @compileLog("no expression arguments");
                    }

                    return parser.addEntry(.{ .node = .{ .tag = tag, .list = list } });
                },
                // the start of an identifier
                '?' => {
                    if (!std.ascii.isAlphabetic(parser.peak())) {
                        // the next character must be a letter, since only
                        // identifiers start with question marks
                        @compileLog("question mark without letter");
                    }

                    // this - 1 is to include the `?`, which we will use later in the pipeline
                    const ident_start = parser.index - 1;
                    while (parser.index < parser.buffer.len and
                        std.mem.indexOfScalar(u8, ident_delim, parser.peak()) == null)
                    {
                        parser.index += 1;
                    }
                    const ident_end = parser.index;

                    const ident = parser.buffer[ident_start..ident_end];
                    if (ident.len != 2) {
                        // identifiers should be a single character, including the ? that's 2 length
                        @compileLog("ident too long");
                    }

                    return parser.addEntry(.{ .atom = ident });
                },
                '0'...'9' => {
                    // this -1 is to include the first number
                    const constant_start = parser.index - 1;
                    while (parser.index < parser.buffer.len and
                        std.mem.indexOfScalar(u8, ident_delim, parser.peak()) == null)
                    {
                        parser.index += 1;
                    }
                    const constant_end = parser.index;
                    const constant = parser.buffer[constant_start..constant_end];

                    const value: i64 = try std.fmt.parseInt(i64, constant, 0);
                    return parser.addEntry(.{ .constant = value });
                },
                // the start of a builtin function
                '@' => {
                    const builtin_start = parser.index;
                    try parser.eatUntilDelimiter('(');
                    const builtin_end = parser.index;
                    _ = parser.eat();

                    const builtin_name = parser.buffer[builtin_start..builtin_end];
                    const builtin_tag = std.meta.stringToEnum(BuiltinFn.Tag, builtin_name) orelse
                        @compileError("unknown builtin function");

                    const param_start = parser.index;
                    try parser.eatUntilDelimiter(')');
                    const param_end = parser.index;

                    const param = parser.buffer[param_start..param_end];

                    return parser.addEntry(.{ .builtin = .{
                        .tag = builtin_tag,
                        .expr = param,
                    } });
                },
                else => @compileError("unknown character: '" ++ .{c} ++ "'"),
            }
        }
        @compileError("unexpected end of expression");
    }

    fn addEntry(parser: *Parser, entry: Entry) Index {
        const index: Index = @enumFromInt(parser.nodes.len);
        var copy = (parser.nodes ++ (&entry)[0..1])[0..].*;
        parser.nodes = &copy;
        return index;
    }

    fn eat(parser: *Parser) u8 {
        const char = parser.peak();
        parser.index += 1;
        return char;
    }

    fn peak(parser: *Parser) u8 {
        return parser.buffer[parser.index];
    }

    fn eatUntilDelimiter(parser: *Parser, delem: u8) !void {
        while (parser.peak() != delem) : (parser.index += 1) {
            if (parser.index == parser.buffer.len) return error.OutOfBounds;
        }
    }

    /// The characters that can deliminate an identifier.
    const ident_delim: []const u8 = &.{ ' ', ')' };
};

pub inline fn parse(comptime buffer: []const u8) SExpr {
    comptime {
        var parser: Parser = .{ .buffer = buffer };
        _ = parser.parseInternal();
        const copy = parser.nodes[0..].*;
        return .{ .nodes = &copy };
    }
}

pub fn root(expr: SExpr) Index {
    return @enumFromInt(expr.nodes.len - 1);
}

pub fn get(expr: SExpr, idx: Index) Entry {
    return expr.nodes[@intFromEnum(idx)];
}

pub fn deinit(expr: SExpr, allocator: std.mem.Allocator) void {
    for (expr.nodes) |node| {
        switch (node) {
            .node => |n| allocator.free(n.list),
            else => {},
        }
    }
    allocator.free(expr.nodes);
}

pub fn format(
    expr: SExpr,
    comptime fmt: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    comptime assert(fmt.len == 0);

    const r: Entry = expr.get(expr.root());
    try writer.print("{}", .{r.fmt(expr)});
}

pub fn isIdent(expr: *const SExpr) bool {
    return expr.data == .atom and expr.data.atom[0] == '?';
}

test "single-layer, multi-variable" {
    const expr = comptime SExpr.parse("(mul ?x ?y)");

    const root_node = expr.get(expr.root());

    try expect(root_node == .node and root_node.node.tag == .mul);

    const lhs = expr.nodes[0];
    const rhs = expr.nodes[1];

    try expect(lhs == .atom);
    try expect(std.mem.eql(u8, lhs.atom, "?x"));

    try expect(rhs == .atom);
    try expect(std.mem.eql(u8, rhs.atom, "?y"));
}

test "single-layer, single variable single constant" {
    const expr = comptime SExpr.parse("(mul 10 ?y)");

    const root_node = expr.get(expr.root());

    try expect(root_node == .node and root_node.node.tag == .mul);

    const lhs = expr.nodes[0];
    const rhs = expr.nodes[1];

    try expect(lhs == .constant);
    try expect(lhs.constant == 10);

    try expect(rhs == .atom);
    try expect(std.mem.eql(u8, rhs.atom, "?y"));
}

test "multi-layer, multi-variable" {
    @setEvalBranchQuota(20_000);
    const expr = comptime SExpr.parse("(div_exact ?z (mul ?x ?y))");

    const root_node = expr.get(expr.root());

    try expect(root_node == .node and root_node.node.tag == .div_exact);

    const lhs = expr.get(root_node.node.list[0]);
    const rhs = expr.get(root_node.node.list[1]);

    try expect(lhs == .atom);
    try expect(std.mem.eql(u8, lhs.atom, "?z"));

    try expect(rhs == .node);
    try expect(rhs.node.tag == .mul);

    const mul_lhs = expr.get(rhs.node.list[0]);
    const mul_rhs = expr.get(rhs.node.list[1]);

    try expect(mul_lhs == .atom);
    try expect(std.mem.eql(u8, mul_lhs.atom, "?x"));

    try expect(mul_rhs == .atom);
    try expect(std.mem.eql(u8, mul_rhs.atom, "?y"));
}

test "builtin function" {
    const expr = comptime SExpr.parse("(mul ?x @known_pow2(y))");

    const root_node = expr.get(expr.root());

    try expect(root_node == .node and root_node.node.tag == .mul);

    const lhs = expr.get(root_node.node.list[0]);
    const rhs = expr.get(root_node.node.list[1]);

    try expect(lhs == .atom);
    try expect(std.mem.eql(u8, lhs.atom, "?x"));

    try expect(rhs == .builtin);
    try expect(rhs.builtin.tag == .known_pow2);
    try expect(std.mem.eql(u8, "y", rhs.builtin.expr));
}

const SExpr = @This();
const Oir = @import("../../Oir.zig");
const NodeTag = Oir.Node.Tag;
const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
