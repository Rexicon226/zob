//! TODO: We should have seperate tokenization passes and parsing pass.
//! Currently this is just trying ot parse a similar output to what
//! --verbose-air creates in the Zig compiler, but I think I'd like to go
//! in a bit of a different direction, and create a complete textual IR.
//! Although of course we still want the main user interface to be through the
//! builder API.

const std = @import("std");
const Ir = @import("../Ir.zig");
const Inst = Ir.Inst;
const Parser = @This();

const assert = std.debug.assert;

pub fn parse(allocator: std.mem.Allocator, buffer: []const u8) !Ir {
    var builder: Ir.Builder = .{
        .allocator = allocator,
        .instructions = .{},
    };
    defer builder.deinit();

    var next_index: u32 = 0;
    var block = try parseBlock(allocator, &builder, buffer, &next_index);
    defer block.deinit();

    return builder.toIr(&block);
}

fn parseBlock(
    allocator: std.mem.Allocator,
    builder: *Ir.Builder,
    buffer: []const u8,
    next_index: *u32,
) !Ir.Builder.Block {
    var lines = std.mem.splitScalar(u8, buffer, '\n');

    var block: Ir.Builder.Block = .{
        .instructions = .{},
        .parent = builder,
    };
    errdefer block.deinit();

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // split on the '=' of "%1 = arg(1)"
        var sides = std.mem.splitScalar(u8, line, '=');

        var result_node = sides.next() orelse return error.NoResultNode;
        var expression = sides.next() orelse return error.NoExpression;
        if (sides.next() != null) return error.ExtraEquals;

        // trim any whitespace
        result_node = std.mem.trim(u8, result_node, &std.ascii.whitespace);
        expression = std.mem.trim(u8, expression, &std.ascii.whitespace);

        const left_paren = std.mem.indexOfScalar(u8, expression, '(') orelse
            return error.NoLeftParen;

        const tag_slice = expression[0..left_paren];

        const tag = std.meta.stringToEnum(Inst.Tag, tag_slice) orelse
            return error.NotValidTag;

        const data: Inst.Data = switch (tag) {
            .cond_br => data: {
                const predicate_index = std.mem.indexOfScalar(
                    u8,
                    expression,
                    ',',
                ) orelse expression.len;
                const predicate_slice = expression[left_paren + 1 .. predicate_index];
                const predicate = try parseNodeNumber(predicate_slice);

                var then_block = blk: {
                    var case: std.ArrayListUnmanaged(u8) = .empty;
                    defer case.deinit(allocator);
                    while (lines.next()) |l| {
                        if (std.mem.startsWith(u8, l, "}, {")) break;
                        try case.appendSlice(allocator, l);
                    }

                    break :blk try parseBlock(
                        allocator,
                        builder,
                        case.items,
                        next_index,
                    );
                };
                errdefer then_block.deinit();

                var else_block = blk: {
                    var case: std.ArrayListUnmanaged(u8) = .empty;
                    defer case.deinit(allocator);

                    while (lines.next()) |l| {
                        if (std.mem.startsWith(u8, l, "})")) break;
                        try case.appendSlice(allocator, l);
                    }

                    break :blk try parseBlock(
                        allocator,
                        builder,
                        case.items,
                        next_index,
                    );
                };
                errdefer else_block.deinit();

                const then_instructions = try then_block.instructions.toOwnedSlice(allocator);
                errdefer allocator.free(then_instructions);

                const else_instructions = try else_block.instructions.toOwnedSlice(allocator);
                errdefer allocator.free(else_instructions);

                break :data .{ .cond_br = .{
                    .pred = @enumFromInt(predicate),
                    .then = then_instructions,
                    .@"else" = else_instructions,
                } };
            },
            else => data: {
                const right_paren = std.mem.indexOfScalar(u8, expression, ')') orelse
                    return error.NoRightParen;
                const args_slice = expression[left_paren + 1 .. right_paren];

                var scratch: std.BoundedArray(Inst.Operand, Inst.Tag.max_args) = .{};

                var args = std.mem.splitScalar(u8, args_slice, ',');
                while (args.next()) |arg_with_whitespace| {
                    var arg = arg_with_whitespace;
                    arg = std.mem.trim(u8, arg, &std.ascii.whitespace);

                    // it's refering to another node
                    if (std.mem.startsWith(u8, arg, "%")) {
                        const number = try parseNodeNumber(arg);
                        try scratch.append(.{ .index = @enumFromInt(number) });
                    } else {
                        // must be a constant value
                        const number = try std.fmt.parseInt(i64, arg, 10);
                        try scratch.append(.{ .value = number });
                    }
                }

                switch (tag.numNodeArgs()) {
                    0 => switch (tag) {
                        .arg => {
                            assert(scratch.len == 1);
                            break :data .{ .arg = @intCast(scratch.buffer[0].value) };
                        },
                        else => std.debug.panic("TODO: {s}", .{@tagName(tag)}),
                    },
                    1 => {
                        assert(scratch.len == 1);
                        break :data .{ .un_op = scratch.buffer[0] };
                    },
                    2 => {
                        assert(scratch.len == 2);
                        break :data .{ .bin_op = .{
                            .lhs = scratch.buffer[0],
                            .rhs = scratch.buffer[1],
                        } };
                    },
                    else => std.debug.panic("TODO: {s}", .{@tagName(tag)}),
                }
            },
        };
        errdefer data.deinit(allocator);

        _ = try block.addInst(.{ .tag = tag, .data = data });
        if (try parseNodeNumber(result_node) != next_index.*) {
            @panic("nodes must be declared in order");
        }
        next_index.* += 1;
    }

    return block;
}

fn parseNodeNumber(string: []const u8) !usize {
    if (std.mem.startsWith(u8, string, "%")) {
        return std.fmt.parseInt(usize, string[1..], 10);
    } else {
        return error.ResultNodeNotPercent;
    }
}

const testing = std.testing;
const expect = testing.expect;

fn testParsing(
    allocator: std.mem.Allocator,
    expected: []const u8,
    input: []const u8,
) !void {
    var ir = try Parser.parse(allocator, input);
    defer ir.deinit(allocator);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try ir.dump(buffer.writer());
    try testing.expectEqualSlices(u8, expected, buffer.items);
}

test "parser basic" {
    const input =
        \\%0 = arg(0)
        \\%1 = arg(1)
        \\%2 = mul(%0, %1)
        \\%3 = ret(%2)
    ;

    var ir = try Parser.parse(testing.allocator, input);
    defer ir.deinit(testing.allocator);

    try expect(ir.instructions.get(0).tag == .arg);
    try expect(ir.instructions.get(1).tag == .arg);
    try expect(ir.instructions.get(2).tag == .mul);
    try expect(ir.instructions.get(3).tag == .ret);
}

test "parse cond_br" {
    const allocator = testing.allocator;
    const input =
        \\%0 = arg(0)
        \\%1 = arg(1)
        \\%2 = cmp_gt(%0, %1)
        \\%5 = cond_br(%2, {
        \\    %3 = br(%5, 10)
        \\}, {
        \\    %4 = br(%5, 20)
        \\})
        \\%6 = ret(%5)
        \\
    ;

    try testParsing(allocator, input, input);

    // try testing.checkAllAllocationFailures(
    //     allocator,
    //     testParsing,
    //     .{ input, input },
    // );
}
