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

const IR = @This();
const std = @import("std");
