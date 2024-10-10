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
        constant,
    };

    pub const Data = union(enum) {
        none: void,
        un_op: Index,
        bin_op: struct {
            lhs: Index,
            rhs: Index,
        },
        value: i64,
        /// The arg number, meant to be persistent across all optimizations.
        arg: usize,
    };

    pub const Index = enum(u32) {
        _,
    };
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    instructions: std.MultiArrayList(Inst),

    pub fn toIr(b: *Builder) IR {
        return .{
            .instructions = b.instructions.toOwnedSlice(),
        };
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
        val: i64,
    ) !Inst.Index {
        return b.addInst(.{
            .tag = .constant,
            .data = .{ .value = val },
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

/// Only call when you're the direct owner of the IR. Make
/// sure it hasn't been passed into an OIR.
pub fn deinit(ir: *IR, allocator: std.mem.Allocator) void {
    ir.instructions.deinit(allocator);
}

const Writer = struct {
    ir: *const IR,
    indent: usize,

    fn printInst(w: *Writer, inst: IR.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const tag = w.ir.instructions.items(.tag)[@intFromEnum(inst)];
        try s.writeByteNTimes(' ', w.indent);
        try s.print("%{d} = {s}(", .{ @intFromEnum(inst), @tagName(tag) });
        switch (tag) {
            .ret,
            => try w.writeUnOp(inst, s),
            .mul,
            .shl,
            => try w.writeBinOp(inst, s),
            .arg,
            => try w.writeArg(inst, s),
            .constant,
            => try w.writeConstant(inst, s),
            else => std.debug.panic("TODO: {s}", .{@tagName(tag)}),
        }
        try s.writeAll(")");
    }

    fn writeBinOp(w: *Writer, inst: IR.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const bin_op = w.ir.instructions.items(.data)[@intFromEnum(inst)].bin_op;
        try s.print("%{d}", .{@intFromEnum(bin_op.lhs)});
        try s.writeAll(", ");
        try s.print("%{d}", .{@intFromEnum(bin_op.rhs)});
    }

    fn writeUnOp(w: *Writer, inst: IR.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const un_op = w.ir.instructions.items(.data)[@intFromEnum(inst)].un_op;
        try s.print("%{d}", .{@intFromEnum(un_op)});
    }

    fn writeConstant(w: *Writer, inst: IR.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        const value = w.ir.instructions.items(.data)[@intFromEnum(inst)].value;
        try s.print("${d}", .{value});
    }

    fn writeArg(w: *Writer, inst: IR.Inst.Index, s: anytype) @TypeOf(s).Error!void {
        _ = w;
        _ = inst;
        // try s.print("{d}", .{arg});
    }
};

/// Dumps the IR in a human-readable form.
pub fn dump(ir: *const IR, writer: anytype) !void {
    var w: Writer = .{
        .ir = ir,
        .indent = 0,
    };

    for (0..ir.instructions.len) |i| {
        try w.printInst(@enumFromInt(i), writer);
        try writer.writeByte('\n');
    }
}

const IR = @This();
const std = @import("std");
