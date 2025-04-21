const std = @import("std");
const Tokenizer = @This();

const Ast = @import("Ast.zig");
const Token = Ast.Token;

source: [:0]const u8,
index: usize = 0,

const State = enum {
    start,
    invalid,
    identifier,
    plus,
    minus,
    int,
    asterisk,
    slash,
    equal,
    angle_bracket_right,
    angle_bracket_left,
};

pub fn next(self: *Tokenizer) Token {
    var result: Token = .{
        .tag = undefined,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    state: switch (State.start) {
        .start => switch (self.source[self.index]) {
            0 => {
                if (self.index == self.source.len) {
                    return .{
                        .tag = .eof,
                        .loc = .{
                            .start = self.index,
                            .end = self.index,
                        },
                    };
                } else continue :state .invalid;
            },
            'a'...'z', 'A'...'Z', '_' => {
                result.tag = .identifier;
                continue :state .identifier;
            },
            ';' => {
                result.tag = .semicolon;
                self.index += 1;
            },
            '{' => {
                result.tag = .l_brace;
                self.index += 1;
            },
            '}' => {
                result.tag = .r_brace;
                self.index += 1;
            },
            '(' => {
                result.tag = .l_paren;
                self.index += 1;
            },
            ')' => {
                result.tag = .r_paren;
                self.index += 1;
            },
            '+' => continue :state .plus,
            '-' => continue :state .minus,
            '/' => continue :state .slash,
            '*' => continue :state .asterisk,
            '=' => continue :state .equal,
            '>' => continue :state .angle_bracket_right,
            '<' => continue :state .angle_bracket_left,
            ' ', '\n', '\t', '\r' => {
                self.index += 1;
                result.loc.start = self.index;
                continue :state .start;
            },
            '0'...'9' => {
                result.tag = .number_literal;
                self.index += 1;
                continue :state .int;
            },
            else => continue :state .invalid,
        },
        .identifier => {
            self.index += 1;
            switch (self.source[self.index]) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                else => {
                    if (Token.keywords.get(self.source[result.loc.start..self.index])) |tag| {
                        result.tag = tag;
                    }
                },
            }
        },
        .plus,
        .minus,
        .asterisk,
        .slash,
        => |t| {
            self.index += 1;
            switch (self.source[self.index]) {
                else => result.tag = switch (t) {
                    .plus => .plus,
                    .minus => .minus,
                    .asterisk => .asterisk,
                    .slash => .slash,
                    else => unreachable,
                },
            }
        },
        .equal => {
            self.index += 1;
            switch (self.source[self.index]) {
                '=' => {
                    result.tag = .equal_equal;
                    self.index += 1;
                },
                else => result.tag = .equal,
            }
        },
        .int => switch (self.source[self.index]) {
            '0'...'9' => {
                self.index += 1;
                continue :state .int;
            },
            else => {},
        },
        .angle_bracket_left => {
            self.index += 1;
            switch (self.source[self.index]) {
                '=' => {
                    result.tag = .angle_bracket_left_equal;
                    self.index += 1;
                },
                else => result.tag = .angle_bracket_left,
            }
        },
        .angle_bracket_right => {
            self.index += 1;
            switch (self.source[self.index]) {
                '=' => {
                    result.tag = .angle_bracket_right_equal;
                    self.index += 1;
                },
                else => result.tag = .angle_bracket_right,
            }
        },
        .invalid => {
            self.index += 1;
            switch (self.source[self.index]) {
                0 => if (self.index == self.source.len) {
                    result.tag = .invalid;
                } else continue :state .invalid,
                '\n' => result.tag = .invalid,
                else => continue :state .invalid,
            }
        },
    }

    result.loc.end = self.index;
    return result;
}

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer: Tokenizer = .{ .source = source };
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}

test "basic" {
    try testTokenize("10", &.{.number_literal});
}

test "keywords" {
    try testTokenize("return", &.{.keyword_return});
}

test "block" {
    try testTokenize("{ return 10; }", &.{
        .l_brace,
        .keyword_return,
        .number_literal,
        .semicolon,
        .r_brace,
    });
}

test "operation" {
    try testTokenize("{ return 10 + 20; }", &.{
        .l_brace,
        .keyword_return,
        .number_literal,
        .plus,
        .number_literal,
        .semicolon,
        .r_brace,
    });

    try testTokenize("{ return 10 == 20; }", &.{
        .l_brace,
        .keyword_return,
        .number_literal,
        .equal_equal,
        .number_literal,
        .semicolon,
        .r_brace,
    });
}
