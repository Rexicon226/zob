//! Trip counts are derived *analytically* (a closed-form formula), never by
//! interpreting the loop, so folding cost is independent of the iteration count.
//!
//! Loop simplifications.
//!
//! - Constant evaluation: interpret a memory-effect-free loop with a small constant
//!   trip and constant-foldable predicate/steps away entirely.
//!
//! - Affine closed form, constant trip: a slot stepping by `+/-D` over a constant
//!   trip count `T` folds to `init +/- T*D` (`D` loop-invariant), and a slot summing
//!   an affine IV folds to its quadratic closed form.
//!
//! - Affine closed form, symbolic trip: a unit-step loop bounded by `b` folds each
//!   slot to `gamma(entry, init +/- T*D, init)`, with symbolic `T = |b - init|`.
//! - Invariant-slot elimination: a slot that never changes equals its init.
//!
//! - Dead-slot elimination: drop carried slots nothing observes.

const std = @import("std");
const Oir = @import("../Oir.zig");
const eval = @import("eval.zig");

const Class = Oir.Class;
const Node = Oir.Node;

pub fn run(oir: *Oir) !bool {
    if (try evaluateConstantLoops(oir)) return true;
    if (try affineClosedForms(oir)) return true;
    if (try symbolicClosedForms(oir)) return true;
    if (try eliminateInvariantSlots(oir)) return true;
    if (try eliminateDeadSlots(oir)) return true;
    return false;
}

const Loop = struct {
    class: Class.Index,
    id: u32,
    args: []Class.Index,
    inits: []Class.Index,
    nexts: []Class.Index,
    pred: Class.Index,

    fn count(loop: Loop) usize {
        return loop.args.len;
    }

    /// The memory slot never changes, so the loop has no observable stores.
    fn memoryInvariant(loop: Loop) bool {
        return loop.args[0] == loop.nexts[0];
    }

    /// The slot whose loopvar is `class`, if any scalar slot (skipping memory).
    fn slotOf(loop: Loop, class: Class.Index) ?usize {
        for (loop.args[1..], 1..) |arg, s| {
            if (arg == class) return s;
        }
        return null;
    }

    fn deinit(loop: *Loop, gpa: std.mem.Allocator) void {
        gpa.free(loop.args);
        gpa.free(loop.inits);
        gpa.free(loop.nexts);
    }
};

fn snapshot(oir: *Oir, idx: usize) !?Loop {
    const node = oir.getNodes()[idx];
    if (node.tag != .theta) return null;
    const loop = node.data.loop;
    if (loop.count <= 1) return null; // only the memory slot; nothing to do

    const gpa = oir.allocator;
    const args = try gpa.alloc(Class.Index, loop.count);
    errdefer gpa.free(args);
    const inits = try gpa.alloc(Class.Index, loop.count);
    errdefer gpa.free(inits);
    const nexts = try gpa.alloc(Class.Index, loop.count);
    errdefer gpa.free(nexts);

    for (loop.args(oir), args) |c, *out| out.* = oir.union_find.find(c);
    for (loop.inits(oir), inits) |c, *out| out.* = c;
    for (loop.nexts(oir), nexts) |c, *out| out.* = oir.union_find.find(c);

    return .{
        .class = oir.findClass(@enumFromInt(idx)),
        .id = loop.id,
        .args = args,
        .inits = inits,
        .nexts = nexts,
        .pred = oir.union_find.find(loop.pred(oir)),
    };
}

/// Whether a scalar output projection of the loop already holds a rewritten
/// form. The closed-form/constant passes use this to stay idempotent.
fn alreadyRewritten(oir: *Oir, theta_class: Class.Index) bool {
    const class = oir.classes.get(theta_class) orelse return false;
    for (class.parents.items) |pair| {
        const parent = oir.getNode(pair[0]);
        if (parent.tag != .project or parent.data.project.index == 0) continue; // skip memory
        if (oir.union_find.find(parent.data.project.tuple) != theta_class) continue;
        const proj_class = oir.classes.get(oir.findClass(pair[0])) orelse continue;
        for (proj_class.bag.items) |node_idx| {
            if (oir.getNode(node_idx).tag != .project) return true;
        }
    }
    return false;
}

