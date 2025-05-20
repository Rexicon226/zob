//! Uses Z3 in order to extract an optimal pattern from the E-Graph.

const std = @import("std");
const build_options = @import("build_options");
const z3 = if (build_options.has_z3) @import("z3") else {};
const Oir = @import("../Oir.zig");
const cost = @import("../cost.zig");
const Recursive = @import("extraction.zig").Recursive;

const log = std.log.scoped(.z3_extractor);

const Node = Oir.Node;
const Class = Oir.Class;

const ClassVars = struct {
    active: z3.Bool,
    order: z3.Int,
    nodes: []const z3.Bool,
};

pub fn extract(oir: *const Oir) !Recursive {
    if (!build_options.has_z3) @panic("need z3 enabled to use z3 extractor");

    var arena: std.heap.ArenaAllocator = .init(oir.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var cycles = try oir.findCycles();
    defer cycles.deinit(oir.allocator);

    var model = z3.Model.init(.optimize);
    defer model.deinit();

    var vars: std.AutoHashMapUnmanaged(Class.Index, ClassVars) = .{};
    defer vars.deinit(gpa);

    var iter = oir.classes.iterator();
    while (iter.next()) |entry| {
        const class = entry.value_ptr;
        const active = model.constant(.bool, null);
        const order = model.constant(.int, null);

        const max_order = model.int(@intCast(oir.nodes.count() * 10));
        model.assert(model.le(order, max_order));

        const nodes = try gpa.alloc(z3.Bool, class.bag.items.len);
        for (nodes) |*node| node.* = model.constant(.bool, null);

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
        const class_or = model.@"or"(class.nodes);
        const equiv = model.iff(class.active, class_or);
        model.assert(equiv);

        for (oir.getClass(id).bag.items, class.nodes) |node, node_active| {
            // If there's a cycle through this node, it can never be chosen, so we just de-active it.
            if (cycles.contains(node)) {
                model.assert(model.not(node_active));
            }

            // node_active == true implies that child_active == true
            for (oir.getNode(node).operands(oir)) |child| {
                const child_active = vars.get(child).?.active;
                const implication = model.implies(node_active, child_active);
                model.assert(implication);
            }
        }
    }

    // Each node in the graph is a term in the objective. Each term has a
    // weight, which is 0 if it isn't active, or 1 * cost(tag) if it is.
    // The goal of the optimizer is to reduce this number to the smallest possible
    // cost of the total graph, while keeping the root nodes alive.
    var terms: std.ArrayListUnmanaged(z3.Int) = .{};
    defer terms.deinit(gpa);

    var class_iter = oir.classes.iterator();
    while (class_iter.next()) |entry| {
        for (
            entry.value_ptr.bag.items,
            vars.get(entry.value_ptr.index).?.nodes,
        ) |node, node_active| {
            const one = model.int(1);
            const zero = model.int(0);
            const int = model.ite(node_active, one, zero);
            const weight = model.int(@intCast(cost.getCost(oir.getNode(node).tag)));
            try terms.append(gpa, model.mul(&.{ weight, int }));
        }
    }

    const objective = model.add(terms.items);
    model.minimize(objective);

    // Force active == true for the roots. Otherwise, we'd just optimize into nothing!
    const exit_list = oir.getNode(.start).data.list.toSlice(oir);
    for (exit_list) |exit| {
        const root = vars.get(@enumFromInt(exit)).?.active;
        const eq = model.eq(root, model.true());
        model.assert(eq);
    }

    log.debug("solver:\n{s}\n", .{model.toString()});

    const result = model.check();

    if (result == .true) {
        var partial_model = model.getLastModel();
        defer partial_model.deinit();
        log.debug("found solution model:\n{s}\n", .{partial_model.toString()});

        var recv: Recursive = .{};
        var start_class: ?Class.Index = null;

        var new_exit_list: std.ArrayListUnmanaged(Class.Index) = .{};
        defer new_exit_list.deinit(gpa);

        var queue: std.ArrayListUnmanaged(Class.Index) = .{};
        defer queue.deinit(gpa);

        var map: std.AutoHashMapUnmanaged(Class.Index, Class.Index) = .{};
        defer map.deinit(gpa);

        for (exit_list) |exit| {
            try queue.append(gpa, oir.union_find.find(@enumFromInt(exit)));
        }

        while (queue.getLastOrNull()) |id| {
            if (map.contains(id)) {
                _ = queue.pop();
                continue;
            }
            const v = vars.get(id).?;
            std.debug.assert(partial_model.isTrue(v.active));

            const node_idx = for (v.nodes, 0..) |node, i| {
                if (partial_model.isTrue(node)) break i;
            } else @panic("TODO");
            const node = oir.getNode(oir.getClass(id).bag.items[node_idx]);

            // Check whether all operands are in the memo map.
            var all: bool = true;
            for (node.operands(oir)) |child| {
                if (!map.contains(child)) all = false;
            }
            if (all) {
                const new_id = try recv.addNode(oir.allocator, try node.mapNode(oir, &map));
                switch (node.tag) {
                    .ret => try new_exit_list.append(gpa, new_id),
                    .start => start_class = new_id,
                    else => {},
                }
                try map.put(gpa, id, new_id);
                _ = queue.pop();
            } else {
                try queue.appendSlice(gpa, node.operands(oir));
            }
        }

        if (start_class == null) @panic("no start class?");
        recv.nodes.items[@intFromEnum(start_class.?)].data = .{
            .list = try recv.listToSpan(
                new_exit_list.items,
                oir.allocator,
            ),
        };

        return recv;
    } else {
        std.debug.panic("no solution found!!!! what??", .{});
    }
}
