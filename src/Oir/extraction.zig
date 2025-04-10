const std = @import("std");
const z3 = @import("z3");
const Oir = @import("../Oir.zig");
const cost = @import("../cost.zig");
const build_options = @import("build_options");
const SimpleExtractor = @import("SimpleExtractor.zig");

const log = std.log.scoped(.extraction);
const Node = Oir.Node;
const Class = Oir.Class;

/// A form of OIR where nodes reference other nodes.
pub const Recursive = struct {
    nodes: std.ArrayListUnmanaged(Node) = .{},
    extra: std.ArrayListUnmanaged(u32) = .{},

    // TODO: Explore making this its own unique type. Currently we can't do that because
    // the Node data payload types use Class.Index to reference other Classes, which isn't
    // compatible with this. Maybe we can bitcast safely between them?
    // pub const Index = enum(u32) {
    //     start,
    //     _,
    // };

    pub fn getNode(r: *const Recursive, idx: Class.Index) Node {
        return r.nodes.items[@intFromEnum(idx)];
    }

    pub fn addNode(r: *Recursive, allocator: std.mem.Allocator, node: Node) !Class.Index {
        const idx: Class.Index = @enumFromInt(r.nodes.items.len);
        try r.nodes.append(allocator, node);
        return idx;
    }

    pub fn dump(recv: Recursive, name: []const u8) !void {
        const graphviz_file = try std.fs.cwd().createFile(name, .{});
        defer graphviz_file.close();
        try @import("print_oir.zig").dumpRecvGraph(recv, graphviz_file.writer());
    }

    pub fn deinit(r: *Recursive, allocator: std.mem.Allocator) void {
        r.nodes.deinit(allocator);
        r.extra.deinit(allocator);
    }

    pub fn listToSpan(
        r: *Recursive,
        list: []const Class.Index,
        gpa: std.mem.Allocator,
    ) !Oir.Node.Span {
        try r.extra.appendSlice(gpa, @ptrCast(list));
        return .{
            .start = @intCast(r.extra.items.len - list.len),
            .end = @intCast(r.extra.items.len),
        };
    }

    pub fn print(recv: Recursive, writer: anytype) !void {
        try @import("print_oir.zig").print(recv, writer);
    }
};

pub const CostStrategy = enum {
    /// A super basic cost strategy that simply looks at the number of child nodes
    /// a particular node has to determine its cost.
    simple_latency,
    /// Uses Z3 and a column approach to find the optimal solution.
    z3,

    pub const auto: CostStrategy = if (build_options.has_z3) .z3 else .simple_latency;
};

const ClassVars = struct {
    active: z3.Z3_ast,
    order: z3.Z3_ast,
    nodes: []const z3.Z3_ast,
};

const LiftedBool = enum(i2) {
    false = -1,
    undef = 0,
    true = 1,
};

fn isTrue(ctx: z3.Z3_context, model: z3.Z3_model, v: z3.Z3_ast) bool {
    var value: z3.Z3_ast = undefined;
    if (!z3.Z3_model_eval(ctx, model, v, true, &value)) return false;
    const boolean: LiftedBool = @enumFromInt(z3.Z3_get_bool_value(ctx, value));
    return boolean == .true;
}

