//! Some alias analysis tools used for performing certain passes over the OIR.
//!
//! - addresses decompose to `alloc#id + const`
//! - distinct allocas never alias
//! - equal base+range at equal width must-alias
//! - disjoint ranges no-alias

const std = @import("std");
const Oir = @import("../Oir.zig");

const Class = Oir.Class;

pub const AliasRel = enum { must_exact, no_alias, unknown };
pub const Addr = struct { base: ?u32, off: i64 };

pub fn aliasRel(oir: *const Oir, a: Class.Index, bits_a: u16, b: Class.Index, bits_b: u16) AliasRel {
    if (oir.union_find.find(a) == oir.union_find.find(b))
        return if (bits_a == bits_b) .must_exact else .unknown;

    const da = decompose(oir, a);
    const db = decompose(oir, b);
    if (da.base == null or db.base == null) return .unknown;
    if (da.base.? != db.base.?) return .no_alias;

    const a0 = da.off;
    const a1 = da.off + @as(i64, bits_a / 8);
    const b0 = db.off;
    const b1 = db.off + @as(i64, bits_b / 8);
    if (a0 == b0 and bits_a == bits_b) return .must_exact;
    if (a1 <= b0 or b1 <= a0) return .no_alias;
    return .unknown;
}

pub fn decompose(oir: *const Oir, class: Class.Index) Addr {
    var cur = class;
    var off: i64 = 0;
    for (0..64) |_| { // TODO: find a better limit? 64 depth maybe enough?
        if (allocaIdOf(oir, cur)) |id| return .{ .base = id, .off = off };
        if (addConstOf(oir, cur)) |split| {
            off += split.@"1";
            cur = split.@"0";
            continue;
        }
        break;
    }
    return .{ .base = null, .off = off };
}

/// The set of private, never-loaded `alloca` ids.
pub fn deadSlots(oir: *const Oir, gpa: std.mem.Allocator) !std.AutoHashMapUnmanaged(u32, void) {
    var escaping: std.AutoHashMapUnmanaged(u32, void) = .{};
    defer escaping.deinit(gpa);

    var surviving: std.AutoHashMapUnmanaged(u32, void) = .{};
    defer surviving.deinit(gpa);

    var allocas: std.AutoHashMapUnmanaged(u32, void) = .{};
    defer allocas.deinit(gpa);

    for (oir.getNodes(), 0..) |node, i| {
        if (node.tag == .alloca) try allocas.put(gpa, node.data.alloca.id, {});
        const node_class = oir.findClass(@enumFromInt(i));
        // A load in a load-only class is one the extractor will actually emit,
        // as it has no non-load alternatives to prefer, so it observes its slot.
        if (node.tag == .load and !classHasNonLoad(oir, node_class)) {
            if (decompose(oir, node.data.load.ops[1]).base) |id| try surviving.put(gpa, id, {});
        }
        for (node.operands(oir), 0..) |op, p| {
            const id = decompose(oir, op).base orelse continue;
            if (addressUse(oir, node, p, node_class)) continue;
            try escaping.put(gpa, id, {});
        }
    }

    var dead: std.AutoHashMapUnmanaged(u32, void) = .{};
    errdefer dead.deinit(gpa);
    var it = allocas.keyIterator();
    while (it.next()) |id| {
        if (!escaping.contains(id.*) and !surviving.contains(id.*)) {
            try dead.put(gpa, id.*, {});
        }
    }
    return dead;
}

/// Whether operand `p` of `node` (of `class`) is legitimate non-escaping
/// use of a slot-derived pointer.
fn addressUse(oir: *const Oir, node: Oir.Node, p: usize, class: Class.Index) bool {
    return switch (node.tag) {
        .load, .store => p == 1,
        .add => decompose(oir, class).base != null,
        else => false,
    };
}

fn classHasNonLoad(oir: *const Oir, class: Class.Index) bool {
    const leader = oir.union_find.find(class);
    const c = oir.classes.get(leader) orelse return false;
    for (c.bag.items) |ni| {
        if (oir.getNode(ni).tag != .load) return true;
    }
    return false;
}

fn allocaIdOf(oir: *const Oir, class: Class.Index) ?u32 {
    const leader = oir.union_find.find(class);
    const c = oir.classes.get(leader) orelse return null;
    for (c.bag.items) |ni| {
        const node = oir.getNode(ni);
        if (node.tag == .alloca) return node.data.alloca.id;
    }
    return null;
}

fn addConstOf(oir: *const Oir, class: Class.Index) ?struct { Class.Index, i64 } {
    const leader = oir.union_find.find(class);
    const c = oir.classes.get(leader) orelse return null;
    for (c.bag.items) |ni| {
        const node = oir.getNode(ni);
        if (node.tag != .add) continue;
        const ops = node.data.bin_op;
        if (constInClass(oir, ops[1])) |k| return .{ ops[0], k };
        if (constInClass(oir, ops[0])) |k| return .{ ops[1], k };
    }
    return null;
}

fn constInClass(oir: *const Oir, class: Class.Index) ?i64 {
    const leader = oir.union_find.find(class);
    const c = oir.classes.get(leader) orelse return null;
    for (c.bag.items) |ni| {
        const node = oir.getNode(ni);
        if (node.tag == .constant) return node.data.constant.val;
    }
    return null;
}
