const std = @import("std");
const Ast = @This();

const Parser = @import("Parser.zig");
const Tokenizer = @import("Tokenizer.zig");

source: [:0]const u8,
source_path: []const u8,
tokens: std.MultiArrayList(Token).Slice,
nodes: std.MultiArrayList(Node).Slice,
extra_data: []const Node.Index,
errors: []const Error,

/// Takes ownership of the `source`.
pub fn parse(
    gpa: std.mem.Allocator,
    source: [:0]const u8,
    source_path: []const u8,
) !Ast {
    var tokenizer: Tokenizer = .{ .source = source };

    var tokens: std.MultiArrayList(Token) = .{};
    defer tokens.deinit(gpa);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, token);
        if (token.tag == .eof) break;
    }

    var parser: Parser = .{
        .gpa = gpa,
        .source = source,
        .tokens = tokens,
        .token_index = 0,
        .nodes = .{},
        .errors = .{},
        .scratch = .{},
        .extra_data = .{},
    };
    defer {
        parser.nodes.deinit(gpa);
        parser.errors.deinit(gpa);
        parser.extra_data.deinit(gpa);
        parser.scratch.deinit(gpa);
    }

    try parser.parse();

    const errors = try parser.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);
    const extra_data = try parser.extra_data.toOwnedSlice(gpa);

    return .{
        .source = source,
        .source_path = source_path,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .errors = errors,
        .extra_data = extra_data,
    };
}

pub fn deinit(ast: *Ast, allocator: std.mem.Allocator) void {
    ast.tokens.deinit(allocator);
    ast.nodes.deinit(allocator);
    allocator.free(ast.errors);
    allocator.free(ast.extra_data);
    allocator.free(ast.source);
}

pub fn getNode(ast: Ast, idx: Node.Index) Node {
    return ast.nodes.get(@intFromEnum(idx));
}

fn getToken(ast: Ast, idx: Token.Index) Token {
    return ast.tokens.get(@intFromEnum(idx));
}

pub fn ident(ast: *const Ast, idx: Token.Index) []const u8 {
    const token = ast.getToken(idx);
    return ast.source[token.loc.start..token.loc.end];
}

pub fn spanToList(ast: Ast, idx: Node.Index) []const Node.Index {
    const root = ast.nodes.items(.data)[@intFromEnum(idx)].span;
    return ast.extra_data[@intFromEnum(root.start)..@intFromEnum(root.end)];
}

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Index = enum(u32) { _ };

    pub const OptionalIndex = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(o: OptionalIndex) ?Index {
            return switch (o) {
                .none => null,
                else => @enumFromInt(@intFromEnum(o)),
            };
        }

        pub fn wrap(i: Index) OptionalIndex {
            const wrapped: OptionalIndex = @enumFromInt(@intFromEnum(i));
            std.debug.assert(wrapped != .none);
            return wrapped;
        }
    };

    const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(&.{
        .{ "return", .keyword_return },
        .{ "if", .keyword_if },
        .{ "else", .keyword_else },
        .{ "int", .keyword_int },
    });

    pub const Tag = enum {
        string_literal,
        number_literal,
        identifier,
        semicolon,
        l_brace,
        r_brace,
        l_paren,
        r_paren,
        keyword_return,
        keyword_if,
        keyword_else,
        keyword_int,
        plus,
        minus,
        asterisk,
        slash,
        equal,
        equal_equal,
        angle_bracket_left_equal,
        angle_bracket_left,
        angle_bracket_right_equal,
        angle_bracket_right,
        eof,
        invalid,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .semicolon => ";",
                .l_brace => "{",
                .r_brace => "}",
                .l_paren => "(",
                .r_paren => ")",
                .plus => "+",
                .minus => "-",
                .asterisk => "*",
                .slash => "/",
                .equal => "=",
                .equal_equal => "==",
                .angle_bracket_right => ">",
                .angle_bracket_right_equal => ">=",
                .angle_bracket_left_equal => "<",
                .angle_bracket_left => "<=",
                else => null,
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .string_literal => "a string literal",
                .number_literal => "a number literal",
                .keyword_int => "int",
                .keyword_return => "return",
                .keyword_if => "if",
                .keyword_else => "else",
                .eof => "EOF",
                .identifier => "an identifier",
                .invalid => "invalid",
                else => std.debug.panic("tag: {s}", .{@tagName(tag)}),
            };
        }
    };
};