pub fn extract(oir: *const Oir, strat: CostStrategy) !Recursive {
    switch (strat) {
        .simple_latency => return SimpleExtractor.extract(oir),
        .z3 => {
            std.debug.assert(build_options.has_z3);

            var arena: std.heap.ArenaAllocator = .init(oir.allocator);
            defer arena.deinit();
            const gpa = arena.allocator();

            var cycles = try oir.findCycles();
            defer cycles.deinit(oir.allocator);

            const max_order: i32 = @intCast(oir.nodes.items.len * 10);

            const cfg = z3.Z3_mk_config();
            const ctx = z3.Z3_mk_context(cfg);
            const int_sort = z3.Z3_mk_int_sort(ctx);
            const bool_sort = z3.Z3_mk_bool_sort(ctx);

            const opt = z3.Z3_mk_optimize(ctx);
            z3.Z3_optimize_inc_ref(ctx, opt);

            var vars: std.AutoHashMapUnmanaged(Class.Index, ClassVars) = .{};
            defer vars.deinit(gpa);

            var iter = oir.classes.iterator();
            while (iter.next()) |entry| {
                const class = entry.value_ptr;
                const active = z3.Z3_mk_const(ctx, z3.Z3_mk_string_symbol(
                    ctx,
                    try std.fmt.allocPrintZ(gpa, "active:{}", .{class.index}),
                ), bool_sort);
                const order = z3.Z3_mk_const(ctx, z3.Z3_mk_string_symbol(
                    ctx,
                    try std.fmt.allocPrintZ(gpa, "order:{}", .{class.index}),
                ), int_sort);

                const max_order_ast = z3.Z3_mk_int(ctx, max_order, int_sort);
                z3.Z3_optimize_assert(
                    ctx,
                    opt,
                    z3.Z3_mk_le(ctx, order, max_order_ast),
                );

                const nodes = try gpa.alloc(z3.Z3_ast, class.bag.items.len);
                for (nodes, 0..) |*node, i| {
                    node.* = z3.Z3_mk_const(
                        ctx,
                        z3.Z3_mk_string_symbol(
                            ctx,
                            try std.fmt.allocPrintZ(gpa, "node {}:{d}", .{ class.index, i }),
                        ),
                        bool_sort,
                    );
                }

                try vars.put(gpa, class.index, .{
                    .active = active,
                    .order = order,
                    .nodes = nodes,
                });
            }

            var var_iter = vars.iterator();
            while (var_iter.next()) |entry| {
                const id = entry.key_ptr.*;
                const class = entry.value_ptr;

                // Class is active if and only if at least one of the nodes is active.
                const class_or = z3.Z3_mk_or(ctx, @intCast(class.nodes.len), class.nodes.ptr);
                const equiv = z3.Z3_mk_iff(ctx, class.active, class_or);
                z3.Z3_optimize_assert(ctx, opt, equiv);

                for (oir.getClass(id).bag.items, class.nodes) |node, node_active| {
                    if (cycles.contains(node)) {
                        if (true) @panic("confirm");
                        z3.Z3_optimize_assert(ctx, opt, z3.Z3_mk_not(ctx, node_active));
                    }

                    // node_active == true implies that child_active == true
                    for (oir.getNode(node).operands(oir)) |child| {
                        const child_active = vars.get(child).?.active;
                        const implication = z3.Z3_mk_implies(ctx, node_active, child_active);
                        z3.Z3_optimize_assert(ctx, opt, implication);
                    }
                }
            }

            // Each node in the graph is a term in the objective. Each term has a
            // weight, which is 0 if it isn't active, or 1 * cost(tag) if it is.
            // The goal of the optimizer is to reduce this number to the smallest possible
            // cost of the total graph, while keeping the root nodes alive.
            var terms: std.ArrayListUnmanaged(z3.Z3_ast) = .{};
            defer terms.deinit(gpa);

            var class_iter = oir.classes.iterator();
            while (class_iter.next()) |entry| {
                for (
                    entry.value_ptr.bag.items,
                    vars.get(entry.value_ptr.index).?.nodes,
                ) |node, node_active| {
                    const one = z3.Z3_mk_int(ctx, 1, int_sort);
                    const zero = z3.Z3_mk_int(ctx, 0, int_sort);
                    const int = z3.Z3_mk_ite(ctx, node_active, one, zero);
                    const weight = z3.Z3_mk_int(
                        ctx,
                        @intCast(cost.getCost(oir.getNode(node).tag)),
                        int_sort,
                    );
                    try terms.append(gpa, z3.Z3_mk_mul(ctx, 2, &[_]z3.Z3_ast{ weight, int }));
                }
            }

            const objective = z3.Z3_mk_add(
                ctx,
                @intCast(terms.items.len),
                terms.items.ptr,
            );
            _ = z3.Z3_optimize_minimize(ctx, opt, objective);

            // Force active == true for the roots. Otherwise, we'd just optimize into nothing!
            const exit_list = oir.getNode(.start).data.list.toSlice(oir);
            for (exit_list) |exit| {
                const root = vars.get(@enumFromInt(exit)).?.active;
                const one = z3.Z3_mk_true(ctx);
                const eq = z3.Z3_mk_eq(ctx, root, one);
                z3.Z3_optimize_assert(ctx, opt, eq);
            }

            log.debug("solver:\n{s}\n", .{z3.Z3_optimize_to_string(ctx, opt)});

            const result = z3.Z3_optimize_check(ctx, opt, 0, null);

            if (result == 1) {
                const model = z3.Z3_optimize_get_model(ctx, opt);
                z3.Z3_model_inc_ref(ctx, model);
                const string = z3.Z3_model_to_string(ctx, model);
                log.debug("found solution model:\n{s}\n", .{string});

                var repr: Recursive = .{
                    .extra = try oir.extra.clone(oir.allocator),
                };

                var queue: std.ArrayListUnmanaged(Class.Index) = .{};
                defer queue.deinit(gpa);

                for (exit_list) |exit| {
                    try queue.append(gpa, oir.union_find.find(@enumFromInt(exit)));
                }

                var map: std.AutoHashMapUnmanaged(Class.Index, Class.Index) = .{};
                defer map.deinit(gpa);

                while (queue.getLastOrNull()) |id| {
                    if (map.contains(id)) {
                        _ = queue.pop();
                        continue;
                    }
                    const v = vars.get(id).?;
                    std.debug.assert(isTrue(ctx, model, v.active));
                    const node_idx = for (v.nodes, 0..) |node, i| {
                        if (isTrue(ctx, model, node)) break i;
                    } else @panic("TODO");
                    const node = oir.getNode(oir.getClass(id).bag.items[node_idx]);

                    // Check whether all operands are in the memo map.
                    var all: bool = true;
                    for (node.operands(oir)) |child| {
                        if (!map.contains(child)) all = false;
                    }
                    if (all) {
                        const new_id = try repr.addNode(oir.allocator, try mapNode(oir, node, &map));
                        try map.put(gpa, id, new_id);
                        _ = queue.pop();
                    } else {
                        try queue.appendSlice(gpa, node.operands(oir));
                    }
                }

                return repr;
            } else {
                std.debug.panic("no solution found!!!! what??", .{});
            }
        },
    }
}

fn mapNode(
    oir: *const Oir,
    old: Node,
    map: *std.AutoHashMapUnmanaged(Class.Index, Class.Index),
) !Node {
    var copy = old;
    for (copy.mutableOperands(oir)) |*op| {
        op.* = map.get(oir.union_find.find(op.*)).?;
    }
    return copy;
}
