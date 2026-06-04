const std = @import("std");
const Oir = @import("../Oir.zig");
const eval = @import("../passes/eval.zig");

const Node = Oir.Node;
const Class = Oir.Class;

pub const KnownBits = struct {
    /// Bits proven 0 and bits proven 1.
    /// When not `bottom`, `zeroes & ones == 0`.
    zeros: u64,
    ones: u64,

    /// Every bit unknown.
    pub const top: KnownBits = .{ .zeros = 0, .ones = 0 };

    /// Every value is in `{0, 1}`.
    pub const boolean: KnownBits = .{ .zeros = ~@as(u64, 1), .ones = 0 };

    pub fn fromConst(v: i64) KnownBits {
        const u: u64 = @bitCast(v);
        return .{ .zeros = ~u, .ones = u };
    }

    pub fn isBottom(k: KnownBits) bool {
        return (k.zeros & k.ones) != 0;
    }

    pub fn isFullyKnown(k: KnownBits) bool {
        return !k.isBottom() and (k.zeros | k.ones) == ~@as(u64, 0);
    }

    pub fn value(k: KnownBits) i64 {
        std.debug.assert(k.isFullyKnown());
        return @bitCast(k.ones);
    }

    pub fn eql(a: KnownBits, b: KnownBits) bool {
        return a.zeros == b.zeros and a.ones == b.ones;
    }

    /// A union of the two facts.
    pub fn meet(a: KnownBits, b: KnownBits) KnownBits {
        return .{ .zeros = a.zeros | b.zeros, .ones = a.ones | b.ones };
    }
};

pub const Facts = std.AutoHashMapUnmanaged(Class.Index, KnownBits);

fn factOf(oir: *const Oir, facts: *const Facts, idx: Class.Index) KnownBits {
    return facts.get(oir.union_find.find(idx)) orelse .top;
}

/// Known bits of `zext` from `src_bits`. The lower `src_bits` come from
/// the operand, everything above is zero-filled so bits `src_bits..63` are
/// all known zero.
fn zextBits(a: KnownBits, src_bits: u16) KnownBits {
    if (src_bits == 0 or src_bits >= 64) return a;
    const mask = eval.lowMask(src_bits);
    return .{ .zeros = (a.zeros & mask) | ~mask, .ones = a.ones & mask };
}

/// Known bits of `trunc` to `dst_bits`. Keep the low `dst_bits` bits, then
/// reproduce the canonical sign extension from bit `dst_bits-1`.
fn truncBits(a: KnownBits, dst_bits: u16) KnownBits {
    if (dst_bits == 0 or dst_bits >= 64) return a;
    if (dst_bits == 1) return .{ .zeros = (a.zeros & 1) | ~@as(u64, 1), .ones = a.ones & 1 };

    const mask = eval.lowMask(dst_bits);
    const high = ~mask;
    const sign: u6 = @intCast(dst_bits - 1);
    var zeros = a.zeros & mask;
    var ones = a.ones & mask;
    if ((a.zeros >> sign) & 1 != 0) {
        zeros |= high;
    } else if ((a.ones >> sign) & 1 != 0) {
        ones |= high;
    }
    return .{ .zeros = zeros, .ones = ones };
}

/// Computes the known bits of a node given its operands. Worst case, returns
/// `top` if it doesn't know anything.
fn transfer(oir: *const Oir, facts: *const Facts, node: Node) KnownBits {
    return switch (node.tag) {
        .constant => KnownBits.fromConst(node.data.constant.val),
        .@"and" => blk: {
            const a = factOf(oir, facts, node.data.bin_op[0]);
            const b = factOf(oir, facts, node.data.bin_op[1]);
            break :blk .{ .zeros = a.zeros | b.zeros, .ones = a.ones & b.ones };
        },
        .@"or" => blk: {
            const a = factOf(oir, facts, node.data.bin_op[0]);
            const b = factOf(oir, facts, node.data.bin_op[1]);
            break :blk .{ .zeros = a.zeros & b.zeros, .ones = a.ones | b.ones };
        },
        .cmp_eq, .cmp_lt, .cmp_gt, .cmp_ult, .cmp_ugt => .boolean,
        // `sext` is a no-op on the canonical (already sign-extended) form.
        .sext => factOf(oir, facts, node.data.cast.operand),
        .zext => zextBits(factOf(oir, facts, node.data.cast.operand), oir.typeOf(node.data.cast.operand)),
        .trunc => truncBits(factOf(oir, facts, node.data.cast.operand), node.data.cast.bits),
        else => .top,
    };
}

pub fn analyze(oir: *const Oir, gpa: std.mem.Allocator) !Facts {
    var facts: Facts = .{};
    errdefer facts.deinit(gpa);

    while (true) {
        var changed = false;
        var iter = oir.classes.iterator();
        while (iter.next()) |entry| {
            const leader = entry.key_ptr.*;
            var f: KnownBits = .top;
            for (entry.value_ptr.bag.items) |node_idx| {
                f = f.meet(transfer(oir, &facts, oir.getNode(node_idx)));
            }
            const old = facts.get(leader) orelse KnownBits.top;
            if (!f.eql(old)) {
                try facts.put(gpa, leader, f);
                changed = true;
            }
        }
        if (!changed) break;
    }
    return facts;
}
