//! Analysis passes to run on MIR

const Error = error{VerifyFailed} || std.mem.Allocator.Error;

pub const map = std.StaticStringMap(type).initComptime(&.{
    .{ "regAlloc", RegAllocPass },
});

const RegAllocPass = struct {
    something: []const u8 = "",

    const log = std.log.scoped(.reg_alloc_pass);

    pub fn init(mir: *Mir) !*RegAllocPass {
        const gpa = mir.gpa;
        const pass = try gpa.create(RegAllocPass);
        pass.* = .{};
        return pass;
    }

    pub fn deinit(pass: *RegAllocPass, mir: *Mir) void {
        const gpa = mir.gpa;
        gpa.destroy(pass);
    }

    /// The goal of this pass is to perform register allocation
    /// and remove all uses of virtual registers.
    ///
    /// TODO: we want to support "fast" and "greedy" modes
    /// of register allocation. this is currently just "fast" or "simple".
    pub fn run(pass: *RegAllocPass, mir: *Mir) Error!void {
        _ = pass;
        const gpa = mir.gpa;
        var virt_to_reg: std.AutoHashMapUnmanaged(VirtualRegister, Register) = .{};
        defer virt_to_reg.deinit(gpa);

        // start off by analysing the MIR and finding all usages of VRegs.
        for (0..mir.instructions.len) |i| {
            const tag: Mir.Instruction.Tag = mir.instructions.items(.tag)[i];
            const data: Mir.Instruction.Data = mir.instructions.items(.data)[i];
            if (!tag.canHaveVRegOperand()) continue;

            switch (tag) {
                .copy => {
                    // COPY instructions are special in that they already have a physical
                    // register for the virtual register.
                    // every virtual register index is unique in the IR, so when we use the
                    // virtual registers are the key to the map, we can point to the same physical
                    // register with multiple virtual registers.
                    const bin_op = data.bin_op;

                    var physical: ?Register = null;
                    var virtual: ?VirtualRegister = null;

                    inline for (.{ bin_op.lhs, bin_op.rhs }) |operand| {
                        switch (operand) {
                            .register => |reg| {
                                // TODO: investigate where a COPY could be going from a
                                // virtual to a virtual or from a physical to a physical.
                                assert(physical == null);
                                physical = reg;
                            },
                            .virtual => |vreg| {
                                assert(virtual == null);
                                virtual = vreg;
                            },
                            else => unreachable,
                        }
                    }

                    if (physical == null or virtual == null) {
                        @panic("TODO: should this be possible? just not sure yet");
                    }

                    try virt_to_reg.put(gpa, virtual.?, physical.?);

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

        // now replace and allocate other instructions as needed
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
                        switch (operand) {
                            .virtual => |vreg| {
                                const gop = try virt_to_reg.getOrPut(gpa, vreg);
                                // another instruction or operand has already allocated a physical register
                                // for this virtual register. we can simply set it here.
                                if (gop.found_existing) {
                                    value.* = .{ .register = gop.value_ptr.* };
                                } else {
                                    // otherwise we need to allocate a new register to be used here
                                    const allocated_register = try mir.allocPhysicalRegister(.int);
                                    gop.value_ptr.* = allocated_register;
                                    value.* = .{ .register = allocated_register };
                                }
                            },
                            else => {},
                        }
                    }

                    mir.instructions.set(i, .{
                        .tag = tag,
                        .data = .{ .bin_op = new_bin_op },
                    });
                },
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
            if (tag == .copy) {
                log.err("COPY instruction found in verification step", .{});
                return error.VerifyFailed;
            }

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
            }
        }
    }
};

const std = @import("std");
const Mir = @import("../Mir.zig");
const bits = @import("../bits.zig");
const assert = std.debug.assert;

const VirtualRegister = bits.VirtualRegister;
const Register = bits.Register;