/// How a loop slot evolves each iteration, relative to its own value `arg`.
const Step = union(enum) {
    /// `next == arg`: the slot never changes.
    invariant,
    /// `next == arg + delta`, `delta` loop-invariant.
    add: Class.Index,
    /// `next == arg - delta`, `delta` loop-invariant.
    sub: Class.Index,
    /// Not a recognized affine recurrence.
    none,
};

/// Classify how each slot evolves. Caller owns the returned slice.
fn stepsOf(oir: *Oir, loop: Loop) ![]Step {
    const steps = try oir.allocator.alloc(Step, loop.count());
    for (steps, loop.nexts, loop.args) |*s, next, arg| s.* = stepOf(oir, next, arg);
    return steps;
}

/// Recognizes `next` as `arg` (invariant), `arg + D`, or `arg - D`.
fn stepOf(oir: *Oir, next: Class.Index, arg: Class.Index) Step {
    const uf = &oir.union_find;
    const arg_c = uf.find(arg);
    if (uf.find(next) == arg_c) return .invariant;
    const cls = oir.classes.get(uf.find(next)) orelse return .none;
    for (cls.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        switch (node.tag) {
            .add => {
                const ops = node.data.bin_op;
                if (uf.find(ops[0]) == arg_c) return .{ .add = uf.find(ops[1]) };
                if (uf.find(ops[1]) == arg_c) return .{ .add = uf.find(ops[0]) };
            },
            .sub => {
                const ops = node.data.bin_op;
                if (uf.find(ops[0]) == arg_c) return .{ .sub = uf.find(ops[1]) };
            },
            else => {},
        }
    }
    return .none;
}

const Partition = struct {
    inv_init: std.AutoHashMapUnmanaged(Class.Index, Class.Index) = .{},
    variant: std.AutoHashMapUnmanaged(Class.Index, void) = .{},

    fn deinit(p: *Partition, gpa: std.mem.Allocator) void {
        p.inv_init.deinit(gpa);
        p.variant.deinit(gpa);
    }
};

fn partition(oir: *Oir, loop: Loop, steps: []const Step) !Partition {
    var p: Partition = .{};
    for (steps, loop.args, loop.inits) |step, arg, init| {
        if (step == .invariant) {
            try p.inv_init.put(oir.allocator, arg, init);
        } else {
            try p.variant.put(oir.allocator, arg, {});
        }
    }
    return p;
}

const Analysis = struct {
    loop: Loop,
    steps: []Step,
    part: Partition,

    fn deinit(a: *Analysis, gpa: std.mem.Allocator) void {
        a.part.deinit(gpa);
        gpa.free(a.steps);
        a.loop.deinit(gpa);
    }
};

fn analyze(oir: *Oir, idx: usize) !?Analysis {
    const gpa = oir.allocator;
    var loop = (try snapshot(oir, idx)) orelse return null;
    if (!loop.memoryInvariant() or alreadyRewritten(oir, loop.class)) {
        loop.deinit(gpa);
        return null;
    }
    errdefer loop.deinit(gpa);
    const steps = try stepsOf(oir, loop);
    errdefer gpa.free(steps);
    return .{ .loop = loop, .steps = steps, .part = try partition(oir, loop, steps) };
}

/// A slot's value sequence `init, init+step, init+2*step, ...` with constant terms.
const Iv = struct { init: i64, step: i64 };

fn constIv(oir: *Oir, loop: Loop, steps: []const Step, slot: usize) ?Iv {
    const init = constOf(oir, loop.inits[slot]) orelse return null;
    const step: i64 = switch (steps[slot]) {
        .invariant => 0,
        .add => |c| constOf(oir, c) orelse return null,
        .sub => |c| -(constOf(oir, c) orelse return null),
        .none => return null,
    };
    return .{ .init = init, .step = step };
}

const Cmp = enum { lt, gt };

