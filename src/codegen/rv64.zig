//! Backend for RISC-V 64-bit code generation

const std = @import("std");
const Oir = @import("../Oir.zig");
const Recursive = Oir.extraction.Recursive;
const Node = Oir.Node;
const Class = Oir.Class;

const log = std.log.scoped(.rv64);

const Register = enum(u5) {
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

    const fp: Register = .s0;
};

const temp_regs = [_]Register{ .t0, .t1, .t2, .t3, .t4, .t5, .t6, .s2, .s3, .s4, .s5, .s6, .s7, .s8, .s9, .s10, .s11 };
const arg_regs = [_]Register{ .a0, .a1, .a2, .a3, .a4, .a5, .a6, .a7 };

const CodeGen = struct {
    allocator: std.mem.Allocator,

    recv: *const Recursive,
    output: std.ArrayList(u8),

    reg_map: std.AutoHashMapUnmanaged(Class.Index, Register),
    next_temp: usize,
    used_saved_regs: std.AutoHashMapUnmanaged(Register, void),

    fn init(allocator: std.mem.Allocator, recv: *const Recursive) CodeGen {
        return .{
            .recv = recv,
            .output = .empty,
            .allocator = allocator,
            .reg_map = .empty,
            .next_temp = 0,
            .used_saved_regs = .empty,
        };
    }

    fn deinit(cg: *CodeGen) void {
        cg.output.deinit(cg.allocator);
        cg.reg_map.deinit(cg.allocator);
        cg.used_saved_regs.deinit(cg.allocator);
    }

    fn emit(cg: *CodeGen, comptime fmt: []const u8, args: anytype) !void {
        try cg.output.print(cg.allocator, "    " ++ fmt ++ "\n", args);
    }

    fn emitLabel(cg: *CodeGen, comptime fmt: []const u8, args: anytype) !void {
        try cg.output.print(cg.allocator, fmt ++ "\n", args);
    }

    fn allocReg(cg: *CodeGen, idx: Class.Index) !Register {
        if (cg.reg_map.get(idx)) |reg| {
            return reg;
        }

        if (cg.next_temp >= temp_regs.len) {
            return error.OutOfRegisters;
        }

        const reg = temp_regs[cg.next_temp];
        cg.next_temp += 1;

        try cg.reg_map.put(cg.allocator, idx, reg);

        if (@intFromEnum(reg) >= @intFromEnum(Register.s2) and
            @intFromEnum(reg) <= @intFromEnum(Register.s11))
        {
            try cg.used_saved_regs.put(cg.allocator, reg, {});
        }

        return reg;
    }

    fn getReg(cg: *CodeGen, idx: Class.Index) !Register {
        return cg.reg_map.get(idx) orelse error.UnmappedNode;
    }

    fn generateNode(cg: *CodeGen, idx: Class.Index) !void {
        const node = cg.recv.getNode(idx);

        switch (node.tag) {
            .start => {},
            .project => {
                const project = node.data.project;
                if (project.type == .data) {
                    const arg_idx = project.index;
                    if (arg_idx >= 1 and arg_idx <= arg_regs.len) {
                        const arg_reg = arg_regs[arg_idx - 1];
                        try cg.reg_map.put(cg.allocator, idx, arg_reg);
                    }
                }
            },

            .constant => {
                const value = node.data.constant;
                const dest = try cg.allocReg(idx);
                try cg.emit("li {t}, {d}", .{ dest, value });
            },

            .add => {
                const lhs_idx = node.data.bin_op[0];
                const rhs_idx = node.data.bin_op[1];

                const lhs_reg = try cg.getReg(lhs_idx);
                const rhs_reg = try cg.getReg(rhs_idx);
                const dest = try cg.allocReg(idx);

                try cg.emit("add {t}, {t}, {t}", .{ dest, lhs_reg, rhs_reg });
            },

            .cmp_eq => {
                const lhs_idx = node.data.bin_op[0];
                const rhs_idx = node.data.bin_op[1];

                const lhs_reg = try cg.getReg(lhs_idx);
                const rhs_reg = try cg.getReg(rhs_idx);
                const dest = try cg.allocReg(idx);

                try cg.emit("xor {t}, {t}, {t}", .{ dest, lhs_reg, rhs_reg });
                try cg.emit("seqz {t}, {t}", .{ dest, dest });
            },

            .ret => {
                const val_idx = node.data.bin_op[1];
                const val_reg = try cg.getReg(val_idx);

                if (val_reg != .a0) {
                    try cg.emit("mv a0, {t}", .{val_reg});
                }
            },

            .branch, .region => {},
            .dead => unreachable,

            else => |t| std.debug.panic("TODO: rv64 codegen {t}", .{t}),
        }
    }

    fn generateFunction(cg: *CodeGen, name: []const u8) !void {
        try cg.emitLabel(".globl {s}", .{name});
        try cg.emitLabel(".type {s}, @function", .{name});
        try cg.emitLabel("{s}:", .{name});

        for (cg.recv.nodes.items, 0..) |_, i| {
            const idx: Class.Index = @enumFromInt(i);
            try cg.generateNode(idx);
        }

        try cg.emit("ret", .{});
        try cg.emitLabel(".size {s}, .-{s}", .{ name, name });
    }
};

pub fn generate(recv: *const Recursive, io: std.Io) !void {
    const allocator = std.heap.page_allocator;

    var cg = CodeGen.init(allocator, recv);
    defer cg.deinit();

    try cg.emitLabel(".text", .{});
    try cg.generateFunction("foo");

    _ = io;
    std.debug.print("ASM:\n", .{});
    std.debug.print("{s}\n", .{cg.output.items});
}
