//! Recovers control structure from the flat, topologically-ordered recursive
//! Oir and decide, for every node, *which region* it executes in.
//!
//! A region is a straight-line piece of control flow: the function root, or one
//! arm of a `gamma`. Placement follows an idea similar to "global code motion",
//! but applied to RVSDG's already-structured region tree. A node belongs in
//! the innermost region that dominates all of its uses. More concretely, a node's
//! region is the lowest-common-ancestor (in the region tree) of the regions
//! of its users. A value used in both arms of a `gamma` is therefore hoisted
//! above the branch, while a value (or side-effect, like a `store`) used only
//! inside one arm stays inside that arm.
//!
//! Because the input is topologically ordered, a single backward pass over the
//! array finalizes every node's region with no fixpoint iteration.

const std = @import("std");
const Oir = @import("../../Oir.zig");

const Recursive = Oir.extraction.Recursive;
const Index = Oir.Class.Index;

pub const Region = struct {
    parent: Id,
    depth: u32,
    kind: Kind,

    pub const Id = enum(u32) {
        root = 0,
        unplaced = std.math.maxInt(u32),
        _,
    };

    pub const Kind = enum {
        root,
        gamma_then,
        gamma_else,
        // loop, we'll use this for `theta` lowering
    };
};

regions: std.ArrayList(Region),
/// Region assigned to each node, indexed by node index. `unplaced` means the
/// node is unreachable from an exit (dead) and should be skipped by codegen.
node_region: []Region.Id,
/// For each `gamma` node, the `{ then, else }` child regions of its own region.
gamma_regions: std.AutoHashMapUnmanaged(Index, [2]Region.Id),
/// Whether a node produces a memory-state token rather than a data value.
/// Memory-state values never occupy a register; they only sequence side effects.
is_mem: []bool,

const Schedule = @This();

const FusionKey = struct { region: Region.Id, pred: Index };

pub fn compute(gpa: std.mem.Allocator, recv: *const Recursive) !Schedule {
    const n = recv.nodes.items.len;

    var node_region = try gpa.alloc(Region.Id, n);
    errdefer gpa.free(node_region);
    @memset(node_region, .unplaced);

    const is_mem = try gpa.alloc(bool, n);
    errdefer gpa.free(is_mem);

    var regions: std.ArrayList(Region) = .empty;
    errdefer regions.deinit(gpa);
    try regions.append(gpa, .{ .parent = .root, .depth = 0, .kind = .root });

    var gamma_regions: std.AutoHashMapUnmanaged(Index, [2]Region.Id) = .{};

    // Gammas that live in the same region and branch on the same predicate share
    // one pair of arm regions (and, in the emitter, one branch). Keyed by
    // `(parent region, predicate node)`.
    var fusion: std.AutoHashMapUnmanaged(FusionKey, [2]Region.Id) = .{};
    defer fusion.deinit(gpa);

    // Classify memory-state vs data nodes.
    // Loop runs forwards, as operands have lower indices.
    for (recv.nodes.items, 0..) |node, i| {
        is_mem[i] = switch (node.tag) {
            .store, .start => true,
            .project => node.data.project.index == 0,
            .gamma => is_mem[@intFromEnum(node.data.tri_op[1])],
            else => false,
        };
    }

    // Exits (the `ret`) execute in the root region.
    for (recv.exit_list.items) |exit| node_region[@intFromEnum(exit)] = .root;

    // Backwards pass. By the time we reach a node, every user has already pushed
    // its use-region into it, so its region is final.
    var i = n;
    while (i > 0) {
        i -= 1;
        const region = node_region[i];
        if (region == .unplaced) continue; // dead node

        const node = recv.nodes.items[i];
        switch (node.tag) {
            .gamma => {
                const ops = node.data.tri_op;
                const key: FusionKey = .{ .region = region, .pred = ops[0] };

                // Reuse the arm regions of an already-seen sibling gamma with the
                // same predicate, so they all lower to a single branch.
                const arms = fusion.get(key) orelse arms: {
                    const then_region = try addRegion(&regions, gpa, region, .gamma_then);
                    const else_region = try addRegion(&regions, gpa, region, .gamma_else);
                    const pair: [2]Region.Id = .{ then_region, else_region };
                    try fusion.put(gpa, key, pair);
                    break :arms pair;
                };
                try gamma_regions.put(gpa, @enumFromInt(i), arms);

                // predicate is evaluated in the gamma's own region
                // each arm value is needed only inside that arm.
                mergeUse(node_region, regions.items, ops[0], region);
                mergeUse(node_region, regions.items, ops[1], arms[0]);
                mergeUse(node_region, regions.items, ops[2], arms[1]);
            },
            .theta => @panic("rv64: theta/loops are not supported yet"),
            else => for (node.operands(recv)) |op| {
                mergeUse(node_region, regions.items, op, region);
            },
        }
    }

    // Function arguemnts and the intial memory state are entry values.
    // We pin them to the root region so they're materialized once, at entry,
    // and never recomputed inside a branch where the source arg register may
    // be gone.
    for (recv.nodes.items, 0..) |node, idx| {
        if (node.tag == .project) node_region[idx] = .root;
    }

    return .{
        .regions = regions,
        .node_region = node_region,
        .gamma_regions = gamma_regions,
        .is_mem = is_mem,
    };
}

fn addRegion(
    regions: *std.ArrayList(Region),
    gpa: std.mem.Allocator,
    parent: Region.Id,
    kind: Region.Kind,
) !Region.Id {
    const id: Region.Id = @enumFromInt(regions.items.len);
    try regions.append(gpa, .{
        .parent = parent,
        .depth = regions.items[@intFromEnum(parent)].depth + 1,
        .kind = kind,
    });
    return id;
}

fn mergeUse(node_region: []Region.Id, regions: []const Region, node: Index, use_region: Region.Id) void {
    const idx = @intFromEnum(node);
    node_region[idx] = if (node_region[idx] == .unplaced)
        use_region
    else
        lca(regions, node_region[idx], use_region);
}

/// Computes the lowest-common-ancestor within `regions` for `a` and `b`.
fn lca(regions: []const Region, a: Region.Id, b: Region.Id) Region.Id {
    var x = a;
    var y = b;
    while (x != y) {
        if (regions[@intFromEnum(x)].depth < regions[@intFromEnum(y)].depth) {
            y = regions[@intFromEnum(y)].parent;
        } else {
            x = regions[@intFromEnum(x)].parent;
        }
    }
    return x;
}

pub fn deinit(s: *Schedule, gpa: std.mem.Allocator) void {
    s.regions.deinit(gpa);
    gpa.free(s.node_region);
    s.gamma_regions.deinit(gpa);
    gpa.free(s.is_mem);
}
