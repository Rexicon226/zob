//! Implements E-matching through an Abstract Virtual Machine.
//!
//! Based on this paper: https://leodemoura.github.io/files/ematching.pdf

const std = @import("std");
const Oir = @import("../../Oir.zig");
const rewrite = @import("../rewrite.zig");
const SExpr = @import("SExpr.zig");

const Node = Oir.Node;
const Class = Oir.Class;
const Result = rewrite.Result;
const Rewrite = rewrite.Rewrite;
const MultiRewrite = rewrite.MultiRewrite;

const Compiler = struct {
    next_reg: Reg,
    instructions: std.ArrayListUnmanaged(Instruction),
    todo_nodes: std.AutoHashMapUnmanaged(struct { SExpr.Index, Reg }, SExpr.Entry),
    v2r: std.StringHashMapUnmanaged(Reg),
    free_vars: std.ArrayListUnmanaged(std.StringArrayHashMapUnmanaged(void)),
    subtree_size: std.ArrayListUnmanaged(u64),

    const Todo = struct { SExpr.Index, Reg };

    fn compile(
        c: *Compiler,
        allocator: std.mem.Allocator,
        bind: ?[]const u8,
        pattern: SExpr,
    ) !void {
        try c.loadPattern(allocator, pattern);
        const root = pattern.root();

        if (bind) |v| {
            if (c.v2r.get(v)) |i| {
                try c.addTodo(allocator, pattern, root, i);
            } else {
                try c.addPattern(allocator, pattern, root);
                try c.v2r.put(allocator, v, c.next_reg);
                c.next_reg.add(1);
            }
        } else {
            try c.addPattern(allocator, pattern, root);
            c.next_reg.add(1);
        }

        while (c.next()) |entry| {
            const todo, const node = entry;
            const id, const reg = todo;

            if (c.isGrounded(id) and node.operands().len != 0) {
                const new_node = try newRoot(pattern, allocator, id);
                try c.instructions.append(allocator, .{ .lookup = .{
                    .i = reg,
                    .term = new_node,
                } });
            } else {
                const out = c.next_reg;
                c.next_reg.add(@intCast(node.operands().len));

                try c.instructions.append(allocator, .{ .bind = .{
                    .node = node,
                    .i = reg,
                    .out = out,
                } });

                for (node.operands(), 0..) |child, i| {
                    try c.addTodo(
                        allocator,
                        pattern,
                        child,
                        @enumFromInt(@intFromEnum(out) + i),
                    );
                }
            }
        }
    }

    fn addPattern(
        c: *Compiler,
        allocator: std.mem.Allocator,
        pattern: SExpr,
        root: SExpr.Index,
    ) !void {
        if (c.instructions.items.len != 0) {
            try c.instructions.append(allocator, .{ .scan = c.next_reg });
        }
        try c.addTodo(allocator, pattern, root, c.next_reg);
    }

    fn isGrounded(c: *Compiler, id: SExpr.Index) bool {
        for (c.free_vars.items[@intFromEnum(id)].keys()) |v| {
            if (!c.v2r.contains(v)) return false;
        }
        return true;
    }

    /// Clones and owner must free Program.
    ///
    /// TODO: should just ref and deinit with Compiler, unsure if there's anything stopping that.
    fn extract(c: *Compiler, allocator: std.mem.Allocator) !Program {
        return .{
            .instructions = try c.instructions.toOwnedSlice(allocator),
            .map = try c.v2r.clone(allocator),
        };
    }

    fn loadPattern(c: *Compiler, allocator: std.mem.Allocator, pattern: SExpr) !void {
        const len = pattern.nodes.len;
        try c.free_vars.ensureTotalCapacityPrecise(allocator, len);
        try c.subtree_size.ensureTotalCapacityPrecise(allocator, len);

        for (pattern.nodes) |node| {
            var free: std.StringArrayHashMapUnmanaged(void) = .{};
            var size: usize = 0;

            switch (node) {
                .node => |n| {
                    size = 1;
                    for (n.list) |child| {
                        for (c.free_vars.items[@intFromEnum(child)].keys()) |fv| {
                            try free.put(allocator, fv, {});
                        }
                        size += c.subtree_size.items[@intFromEnum(child)];
                    }
                },
                .constant => size = 1,
                .builtin => |b| try free.put(allocator, b.expr, {}),
                .atom => |v| try free.put(allocator, v, {}),
            }
            try c.free_vars.append(allocator, free);
            try c.subtree_size.append(allocator, size);
        }
    }

    fn addTodo(
        c: *Compiler,
        allocator: std.mem.Allocator,
        pattern: SExpr,
        id: SExpr.Index,
        reg: Reg,
    ) !void {
        const node = pattern.nodes[@intFromEnum(id)];
        switch (node) {
            .atom => |v| {
                if (c.v2r.get(v)) |j| {
                    try c.instructions.append(allocator, .{ .compare = .{
                        .i = reg,
                        .j = j,
                    } });
                } else {
                    try c.v2r.put(allocator, v, reg);
                }
            },
            .builtin,
            .node,
            .constant,
            => try c.todo_nodes.put(allocator, .{ id, reg }, node),
        }
    }

    fn next(c: *Compiler) ?struct { Todo, SExpr.Entry } {
        var iter = c.todo_nodes.keyIterator();
        if (c.todo_nodes.count() == 0) return null;

        const Fill = struct {
            grounded: bool,
            free: u64,
            size: u64,
            node: ?Todo,

            fn better(new: @This(), old: @This()) bool {
                // Prefer grounded.
                if (old.grounded == true and new.grounded == false) return false;
                if (new.free < old.free) return false;
                if (new.size > old.size) return false;
                return true;
            }
        };

        var best: Fill = .{
            .grounded = false,
            // Prefer more free variables.
            .free = 0,
            // Prefer smaller terms.
            .size = std.math.maxInt(u64),
            .node = null,
        };

        while (iter.next()) |node| {
            const id = node.@"0";
            const vars = c.free_vars.items[@intFromEnum(id)];
            var n_bound: usize = 0;
            for (vars.keys()) |v| {
                if (c.v2r.contains(v)) n_bound += 1;
            }
            const n_free = vars.count() - n_bound;
            const size = c.subtree_size.items[@intFromEnum(id)];

            const new: Fill = .{
                .grounded = n_free == 0,
                .free = n_free,
                .size = size,
                .node = node.*,
            };

            if (best.node == null or new.better(best)) {
                best = new;
            }
        }

        const removed = c.todo_nodes.fetchRemove(best.node.?).?.value;
        return .{ best.node.?, removed };
    }

    fn deinit(c: *Compiler, allocator: std.mem.Allocator) void {
        c.instructions.deinit(allocator);
        c.v2r.deinit(allocator);
        c.todo_nodes.deinit(allocator);
        for (c.free_vars.items) |*set| {
            set.deinit(allocator);
        }
        c.free_vars.deinit(allocator);
        c.subtree_size.deinit(allocator);
    }
};

