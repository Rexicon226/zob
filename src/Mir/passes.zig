//! Analysis passes to run on MIR

const Error = error{VerifyFailed} || std.mem.Allocator.Error;

pub const map = std.StaticStringMap(type).initComptime(&.{
    .{ "liveVars", LivenessPass },
    .{ "regAlloc", RegAllocPass },
});

/// A MIR pass that generates liveness data for Values.
///
/// Creates a map that relates a MIR instruction to a bundle of data
/// that describes the status of their operands.
///
/// Intended to be ran before register allocation, so that registers
/// can be allocated more efficiently.
const LivenessPass = struct {
    /// A map that relates virtual registers to their variable info struct.
    virtinfo: std.AutoHashMapUnmanaged(VirtualRegister.Index, ValueInfo),

    /// The ValueInfo struct describes a couple of different properties about a
    /// Value. The most important one is that it describes what the instruction
    /// inside of the current MIR is last to use this Value.
    const ValueInfo = struct {
        last_usage: Mir.Instruction.Index,
    };

    pub fn init(mir: *Mir) !*LivenessPass {
        const gpa = mir.gpa;
        const pass = try gpa.create(LivenessPass);
        pass.* = .{
            .virtinfo = .{},
        };
        return pass;
    }

    pub fn deinit(pass: *LivenessPass, mir: *Mir) void {
        const gpa = mir.gpa;
        pass.virtinfo.deinit(gpa);
        gpa.destroy(pass);
    }

    pub fn run(pass: *LivenessPass, mir: *Mir) Error!void {
        // go through instructions and find the last usages of virtual registers
        for (0..mir.instructions.len) |i| {
            const tag: Mir.Instruction.Tag = mir.instructions.items(.tag)[i];
            const data: Mir.Instruction.Data = mir.instructions.items(.data)[i];
            if (!tag.canHaveVRegOperand()) continue;

            switch (data) {
                .register => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
                .none => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
                .bin_op => |bin_op| {
                    inline for (.{ bin_op.rhs, bin_op.lhs, bin_op.dst }) |value| {
                        try pass.updateInfo(mir, value, @enumFromInt(i));
                    }
                },
                .un_op => |un_op| {
                    inline for (.{ un_op.dst, un_op.src }) |value| {
                        try pass.updateInfo(mir, value, @enumFromInt(i));
                    }
                },
            }
        }
    }

    fn updateInfo(
        pass: *LivenessPass,
        mir: *Mir,
        operand: Value,
        inst: Mir.Instruction.Index,
    ) !void {
        switch (operand) {
            .virtual => |vreg| {
                const gop = try pass.virtinfo.getOrPut(mir.gpa, vreg.index);
                // an earlier instruction already used this virtual register. update the entry
                // to this later one.
                if (gop.found_existing)
                    assert(@intFromEnum(gop.value_ptr.last_usage) <= @intFromEnum(inst));
                gop.value_ptr.last_usage = inst;
            },
            else => {},
        }
    }

    pub fn verify(pass: *LivenessPass, mir: *Mir) Error!void {
        _ = pass;
        _ = mir;
    }
};

