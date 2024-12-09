//! Defines simple cost information about MIR instructions

pub fn getCost(tag: Oir.Node.Tag) u32 {
    return switch (tag) {
        // ALU operations
        .add,
        .sub,
        .mul,
        .div_trunc,
        .div_exact,
        => 2,

        // On most CPUs, shl will have an identical latency and throughput as add.
        // We still want to bias it, since it's clearer and has access to more ports.
        .shl,
        .shr,
        => 1,

        // Basic memory operations
        .load,
        .store,
        => 1,

        // Branching
        .cmp_gt,
        .gamma,
        => 1,

        // constants have zero latency so that we bias towards
        // selecting the "free" absorbing element.
        .arg,
        .ret,
        .constant,
        => 0,
    };
}

const Oir = @import("Oir.zig");
