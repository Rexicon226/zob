//! Defines simple cost information about MIR instructions

pub fn hasLatency(tag: Oir.Node.Tag) bool {
    return switch (tag) {
        .arg,
        .ret,
        => false,
        else => true,
    };
}

pub fn getLatency(tag: Oir.Node.Tag) u32 {
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

        // constants have zero latency so that we bias towards
        // selecting the "free" absorbing element.
        .constant,
        => 0,

        .arg,
        .ret,
        => unreachable, // doesn't have a latency
    };
}

const Oir = @import("Oir.zig");