/// A MIR pass that focuses on allocating physical registers and replacing
/// all virtual register usages.
///
/// When possible, removes stale COPY instructions, leaving only ones that
/// have both operands as physical registers.
const RegAllocPass = struct {
    /// A map that ties a virtual register to a physically allocated register.
    ///
    /// Multiple virtual registers can point at the same physical register.
    virt_to_physical: std.AutoHashMapUnmanaged(VirtualRegister, Register),
    register_manager: RegisterManager,

    const log = std.log.scoped(.reg_alloc_pass);

    pub fn init(mir: *Mir) !*RegAllocPass {
        const gpa = mir.gpa;
        const pass = try gpa.create(RegAllocPass);
        pass.* = .{
            .virt_to_physical = .{},
            .register_manager = .{},
        };
        return pass;
    }

    pub fn deinit(pass: *RegAllocPass, mir: *Mir) void {
        const gpa = mir.gpa;
        pass.virt_to_physical.deinit(gpa);
        gpa.destroy(pass);
    }

    /// The goal of this pass is to perform register allocation
    /// and remove all uses of virtual registers.
    ///
    /// TODO: we want to support "fast" and "greedy" modes
    /// of register allocation. this is currently just "fast" or "simple".
    pub fn run(pass: *RegAllocPass, mir: *Mir) Error!void {
        try pass.coalesceRegisters(mir);
        try pass.rewriteVRegisters(mir);
    }

    /// TODO: this should probably be split off into its own pass.
    /// need to setup persistent storage of pass metadata in order to cache the
    /// virtual to physical register map.
    fn coalesceRegisters(pass: *RegAllocPass, mir: *Mir) !void {
        const gpa = mir.gpa;

        // start off by seeding the map by analysing the COPY instructions
        for (0..mir.instructions.len) |i| {
            const tag: Mir.Instruction.Tag = mir.instructions.items(.tag)[i];
            const data: Mir.Instruction.Data = mir.instructions.items(.data)[i];
            if (!tag.canHaveVRegOperand()) continue;

            switch (tag) {
                .copy => {
                    // we want to get the most "up to date" version of the COPY we can
                    // because virtual registers are always unique and allocated in order,
                    // when we analyse this COPY instruction, we can look at the map and see if
                    // any of the inputs have already been resolved to physical registers.
                    //
                    // this is needed to tell whether a COPY instructions has both operands as
                    // physical registers, and needs to exist post register allocation.
                    const un_op = data.un_op;
                    const src: Mir.Value = if (un_op.src == .virtual) lhs: {
                        if (pass.virt_to_physical.get(un_op.src.virtual)) |reg| {
                            break :lhs .{ .register = reg };
                        }
                        break :lhs un_op.src;
                    } else un_op.src;

                    const dst: Mir.Value = if (un_op.dst == .virtual) rhs: {
                        if (pass.virt_to_physical.get(un_op.dst.virtual)) |reg| {
                            break :rhs .{ .register = reg };
                        }
                        break :rhs un_op.dst;
                    } else un_op.dst;

                    // the COPY can be removed if one or both of the operands is a virtual register,
                    // even after checking the map.
                    // COPY instructions between two physical registers need to stay, since we need
                    // to move values between registers.
                    // an example of this could be:
                    // %0 = arg(0)
                    // %1 = arg(1)
                    // %2 = ret(%1)
                    var should_remove: bool = true;

                    var physical: ?Register = null;
                    var virtual: ?VirtualRegister = null;

                    inline for (.{ src, dst }) |operand| {
                        switch (operand) {
                            .register => |reg| {
                                // both operands are physical registers, we can't remove it.
                                if (physical != null) should_remove = false;
                                physical = reg;
                            },
                            .virtual => |vreg| {
                                assert(virtual == null);
                                virtual = vreg;
                            },
                            .immediate => {},
                            else => unreachable,
                        }
                    }
                    if (!should_remove) continue;
                    if (physical == null or virtual == null) continue;

                    try pass.virt_to_physical.put(gpa, virtual.?, physical.?);
                    log.debug("setting {} for vreg {}", .{ physical.?, virtual.? });
                    pass.register_manager.lockClobber(physical.?);

                    // the final change we can make is setting this COPY instruction
                    // to a tombstone, since after this pass COPY instructions can't exist.
                    mir.instructions.set(i, .{
                        .tag = .tombstone,
                        .data = .none,
                    });

                    continue;
                },
                else => {},
            }
        }
    }

    fn rewriteVRegisters(pass: *RegAllocPass, mir: *Mir) !void {
        // now replace other instructions and allocate as needed
        for (0..mir.instructions.len) |i| {
            const tag: Mir.Instruction.Tag = mir.instructions.items(.tag)[i];
            const data: Mir.Instruction.Data = mir.instructions.items(.data)[i];
            if (!tag.canHaveVRegOperand()) continue;

            switch (data) {
                .register => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
                .none => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
                .bin_op => |bin_op| {
                    var new_bin_op: Mir.Instruction.BinOp = .{
                        .rhs = bin_op.rhs,
                        .lhs = bin_op.lhs,
                        .dst = bin_op.dst,
                    };

                    inline for (
                        .{ bin_op.lhs, bin_op.rhs, bin_op.dst },
                        .{ &new_bin_op.lhs, &new_bin_op.rhs, &new_bin_op.dst },
                    ) |operand, value| {
                        try pass.updateValue(mir, @enumFromInt(i), operand, value);
                    }

                    mir.instructions.set(i, .{
                        .tag = tag,
                        .data = .{ .bin_op = new_bin_op },
                    });
                },
                .un_op => |un_op| {
                    var new_un_op: Mir.Instruction.UnOp = .{
                        .src = un_op.src,
                        .dst = un_op.dst,
                    };

                    inline for (
                        .{ un_op.src, un_op.dst },
                        .{ &new_un_op.src, &new_un_op.dst },
                    ) |operand, value| {
                        try pass.updateValue(mir, @enumFromInt(i), operand, value);
                    }

                    mir.instructions.set(i, .{
                        .tag = tag,
                        .data = .{ .un_op = new_un_op },
                    });
                },
            }
        }
    }

    fn updateValue(
        pass: *RegAllocPass,
        mir: *Mir,
        inst: Mir.Instruction.Index,
        operand: Value,
        value: *Mir.Value,
    ) !void {
        const gpa = mir.gpa;
        const vreg = if (operand == .virtual) operand.virtual else return;
        const liveness: *const LivenessPass = mir.getPassData("liveVars").?; // liveness should run before regalloc

        const gop = try pass.virt_to_physical.getOrPut(gpa, vreg);
        // another instruction or operand has already allocated a physical register
        // for this virtual register. we can simply set it here.
        if (gop.found_existing) {
            value.* = .{ .register = gop.value_ptr.* };
        } else {
            // otherwise we need to allocate a new register to be used here
            const allocated_register = pass.register_manager.allocateGeneral(.int);
            log.debug("allocating {} for vreg {}", .{ allocated_register, vreg });
            pass.register_manager.lock(allocated_register);
            gop.value_ptr.* = allocated_register;
            value.* = .{ .register = allocated_register };
        }

        if (liveness.virtinfo.get(vreg.index)) |info| {
            if (info.last_usage == inst) {
                // this is the last usage, we can unlock the register to be used later
                pass.register_manager.unlock(value.register);
            }
        }
    }

    /// To verify this pass ran correctly and left the MIR in a sound state
    /// we can iterate and check that there are no COPY instructions
    /// or virtual registers used anywhere.
    pub fn verify(pass: *RegAllocPass, mir: *Mir) Error!void {
        _ = pass;

        const tags = mir.instructions.items(.tag);
        const data = mir.instructions.items(.data);

        for (tags, data) |tag, inst| {
            if (!tag.canHaveVRegOperand()) continue;
            switch (inst) {
                .register => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
                .none => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
                .bin_op => |bin_op| {
                    inline for (.{ bin_op.dst, bin_op.lhs, bin_op.rhs }) |val| {
                        if (val == .virtual) {
                            log.err("virtual register usage found in verification step", .{});
                            return error.VerifyFailed;
                        }
                    }
                },
                .un_op => |un_op| {
                    inline for (.{ un_op.dst, un_op.src }) |val| {
                        if (val == .virtual) {
                            log.err("virtual register usage found in verification step", .{});
                            return error.VerifyFailed;
                        }
                    }
                },
            }
        }
    }
};

const std = @import("std");
const Mir = @import("../Mir.zig");
const bits = @import("bits.zig");
const RegisterManager = @import("RegisterManager.zig");
const assert = std.debug.assert;

const VirtualRegister = bits.VirtualRegister;
const Register = bits.Register;
const Value = Mir.Value;
