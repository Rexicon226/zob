//! Performs instruction selection over the region tree, lowering each node to
//! abstraction RV64-flavoured instructions using virtual registers.
//!
//! Interesting considerations:
//! - `gamma`: Emit a branch diamond, with its two arms emitted as nested
//! regions, so an arm-exlusive side effect is only reached on its control path.

const std = @import("std");
const Oir = @import("../../Oir.zig");
const Schedule = @import("Schedule.zig");

const Recursive = Oir.extraction.Recursive;
const NodeIdx = Oir.Class.Index;

pub const VReg = NodeIdx;
pub const Label = u32;

pub const BinOp = enum {
    add,
    sub,
    mul,
    @"and",
    sll,
    srl,
    div,
    xor,
    slt,
};

pub const UnOp = enum {
    seqz,
    load,
    store,
    mv,
};

// TODO: uhh, this is ugly obviously,
// will use a real Mir i wrote for riscv2.0 in Zig here prob
pub const Inst = union(enum) {
    bin: struct { op: BinOp, dst: VReg, lhs: VReg, rhs: VReg },
    un: struct { op: UnOp, dst: VReg, src: VReg },
    li: struct { dst: VReg, imm: i64 },
    beqz: struct { src: VReg, target: Label },
    j: Label,
    label: Label,
    /// `mv a0, src`, sets the return value.
    set_ret: VReg,
    // `mv dst, {arg}`
    arg: struct { dst: VReg, index: u32 },
    ret,

    /// Calls `f(ctx, vreg)` for each vreg this instruction defines.
    pub fn forEachDef(inst: Inst, ctx: anytype, comptime f: fn (@TypeOf(ctx), VReg) void) void {
        switch (inst) {
            inline .arg, .li, .bin, .un => |p| f(ctx, p.dst),
            .beqz, .j, .label, .set_ret, .ret => {},
        }
    }

    /// Calls `f(ctx, vreg)` for each vreg this instruction uses.
    pub fn forEachUse(inst: Inst, ctx: anytype, comptime f: fn (@TypeOf(ctx), VReg) void) void {
        switch (inst) {
            .arg, .li, .j, .label, .ret => {},
            .un => |p| f(ctx, p.src),
            .beqz => |p| f(ctx, p.src),
            .set_ret => |v| f(ctx, v),
            .bin => |p| {
                f(ctx, p.lhs);
                f(ctx, p.rhs);
            },
        }
    }

    fn xor(dst: VReg, lhs: VReg, rhs: VReg) Inst {
        return .{ .bin = .{ .op = .xor, .dst = dst, .lhs = lhs, .rhs = rhs } };
    }
    fn slt(dst: VReg, lhs: VReg, rhs: VReg) Inst {
        return .{ .bin = .{ .op = .slt, .dst = dst, .lhs = lhs, .rhs = rhs } };
    }

    fn seqz(dst: VReg, src: VReg) Inst {
        return .{ .un = .{ .op = .seqz, .dst = dst, .src = src } };
    }
    fn mv(dst: VReg, src: VReg) Inst {
        return .{ .un = .{ .op = .mv, .dst = dst, .src = src } };
    }
    fn load(dst: VReg, src: VReg) Inst {
        return .{ .un = .{ .op = .load, .dst = dst, .src = src } };
    }
    fn store(dst: VReg, src: VReg) Inst {
        return .{ .un = .{ .op = .store, .dst = dst, .src = src } };
    }
};

insts: std.ArrayList(Inst),

const Mir = @This();

pub fn build(gpa: std.mem.Allocator, recv: *const Recursive, sched: *const Schedule) !Mir {
    var b: Builder = .{ .gpa = gpa, .recv = recv, .sched = sched };
    try b.emitRegion(.root);
    return .{ .insts = b.insts };
}

pub fn deinit(m: *Mir, gpa: std.mem.Allocator) void {
    m.insts.deinit(gpa);
}

const Builder = struct {
    gpa: std.mem.Allocator,
    recv: *const Recursive,
    sched: *const Schedule,
    insts: std.ArrayList(Inst) = .empty,
    next_label: Label = 0,

    fn add(b: *Builder, inst: Inst) !void {
        try b.insts.append(b.gpa, inst);
    }

    fn new(b: *Builder) Label {
        defer b.next_label += 1;
        return b.next_label;
    }

    /// Emit every node assigned to a `region`, in topological order.
    /// Nodes belonging to nested regions are skipped here and emitted when their
    /// owning `gamma` is reached.
    fn emitRegion(b: *Builder, region: Schedule.Region.Id) std.mem.Allocator.Error!void {
        for (b.recv.nodes.items, 0..) |_, i| {
            if (b.sched.node_region[i] == region) try b.emitNode(@enumFromInt(i));
        }
    }

    fn emitNode(b: *Builder, n: NodeIdx) std.mem.Allocator.Error!void {
        const node = b.recv.nodes.items[@intFromEnum(n)];
        switch (node.tag) {
            .start => {}, // abstract entry, nothing to emit
            .project => {
                const project = node.data.project;
                if (project.index != 0) {
                    try b.add(.{ .arg = .{ .dst = n, .index = project.index - 1 } });
                }
            },
            .constant => try b.add(.{ .li = .{ .dst = n, .imm = node.data.constant } }),
            .add, .sub, .mul, .@"and", .shl, .shr, .div_trunc, .div_exact => {
                const ops = node.data.bin_op;
                try b.add(.{ .bin = .{
                    .op = switch (node.tag) {
                        .add => .add,
                        .sub => .sub,
                        .mul => .mul,
                        .@"and" => .@"and",
                        .shl => .sll,
                        .shr => .srl,
                        .div_trunc, .div_exact => .div,
                        else => unreachable,
                    },
                    .dst = n,
                    .lhs = ops[0],
                    .rhs = ops[1],
                } });
            },
            .cmp_eq => {
                // a == b <=> (a ^ b) == 0
                const ops = node.data.bin_op;
                try b.add(.xor(n, ops[0], ops[1]));
                try b.add(.seqz(n, n));
            },
            .cmp_gt => {
                // a > b <=> b < a
                const ops = node.data.bin_op;
                try b.add(.slt(n, ops[1], ops[0]));
            },
            .load => {
                // (mem, address)
                const ops = node.data.bin_op;
                try b.add(.load(n, ops[1]));
            },
            .store => {
                // (mem, address, value)
                const ops = node.data.tri_op;
                try b.add(.store(ops[2], ops[1]));
            },
            .gamma => {
                const ops = node.data.tri_op;
                const arms = b.sched.gamma_regions.get(n).?;
                const is_data = !b.sched.is_mem[@intFromEnum(n)];

                const else_label = b.new();
                const join_label = b.new();

                try b.add(.{ .beqz = .{ .src = ops[0], .target = else_label } });

                try b.emitRegion(arms[0]); // then
                if (is_data) try b.add(.mv(n, ops[1]));
                try b.add(.{ .j = join_label });

                try b.add(.{ .label = else_label });
                try b.emitRegion(arms[1]); // else
                if (is_data) try b.add(.mv(n, ops[2]));

                try b.add(.{ .label = join_label });
            },
            .theta => @panic("rv64: theta/loops are not supported yet"),
            .ret => {
                // (final_mem, ret)
                const ops = node.operands(b.recv);
                if (ops.len > 1) try b.add(.{ .set_ret = ops[1] });
                try b.add(.ret);
            },
        }
    }
};
