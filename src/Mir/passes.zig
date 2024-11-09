//! Analysis passes to run on MIR

pub const Pass = struct {
    name: []const u8,
    func: *const fn (*Mir) Error!void,

    const Error = error{} || std.mem.Allocator.Error;
};

pub const list: []const Pass = &.{
    .{ .name = "regAlloc", .func = regAlloc },
};

/// The goal of this pass is to perform register allocation
/// and remove all uses of virtual registers.
///
/// TODO: we want to support "fast" and "greedy" modes
/// of register allocation. this is currently just "fast" or "simple".
pub fn regAlloc(mir: *Mir) Pass.Error!void {
    const gpa = mir.gpa;
    var virt_to_reg: std.AutoHashMapUnmanaged(VirtualRegister, Register) = .{};
    defer virt_to_reg.deinit(gpa);

    // start off by analysing the MIR and finding all usages of VRegs.
    for (0..mir.instructions.len) |i| {
        const tag: Mir.Instruction.Tag = mir.instructions.items(.tag)[i];
        const data: Mir.Instruction.Data = mir.instructions.items(.data)[i];
        if (!tag.canHaveVRegOperand()) continue;

        switch (data) {
            .reg => unreachable, // should be unreachable due to `canHaveVRegOperand` check.
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

const std = @import("std");
const Mir = @import("../Mir.zig");
const bits = @import("../bits.zig");

const VirtualRegister = bits.VirtualRegister;
const Register = bits.Register;
