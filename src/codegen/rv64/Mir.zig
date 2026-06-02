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
    /// `mv a{index}, src`, places a call argument into its ABI register.
    set_arg: struct { index: u32, src: VReg },
    /// `call {name}; mv dst, a0`. Clobbers the caller-saved registers.
    call: struct { callee: u32, dst: VReg },
    ret,

    /// Calls `f(ctx, vreg)` for each vreg this instruction defines.
    pub fn forEachDef(inst: Inst, ctx: anytype, comptime f: fn (@TypeOf(ctx), VReg) void) void {
        switch (inst) {
            inline .arg, .li, .bin, .un => |p| f(ctx, p.dst),
            .call => |p| f(ctx, p.dst),
            .beqz, .j, .label, .set_ret, .set_arg, .ret => {},
        }
    }

    /// Calls `f(ctx, vreg)` for each vreg this instruction uses.
    pub fn forEachUse(inst: Inst, ctx: anytype, comptime f: fn (@TypeOf(ctx), VReg) void) void {
        switch (inst) {
            .arg, .li, .j, .label, .ret, .call => {},
            .un => |p| f(ctx, p.src),
            .beqz => |p| f(ctx, p.src),
            .set_ret => |v| f(ctx, v),
            .set_arg => |p| f(ctx, p.src),
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
    const emitted = try gpa.alloc(bool, recv.nodes.items.len);
    defer gpa.free(emitted);
    @memset(emitted, false);

    var b: Builder = .{ .gpa = gpa, .recv = recv, .sched = sched, .emitted = emitted };

    // Move incoming arguments out of a0..a7 at the very top of the function,
    // before any `call` can clobber them.
    for (recv.nodes.items, 0..) |node, i| {
        if (node.tag == .param and node.data.param.index >= 1) {
            try b.add(.{ .arg = .{ .dst = @enumFromInt(i), .index = node.data.param.index - 1 } });
        }
    }

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
    /// Gammas already lowered as part of a fused branch group, indexed by node.
    emitted: []bool,

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

    /// At the tail of a fused branch arm, copy each data gamma's selected value
    /// into its result vreg. Memory gammas produce no value, so they are skipped.
    fn emitGroupMoves(
        b: *Builder,
        region: Schedule.Region.Id,
        pred: NodeIdx,
        arm: enum { then, @"else" },
    ) !void {
        for (b.recv.nodes.items, 0..) |g, i| {
            if (g.tag != .gamma) continue;
            if (b.sched.node_region[i] != region) continue;
            if (g.data.tri_op[0] != pred) continue;
            if (b.sched.is_mem[i]) continue;
            const dst: NodeIdx = @enumFromInt(i);
            const src = switch (arm) {
                .then => g.data.tri_op[1],
                .@"else" => g.data.tri_op[2],
            };
            try b.add(.mv(dst, src));
        }
    }

    fn emitNode(b: *Builder, n: NodeIdx) std.mem.Allocator.Error!void {
        const node = b.recv.nodes.items[@intFromEnum(n)];
        switch (node.tag) {
            .start => {}, // abstract entry, nothing to emit
            .loopvar => {},
            .project => {
                if (b.sched.is_mem[@intFromEnum(n)]) return; // memory state, no register
                const project = node.data.project;
                const tuple = b.recv.nodes.items[@intFromEnum(project.tuple)];
                switch (tuple.tag) {
                    .start => try b.add(.{ .arg = .{ .dst = n, .index = project.index - 1 } }),
                    .theta => try b.add(.mv(n, tuple.data.loop.args(b.recv)[project.index])),
                    .call => try b.add(.mv(n, project.tuple)),
                    else => std.debug.panic("project of {s}", .{@tagName(tuple.tag)}),
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
            .cmp_lt => {
                const ops = node.data.bin_op;
                try b.add(.slt(n, ops[0], ops[1]));
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
                // Lowered as part of a fused branch group already.
                if (b.emitted[@intFromEnum(n)]) return;

                const region = b.sched.node_region[@intFromEnum(n)];
                const pred = node.data.tri_op[0];
                const arms = b.sched.gamma_regions.get(n).?;

                const else_label = b.new();
                const join_label = b.new();

                try b.add(.{ .beqz = .{ .src = pred, .target = else_label } });

                try b.emitRegion(arms[0]); // then
                try b.emitGroupMoves(region, pred, .then);
                try b.add(.{ .j = join_label });

                try b.add(.{ .label = else_label });
                try b.emitRegion(arms[1]); // else
                try b.emitGroupMoves(region, pred, .@"else");

                try b.add(.{ .label = join_label });

                // Mark the whole group lowered.
                for (b.recv.nodes.items, 0..) |g, i| {
                    if (g.tag == .gamma and
                        b.sched.node_region[i] == region and
                        g.data.tri_op[0] == pred)
                    {
                        b.emitted[i] = true;
                    }
                }
            },
            .theta => {
                const loop = node.data.loop;
                const regions = b.sched.theta_regions.get(n).?;
                const args = loop.args(b.recv);
                const inits = loop.inits(b.recv);
                const nexts = loop.nexts(b.recv);

                const head = b.new();
                const exit = b.new();

                // Initialize each loop slot register. Slot 0 is the memory state
                // so we skip it. The rest get `arg_i := init_i`.
                for (args, inits, 0..) |arg, init, slot| {
                    if (slot == 0) continue;
                    try b.add(.mv(arg, init));
                }

                try b.add(.{ .label = head });
                try b.emitRegion(regions[0]); // test: compute the predicate
                try b.add(.{ .beqz = .{ .src = loop.pred(b.recv), .target = exit } });
                try b.emitRegion(regions[1]); // body: compute next values (side effects)

                // Advance the slot registers. The next values are already in their
                // own vregs, so sequential copies are safe (no slot is read again).
                for (args, nexts, 0..) |arg, next, slot| {
                    if (slot == 0) continue;
                    try b.add(.mv(arg, next));
                }
                try b.add(.{ .j = head });
                try b.add(.{ .label = exit });
            },
            .ret => {
                // (final_mem, ret)
                const ops = node.operands(b.recv);
                if (ops.len > 1) try b.add(.{ .set_ret = ops[1] });
                try b.add(.ret);
            },
            // A function root. Its results are (final_mem, value?).
            // Set the return register from the value and return.
            .lambda => {
                const results = node.data.lambda.results(b.recv);
                if (results.len > 1) try b.add(.{ .set_ret = results[1] });
                try b.add(.ret);
            },
            .param => {},
            .call => {
                const c = node.data.call;
                for (c.args(b.recv), 0..) |arg, i| {
                    try b.add(.{ .set_arg = .{ .index = @intCast(i), .src = arg } });
                }
                try b.add(.{ .call = .{ .callee = c.callee, .dst = n } });
            },
        }
    }
};