/// Extracts an S-expression that starts from new_root and contains its children.
///
/// Caller must free the expr.
pub fn newRoot(
    expr: SExpr,
    allocator: std.mem.Allocator,
    new_root_idx: SExpr.Index,
) !SExpr {
    var list: std.ArrayListUnmanaged(SExpr.Entry) = .{};
    defer list.deinit(allocator);

    var queue: std.ArrayListUnmanaged(SExpr.Index) = .{};
    defer queue.deinit(allocator);
    var map: std.AutoHashMapUnmanaged(SExpr.Index, SExpr.Index) = .{};
    defer map.deinit(allocator);

    const new_root = expr.nodes[@intFromEnum(new_root_idx)];

    try queue.appendSlice(
        allocator,
        new_root.operands(),
    );

    while (queue.getLastOrNull()) |id| {
        if (map.contains(id)) {
            _ = queue.pop();
            continue;
        }

        const node = expr.nodes[@intFromEnum(id)];

        var resolved: bool = true;
        for (node.operands()) |child| {
            if (!map.contains(child)) {
                resolved = false;
                try queue.append(allocator, child);
            }
        }

        if (resolved) {
            const new_node = try node.map(allocator, &map);
            const new_id: SExpr.Index = @enumFromInt(list.items.len);
            try list.append(allocator, new_node);
            try map.put(allocator, id, new_id);
            _ = queue.pop();
        }
    }

    const new_root_node = try new_root.map(allocator, &map);
    try list.append(allocator, new_root_node);
    return .{ .nodes = try list.toOwnedSlice(allocator) };
}

