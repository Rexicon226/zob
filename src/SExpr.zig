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

tag: Tag,
data: Data,

const Data = union(enum) {
    atom: []const u8,
    list: []const SExpr,
};

/// TODO: better error reporting!
pub const Parser = struct {
    buffer: []const u8,
    index: u32 = 0,

    pub fn parse(parser: *Parser, allocator: std.mem.Allocator) !SExpr {
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
                    const tag = std.meta.stringToEnum(Tag, tag_string) orelse
                        return error.UnknownTag;

                    // now there will be a list of parameters to this expression
                    // i.e (mul ?x ?y), where ?x and ?y are the parameters.
                    // these are delimited by the right paren.
                    var list: std.ArrayListUnmanaged(SExpr) = .{};
                    while (parser.peak() != ')') {
                        if (parser.index == parser.buffer.len) {
                            return error.NoClosingParen;
                        }
                        // this should only happen when an expression was parsed
                        // but a space wasn't provided after it. so, (mul ?x?y).
                        // the issue here is that identifiers are only allowed to
                        // have single letter names, so `?y?` would be in a second
                        // loop.
                        if (parser.peak() != ' ') {
                            return error.NoSpaceAfterArg;
                        }
                        // eat the space before parsing the next expression
                        assert(parser.eat() == ' ');
                        const expr = try parser.parse(allocator);
                        try list.append(allocator, expr);
                    }
                    // closing off the expression with a parenthesis
                    assert(parser.eat() == ')');
                    const expression_list = try list.toOwnedSlice(allocator);
                    if (expression_list.len == 0) {
                        return error.NoExpressionArguments;
                    }
                    return .{ .tag = tag, .data = .{ .list = expression_list } };
                },
                // the start of an identifier
                '?' => {
                    if (!std.ascii.isAlphabetic(parser.peak())) {
                        // the next character must be a letter, since only
                        // identifiers start with question marks
                        return error.QuestionMarkWithoutLetter;
                    }

                    // this - 1 is to include the `?`, which we will use later in the pipeline
                    const ident_start = parser.index - 1;
                    while (std.mem.indexOfScalar(u8, ident_delim, parser.peak()) == null) {
                        parser.index += 1;
                    }
                    const ident_end = parser.index;

                    const ident = parser.buffer[ident_start..ident_end];
                    if (ident.len != 2) {
                        // identifiers should be a single character, including the ? that's 2 length
                        return error.IdentifierTooLong;
                    }
                    return .{ .tag = .constant, .data = .{ .atom = ident } };
                },
                '0'...'9' => {
                    // this  -1 is to include the first number
                    const constant_start = parser.index - 1;
                    while (std.mem.indexOfScalar(u8, ident_delim, parser.peak()) == null) {
                        parser.index += 1;
                    }
                    const constant_end = parser.index;
                    const constant = parser.buffer[constant_start..constant_end];

                    // make sure it parses correctly!
                    switch (std.zig.parseNumberLiteral(constant)) {
                        .int => {}, // all good!
                        // we don't support this yet, floats are a complicated rabbit hole
                        .float => return error.FloatConstant,
                        .big_int => return error.IntegerConstantTooLarge, // TODO: we should support this, just not yet!
                        .failure => |err| {
                            _ = err;
                            return error.InvalidConstant;
                        },
                    }
                    return .{ .tag = .constant, .data = .{ .atom = constant } };
                },
                else => return error.UnknownCharacter,
            }
        }
        return error.UnexpectedEnd;
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

pub fn deinit(expr: *const SExpr, allocator: std.mem.Allocator) void {
    switch (expr.data) {
        .atom => {},
        .list => |list| {
            for (list) |sub_expr| {
                sub_expr.deinit(allocator);
            }
            allocator.free(list);
        },
    }
}

test "single-layer, multi-variable" {
    const allocator = std.testing.allocator;
    var parser: Parser = .{ .buffer = "(mul ?x ?y)" };
    const expr = try parser.parse(allocator);
    defer expr.deinit(allocator);

    try expect(expr.tag == .mul and expr.data == .list);

    const lhs = expr.data.list[0];
    const rhs = expr.data.list[1];

    try expect(lhs.tag == .constant and lhs.data == .atom);
    try expect(rhs.tag == .constant and rhs.data == .atom);

    try expect(std.mem.eql(u8, "?x", lhs.data.atom));
    try expect(std.mem.eql(u8, "?y", rhs.data.atom));
}

test "single-layer, single variable single constant" {
    const allocator = std.testing.allocator;
    var parser: Parser = .{ .buffer = "(mul 10 ?y)" };
    const expr = try parser.parse(allocator);
    defer expr.deinit(allocator);

    try expect(expr.tag == .mul and expr.data == .list);

    const lhs = expr.data.list[0];
    const rhs = expr.data.list[1];

    try expect(lhs.tag == .constant and lhs.data == .atom);
    try expect(rhs.tag == .constant and rhs.data == .atom);

    try expect(std.mem.eql(u8, "10", lhs.data.atom));
    try expect(std.mem.eql(u8, "?y", rhs.data.atom));
}

test "multi-layer, multi-variable" {
    const allocator = std.testing.allocator;
    var parser: Parser = .{ .buffer = "(div_exact ?z (mul ?x ?y))" };
    const expr = try parser.parse(allocator);
    defer expr.deinit(allocator);

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

const SExpr = @This();
const Tag = @import("Oir.zig").Node.Tag;
const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
