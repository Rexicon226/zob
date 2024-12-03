//! This is meant to be a sort of representation of the AIR in Zig

instructions: std.MultiArrayList(Inst).Slice,

pub const Inst = struct {
    tag: Tag,
    data: Data,

    pub const Tag = enum {
        arg,
        add,
        sub,
        mul,
        shl,
        div_trunc,
        div_exact,
        ret,
        load,
        store,

        pub const max_args = 2;

        /// Returns the number of arguments that are other nodes.
        /// Does not include constants,
        pub fn numNodeArgs(tag: Tag) u32 {
            return switch (tag) {
                .arg,
                => 0,
                .ret,
                .load,
                => 1,
                .add,
                .sub,
                .mul,
                .shl,
                .div_trunc,
                .div_exact,
                .store,
                => 2,
            };
        }
    };

    pub const Data = union(enum) {
        none: void,
        un_op: Operand,
        bin_op: struct {
            lhs: Operand,
            rhs: Operand,
        },
    };

    pub const Index = enum(u32) {
        _,
    };

    pub const Operand = union(enum) {
        index: Index,
        value: i64,

        pub fn format(
            op: Operand,
            comptime fmt: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            comptime assert(fmt.len == 0);
            switch (op) {
                .index => |index| try writer.print("%{d}", .{@intFromEnum(index)}),
                .value => |value| try writer.print("{d}", .{value}),
            }
        }
    };
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    instructions: std.MultiArrayList(Inst),

    pub fn toIr(b: *Builder) Ir {
        return .{ .instructions = b.instructions.toOwnedSlice() };
    }

    pub fn deinit(b: *Builder) void {
        b.instructions.deinit(b.allocator);
    }

    pub fn addUnOp(
        b: *Builder,
        tag: Inst.Tag,
        operand: Inst.Index,
    ) !Inst.Index {
        return b.addInst(.{
            .tag = tag,
            .data = .{ .un_op = operand },
        });
    }

    pub fn addBinOp(
        b: *Builder,
        tag: Inst.Tag,
        lhs: Inst.Index,
        rhs: Inst.Index,
    ) !Inst.Index {
        return b.addInst(.{
            .tag = tag,
            .data = .{ .bin_op = .{
                .lhs = lhs,
                .rhs = rhs,
            } },
        });
    }

    pub fn addNone(
        b: *Builder,
        tag: Inst.Tag,
    ) !Inst.Index {
        return b.addInst(.{
            .tag = tag,
            .data = .none,
        });
    }

    pub fn addConstant(
        b: *Builder,
        tag: Inst.Tag,
        val: i64,
    ) !Inst.Index {
        return b.addInst(.{
            .tag = tag,
            .data = .{ .un_op = .{ .value = val } },
        });
    }

    fn addInst(b: *Builder, inst: Inst) !Inst.Index {
        const gpa = b.allocator;
        try b.instructions.ensureUnusedCapacity(gpa, 1);

        const result_index: Inst.Index = @enumFromInt(b.instructions.len);
        b.instructions.appendAssumeCapacity(inst);
        return result_index;
    }
};

/// Only call when you're the direct owner of the Ir. Make
/// sure it hasn't been passed into an OIR.
pub fn deinit(ir: *Ir, allocator: std.mem.Allocator) void {
    ir.instructions.deinit(allocator);
}

const Writer = struct {
    ir: *const Ir,
    indent: usize,

    fn printInst(w: *Writer, inst: Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const tag = w.ir.instructions.items(.tag)[@intFromEnum(inst)];
        try s.writeByteNTimes(' ', w.indent);
        try s.print("%{d} = {s}(", .{ @intFromEnum(inst), @tagName(tag) });
        switch (tag) {
            .ret,
            .load,
            => try w.writeUnOp(inst, s),
            .mul,
            .shl,
            .add,
            .sub,
            .div_trunc,
            .div_exact,
            => try w.writeBinOp(inst, s),
            .arg,
            => try w.writeArg(inst, s),
            else => std.debug.panic("TODO: {s}", .{@tagName(tag)}),
        }
        try s.writeAll(")");
    }

    fn writeBinOp(w: *Writer, inst: Ir.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const bin_op = w.ir.instructions.items(.data)[@intFromEnum(inst)].bin_op;
        try s.print("{}", .{bin_op.lhs});
        try s.writeAll(", ");
        try s.print("{}", .{bin_op.rhs});
    }

    fn writeUnOp(w: *Writer, inst: Ir.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const un_op = w.ir.instructions.items(.data)[@intFromEnum(inst)].un_op;
        try s.print("{}", .{un_op});
    }

    fn writeArg(w: *Writer, inst: Ir.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const un_op = w.ir.instructions.items(.data)[@intFromEnum(inst)].un_op;
        try s.print("{d}", .{un_op.value});
    }
};