/// Iterations of `x` (the affine sequence `i0, id+d, ...`) for which `x < B` / `x > B`
/// holds before turning false, or null if it never turns false.
fn tripFor(start: i64, d: i64, kind: Cmp, bound: i64) ?i64 {
    switch (kind) {
        .lt => {
            if (start >= bound) return 0; // predicate already false
            if (d <= 0) return null; // moves away from the bound -> never ends
            return @divTrunc(bound - start + d - 1, d); // ceil((bound - start) / d)
        },
        .gt => {
            if (start <= bound) return 0;
            if (d >= 0) return null;
            return @divTrunc(start - bound + (-d) - 1, -d); // ceil((start - bound) / -d)
        },
    }
}

/// The constant trip count of a loop whose predicate is a single comparison between
/// an affine IV and a constant bound, or null otherwise.
fn analyticTrip(oir: *Oir, loop: Loop, steps: []const Step) ?i64 {
    const cls = oir.classes.get(loop.pred) orelse return null;
    for (cls.bag.items) |node_idx| {
        const n = oir.getNode(node_idx);
        const kind: Cmp = switch (n.tag) {
            .cmp_lt => .lt,
            .cmp_gt => .gt,
            else => continue,
        };
        const lhs = oir.union_find.find(n.data.bin_op[0]);
        const rhs = oir.union_find.find(n.data.bin_op[1]);

        // `iv <cmp> bound`
        if (loop.slotOf(lhs)) |s| {
            if (constOf(oir, rhs)) |bound| {
                if (constIv(oir, loop, steps, s)) |iv| {
                    if (tripFor(iv.init, iv.step, kind, bound)) |t| return t;
                }
            }
        }
        // `bound <cmp> iv`, same comparison with the IV on the left flips the sense.
        if (loop.slotOf(rhs)) |s| {
            if (constOf(oir, lhs)) |bound| {
                if (constIv(oir, loop, steps, s)) |iv| {
                    const flipped: Cmp = if (kind == .lt) .gt else .lt;
                    if (tripFor(iv.init, iv.step, flipped, bound)) |t| return t;
                }
            }
        }
    }
    return null;
}

/// Interpret a fully-constant loop with a small trip count to fold it to constants.
/// This is the fallback for recurrences the closed-form passes can't model.
fn evaluateConstantLoops(oir: *Oir) !bool {
    const gpa = oir.allocator;
    const trip_cap = 1 << 16;

    var memo: std.AutoHashMapUnmanaged(Class.Index, i64) = .{};
    defer memo.deinit(gpa);

    outer: for (0..oir.getNodes().len) |i| {
        var a = (try analyze(oir, i)) orelse continue;
        defer a.deinit(gpa);
        const loop = a.loop;
        const count = loop.count();

        const trip = analyticTrip(oir, loop, a.steps) orelse continue;
        if (trip < 0 or trip > trip_cap) continue;

        var lv2slot: std.AutoHashMapUnmanaged(Class.Index, usize) = .{};
        defer lv2slot.deinit(gpa);

        const state = try gpa.alloc(i64, count);
        defer gpa.free(state);

        const next_state = try gpa.alloc(i64, count);
        defer gpa.free(next_state);
        for (1..count) |s| {
            try lv2slot.put(gpa, loop.args[s], s);
            const init_idx = oir.classContains(loop.inits[s], .constant) orelse continue :outer;
            state[s] = oir.getNode(init_idx).data.constant.val;
        }

        for (0..@intCast(trip)) |_| {
            memo.clearRetainingCapacity();
            for (1..count) |s| {
                next_state[s] = (try evalConst(oir, loop.nexts[s], lv2slot, state, &memo, 0)) orelse continue :outer;
            }
            @memcpy(state[1..count], next_state[1..count]);
        }

        var changed = false;
        for (1..count) |s| {
            const cst = try oir.add(.constant(state[s]));
            const proj = try oir.add(.project(@intCast(s), loop.class, .data, oir.typeOf(loop.args[s])));
            if (try oir.@"union"(proj, cst)) changed = true;
        }
        if (changed) {
            try oir.rebuild();
            return true;
        }
    }
    return false;
}

