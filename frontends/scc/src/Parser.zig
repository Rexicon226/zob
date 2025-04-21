const std = @import("std");
const Ast = @import("Ast.zig");

const Parser = @This();

const Token = Ast.Token;
const Node = Ast.Node;

gpa: std.mem.Allocator,
source: [:0]const u8,
tokens: std.MultiArrayList(Token),
token_index: u32,
nodes: std.MultiArrayList(Node),
errors: std.ArrayListUnmanaged(Ast.Error),
scratch: std.ArrayListUnmanaged(Node.Index),
extra_data: std.ArrayListUnmanaged(Node.Index),

const Error = error{
    OutOfMemory,
    ParserError,
    // TODO: hook these up with the error messages
    Overflow,
    InvalidCharacter,
};

pub fn parse(p: *Parser) !void {
    try p.nodes.append(p.gpa, .{
        .tag = .root,
        .main_token = .none,
        .data = undefined,
    });

    var statements: std.ArrayListUnmanaged(Node.Index) = .{};
    defer statements.deinit(p.gpa);

    while (p.tokens.get(p.token_index).tag != .eof) {
        const stmt = p.parseStatement() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParserError => {
                std.debug.assert(p.errors.items.len > 0);
                return;
            },
            else => |e| return e,
        };
        try statements.append(p.gpa, stmt);
    }

    p.nodes.items(.data)[0] = .{ .span = try p.listToSpan(statements.items) };
}

fn parseStatement(p: *Parser) Error!Node.Index {
    if (p.token_index >= p.tokens.len) {
        return p.failExpecting(.eof);
    }

    while (true) {
        switch (p.tokens.get(p.token_index).tag) {
            .l_brace => return p.parseCompoundStatement(),
            .keyword_return => {
                const main_token = try p.expectToken(.keyword_return);
                const payload = try p.parseExpression(0);
                _ = try p.expectToken(.semicolon);
                return p.addNode(.{
                    .tag = .@"return",
                    .main_token = .wrap(main_token),
                    .data = .{ .un_op = payload },
                });
            },
            .keyword_if => {
                const main_token = try p.expectToken(.keyword_if);

                _ = try p.expectToken(.l_paren);
                const predicate = try p.parseExpression(0);
                _ = try p.expectToken(.r_paren);

                const then_body = try p.parseCompoundStatement();
                _ = try p.expectToken(.keyword_else);
                const else_body = try p.parseCompoundStatement();

                return p.addNode(.{
                    .tag = .@"if",
                    .main_token = .wrap(main_token),
                    .data = .{ .cond_br = .{
                        .pred = predicate,
                        .then = then_body,
                        .@"else" = else_body,
                    } },
                });
            },
            .keyword_int => {
                _ = try p.expectToken(.keyword_int);
                const ident_token = try p.expectToken(.identifier);
                const assign_token = try p.expectToken(.equal);

                const rvalue = try p.parseExpression(0);
                _ = try p.expectToken(.semicolon);

                return p.addNode(.{
                    .tag = .assign,
                    .main_token = .wrap(assign_token),
                    .data = .{ .token_and_node = .{
                        ident_token,
                        rvalue,
                    } },
                });
            },
            .identifier => {
                const ident_token = try p.expectToken(.identifier);
                const assign_token = try p.expectToken(.equal);
                const rvalue = try p.parseExpression(0);
                _ = try p.expectToken(.semicolon);

                return p.addNode(.{
                    .tag = .assign,
                    .main_token = .wrap(assign_token),
                    .data = .{ .token_and_node = .{
                        ident_token,
                        rvalue,
                    } },
                });
            },
            .eof => break,
            else => return p.failMsg(.{
                .tag = .expected_statement,
                .token = @enumFromInt(p.token_index),
            }),
        }
    }

    @panic("TODO");
}

const Assoc = enum {
    left,
    none,
};

const OperatorInfo = struct {
    prec: i8,
    tag: Node.Tag,
    assoc: Assoc = Assoc.left,
};

const operatorTable = std.enums.directEnumArrayDefault(
    Token.Tag,
    OperatorInfo,
    .{ .prec = -1, .tag = Node.Tag.root },
    0,
    .{
        .equal_equal = .{ .prec = 30, .tag = .equal, .assoc = Assoc.none },
        .angle_bracket_left = .{ .prec = 30, .tag = .less_than, .assoc = Assoc.none },
        .angle_bracket_right = .{ .prec = 30, .tag = .greater_than, .assoc = Assoc.none },
        .angle_bracket_left_equal = .{ .prec = 30, .tag = .less_or_equal, .assoc = Assoc.none },
        .angle_bracket_right_equal = .{ .prec = 30, .tag = .greater_or_equal, .assoc = Assoc.none },

        .plus = .{ .prec = 60, .tag = .add },
        .minus = .{ .prec = 60, .tag = .sub },

        .asterisk = .{ .prec = 70, .tag = .mul },
        .slash = .{ .prec = 70, .tag = .div },
    },
);