/// Dumps the Ir in a human-readable form.
pub fn dump(ir: *const Ir, writer: anytype) !void {
    var w: Writer = .{
        .ir = ir,
        .indent = 0,
    };

    for (0..ir.instructions.len) |i| {
        try w.printInst(@enumFromInt(i), writer);
        try writer.writeByte('\n');
    }
}

/// Simple parser for a made-up syntax for the Ir
pub const Parser = struct {
    pub fn parse(allocator: std.mem.Allocator, buffer: []const u8) !Ir {
        var lines = std.mem.splitScalar(u8, buffer, '\n');

        var list: std.MultiArrayList(Inst) = .{};
        var args_buffer = std.ArrayList(Inst.Operand).init(allocator);
        errdefer list.deinit(allocator);
        defer args_buffer.deinit();

        while (lines.next()) |line| {
            defer args_buffer.clearRetainingCapacity();
            if (line.len == 0) continue;

            // split on the '=' of "%1 = arg(1)"
            var sides = std.mem.splitScalar(u8, line, '=');

            var result_node = sides.next() orelse return error.NoResultNode;
            var expression = sides.next() orelse return error.NoExpression;

            const comment_index = std.mem.indexOfScalar(u8, expression, ';');
            if (comment_index) |index| expression = expression[0..index];

            if (sides.next() != null) return error.ExtraEquals;

            // trim any whitespace
            result_node = std.mem.trim(u8, result_node, &std.ascii.whitespace);
            expression = std.mem.trim(u8, expression, &std.ascii.whitespace);

            const left_paren = std.mem.indexOfScalar(u8, expression, '(') orelse
                return error.NoLeftParen;
            const right_paren = std.mem.indexOfScalar(u8, expression, ')') orelse
                return error.NoRightParen;

            const tag_slice = expression[0..left_paren];
            const args_slice = expression[left_paren + 1 .. right_paren];

            var args = std.mem.splitScalar(u8, args_slice, ',');
            while (args.next()) |arg_whitespace| {
                var arg = arg_whitespace;
                arg = std.mem.trim(u8, arg, &std.ascii.whitespace);

                // it's refering to another node
                if (std.mem.startsWith(u8, arg, "%")) {
                    const number = try parseNodeNumber(arg);
                    try args_buffer.append(.{ .index = @enumFromInt(number) });
                } else {
                    // must be a constant value
                    const number = try std.fmt.parseInt(i64, arg, 10);
                    try args_buffer.append(.{ .value = number });
                }
            }

            const tag = std.meta.stringToEnum(Inst.Tag, tag_slice) orelse
                return error.NotValidTag;

            var data: Inst.Data = undefined;
            switch (tag.numNodeArgs()) {
                0 => {
                    assert(args_buffer.items.len == 1);
                    data = .{ .un_op = args_buffer.items[0] };
                },
                1 => {
                    assert(args_buffer.items.len == 1);
                    data = .{ .un_op = args_buffer.items[0] };
                },
                2 => {
                    assert(args_buffer.items.len == 2);
                    data = .{ .bin_op = .{
                        .lhs = args_buffer.items[0],
                        .rhs = args_buffer.items[1],
                    } };
                },
                else => std.debug.panic("TODO: {s}", .{@tagName(tag)}),
            }

            const result_number = try parseNodeNumber(result_node);
            try list.insert(allocator, result_number, .{
                .tag = tag,
                .data = data,
            });
        }

        return .{ .instructions = list.toOwnedSlice() };
    }

    fn parseNodeNumber(string: []const u8) !usize {
        if (std.mem.startsWith(u8, string, "%")) {
            return std.fmt.parseInt(usize, string[1..], 10);
        } else {
            return error.ResultNodeNotPercent;
        }
    }
};

const testing = std.testing;
const expect = testing.expect;

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

const Ir = @This();
const std = @import("std");
const assert = std.debug.assert;