/// Close recurrences over a constant trip count `T`, first-order slots (`init +/- T*D`,
/// `D` loop-invariant) and second-order slots (summing an affine IV).
fn affineClosedForms(oir: *Oir) !bool {
    for (0..oir.getNodes().len) |i| {
        var a = (try analyze(oir, i)) orelse continue;
        defer a.deinit(oir.allocator);

        const trip_count = analyticTrip(oir, a.loop, a.steps) orelse continue;
        const trip = try oir.add(.constant(trip_count));

        var changed = false;
        for (1..a.loop.count()) |s| {
            const exit: Class.Index = switch (a.steps[s]) {
                .none => continue,
                .invariant => a.loop.inits[s],
                .add, .sub => (try closedExit(oir, a.loop, s, a.steps, a.part, trip)) orelse
                    (try secondOrderExit(oir, a, s, trip_count)) orelse continue,
            };
            const proj = try oir.add(.project(@intCast(s), a.loop.class, .data, oir.typeOf(a.loop.args[s])));
            if (try oir.@"union"(proj, exit)) changed = true;
        }
        if (changed) {
            try oir.rebuild();
            return true;
        }
    }
    return false;
}

/// The exit value of a first-order affine slot `s` over symbolic trip `trip`, i.e.
/// `init +/- delta*trip`. Returns null unless the step is a loop-invariant affine
/// recurrence (its delta reaches no varying loopvar). Invariant loopvarss in the delta
/// are rewritten to their inits so the result is valid outside the loop.
fn closedExit(oir: *Oir, loop: Loop, s: usize, steps: []const Step, part: Partition, trip: Class.Index) !?Class.Index {
    const raw_delta = switch (steps[s]) {
        .add, .sub => |d| d,
        else => return null,
    };
    if (!try reachesOnly(oir, raw_delta, part.variant)) return null;
    const delta = try substInvariant(oir, raw_delta, part.inv_init);
    const op: Node.Tag = if (steps[s] == .add) .add else .sub;
    const product = try oir.add(.binOp(.mul, delta, trip));
    return try oir.add(.binOp(op, loop.inits[s], product));
}

/// The exit value of a second-order slot `s` that accumulates an affine IV each
/// iteration (`s +/-= j`, where slot `j` is itself affine with a loop-invariant
/// step). Over a constant trip `T`,
/// `s_exit = s_init +/- (j_init*T + j_step * T*(T-1)/2)`.
///
/// Returns null when `s`'s step isn't exactly another affine slot's loopvar.
///
/// TODO: just an idea on how to optimize a certain test case, would probably
/// want to generalize this more.
fn secondOrderExit(oir: *Oir, a: Analysis, s: usize, trip: i64) !?Class.Index {
    const d = switch (a.steps[s]) {
        .add, .sub => |x| oir.union_find.find(x),
        else => return null,
    };
    const j = a.loop.slotOf(d) orelse return null; // step must be slot j's loopvar
    if (j == s) return null; // self-reference (e.g. `s += s`) is not an affine sum

    const j_step_delta = switch (a.steps[j]) {
        .add, .sub => |c| c,
        else => return null,
    };
    if (!try reachesOnly(oir, j_step_delta, a.part.variant)) return null; // j affine
    const j_step_inv = try substInvariant(oir, j_step_delta, a.part.inv_init);
    const j_step = if (a.steps[j] == .add) j_step_inv else try negate(oir, j_step_inv);

    // sum_{k=0}^{T-1} (j_init + k*j_step) = j_init*T + j_step * T*(T-1)/2
    const trip_class = try oir.add(.constant(trip));
    const triangle = try oir.add(.constant(@divTrunc(trip * (trip - 1), 2)));
    const linear = try oir.add(.binOp(.mul, a.loop.inits[j], trip_class));
    const quad = try oir.add(.binOp(.mul, j_step, triangle));
    const sum = try oir.add(.binOp(.add, linear, quad));

    const op: Node.Tag = if (a.steps[s] == .add) .add else .sub;
    return try oir.add(.binOp(op, a.loop.inits[s], sum));
}

fn negate(oir: *Oir, x: Class.Index) !Class.Index {
    const zero = try oir.add(.constant(0));
    return oir.add(.binOp(.sub, zero, x));
}

/// A loop controlled by a single unit-step comparison, giving an exact (but
/// symbolic) trip count.
const Control = struct {
    /// Controlling slot index (its loopvar drives the predicate).
    slot: usize,
    /// `pred(inits)`, the gamma predicate, nonzero iff the loop runs at least once.
    entry: Class.Index,
    /// Iteration count when entered (the symbolic `T`).
    trip: Class.Index,
    /// The bound the controlling slot lands on at exit.
    bound: Class.Index,
};

