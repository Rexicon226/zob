//! A super simple register allocation algorithm.

free: RegisterBitSet = RegisterBitSet.initFull(),
allocated: RegisterBitSet = RegisterBitSet.initEmpty(),
locked: RegisterBitSet = RegisterBitSet.initEmpty(),

pub const RegisterBitSet = std.StaticBitSet(allocatable_registers.len);

/// Allocates the next non-locked free registers from the general register bitset
/// of the given class.
pub fn allocateGeneral(manager: *Manager, class: Register.Class) Register {
    const bitset = generalSet(class);
    return manager.tryAllocateRegister(bitset);
}

fn generalSet(class: Register.Class) RegisterBitSet {
    return switch (class) {
        .int => Registers.Integer.general_purpose,
        .float => Registers.Float.general_purpose,
        .vector => Registers.Vector.general_purpose,
    };
}

fn tryAllocateRegister(
    manager: *Manager,
    register_class: RegisterBitSet,
) Register {
    var free_and_not_locked_registers = manager.free;
    free_and_not_locked_registers.setIntersection(register_class);

    var unlocked_registers = manager.locked;
    unlocked_registers.toggleAll();

    free_and_not_locked_registers.setIntersection(unlocked_registers);

    for (allocatable_registers) |reg| {
        if (excludeRegister(reg, register_class)) continue;
        if (manager.isRegLocked(reg)) continue;
        if (!manager.isRegFree(reg)) continue;

        return reg;
    }

    @panic("out of registers");
}

fn excludeRegister(reg: Register, register_class: RegisterBitSet) bool {
    const index = indexOfReg(reg) orelse return true;
    return !register_class.isSet(index);
}

fn isRegLocked(manager: *Manager, reg: Register) bool {
    return manager.locked.isSet(indexOfReg(reg) orelse return false);
}

fn isRegFree(manager: *Manager, reg: Register) bool {
    return manager.free.isSet(indexOfReg(reg) orelse return true);
}

fn indexOfReg(
    reg: Register,
) ?std.math.IntFittingRange(0, allocatable_registers.len - 1) {
    const set = allocatable_registers;
    @setEvalBranchQuota(3000);

    const Id = @TypeOf(reg.id());
    comptime var min_id: Id = std.math.maxInt(Id);
    comptime var max_id: Id = std.math.minInt(Id);
    inline for (set) |elem| {
        const elem_id = comptime elem.id();
        min_id = @min(elem_id, min_id);
        max_id = @max(elem_id, max_id);
    }

    const OptionalIndex = std.math.IntFittingRange(0, set.len);
    comptime var map = [1]OptionalIndex{set.len} ** (max_id - min_id + 1);
    inline for (set, 0..) |elem, elem_index| map[comptime elem.id() - min_id] = elem_index;

    const id_index = reg.id() -% min_id;
    if (id_index >= map.len) return null;
    const set_index = map[id_index];
    return if (set_index < set.len) @intCast(set_index) else null;
}

pub fn lock(manager: *Manager, reg: Register) void {
    if (manager.isRegLocked(reg)) {
        @panic("register already locked");
    }
    manager.lockClobber(reg);
}

/// Same as `lock`, however doesn't panic on double-locks. Useful for blanket locks.
pub fn lockClobber(manager: *Manager, reg: Register) void {
    log.debug("locking register: {}", .{reg});
    manager.locked.set(indexOfReg(reg) orelse @panic("what to do about this?"));
}

pub fn unlock(manager: *Manager, reg: Register) void {
    log.debug("unlocking register: {}", .{reg});
    manager.locked.unset(indexOfReg(reg) orelse @panic("what to do about this?"));
}

const allocatable_registers =
    Registers.Integer.all_regs ++
    Registers.Float.all_regs ++
    Registers.Vector.all_regs;

const log = std.log.scoped(.register_manager);

const std = @import("std");
const assert = std.debug.assert;
const Manager = @This();
const bits = @import("../bits.zig");
const Register = bits.Register;
const Registers = bits.Registers;
