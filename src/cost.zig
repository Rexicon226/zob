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

        .@"and",
        .shl,
        .shr,
        => 1,

        // Basic memory operations
        .load,
        .store,
        => 1,

        // Compare
        .cmp_eq,
        .cmp_gt,
        .branch,
        => 1,

        .start,
        .ret,
        .dead,
        .region,
        // constants have zero latency so that we bias towards
        // selecting the "free" absorbing element.
        .constant,
        .project,
        => 0,
    };
}

const Oir = @import("Oir.zig");
