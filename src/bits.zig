const std = @import("std");

pub const Registers = struct {
    pub const all_preserved = Integer.callee_preserved_regs ++ Float.callee_preserved_regs;

    pub const Integer = struct {
        pub const callee_preserved_regs = [_]Register{
            // .s0 is omitted to be used as the frame pointer register
            .s1, .s2, .s3, .s4, .s5, .s6, .s7, .s8, .s9, .s10, .s11,
        };

        pub const function_arg_regs = [_]Register{
            .a0, .a1, .a2, .a3, .a4, .a5, .a6, .a7,
        };

        pub const function_ret_regs = [_]Register{
            .a0, .a1,
        };

        pub const temporary_regs = [_]Register{
            .t0, .t1, .t2, .t3, .t4, .t5, .t6,
        };

        pub const all_regs = callee_preserved_regs ++ function_arg_regs ++ temporary_regs;
    };

    pub const Float = struct {
        pub const callee_preserved_regs = [_]Register{
            .fs0, .fs1, .fs2, .fs3, .fs4, .fs5, .fs6, .fs7, .fs8, .fs9, .fs10, .fs11,
        };

        pub const function_arg_regs = [_]Register{
            .fa0, .fa1, .fa2, .fa3, .fa4, .fa5, .fa6, .fa7,
        };

        pub const function_ret_regs = [_]Register{
            .fa0, .fa1,
        };

        pub const temporary_regs = [_]Register{
            .ft0, .ft1, .ft2, .ft3, .ft4, .ft5, .ft6, .ft7, .ft8, .ft9, .ft10, .ft11,
        };

        pub const all_regs = callee_preserved_regs ++ function_arg_regs ++ temporary_regs;
    };

    pub const Vector = struct {
        // zig fmt: off
        pub const all_regs = [_]Register{
            .v0,  .v1,  .v2,  .v3,  .v4,  .v5,  .v6,  .v7,
            .v8,  .v9,  .v10, .v11, .v12, .v13, .v14, .v15,
            .v16, .v17, .v18, .v19, .v20, .v21, .v22, .v23,
            .v24, .v25, .v26, .v27, .v28, .v29, .v30, .v31,
        };
        // zig fmt: on
    };
};

pub const Memory = struct {
    pub const Size = enum {
        /// 1 byte
        byte,
        /// 2 bytes
        half,
        /// 4 bytes
        word,
        /// 8 bytes
        double,
    };
};

pub const Register = enum(u8) {
    // zig fmt: off

    // base extension registers

    zero, // zero
    ra, // return address. caller saved
    sp, // stack pointer. callee saved.
    gp, // global pointer
    tp, // thread pointer
    t0, t1, t2, // temporaries. caller saved.
    s0, // s0/fp, callee saved.
    s1, // callee saved.
    a0, a1, // fn args/return values. caller saved.
    a2, a3, a4, a5, a6, a7, // fn args. caller saved.
    s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, // saved registers. callee saved.
    t3, t4, t5, t6, // caller saved

    x0,  x1,  x2,  x3,  x4,  x5,  x6,  x7,
    x8,  x9,  x10, x11, x12, x13, x14, x15,
    x16, x17, x18, x19, x20, x21, x22, x23,
    x24, x25, x26, x27, x28, x29, x30, x31,


    // F extension registers

    ft0, ft1, ft2, ft3, ft4, ft5, ft6, ft7, // float temporaries. caller saved.
    fs0, fs1, // float saved. callee saved.
    fa0, fa1, // float arg/ret. caller saved.
    fa2, fa3, fa4, fa5, fa6, fa7, // float arg. called saved.
    fs2, fs3, fs4, fs5, fs6, fs7, fs8, fs9, fs10, fs11,  // float saved. callee saved.
    ft8, ft9, ft10, ft11, // foat temporaries. calller saved.

    // this register is accessed only through API instructions instead of directly
    // fcsr, 

    f0, f1,  f2,  f3,  f4,  f5,  f6,  f7,  
    f8, f9,  f10, f11, f12, f13, f14, f15, 
    f16, f17, f18, f19, f20, f21, f22, f23, 
    f24, f25, f26, f27, f28, f29, f30, f31, 


    // V extension registers
    v0,  v1,  v2,  v3,  v4,  v5,  v6,  v7,
    v8,  v9,  v10, v11, v12, v13, v14, v15,
    v16, v17, v18, v19, v20, v21, v22, v23,
    v24, v25, v26, v27, v28, v29, v30, v31,

    // zig fmt: on

    pub const Class = enum {
        int,
        float,
        vector,
    };

    /// in RISC-V registers are stored as 5 bit IDs and a register can have
    /// two names. Example being `zero` and `x0` are the same register and have the
    /// same ID, but are two different entries in the enum. We store floating point
    /// registers in the same enum. RISC-V uses the same IDs for `f0` and `x0` by
    /// infering which register is being talked about given the instruction it's in.
    ///
    /// The goal of this function is to return the same ID for `zero` and `x0` but two
    /// seperate IDs for `x0` and `f0`. We will assume that each register set has 32 registers
    /// and is repeated twice, once for the named version, once for the number version.
    pub fn id(reg: Register) std.math.IntFittingRange(0, @typeInfo(Register).@"enum".fields.len) {
        const base = switch (@intFromEnum(reg)) {
            // zig fmt: off
            @intFromEnum(Register.zero) ... @intFromEnum(Register.x31) => @intFromEnum(Register.zero),
            @intFromEnum(Register.ft0)  ... @intFromEnum(Register.f31) => @intFromEnum(Register.ft0),
            @intFromEnum(Register.v0)   ... @intFromEnum(Register.v31) => @intFromEnum(Register.v0),
            else => unreachable,
            // zig fmt: on
        };

        return @intCast(base + reg.encodeId());
    }

    pub fn encodeId(reg: Register) u5 {
        return @truncate(@intFromEnum(reg));
    }

    pub fn class(reg: Register) Class {
        return switch (@intFromEnum(reg)) {
            // zig fmt: off
            @intFromEnum(Register.zero) ... @intFromEnum(Register.x31) => .int,
            @intFromEnum(Register.ft0)  ... @intFromEnum(Register.f31) => .float,
            @intFromEnum(Register.v0)   ... @intFromEnum(Register.v31) => .vector,
            else => unreachable,
            // zig fmt: on
        };
    }
};

pub const VirtualRegister = struct {
    class: Register.Class,
    /// TODO: remove the `index` field, it should be represented as the index in the
    /// vreg allocator. this leaves the possiblity of clobbering with two vregs having
    /// the same index but different classes.
    index: Index,

    pub const Index = enum(u32) {
        _,
    };
};

pub const FrameAlloc = struct {
    // TODO: metadata about frame allocations
    // we currently just kind of assume everything is 8-bytes.
};

pub const FrameIndex = enum(u32) {
    pub const named_count = @typeInfo(FrameIndex).@"enum".fields.len;

    pub fn isNamed(fi: FrameIndex) bool {
        return @intFromEnum(fi) < named_count;
    }

    pub fn format(
        fi: FrameIndex,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try writer.writeAll("FrameIndex");
        if (fi.isNamed()) {
            try writer.writeByte('.');
            try writer.writeAll(@tagName(fi));
        } else {
            try writer.writeByte('(');
            try std.fmt.formatType(@intFromEnum(fi), fmt, options, writer, 0);
            try writer.writeByte(')');
        }
    }
};
