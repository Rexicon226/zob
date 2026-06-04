//! RISC-V 64-bit assembly backend.
//!
//! TODO: more in-depth comments here would be good
//!
//! Operates on the extracted Oir through a few seperate steps.
//!
//! 1. `Schedule`. Converts the `Oir.extraction.Recursive` into a region-tree
//! and computes placement for nodes.
//! 2. `Mir`. Selects instructions using virtual registers.
//! 3. `RegAlloc`. As the name suggests, allocations physical registers / spills.
//! 4. `Emit`. Prints assembly, in the future of course will emit real objects.

const std = @import("std");
const Oir = @import("../Oir.zig");
const Schedule = @import("rv64/Schedule.zig");
const Mir = @import("rv64/Mir.zig");
const RegAlloc = @import("rv64/RegAlloc.zig");

const Recursive = Oir.extraction.Recursive;

pub const Register = enum(u5) {
    zero = 0,
    ra = 1,
    sp = 2,
    gp = 3,
    tp = 4,
    t0 = 5,
    t1 = 6,
    t2 = 7,
    s0 = 8,
    s1 = 9,
    a0 = 10,
    a1 = 11,
    a2 = 12,
    a3 = 13,
    a4 = 14,
    a5 = 15,
    a6 = 16,
    a7 = 17,
    s2 = 18,
    s3 = 19,
    s4 = 20,
    s5 = 21,
    s6 = 22,
    s7 = 23,
    s8 = 24,
    s9 = 25,
    s10 = 26,
    s11 = 27,
    t3 = 28,
    t4 = 29,
    t5 = 30,
    t6 = 31,
};

pub const arg_regs = [_]Register{ .a0, .a1, .a2, .a3, .a4, .a5, .a6, .a7 };

/// The registers that the allocator may hand out, in preference order.
pub const alloc_pool = [_]Register{ .t0, .t1, .t2, .t3, .s2, .s3, .s4, .s5, .s6, .s7, .s8, .s9, .s10, .s11 };

/// Scratch registers used only by the emitter to materialize spilled operands.
/// Will rework all of this in the future with a real graph-color based RegAlloc.
const scratch_dst: Register = .t4;
const scratch_src0: Register = .t5;
const scratch_src1: Register = .t6;

const slot_size = 8;

fn mnemonic(op: Mir.BinOp, width: u16) []const u8 {
    const w32 = width == 32;
    return switch (op) {
        .add => if (w32) "addw" else "add",
        .sub => if (w32) "subw" else "sub",
        .mul => if (w32) "mulw" else "mul",
        .sll => if (w32) "sllw" else "sll",
        .srl => if (w32) "srlw" else "srl",
        .sra => if (w32) "sraw" else "sra",
        .div => if (w32) "divw" else "div",
        .divu => if (w32) "divuw" else "divu",
        .@"and" => "and",
        .@"or" => "or",
        .xor => "xor",
        .slt => "slt",
        .sltu => "sltu",
    };
}

pub fn isSaved(reg: Register) bool {
    return switch (reg) {
        .s2, .s3, .s4, .s5, .s6, .s7, .s8, .s9, .s10, .s11 => true,
        else => false,
    };
}

pub const Global = struct {
    name: []const u8,
    external: bool,
    data: Data,

    pub const Data = union(enum) {
        declared,
        bss: struct { size: u64, @"align": u32 },
        bytes: struct { bytes: []const u8, @"align": u32 },
    };
};

/// Emits one function per `Recursive`. `names` is indexed by lambda id.
/// This will likely all be tied in differently in the future.
pub fn generate(
    recvs: []const Recursive,
    names: []const []const u8,
    globals: []const Global,
    gpa: std.mem.Allocator,
    stream: *std.Io.Writer,
) !void {
    for (recvs) |*recv| {
        const lambda = recv.getNode(recv.exit_list.items[0]).data.lambda;

        var sched = try Schedule.compute(gpa, recv);
        defer sched.deinit(gpa);

        var mir = try Mir.build(gpa, recv, &sched);
        defer mir.deinit(gpa);

        var regalloc = try RegAlloc.run(gpa, &mir, mir.num_vregs);
        defer regalloc.deinit(gpa);

        var emitter: Emitter = .{
            .w = stream,
            .mir = &mir,
            .ra = &regalloc,
            .names = names,
            .globals = globals,
            .func = names[lambda.id],
        };
        try emitter.run();
    }

    try emitGlobals(globals, stream);
}

