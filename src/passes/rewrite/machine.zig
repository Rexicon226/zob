//! Implements E-matching through an Abstract Virtual Machine.
//!
//! Based on this paper: https://leodemoura.github.io/files/ematching.pdf

const std = @import("std");
const Oir = @import("../../Oir.zig");
const rewrite = @import("../rewrite.zig");
const SExpr = @import("SExpr.zig");

const Node = Oir.Node;
const Class = Oir.Class;
const RewriteResult = rewrite.RewriteResult;
const Rewrite = rewrite.Rewrite;
const RewriteError = rewrite.RewriteError;

const Compiler = struct {
    next_reg: Reg,
    instructions: std.ArrayListUnmanaged(Instruction),
    todo_nodes: std.AutoHashMapUnmanaged(struct { SExpr.Index, Reg }, SExpr.Entry),
    v2r: std.StringHashMapUnmanaged(Reg),
    free_vars: std.ArrayListUnmanaged(std.StringArrayHashMapUnmanaged(void)),
    subtree_size: std.ArrayListUnmanaged(u64),

    const Todo = struct { SExpr.Index, Reg };

    fn compile(c: *Compiler, allocator: std.mem.Allocator, pattern: SExpr) !void {
        try c.loadPattern(allocator, pattern);
        const root = pattern.root();

        var next_out = c.next_reg;
        next_out.add(1);

        if (c.instructions.items.len != 0) {
            @panic("TODO");
        }
        try c.addTodo(allocator, pattern, root, c.next_reg);

        while (c.next()) |entry| {
            const todo, const node = entry;
            const id, const reg = todo;

            if (c.isGrounded(id) and node.operands().len != 0) {
                @panic("TODO");
            }

            try c.instructions.append(allocator, .{ .bind = .{
                .i = reg,
                .out = next_out,
                .node = node,
            } });
            next_out.add(@intCast(node.operands().len));

            for (node.operands(), 0..) |child, i| {
                try c.addTodo(
                    allocator,
                    pattern,
                    child,
                    @enumFromInt(@intFromEnum(reg) + i),
                );
            }
        }
        c.next_reg = next_out;
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
        c.free_vars = try .initCapacity(allocator, len);
        c.subtree_size = try .initCapacity(allocator, len);

        for (pattern.nodes) |node| {
            var free: std.StringArrayHashMapUnmanaged(void) = .{};
            var size: usize = 0;

            std.debug.print("node: {}\n", .{node.fmt(pattern)});

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
                    _ = j;
                    @panic("TODO");
                } else {
                    try c.v2r.put(allocator, v, reg);
                }
            },
            .node, .constant => try c.todo_nodes.put(allocator, .{ id, reg }, node),
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

const Program = struct {
    instructions: []const Instruction,
    map: std.StringHashMapUnmanaged(Reg),

    fn search(
        p: *Program,
        rw: Rewrite,
        oir: *const Oir,
        matches: *std.ArrayListUnmanaged(RewriteResult),
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
            }
        }
    }

    fn searchClass(
        p: *Program,
        oir: *const Oir,
        class: Class.Index,
        pattern: SExpr,
        matches: *std.ArrayListUnmanaged(RewriteResult),
    ) !void {
        std.debug.assert(oir.clean); // must be clean to search

        const allocator = oir.allocator;

        var machine: Machine = .{ .registers = .{} };
        defer machine.deinit(allocator);
        try machine.registers.append(allocator, class);

        var results: std.StringHashMapUnmanaged(Class.Index) = .{};
        try machine.run(oir, p.instructions, p.map, &results);

        if (results.count() > 0) {
            var result_iter = results.iterator();
            while (result_iter.next()) |entry| {
                std.debug.print("({s} in {}) ", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            std.debug.print("\n", .{});

            try matches.append(allocator, .{
                .bindings = results,
                .class = class,
                .pattern = pattern,
            });
        }
    }

    fn deinit(p: *Program, allocator: std.mem.Allocator) void {
        allocator.free(p.instructions);
        p.map.deinit(allocator);
    }
};

const Machine = struct {
    registers: std.ArrayListUnmanaged(Class.Index),

    fn run(
        m: *Machine,
        oir: *const Oir,
        insts: []const Instruction,
        map: std.StringHashMapUnmanaged(Reg),
        result: *std.StringHashMapUnmanaged(Class.Index),
    ) !void {
        for (insts, 1..) |inst, i| {
            switch (inst) {
                .bind => |bind| {
                    const class = oir.getClass(m.registers.items[@intFromEnum(bind.i)]);
                    for (class.bag.items) |node_idx| {
                        const node = oir.getNode(node_idx);
                        if (node.tag == bind.node.tag() and
                            node.operands(oir).len == bind.node.operands().len)
                        {
                            m.registers.shrinkRetainingCapacity(m.registers.items.len - @intFromEnum(bind.out));
                            for (node.operands(oir)) |id| {
                                try m.registers.append(oir.allocator, id);
                            }
                            // run for remaining instructions
                            try m.run(oir, insts[i..], map, result);
                        }
                        return;
                    }
                },
            }
        }

        var iter = map.iterator();
        while (iter.next()) |entry| {
            const class_id = m.registers.items[@intFromEnum(entry.value_ptr.*)];
            try result.put(oir.allocator, entry.key_ptr.*, class_id);
        }
    }

    fn deinit(m: *Machine, allocator: std.mem.Allocator) void {
        m.registers.deinit(allocator);
    }
};

const Instruction = union(enum) {
    bind: struct { node: SExpr.Entry, i: Reg, out: Reg },
};

const Reg = enum(u32) {
    _,

    pub fn add(r: *Reg, n: u32) void {
        r.* = @enumFromInt(@intFromEnum(r.*) + n);
    }
};

pub fn search(
    oir: *const Oir,
    matches: *std.ArrayListUnmanaged(RewriteResult),
    rw: Rewrite,
) RewriteError!void {
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

    try compiler.compile(allocator, rw.from);

    var program = try compiler.extract(allocator);
    defer program.deinit(allocator);

    try program.search(rw, oir, matches);
}