fn parseExpression(p: *Parser, min_prec: i32) Error!Node.Index {
    std.debug.assert(min_prec >= 0);
    var node = try p.parsePrimaryExpression();
    var banned_prec: i8 = -1;

    while (true) {
        const tag = p.tokens.items(.tag)[p.token_index];
        const info = operatorTable[@intFromEnum(tag)];
        if (info.prec < min_prec) break;
        if (info.prec == banned_prec) {
            return p.fail(.chained_comparison_operators);
        }

        const operator_token = p.nextToken();
        const rhs = try p.parseExpression(info.prec + 1);

        node = try p.addNode(.{
            .tag = info.tag,
            .main_token = .wrap(operator_token),
            .data = .{ .bin_op = .{
                .lhs = node,
                .rhs = rhs,
            } },
        });

        if (info.assoc == Assoc.none) {
            banned_prec = info.prec;
        }
    }

    return node;
}

fn parsePrimaryExpression(p: *Parser) Error!Node.Index {
    switch (p.tokens.get(p.token_index).tag) {
        .number_literal => {
            const number_literal = try p.expectToken(.number_literal);
            return p.addNode(.{
                .tag = .number_literal,
                .main_token = .wrap(number_literal),
                .data = .{ .int = try p.parseNumber(number_literal) },
            });
        },
        .l_paren => {
            const main_token = try p.expectToken(.l_paren);
            const inside = try p.parseExpression(0);
            _ = try p.expectToken(.r_paren);
            return p.addNode(.{
                .tag = .group,
                .main_token = .wrap(main_token),
                .data = .{ .un_op = inside },
            });
        },
        .identifier => return p.addNode(.{
            .tag = .identifier,
            .main_token = .wrap(p.nextToken()),
            .data = undefined,
        }),
        else => return p.failMsg(.{
            .tag = .expected_expression,
            .token = @enumFromInt(p.token_index),
        }),
    }
}

fn parseNumber(p: *Parser, node: Token.Index) Error!i64 {
    const string = p.ident(node);
    return std.fmt.parseInt(i64, string, 10);
}

fn parseCompoundStatement(p: *Parser) Error!Node.Index {
    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    _ = try p.expectToken(.l_brace);

    while (true) {
        if (p.tokens.get(p.token_index).tag == .r_brace) break;
        const stmt = try p.parseStatement();
        try p.scratch.append(p.gpa, stmt);
    }

    _ = try p.expectToken(.r_brace);

    const items = p.scratch.items[scratch_top..];
    return p.addNode(.{
        .tag = .block,
        .main_token = .none,
        .data = .{ .span = try p.listToSpan(items) },
    });
}

fn eatToken(p: *Parser, tag: Token.Tag) ?Token.Index {
    return if (p.tokens.get(p.token_index).tag == tag) p.nextToken() else null;
}

fn expectToken(p: *Parser, tag: Token.Tag) !Token.Index {
    const token = p.tokens.get(p.token_index);
    if (token.tag != tag) {
        return p.failExpecting(tag);
    }
    return p.nextToken();
}

fn nextToken(p: *Parser) Token.Index {
    const result = p.token_index;
    p.token_index += 1;
    return @enumFromInt(result);
}

fn getToken(p: *Parser, idx: Token.Index) Token {
    return p.tokens.get(@intFromEnum(idx));
}

fn ident(p: *Parser, idx: Token.Index) []const u8 {
    const token = p.getToken(idx);
    return p.source[token.loc.start..token.loc.end];
}

fn fail(p: *Parser, msg: Ast.Error.Tag) error{ ParserError, OutOfMemory } {
    return p.failMsg(.{ .tag = msg, .token = @enumFromInt(p.token_index) });
}

fn failExpecting(p: *Parser, expected_tag: Token.Tag) error{ ParserError, OutOfMemory } {
    @branchHint(.cold);
    return p.failMsg(.{
        .tag = .expected_token,
        .token = @enumFromInt(p.token_index),
        .extra = .{ .expected_tag = expected_tag },
    });
}

fn failMsg(p: *Parser, msg: Ast.Error) error{ ParserError, OutOfMemory } {
    @branchHint(.cold);
    try p.errors.append(p.gpa, msg);
    return error.ParserError;
}

fn addNode(p: *Parser, node: Node) !Node.Index {
    const result: Node.Index = @enumFromInt(p.nodes.len);
    try p.nodes.append(p.gpa, node);
    return result;
}

fn listToSpan(p: *Parser, list: []const Node.Index) !Node.Span {
    try p.extra_data.appendSlice(p.gpa, list);
    return .{
        .start = @enumFromInt(p.extra_data.items.len - list.len),
        .end = @enumFromInt(p.extra_data.items.len),
    };
}