/// Close affine recurrences over a symbolic trip count.
///
/// When a single unit-step induction variable is compared against a loop-invariant
/// bound, it lands on `b` exactly, so an entered loop runs `T = |b - init_i|` times.
/// Each affine slot closes to `gamma(entry, init +/- T*D, init)`.
///
/// Folds `while (n > 0) n--;` to `gamma(n > 0, 0, n)`.
fn symbolicClosedForms(oir: *Oir) !bool {
    for (0..oir.getNodes().len) |i| {
        var a = (try analyze(oir, i)) orelse continue;
        defer a.deinit(oir.allocator);

        const ctrl = (try findControl(oir, a.loop, a.steps, a.part)) orelse continue;

        var changed = false;
        for (1..a.loop.count()) |s| {
            const init_s = a.loop.inits[s];
            const then_val: Class.Index = if (s == ctrl.slot)
                ctrl.bound // a unit step lands on the bound exactly
            else
                (try closedExit(oir, a.loop, s, a.steps, a.part, ctrl.trip)) orelse continue;
            const g = try oir.add(.gamma(ctrl.entry, then_val, init_s));
            const proj = try oir.add(.project(@intCast(s), a.loop.class, .data, oir.typeOf(a.loop.args[s])));
            if (try oir.@"union"(proj, g)) changed = true;
        }
        if (changed) {
            try oir.rebuild();
            return true;
        }
    }
    return false;
}

/// Recognizes a loop whose predicate is a single unit-step `cmp_gt` and derives its
/// symbolic, exact trip count. Returns null for any other predicate shape.
///
/// TODO: this will need to be either reworked or expanded a lot, unsure how
/// to do this optimally yet.
fn findControl(oir: *Oir, loop: Loop, steps: []const Step, part: Partition) !?Control {
    const cls = oir.classes.get(loop.pred) orelse return null;
    for (cls.bag.items) |node_idx| {
        const n = oir.getNode(node_idx);
        if (n.tag != .cmp_gt) continue;
        const lhs = oir.union_find.find(n.data.bin_op[0]);
        const rhs = oir.union_find.find(n.data.bin_op[1]);

        // Decrement `cmp_gt(arg_c, bound)`: lands on `bound`, runs `init_c - bound`.
        if (loop.slotOf(lhs)) |c| {
            if (isUnit(oir, steps[c], .sub) and try reachesOnly(oir, rhs, part.variant))
                return try control(oir, c, loop.inits[c], try substInvariant(oir, rhs, part.inv_init), .down);
        }
        // Increment `cmp_gt(bound, arg_c)`: lands on `bound`, runs `bound - init_c`.
        if (loop.slotOf(rhs)) |c| {
            if (isUnit(oir, steps[c], .add) and try reachesOnly(oir, lhs, part.variant))
                return try control(oir, c, loop.inits[c], try substInvariant(oir, lhs, part.inv_init), .up);
        }
    }
    return null;
}

fn control(oir: *Oir, slot: usize, init_c: Class.Index, bound: Class.Index, dir: enum { up, down }) !Control {
    const hi, const lo = if (dir == .down) .{ init_c, bound } else .{ bound, init_c };
    return .{
        .slot = slot,
        .entry = try oir.add(.binOp(.cmp_gt, hi, lo)),
        .trip = try oir.add(.binOp(.sub, hi, lo)),
        .bound = bound,
    };
}

/// Whether `step` is a `+1`/`-1` recurrence matching `want`.
fn isUnit(oir: *Oir, step: Step, want: enum { add, sub }) bool {
    const delta = switch (step) {
        .add => |d| if (want == .add) d else return false,
        .sub => |d| if (want == .sub) d else return false,
        else => return false,
    };
    return (constOf(oir, delta) orelse return false) == 1;
}