const Program = struct {
    instructions: []const Instruction,
    map: std.StringHashMapUnmanaged(Reg),

    fn search(
        p: *Program,
        rw: Rewrite,
        oir: *const Oir,
        matches: *std.ArrayListUnmanaged(Result),
    ) !void {
        const pattern = rw.from;
        var iter = oir.classes.valueIterator();
        const root: SExpr.Entry = pattern.nodes[@intFromEnum(pattern.root())];
        while (iter.next()) |class| {
            switch (root) {
                .constant => |value| if (oir.classContains(class.index, .constant)) |idx| {
                    const node_value = oir.getNode(idx).data.constant;
                    if (value == node_value) {
                        try matches.append(oir.allocator, .{
                            .bindings = .{},
                            .class = class.index,
                            .pattern = rw.to,
                        });
                    }
                },
                .node => |n| if (oir.classContainsAny(class.index, n.tag)) {
                    try p.searchClass(oir, class.index, rw.to, matches);
                },
                .atom => @panic("TODO: non-node root"),
                .builtin => @panic("can't have root be a builtin function"),
            }
        }
    }

    fn searchMulti(
        p: *Program,
        oir: *const Oir,
        matches: *std.ArrayListUnmanaged(Result),
    ) !void {
        var iter = oir.classes.valueIterator();
        while (iter.next()) |class| {
            try p.searchClass(oir, class.index, SExpr.parse("10"), matches);
        }
    }

    fn searchClass(
        p: *Program,
        oir: *const Oir,
        class: Class.Index,
        pattern: SExpr,
        matches: *std.ArrayListUnmanaged(Result),
    ) !void {
        std.debug.assert(oir.clean); // must be clean to search
        const allocator = oir.allocator;

        var machine: Machine = .{
            .registers = .{},
            .v2r = &p.map,
            .lookup = .{},
        };
        defer machine.deinit(allocator);
        try machine.registers.append(allocator, class);

        var results: std.ArrayListUnmanaged(Result.Bindings) = .{};
        defer results.deinit(allocator);

        try machine.run(oir, p.instructions, p.map, &results);

        for (results.items) |result| {
            try matches.append(allocator, .{
                .bindings = result,
                .class = class,
                .pattern = pattern,
            });
        }
    }

    fn deinit(p: *Program, allocator: std.mem.Allocator) void {
        for (p.instructions) |inst| inst.deinit(allocator);
        allocator.free(p.instructions);
        p.map.deinit(allocator);
    }
};

const Machine = struct {
    registers: std.ArrayListUnmanaged(Class.Index),
    /// Owned by the overhead Program
    v2r: *const std.StringHashMapUnmanaged(Reg),
    lookup: std.ArrayListUnmanaged(Class.Index),

    fn run(
        m: *Machine,
        oir: *const Oir,
        insts: []const Instruction,
        map: std.StringHashMapUnmanaged(Reg),
        matches: *std.ArrayListUnmanaged(Result.Bindings),
    ) !void {
        for (insts, 1..) |inst, i| {
            switch (inst) {
                .bind => |bind| {
                    const class = oir.getClass(m.registers.items[@intFromEnum(bind.i)]);
                    for (class.bag.items) |node_idx| {
                        const node = oir.getNode(node_idx);
                        if (bind.node.matches(node, oir)) {
                            m.registers.shrinkRetainingCapacity(@intFromEnum(bind.out));
                            for (node.operands(oir)) |id| {
                                try m.registers.append(oir.allocator, id);
                            }
                            // run for remaining instructions
                            try m.run(oir, insts[i..], map, matches);
                        }
                        return;
                    }
                },
                .lookup => |lookup| {
                    m.lookup.clearRetainingCapacity();

                    for (lookup.term.nodes) |node| {
                        switch (node) {
                            .atom => |v| {
                                const reg = m.v2r.get(v).?;
                                try m.lookup.append(
                                    oir.allocator,
                                    oir.union_find.find(m.registers.items[@intFromEnum(reg)]),
                                );
                            },
                            .constant => |c| {
                                const found_idx = oir.findNode(.constant(c)) orelse return; // can't match
                                const class_id = oir.findClass(found_idx);
                                try m.lookup.append(oir.allocator, class_id);
                            },
                            .builtin => |b| {
                                if (b.tag.location() != .src) @panic("can't have non-src builtin in source pattern");

                                switch (b.tag) {
                                    .known_pow2 => {
                                        const reg = m.v2r.get(b.expr).?;
                                        _ = reg;

                                        @panic("TODO");
                                    },
                                    else => unreachable,
                                }
                            },
                            .node => |n| {
                                var new_node = switch (n.tag) {
                                    .region => unreachable,
                                    inline else => |t| Node.init(t, undefined),
                                };
                                for (new_node.mutableOperands(oir), n.list) |*op, l| {
                                    op.* = m.lookup.items[@intFromEnum(l)];
                                }
                                const found_idx = oir.findNode(new_node) orelse return; // can't match
                                const class_id = oir.findClass(found_idx);
                                try m.lookup.append(oir.allocator, class_id);
                            },
                        }
                    }

                    const id = oir.union_find.find(m.registers.items[@intFromEnum(lookup.i)]);
                    if (m.lookup.getLastOrNull() != id) {
                        return; // no match
                    }
                },
                .compare => |compare| {
                    const a = m.registers.items[@intFromEnum(compare.i)];
                    const b = m.registers.items[@intFromEnum(compare.j)];
                    if (oir.union_find.find(a) != oir.union_find.find(b)) {
                        return; // no match
                    }
                },
                .scan => |scan| {
                    var iter = oir.classes.valueIterator();
                    while (iter.next()) |class| {
                        m.registers.shrinkRetainingCapacity(@intFromEnum(scan));
                        try m.registers.append(oir.allocator, class.index);
                        try m.run(oir, insts[i..], map, matches);
                    }
                    return;
                },
            }
        }

        // matched!

        var result: std.StringHashMapUnmanaged(Class.Index) = .{};
        var iter = map.iterator();
        while (iter.next()) |entry| {
            const class_id = m.registers.items[@intFromEnum(entry.value_ptr.*)];
            try result.put(oir.allocator, entry.key_ptr.*, class_id);
        }
        try matches.append(oir.allocator, result);
    }

    fn deinit(m: *Machine, allocator: std.mem.Allocator) void {
        m.registers.deinit(allocator);
        m.lookup.deinit(allocator);
    }
};

