const Oir = @import("../Oir.zig");
const Node = Oir.Node;

pub fn isScalarBinOp(tag: Node.Tag) bool {
    return switch (tag) {
        .add,
        .sub,
        .mul,
        .@"and",
        .shl,
        .shr,
        .div_trunc,
        .div_exact,
        .cmp_eq,
        .cmp_gt,
        .cmp_lt,
        => true,
        else => false,
    };
}

pub fn binOp(tag: Node.Tag, lhs: i64, rhs: i64) ?i64 {
    return switch (tag) {
        .add => lhs +% rhs,
        .sub => lhs -% rhs,
        .mul => lhs *% rhs,
        .@"and" => lhs & rhs,
        .shl => if (rhs >= 0 and rhs < 64) lhs << @intCast(rhs) else null,
        .shr => if (rhs >= 0 and rhs < 64) lhs >> @intCast(rhs) else null,
        .div_trunc => if (rhs != 0) @divTrunc(lhs, rhs) else null,
        .div_exact => if (rhs != 0 and @rem(lhs, rhs) == 0) @divExact(lhs, rhs) else null,
        .cmp_eq => @intFromBool(lhs == rhs),
        .cmp_gt => @intFromBool(lhs > rhs),
        .cmp_lt => @intFromBool(lhs < rhs),
        else => null,
    };
}