/// Evaluate `class` to a constant given the current loop `state` (substituting each
/// slot's loopvar). Returns null if any leaf is non-constant/symbolic.
fn evalConst(
    oir: *Oir,
    class: Class.Index,
    lv2slot: std.AutoHashMapUnmanaged(Class.Index, usize),
    state: []const i64,
    memo: *std.AutoHashMapUnmanaged(Class.Index, i64),
    depth: u32,
) !?i64 {
    if (depth > 256) return null;
    const c = oir.union_find.find(class);
    if (lv2slot.get(c)) |slot| return state[slot];
    if (memo.get(c)) |v| return v;

    const cls = oir.classes.get(c) orelse return null;
    for (cls.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        const value: ?i64 = if (node.tag == .constant)
            node.data.constant.val
        else if (eval.isScalarBinOp(node.tag)) v: {
            const ops = node.data.bin_op;
            const a = (try evalConst(oir, ops[0], lv2slot, state, memo, depth + 1)) orelse break :v null;
            const b = (try evalConst(oir, ops[1], lv2slot, state, memo, depth + 1)) orelse break :v null;
            const bits = oir.typeOfOpt(ops[0]) orelse oir.typeOfOpt(ops[1]) orelse 64;
            break :v eval.binOp(node.tag, a, b, bits);
        } else null;
        if (value) |v| {
            try memo.put(oir.allocator, c, v);
            return v;
        }
    }
    return null;
}

fn constOf(oir: *Oir, class: Class.Index) ?i64 {
    const idx = oir.classContains(class, .constant) orelse return null;
    return oir.getNode(idx).data.constant.val;
}

/// Whether `class` reaches none of the `variant` loopvars.
fn reachesOnly(oir: *Oir, class: Class.Index, variant: std.AutoHashMapUnmanaged(Class.Index, void)) !bool {
    var reached: std.AutoHashMapUnmanaged(Class.Index, void) = .{};
    defer reached.deinit(oir.allocator);
    try collectReachable(oir, class, &reached);
    var it = variant.keyIterator();
    while (it.next()) |key| {
        if (reached.contains(key.*)) return false;
    }
    return true;
}

/// Rewrites `class` so each invariant-slot loopvar becomes that slot's init, yielding
/// an equivalent expression valid outside the loop. Only valid when `class` references
/// no varying loopvar.
fn substInvariant(
    oir: *Oir,
    class: Class.Index,
    inv_init: std.AutoHashMapUnmanaged(Class.Index, Class.Index),
) error{OutOfMemory}!Class.Index {
    const c = oir.union_find.find(class);
    if (inv_init.get(c)) |init| return init; // invariant loopvar -> its init value

    const cls = oir.classes.get(c) orelse return c;
    const node = oir.getNode(cls.bag.items[0]); // a representative
    if (!eval.isScalarBinOp(node.tag)) return c; // constants/pre-loop values, unchanged

    const ops = node.data.bin_op;
    const a = try substInvariant(oir, ops[0], inv_init);
    const b = try substInvariant(oir, ops[1], inv_init);
    return oir.add(.binOp(node.tag, a, b));
}

/// A slot whose next-iteration vlaue is its own loop argument never changes, so
/// its output equals its init.
fn eliminateInvariantSlots(oir: *Oir) !bool {
    for (oir.getNodes(), 0..) |node, i| {
        if (node.tag != .project) continue;
        const proj = node.data.project;

        const class = oir.classes.get(oir.union_find.find(proj.tuple)) orelse continue;
        const theta = for (class.bag.items) |node_idx| {
            const candidate = oir.getNode(node_idx);
            if (candidate.tag == .theta) break candidate;
        } else continue;

        const loop = theta.data.loop;
        if (proj.index >= loop.count) continue;
        if (oir.union_find.find(loop.args(oir)[proj.index]) != oir.union_find.find(loop.nexts(oir)[proj.index])) continue;

        const proj_class = oir.findClass(@enumFromInt(i));
        if (try oir.@"union"(proj_class, loop.inits(oir)[proj.index])) {
            try oir.rebuild();
            return true;
        }
    }
    return false;
}