pub const Node = struct {
    tag: Tag,
    main_token: Token.OptionalIndex,
    data: Data,

    pub const Index = enum(u32) {
        root,
        _,
    };

    pub const OptionalIndex = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(o: OptionalIndex) ?Index {
            return switch (o) {
                .none => null,
                else => @enumFromInt(@intFromEnum(o)),
            };
        }

        pub fn wrap(i: Index) OptionalIndex {
            return @enumFromInt(@intFromEnum(i));
        }
    };

    pub const Tag = enum {
        root,
        @"return",
        @"if",
        block,
        number_literal,
        add,
        sub,
        mul,
        div,
        group,
        assign,
        identifier,
        equal,
        greater_than,
        greater_or_equal,
        less_or_equal,
        less_than,
    };

    pub const Span = struct {
        start: Node.Index,
        end: Node.Index,
    };

    pub const Data = union(enum) {
        un_op: Node.Index,
        bin_op: struct {
            lhs: Node.Index,
            rhs: Node.Index,
        },
        cond_br: struct {
            pred: Node.Index,
            then: Node.Index,
            @"else": Node.Index,
        },
        token_and_node: struct {
            Token.Index,
            Node.Index,
        },
        span: Span,
        int: i64,
    };
};

pub const Error = struct {
    tag: Tag,
    token: Token.Index,
    extra: Extra = .{ .none = {} },

    pub const Tag = enum {
        expected_expression,
        expected_statement,
        expected_token,
        chained_comparison_operators,
    };

    const Extra = union {
        none: void,
        expected_tag: Token.Tag,
    };

    pub fn render(err: Error, ast: Ast, stderr: anytype) !void {
        const ttyconf = std.zig.Color.get_tty_conf(.auto);
        try ttyconf.setColor(stderr, .bold);

        // Somehow an invalid token.
        if (@intFromEnum(err.token) >= ast.tokens.len) {
            try ttyconf.setColor(stderr, .red);
            try stderr.writeAll("error: ");
            try ttyconf.setColor(stderr, .reset);
            try ttyconf.setColor(stderr, .bold);
            try stderr.writeAll("unexpected EOF\n");
            try ttyconf.setColor(stderr, .reset);
            return;
        }

        const token = ast.getToken(err.token);
        const byte_offset = token.loc.start;
        const err_loc = std.zig.findLineColumn(ast.source, byte_offset);

        try stderr.print("{s}:{d}:{d}: ", .{
            ast.source_path,
            err_loc.line + 1,
            err_loc.column + 1,
        });
        try ttyconf.setColor(stderr, .red);
        try stderr.writeAll("error: ");
        try ttyconf.setColor(stderr, .reset);

        try ttyconf.setColor(stderr, .bold);
        try err.write(ast, stderr);
        try stderr.writeByte('\n');
        try ttyconf.setColor(stderr, .reset);
    }

    fn write(err: Error, ast: Ast, stderr: anytype) !void {
        const token_tags = ast.tokens.items(.tag);
        switch (err.tag) {
            .expected_expression => {
                const found_tag = token_tags[@intFromEnum(err.token)];
                return stderr.print(
                    "expected expression, found '{s}'",
                    .{found_tag.symbol()},
                );
            },
            .expected_statement => {
                const found_tag = token_tags[@intFromEnum(err.token)];
                return stderr.print(
                    "expected statement, found '{s}'",
                    .{found_tag.symbol()},
                );
            },
            .chained_comparison_operators => {
                return stderr.writeAll("comparison operators cannot be chained");
            },
            .expected_token => {
                const found_tag = token_tags[@intFromEnum(err.token)];
                const expected_symbol = err.extra.expected_tag.symbol();
                switch (found_tag) {
                    .invalid => return stderr.print(
                        "expected '{s}', found invalid bytes",
                        .{expected_symbol},
                    ),
                    else => return stderr.print(
                        "expected '{s}', found '{s}'",
                        .{ expected_symbol, found_tag.symbol() },
                    ),
                }
            },
        }
    }
};