fn emitGlobals(globals: []const Global, w: *std.Io.Writer) !void {
    for (globals) |g| {
        switch (g.data) {
            .declared => continue, // extern decl, defined elsewhere
            .bss => |b| {
                try w.print(".bss\n", .{});
                if (g.external) try w.print(".globl {s}\n", .{g.name});
                try w.print(".type {s}, @object\n", .{g.name});
                try w.print(".align {d}\n", .{std.math.log2_int(u32, @max(1, b.@"align"))});
                try w.print("{s}:\n", .{g.name});
                try w.print("    .zero {d}\n", .{b.size});
                try w.print(".size {s}, {d}\n", .{ g.name, b.size });
            },
            .bytes => |b| {
                try w.print(".data\n", .{});
                if (g.external) try w.print(".globl {s}\n", .{g.name});
                try w.print(".type {s}, @object\n", .{g.name});
                try w.print(".align {d}\n", .{std.math.log2_int(u32, @max(1, b.@"align"))});
                try w.print("{s}:\n", .{g.name});
                for (b.bytes) |byte| try w.print("    .byte {d}\n", .{byte});
                try w.print(".size {s}, {d}\n", .{ g.name, b.bytes.len });
            },
        }
    }
}

const Emitter = struct {
    w: *std.Io.Writer,
    mir: *const Mir,
    ra: *const RegAlloc.Result,
    names: []const []const u8,
    globals: []const Global,
    /// Whether this function makes any call.
    has_call: bool = false,
    /// Name of the function being emitted.
    func: []const u8,

    fn run(e: *Emitter) !void {
        const name = e.func;
        e.has_call = for (e.mir.insts.items) |inst| {
            if (inst == .call) break true;
        } else false;

        const frame = e.frameSize();

        try e.w.print(".text\n", .{});
        try e.w.print(".globl {s}\n", .{name});
        try e.w.print(".type {s}, @function\n", .{name});
        try e.w.print("{s}:\n", .{name});

        if (frame != 0) {
            try e.emitLine("addi sp, sp, -{d}", .{frame});
            for (e.ra.used_saved, 0..) |reg, j| {
                try e.emitLine("sd {t}, {d}(sp)", .{ reg, e.savedOffset(j) });
            }
            if (e.has_call) try e.emitLine("sd ra, {d}(sp)", .{e.raOffset()});
        }

        for (e.mir.insts.items) |inst| try e.emitInst(inst, frame);

        try e.w.print(".size {s}, .-{s}\n", .{ name, name });
    }

    fn emitInst(e: *Emitter, inst: Mir.Inst, frame: u64) !void {
        switch (inst) {
            .arg => |a| {
                const dst, const slot = e.defReg(a.dst);
                try e.emitLine("mv {t}, {t}", .{ dst, arg_regs[a.index] });
                try e.finishDef(dst, slot);
            },
            .li => |a| {
                const dst, const slot = e.defReg(a.dst);
                try e.emitLine("li {t}, {d}", .{ dst, a.imm });
                try e.finishDef(dst, slot);
            },
            .frame_addr => |a| {
                const dst, const slot = e.defReg(a.dst);
                try e.emitLine("addi {t}, sp, {d}", .{ dst, e.allocaBase() + a.offset });
                try e.finishDef(dst, slot);
            },
            .symbol_addr => |a| {
                const dst, const slot = e.defReg(a.dst);
                try e.emitLine("la {t}, {s}", .{ dst, e.globals[a.global].name });
                try e.finishDef(dst, slot);
            },
            .un => |a| {
                const src = try e.useReg(a.src, scratch_src0);
                const dst, const slot = e.defReg(a.dst);
                try e.emitLine("{s} {t}, {t}", .{ @tagName(a.op), dst, src });
                try e.finishDef(dst, slot);
            },
            .bin => |a| {
                const lhs = try e.useReg(a.lhs, scratch_src0);
                const rhs = try e.useReg(a.rhs, scratch_src1);
                const dst, const slot = e.defReg(a.dst);
                try e.emitLine("{s} {t}, {t}, {t}", .{ mnemonic(a.op, a.width), dst, lhs, rhs });
                try e.finishDef(dst, slot);
            },
            .load => |a| {
                const addr = try e.useReg(a.addr, scratch_src0);
                const dst, const slot = e.defReg(a.dst);
                const mn: []const u8 = switch (a.bits) {
                    8 => "lb",
                    16 => "lh",
                    32 => "lw",
                    else => "ld",
                };
                try e.emitLine("{s} {t}, 0({t})", .{ mn, dst, addr });
                try e.finishDef(dst, slot);
            },
            .store => |a| {
                const value = try e.useReg(a.value, scratch_src0);
                const addr = try e.useReg(a.addr, scratch_src1);
                const mn: []const u8 = switch (a.bits) {
                    8 => "sb",
                    16 => "sh",
                    32 => "sw",
                    else => "sd",
                };
                try e.emitLine("{s} {t}, 0({t})", .{ mn, value, addr });
            },
            .cast => |a| {
                const src = try e.useReg(a.src, scratch_src0);
                const dst, const slot = e.defReg(a.dst);
                try e.emitCast(a.kind, dst, src, a.src_bits, a.dst_bits);
                try e.finishDef(dst, slot);
            },
            .beqz => |a| {
                const src = try e.useReg(a.src, scratch_src0);
                try e.emitLine("beqz {t}, .L{s}_{d}", .{ src, e.func, a.target });
            },
            .j => |target| try e.emitLine("j .L{s}_{d}", .{ e.func, target }),
            .label => |id| try e.w.print(".L{s}_{d}:\n", .{ e.func, id }),
            .set_ret => |v| {
                const src = try e.useReg(v, scratch_src0);
                try e.emitLine("mv a0, {t}", .{src});
            },
            .set_arg => |a| {
                const src = try e.useReg(a.src, scratch_src0);
                try e.emitLine("mv {t}, {t}", .{ arg_regs[a.index], src });
            },
            .call => |c| {
                try e.emitLine("call {s}", .{e.names[c.callee]});
                const dst, const slot = e.defReg(c.dst);
                try e.emitLine("mv {t}, a0", .{dst});
                try e.finishDef(dst, slot);
            },
            .ret => {
                if (frame != 0) {
                    if (e.has_call) try e.emitLine("ld ra, {d}(sp)", .{e.raOffset()});
                    for (e.ra.used_saved, 0..) |reg, j| {
                        try e.emitLine("ld {t}, {d}(sp)", .{ reg, e.savedOffset(j) });
                    }
                    try e.emitLine("addi sp, sp, {d}", .{frame});
                }
                try e.emitLine("ret", .{});
            },
        }
    }

    /// Resolve a source operand to a register, reloading from its spill slot into
    /// `scratch` if necessary.
    fn useReg(e: *Emitter, v: Mir.VReg, scratch: Register) !Register {
        switch (e.ra.locs[@intFromEnum(v)]) {
            .reg => |r| return r,
            .spill => |slot| {
                try e.emitLine("ld {t}, {d}(sp)", .{ scratch, e.spillOffset(slot) });
                return scratch;
            },
        }
    }

    /// Pick the register to write a result into. Returns the spill slot too (if any),
    /// which `finishDef` then stores back.
    fn defReg(e: *Emitter, v: Mir.VReg) struct { Register, ?u32 } {
        switch (e.ra.locs[@intFromEnum(v)]) {
            .reg => |r| return .{ r, null },
            .spill => |slot| return .{ scratch_dst, slot },
        }
    }

    fn finishDef(e: *Emitter, dst: Register, slot: ?u32) !void {
        if (slot) |s| try e.emitLine("sd {t}, {d}(sp)", .{ dst, e.spillOffset(s) });
    }

    fn emitCast(e: *Emitter, kind: Mir.CastKind, dst: Register, src: Register, src_bits: u16, dst_bits: u16) !void {
        switch (kind) {
            .sext => try e.emitLine("mv {t}, {t}", .{ dst, src }),
            .trunc => switch (dst_bits) {
                1 => try e.emitLine("andi {t}, {t}, 1", .{ dst, src }),
                32 => try e.emitLine("sext.w {t}, {t}", .{ dst, src }),
                64 => try e.emitLine("mv {t}, {t}", .{ dst, src }),
                else => {
                    const sh = 64 - dst_bits;
                    try e.emitLine("slli {t}, {t}, {d}", .{ dst, src, sh });
                    try e.emitLine("srai {t}, {t}, {d}", .{ dst, dst, sh });
                },
            },
            .zext => switch (src_bits) {
                1 => try e.emitLine("andi {t}, {t}, 1", .{ dst, src }),
                8 => try e.emitLine("andi {t}, {t}, 255", .{ dst, src }),
                64 => try e.emitLine("mv {t}, {t}", .{ dst, src }),
                else => {
                    const sh = 64 - src_bits;
                    try e.emitLine("slli {t}, {t}, {d}", .{ dst, src, sh });
                    try e.emitLine("srli {t}, {t}, {d}", .{ dst, dst, sh });
                },
            },
        }
    }

    fn spillOffset(_: *Emitter, slot: u32) u64 {
        return @as(u64, slot) * slot_size;
    }

    fn savedOffset(e: *Emitter, j: usize) u64 {
        return (@as(u64, e.ra.num_spills) + j) * slot_size;
    }

    /// `ra` is saved just above the spill slots and callee-saved registers.
    fn raOffset(e: *Emitter) u64 {
        return (@as(u64, e.ra.num_spills) + e.ra.used_saved.len) * slot_size;
    }

    fn allocaBase(e: *Emitter) u64 {
        const ra_slots: u64 = if (e.has_call) 1 else 0;
        return (@as(u64, e.ra.num_spills) + e.ra.used_saved.len + ra_slots) * slot_size;
    }

    fn frameSize(e: *Emitter) u64 {
        return std.mem.alignForward(u64, e.allocaBase() + e.mir.alloca_bytes, 16);
    }

    fn emitLine(e: *Emitter, comptime fmt: []const u8, args: anytype) !void {
        try e.w.print("    " ++ fmt ++ "\n", args);
    }
};
