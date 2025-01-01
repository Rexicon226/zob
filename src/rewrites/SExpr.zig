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

tag: NodeTag,
data: Data,

const Data = union(enum) {
    atom: []const u8,
    builtin: BuiltinFn,
    list: []const SExpr,
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
        /// `(mul ?x @known_pow2(y))` will create bindings where `"y"` is the constant node
        /// that was proven to be a known power of two.
        src,
        /// This builtin can be used in the destination expression, during applying.
        ///
        /// Its parameter is a link to the name of the identifier that was found during matching.
        ///
        /// `(shl ?x @log2(y))` will search up for `"y"` in the bindings and take the log2 of
        /// the constant node that was found.
        dst,
    };
};

/// TODO: better error reporting!
pub const Parser = struct {
    buffer: []const u8,
    index: u32 = 0,

    pub fn parseInternal(comptime parser: *Parser) SExpr {
        @setEvalBranchQuota(100_000);
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
                    var list: []const SExpr = &.{};
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
                    return .{ .tag = tag, .data = .{ .list = list } };
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
                    return .{ .tag = .constant, .data = .{ .atom = ident } };
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

                    // make sure it parses correctly!
                    switch (std.zig.parseNumberLiteral(constant)) {
                        .int => {}, // all good!
                        // we don't support this yet, floats are a complicated rabbit hole
                        .float => @compileError("TODO: float Constants"),
                        .big_int => @compileError("integer constant too large"), // TODO: we should support this, just not yet!
                        .failure => |err| @compileError("invalid constant " ++ @errorName(err)),
                    }
                    return .{ .tag = .constant, .data = .{ .atom = constant } };
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

                    return .{
                        .tag = .constant,
                        .data = .{ .builtin = .{
                            .tag = builtin_tag,
                            .expr = param,
                        } },
                    };
                },
                else => @compileError("unknown character: '" ++ .{c} ++ "'"),
            }
        }
        @compileError("unexpected end of expression");
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
            if (parser.index == parser.buffer.len) return error.Oob;
        }
    }

    /// The characters that can deliminate an identifier.
    const ident_delim: []const u8 = &.{ ' ', ')' };
};

pub fn parse(comptime buffer: []const u8) SExpr {
    comptime {
        var parser: Parser = .{ .buffer = buffer };
        return parser.parseInternal();
    }
}

pub fn format(
    expr: SExpr,
    comptime fmt: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    comptime assert(fmt.len == 0);

    switch (expr.data) {
        .atom => |atom| try writer.writeAll(atom),
        .list => |list| {
            try writer.print("({s}", .{@tagName(expr.tag)});
            for (list) |sub_expr| {
                try writer.print(" {}", .{sub_expr});
            }
            try writer.writeAll(")");
        },
        .builtin => |builtin| {
            const tag = builtin.tag;
            const param = builtin.expr;
            try writer.print("@{s}({s})", .{ @tagName(tag), param });
        },
    }
}

pub fn isIdent(expr: *const SExpr) bool {
    return expr.data == .atom and expr.data.atom[0] == '?';
}

test "single-layer, multi-variable" {
    comptime {
        const expr = SExpr.parse("(mul ?x ?y)");

        try expect(expr.tag == .mul and expr.data == .list);

        const lhs = expr.data.list[0];
        const rhs = expr.data.list[1];

        try expect(lhs.tag == .constant and lhs.data == .atom);
        try expect(rhs.tag == .constant and rhs.data == .atom);

        try expect(std.mem.eql(u8, "?x", lhs.data.atom));
        try expect(std.mem.eql(u8, "?y", rhs.data.atom));
    }
}

test "single-layer, single variable single constant" {
    comptime {
        const expr = SExpr.parse("(mul 10 ?y)");

        try expect(expr.tag == .mul and expr.data == .list);

        const lhs = expr.data.list[0];
        const rhs = expr.data.list[1];

        try expect(lhs.tag == .constant and lhs.data == .atom);
        try expect(rhs.tag == .constant and rhs.data == .atom);

        try expect(std.mem.eql(u8, "10", lhs.data.atom));
        try expect(std.mem.eql(u8, "?y", rhs.data.atom));
    }
}

test "multi-layer, multi-variable" {
    comptime {
        const expr = SExpr.parse("(div_exact ?z (mul ?x ?y))");

        try expect(expr.tag == .div_exact and expr.data == .list);

        const lhs = expr.data.list[0];
        const rhs = expr.data.list[1];

        try expect(lhs.tag == .constant and lhs.data == .atom);
        try expect(rhs.tag == .mul and rhs.data == .list);

        const mul_lhs = rhs.data.list[0];
        const mul_rhs = rhs.data.list[1];

        try expect(mul_lhs.tag == .constant and mul_lhs.data == .atom);
        try expect(mul_rhs.tag == .constant and mul_rhs.data == .atom);

        try expect(std.mem.eql(u8, "?z", lhs.data.atom));
        try expect(std.mem.eql(u8, "?x", mul_lhs.data.atom));
        try expect(std.mem.eql(u8, "?y", mul_rhs.data.atom));
    }
}

test "builtin function" {
    comptime {
        const expr = SExpr.parse("(mul ?x @known_pow2(y))");

        try expect(expr.tag == .mul and expr.data == .list);

        const lhs = expr.data.list[0];
        const rhs = expr.data.list[1];

        try expect(lhs.tag == .constant and lhs.data == .atom);
        try expect(rhs.tag == .constant and rhs.data == .builtin);

        try expect(std.mem.eql(u8, "?x", lhs.data.atom));
        try expect(rhs.data.builtin.tag == .known_pow2);
        try expect(std.mem.eql(u8, "", rhs.data.builtin.expr));
    }
}

const SExpr = @This();
const NodeTag = @import("../Oir.zig").Node.Tag;
const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
