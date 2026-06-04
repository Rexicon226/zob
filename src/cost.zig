//! Defines simple cost information about OIR instructions

pub fn getCost(tag: Oir.Node.Tag) u32 {
    return switch (tag) {
        // ALU operations
        .@"and",
        .@"or",
        .shl,
        .shr,
        .sar,
        => 1,
        .add,
        .sub,
        .mul,
        => 2,
        .div_trunc,
        .udiv,
        .div_exact,
        => 8,

        .trunc,
        .sext,
        .zext,
        => 1,

        // Basic memory operations
        .load,
        .store,
        => 1,

        // A stack-slot address materializes as a single `addi sp`.
        .alloca,
        // A global address materializes as a single `la`.
        .global_addr,
        => 1,

        // Compare
        .cmp_eq,
        .cmp_gt,
        .cmp_lt,
        .cmp_ult,
        .cmp_ugt,
        => 1,

        // We want to bias towards folding away if there exists an equivalent
        // flat form.
        .gamma => 6,
        .theta => 10,

        // TODO: we'll need to price calls for real / inlining etc.
        .call => 5,

        .start,
        .ret,
        // constants have zero latency so that we bias towards
        // selecting the "free" canonical element.
        .constant,
        .project,
        // a loop-carried reference is just a register, free to read.
        .loopvar,
        .lambda,
        .param,
        => 0,
    };
}

const Oir = @import("Oir.zig");