const Instruction = union(enum) {
    bind: struct { node: SExpr.Entry, i: Reg, out: Reg },
    lookup: struct { term: SExpr, i: Reg },
    compare: struct { i: Reg, j: Reg },
    scan: Reg,

    pub fn format(
        inst: Instruction,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (inst) {
            .bind => |b| try writer.print("bind({}, ${}, ${})", .{
                b.node,
                @intFromEnum(b.i),
                @intFromEnum(b.out),
            }),
            .lookup => |l| try writer.print("lookup({}, ${})", .{
                l.term,
                @intFromEnum(l.i),
            }),
            .compare => |c| try writer.print("compare(${} vs ${})", .{
                @intFromEnum(c.i),
                @intFromEnum(c.j),
            }),
            .scan => |s| try writer.print("scan(${})", .{@intFromEnum(s)}),
        }
    }

    fn deinit(inst: Instruction, allocator: std.mem.Allocator) void {
        switch (inst) {
            .lookup => |l| l.term.deinit(allocator),
            else => {},
        }
    }
};

const Reg = enum(u32) {
    _,

    pub fn add(r: *Reg, n: u32) void {
        r.* = @enumFromInt(@intFromEnum(r.*) + n);
    }
};

pub fn search(oir: *const Oir, rw: Rewrite) Result.Error![]const Result {
    const allocator = oir.allocator;

    var compiler: Compiler = .{
        .next_reg = @enumFromInt(0),
        .instructions = .{},
        .todo_nodes = .{},
        .v2r = .{},
        .free_vars = .{},
        .subtree_size = .{},
    };
    defer compiler.deinit(allocator);

    try compiler.compile(allocator, null, rw.from);

    var program = try compiler.extract(allocator);
    defer program.deinit(allocator);

    var matches: std.ArrayListUnmanaged(Result) = .{};
    try program.search(rw, oir, &matches);
    return matches.toOwnedSlice(allocator);
}

// pub fn multiSearch(oir: *const Oir, mrw: MultiRewrite) Result.Error!void {
//     const allocator = oir.allocator;

//     var compiler: Compiler = .{
//         .next_reg = @enumFromInt(0),
//         .instructions = .{},
//         .todo_nodes = .{},
//         .v2r = .{},
//         .free_vars = .{},
//         .subtree_size = .{},
//     };
//     defer compiler.deinit(allocator);

//     for (mrw.from) |rw| {
//         try compiler.compile(allocator, rw.atom, rw.pattern);
//     }

//     var program = try compiler.extract(allocator);
//     defer program.deinit(allocator);

//     std.debug.print("program: {any}\n", .{program.instructions});

//     var matches: std.ArrayListUnmanaged(Result) = .{};
//     try program.searchMulti(oir, &matches);

//     std.debug.print("num: {}\n", .{matches.items.len});
// }
