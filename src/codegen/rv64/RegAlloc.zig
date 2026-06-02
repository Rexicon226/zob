//! A very simple register allocator, just getting something to work.
//! We compute each vreg's live interval over the flattened MIR and do a linear
//! scan, preferring caller-saved temps, spilling to stack slots when the pool
//! is exhausted.

const std = @import("std");
const rv64 = @import("../rv64.zig");
const Mir = @import("Mir.zig");

const Register = rv64.Register;
const VReg = Mir.VReg;

pub const Location = union(enum) {
    reg: Register,
    spill: u32,
};

pub const Result = struct {
    locs: []Location,
    /// Callee-saved registers actually used, for prologue/epilogue save/restore.
    used_saved: []const Register,
    num_spills: u32,

    pub fn deinit(r: *Result, gpa: std.mem.Allocator) void {
        gpa.free(r.locs);
        gpa.free(r.used_saved);
    }
};

pub fn run(gpa: std.mem.Allocator, mir: *const Mir, num_vregs: usize) !Result {
    const start = try gpa.alloc(usize, num_vregs);
    defer gpa.free(start);

    const end = try gpa.alloc(usize, num_vregs);
    defer gpa.free(end);

    const seen = try gpa.alloc(bool, num_vregs);
    defer gpa.free(seen);
    @memset(seen, false);

    var ctx: LiveCtx = .{ .start = start, .end = end, .seen = seen, .idx = 0 };
    for (mir.insts.items, 0..) |inst, idx| {
        ctx.idx = idx;
        inst.forEachDef(&ctx, LiveCtx.mark);
        inst.forEachUse(&ctx, LiveCtx.mark);
    }

    // We need to account for loop back-edges. A value live anywhere in a loop
    // must stay live until the back-edge, otherwise the body could re-use its
    // register and clobber it before the next iteration. A back-edge is a `j`
    // to an earlier label.

    // A back-edge is a jump to an earlier label. We need to account for these
    // while allocating, because a value live anywhere within a loop must stay
    // live until the back-edge. Otherwise, the body could re-use its register
    // and clobber it before the next iteration. We extend the interval of
    // every value overlapping the loop out to the jump.
    {
        const BackEdge = struct { head: usize, edge: usize };
        var edges: std.ArrayList(BackEdge) = .empty;
        defer edges.deinit(gpa);
        for (mir.insts.items, 0..) |inst, idx| {
            const target = switch (inst) {
                .j => |t| t,
                else => continue,
            };
            const head = labelIndex(mir, target) orelse continue;
            if (head < idx) try edges.append(gpa, .{ .head = head, .edge = idx });
        }
        std.sort.pdq(BackEdge, edges.items, {}, struct {
            fn less(_: void, a: BackEdge, b: BackEdge) bool {
                return a.edge < b.edge;
            }
        }.less);
        for (edges.items) |e| {
            for (0..num_vregs) |v| {
                if (!seen[v]) continue;
                if (start[v] <= e.edge and end[v] >= e.head and end[v] < e.edge) {
                    end[v] = e.edge;
                }
            }
        }
    }

    // Order vregs by interval start.
    var order: std.ArrayList(usize) = .empty;
    defer order.deinit(gpa);
    for (0..num_vregs) |v| {
        if (seen[v]) try order.append(gpa, v);
    }
    std.sort.pdq(usize, order.items, start, lessByStart);

    const locs = try gpa.alloc(Location, num_vregs);

    // Free physical registers, popped from the end -> preferred registers last.
    var free: std.ArrayList(Register) = .empty;
    defer free.deinit(gpa);
    var p = rv64.alloc_pool.len;
    while (p > 0) {
        p -= 1;
        try free.append(gpa, rv64.alloc_pool[p]);
    }

    const Active = struct { end: usize, reg: Register };
    var active: std.ArrayList(Active) = .empty;
    defer active.deinit(gpa);

    var used_saved: std.ArrayList(Register) = .empty;
    errdefer used_saved.deinit(gpa);

    var num_spills: u32 = 0;
    for (order.items) |v| {
        // Expire intervals that ended before this one starts.
        var k: usize = 0;
        while (k < active.items.len) {
            if (active.items[k].end < start[v]) {
                try free.append(gpa, active.items[k].reg);
                _ = active.swapRemove(k);
            } else k += 1;
        }

        if (free.pop()) |reg| {
            locs[v] = .{ .reg = reg };
            try active.append(gpa, .{ .end = end[v], .reg = reg });
            if (rv64.isSaved(reg) and !contains(used_saved.items, reg)) {
                try used_saved.append(gpa, reg);
            }
        } else {
            locs[v] = .{ .spill = num_spills };
            num_spills += 1;
        }
    }

    return .{
        .locs = locs,
        .used_saved = try used_saved.toOwnedSlice(gpa),
        .num_spills = num_spills,
    };
}

const LiveCtx = struct {
    start: []usize,
    end: []usize,
    seen: []bool,
    idx: usize,

    fn mark(self: *LiveCtx, v: VReg) void {
        const i = @intFromEnum(v);
        if (!self.seen[i]) {
            self.start[i] = self.idx;
            self.seen[i] = true;
        }
        self.end[i] = self.idx;
    }
};

fn lessByStart(start: []const usize, a: usize, b: usize) bool {
    return start[a] < start[b];
}

fn labelIndex(mir: *const Mir, label: Mir.Label) ?usize {
    for (mir.insts.items, 0..) |inst, idx| {
        if (inst == .label and inst.label == label) return idx;
    }
    return null;
}

fn contains(regs: []const Register, reg: Register) bool {
    for (regs) |r| if (r == reg) return true;
    return false;
}
