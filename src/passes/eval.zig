//! TODO: the whole constant eval thing will be reworked to represent
//! everything as a big-integer instead of the nonsense i'm doing now.

const std = @import("std");
const Oir = @import("../Oir.zig");
const Node = Oir.Node;

pub fn isScalarBinOp(tag: Node.Tag) bool {
    return switch (tag) {
        .add,
        .sub,
        .mul,
        .@"and",
        .@"or",
        .shl,
        .shr,
        .sar,
        .div_trunc,
        .udiv,
        .div_exact,
        .cmp_eq,
        .cmp_lt,
        .cmp_gt,
        .cmp_ult,
        .cmp_ugt,
        => true,
        else => false,
    };
}

pub fn lowMask(bits: u16) u64 {
    return if (bits >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(bits)) - 1;
}

pub fn canon(v: i64, bits: u16) i64 {
    if (bits == 1) return v & 1;
    if (bits == 0 or bits >= 64) return v;
    const s: u6 = @intCast(64 - bits);
    const u: u64 = @bitCast(v);
    return @as(i64, @bitCast(u << s)) >> s;
}

pub fn binOp(tag: Node.Tag, lhs: i64, rhs: i64, bits: u16) ?i64 {
    const ul: u64 = @bitCast(lhs);
    const ur: u64 = @bitCast(rhs);
    const mask = lowMask(bits);
    return switch (tag) {
        .add => canon(lhs +% rhs, bits),
        .sub => canon(lhs -% rhs, bits),
        .mul => canon(lhs *% rhs, bits),
        .@"and" => canon(lhs & rhs, bits),
        .@"or" => canon(lhs | rhs, bits),
        .shl => if (rhs >= 0 and rhs < bits)
            canon(@bitCast(ul << @intCast(rhs)), bits)
        else
            null,
        // Logical right shift: operate on the zero-extended value.
        .shr => if (rhs >= 0 and rhs < bits)
            canon(@bitCast((ul & mask) >> @intCast(rhs)), bits)
        else
            null,
        // Arithmetic right shift: the canonical (sign-extended) value shifts correctly.
        .sar => if (rhs >= 0 and rhs < bits) canon(lhs >> @intCast(rhs), bits) else null,
        .div_trunc => if (divDefined(lhs, rhs)) canon(@divTrunc(lhs, rhs), bits) else null,
        .udiv => if (rhs & @as(i64, @bitCast(mask)) != 0)
            canon(@bitCast((ul & mask) / (ur & mask)), bits)
        else
            null,
        .div_exact => if (divDefined(lhs, rhs) and @rem(lhs, rhs) == 0)
            canon(@divExact(lhs, rhs), bits)
        else
            null,
        .cmp_eq => @intFromBool(lhs == rhs),
        .cmp_lt => @intFromBool(lhs < rhs),
        .cmp_gt => @intFromBool(lhs > rhs),
        .cmp_ult => @intFromBool((ul & mask) < (ur & mask)),
        .cmp_ugt => @intFromBool((ul & mask) > (ur & mask)),
        else => null,
    };
}

pub fn castOp(tag: Node.Tag, val: i64, src_bits: u16, dst_bits: u16) ?i64 {
    const uv: u64 = @bitCast(val);
    return switch (tag) {
        .trunc => canon(val, dst_bits),
        .sext => canon(val, src_bits), // already canonical at src; widening preserves it
        .zext => canon(@bitCast(uv & lowMask(src_bits)), dst_bits),
        else => null,
    };
}

fn divDefined(lhs: i64, rhs: i64) bool {
    if (rhs == 0) return false;
    if (lhs == std.math.minInt(i64) and rhs == -1) return false;
    return true;
}
