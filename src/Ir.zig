//! This is meant to be a sort of representation of the AIR in Zig

instructions: std.MultiArrayList(Inst).Slice,
main_body: []const Inst.Index,

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

        block,
        br,
        cond_br,

        cmp_gt,

        dead,

        pub const max_args = 2;

        /// Returns the number of arguments that are other nodes.
        /// Does not include constants,
        pub fn numNodeArgs(tag: Tag) u32 {
            return switch (tag) {
                .dead,
                => unreachable,
                .arg,
                .block,
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
                .cmp_gt,
                .br,
                => 2,
                .cond_br,
                => 3,
            };
        }
    };

    pub const Data = union(enum) {
        none: void,
        arg: u32,
        un_op: Operand,
        bin_op: struct {
            lhs: Operand,
            rhs: Operand,
        },
        list: []const Inst.Index,
        cond_br: CondBr,

        pub const CondBr = struct {
            pred: Inst.Index,
            then: []const Inst.Index,
            @"else": []const Inst.Index,
        };

        pub fn deinit(data: Data, allocator: std.mem.Allocator) void {
            switch (data) {
                .list => |list| allocator.free(list),
                .cond_br => |cond_br| {
                    allocator.free(cond_br.then);
                    allocator.free(cond_br.@"else");
                },
                else => {},
            }
        }
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

    pub const Block = struct {
        parent: *Builder,
        instructions: std.ArrayListUnmanaged(Inst.Index) = .{},

        pub fn addInst(b: *Block, inst: Inst) !Inst.Index {
            const parent = b.parent;
            const gpa = parent.allocator;
            try parent.instructions.ensureUnusedCapacity(gpa, 1);

            const result_index: Inst.Index = @enumFromInt(parent.instructions.len);
            parent.instructions.appendAssumeCapacity(inst);
            try b.instructions.append(gpa, result_index);
            return result_index;
        }

        pub fn addUnOp(
            b: *Block,
            tag: Inst.Tag,
            operand: Inst.Operand,
        ) !Inst.Index {
            return b.addInst(.{
                .tag = tag,
                .data = .{ .un_op = operand },
            });
        }

        pub fn addBinOp(
            b: *Block,
            tag: Inst.Tag,
            lhs: Inst.Operand,
            rhs: Inst.Operand,
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
            b: *Block,
            tag: Inst.Tag,
        ) !Inst.Index {
            return b.addInst(.{
                .tag = tag,
                .data = .none,
            });
        }

        pub fn addConstant(
            b: *Block,
            tag: Inst.Tag,
            val: i64,
        ) !Inst.Index {
            return b.addInst(.{
                .tag = tag,
                .data = .{ .un_op = .{ .value = val } },
            });
        }

        pub fn addArg(
            b: *Block,
            tag: Inst.Tag,
            index: u32,
        ) !Inst.Index {
            return b.addInst(.{
                .tag = tag,
                .data = .{ .arg = index },
            });
        }

        pub fn deinit(b: *Block) void {
            const allocator = b.parent.allocator;
            b.instructions.deinit(allocator);
        }
    };

    pub fn setBlock(b: *Builder, index: Inst.Index, block: *Block) !void {
        b.instructions.set(@intFromEnum(index), .{
            .tag = .block,
            .data = .{ .list = try block.instructions.toOwnedSlice(b.allocator) },
        });
    }

    pub fn toIr(b: *Builder, block: *Block) !Ir {
        return .{
            .instructions = b.instructions.toOwnedSlice(),
            .main_body = try block.instructions.toOwnedSlice(b.allocator),
        };
    }

    pub fn deinit(b: *Builder) void {
        for (b.instructions.items(.data)) |data| {
            data.deinit(b.allocator);
        }
        b.instructions.deinit(b.allocator);
    }
};

pub fn deinit(ir: *Ir, allocator: std.mem.Allocator) void {
    for (0..ir.instructions.len) |i| {
        const inst = ir.instructions.get(i);
        switch (inst.tag) {
            .block => allocator.free(inst.data.list),
            .cond_br => {
                const cond_br = inst.data.cond_br;
                allocator.free(cond_br.then);
                allocator.free(cond_br.@"else");
            },
            else => {},
        }
    }

    ir.instructions.deinit(allocator);
    allocator.free(ir.main_body);
}

/// Dumps the Ir in a human-readable form.
pub fn dump(ir: *const Ir, writer: anytype) !void {
    var w: Writer = .{
        .ir = ir,
        .indent = 0,
    };
    try w.printBody(ir.main_body, writer);
}

const Writer = struct {
    ir: *const Ir,
    indent: usize,

    fn printBody(w: *Writer, body: []const Inst.Index, s: anytype) @TypeOf(s).Error!void {
        for (body) |index| {
            try w.printInst(index, s);
            try s.writeByte('\n');
        }
    }

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
            .br,
            .cmp_gt,
            => try w.writeBinOp(inst, s),
            .arg,
            => try w.writeArg(inst, s),
            .block,
            => try w.writeBlock(inst, s),
            .cond_br,
            => try w.writeCondBr(inst, s),
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
        const arg = w.ir.instructions.items(.data)[@intFromEnum(inst)].arg;
        try s.print("{d}", .{arg});
    }

    fn writeBlock(w: *Writer, inst: Ir.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const list = w.ir.instructions.items(.data)[@intFromEnum(inst)].list;

        try s.writeAll("{\n");
        w.indent += 4;
        try w.printBody(list, s);
        w.indent -= 4;
        try s.writeAll("}");
    }

    fn writeCondBr(w: *Writer, inst: Ir.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const cond_br = w.ir.instructions.items(.data)[@intFromEnum(inst)].cond_br;

        try s.print("%{}, {{\n", .{@intFromEnum(cond_br.pred)});

        w.indent += 4;
        try w.printBody(cond_br.then, s);
        w.indent -= 4;

        try s.writeByteNTimes(' ', w.indent);
        try s.writeAll("}, {\n");

        w.indent += 4;
        try w.printBody(cond_br.@"else", s);
        w.indent -= 4;

        try s.writeByteNTimes(' ', w.indent);
        try s.writeAll("}");
    }
};

const Ir = @This();
const std = @import("std");
const Oir = @import("Oir.zig");
pub const Parser = @import("Ir/Parser.zig");
pub const Constructor = @import("Ir/Constructor.zig");
const assert = std.debug.assert;