/// Drop carried slots whose output nothing observes and which feed neither the
/// predicate nor any live slot's next value, by building a smaller `theta` and
/// redirecting the surviving output projections to it.
fn eliminateDeadSlots(oir: *Oir) !bool {
    const gpa = oir.allocator;

    for (0..oir.getNodes().len) |i| {
        var loop = (try snapshot(oir, i)) orelse continue;
        defer loop.deinit(gpa);
        const count = loop.count();

        // A smaller look for this id already exists.
        if (hasSmallerLoop(oir, loop.id, @intCast(count))) continue;

        const needed = try gpa.alloc(bool, count);
        defer gpa.free(needed);
        @memset(needed, false);
        needed[0] = true; // always keep the memory slot (stays at position 0)
        markLiveOutputs(oir, loop.class, @intCast(count), needed);

        // A slot is needed if its loopvar feeds the predicate or any needed
        // slot's next value. We recompute reachability until it stabilizes.
        var reached: std.AutoHashMapUnmanaged(Class.Index, void) = .{};
        defer reached.deinit(gpa);
        var changed = true;
        while (changed) {
            changed = false;
            reached.clearRetainingCapacity();

            try collectReachable(oir, loop.pred, &reached);
            for (loop.nexts, 0..) |next, k| {
                if (needed[k]) try collectReachable(oir, next, &reached);
            }
            for (loop.args, 0..) |arg, j| {
                if (!needed[j] and reached.contains(arg)) {
                    needed[j] = true;
                    changed = true;
                }
            }
        }

        var kept: std.ArrayList(usize) = .empty;
        defer kept.deinit(gpa);
        for (0..count) |j| {
            if (needed[j]) try kept.append(gpa, j);
        }
        if (kept.items.len == count) continue; // nothing dead

        var body: std.ArrayList(Class.Index) = .empty;
        defer body.deinit(gpa);
        for (kept.items) |j| try body.append(gpa, loop.args[j]);
        for (kept.items) |j| try body.append(gpa, loop.inits[j]);
        try body.append(gpa, loop.pred);
        for (kept.items) |j| try body.append(gpa, loop.nexts[j]);

        const span = try oir.listToSpan(body.items);
        const new_theta = try oir.add(.theta(loop.id, @intCast(kept.items.len), span));

        var did_union = false;
        for (kept.items, 0..) |orig, pos| {
            const bits = oir.typeOf(loop.args[orig]);
            const old_proj = try oir.add(.project(@intCast(orig), loop.class, .data, bits));
            const new_proj = try oir.add(.project(@intCast(pos), new_theta, .data, bits));
            if (try oir.@"union"(old_proj, new_proj)) did_union = true;
        }
        if (did_union) {
            try oir.rebuild();
            return true;
        }
    }
    return false;
}

/// Whether a `theta` with this loop `id` but fewer slots already exists.
fn hasSmallerLoop(oir: *Oir, id: u32, count: u32) bool {
    for (oir.getNodes()) |node| {
        if (node.tag == .theta and node.data.loop.id == id and node.data.loop.count < count) return true;
    }
    return false;
}

/// Marks slots whose `project(theta, slot)` is referenced by anything.
fn markLiveOutputs(oir: *Oir, theta_class: Class.Index, count: u32, needed: []bool) void {
    const class = oir.classes.get(theta_class) orelse return;
    for (class.parents.items) |pair| {
        const parent = oir.getNode(pair[0]);
        if (parent.tag != .project) continue;
        if (oir.union_find.find(parent.data.project.tuple) != theta_class) continue;
        const slot = parent.data.project.index;
        if (slot >= count) continue;
        const proj = oir.classes.get(oir.findClass(pair[0])) orelse continue;
        if (proj.parents.items.len > 0) needed[slot] = true;
    }
}

/// Collects every E-Class reachable (through operands, across all nodes) from `root`.
fn collectReachable(
    oir: *Oir,
    root: Class.Index,
    out: *std.AutoHashMapUnmanaged(Class.Index, void),
) !void {
    var stack: std.ArrayList(Class.Index) = .empty;
    defer stack.deinit(oir.allocator);
    try stack.append(oir.allocator, oir.union_find.find(root));

    while (stack.pop()) |c| {
        const gop = try out.getOrPut(oir.allocator, c);
        if (gop.found_existing) continue;

        const class = oir.classes.get(c) orelse continue;
        for (class.bag.items) |node_idx| {
            for (oir.getNode(node_idx).operands(oir)) |op| {
                try stack.append(oir.allocator, oir.union_find.find(op));
            }
        }
    }
}
