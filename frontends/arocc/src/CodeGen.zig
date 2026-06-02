const std = @import("std");
const aro = @import("aro");
const zob = @import("zob");
const CodeGen = @This();

const Tree = aro.Tree;
const Oir = zob.Oir;
const Recursive = zob.Recursive;

gpa: std.mem.Allocator,
oir: *Oir,
tree: *const Tree,
exits: *std.ArrayList(Oir.Class.Index),
node_to_class: std.AutoHashMapUnmanaged(Tree.Node.Index, Oir.Class.Index),
symbol_table: SymbolTable,
/// Current memory state, passed through loads and stores.
mem_state: Oir.Class.Index,

const Error = error{OutOfMemory};
const SymbolTable = std.ArrayList(std.StringHashMapUnmanaged(Oir.Class.Index));

pub fn init(
    oir: *Oir,
    gpa: std.mem.Allocator,
    tree: *const Tree,
) !CodeGen {
    _ = try oir.add(.{
        .tag = .start,
        .data = .{ .list = .{ .start = 0, .end = 0 } },
    });

    var symbol_table: SymbolTable = .empty;
    try symbol_table.append(gpa, .{});

    return .{
        .gpa = gpa,
        .oir = oir,
        .tree = tree,
        .node_to_class = .{},
        .exits = &oir.exit_list,
        .symbol_table = symbol_table,
        .mem_state = .start, // just a placeholder, we set per-function in buildFn
    };
}

pub fn build(cg: *CodeGen, io: std.Io) !Recursive {
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    for (cg.tree.root_decls.items) |node| {
        switch (cg.tree.nodes.items(.tag)[@intFromEnum(node)]) {
            .fn_def => try cg.buildFn(node),
            .typedef => {},
            else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(node)])}),
        }
    }

    try cg.oir.rebuild();

    try stdout.writeAll("unoptimized OIR:\n");
    try cg.oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    try cg.oir.optimize(io, .saturate, false);

    try stdout.writeAll("before extraction OIR:\n");
    try cg.oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    const recv = try cg.oir.extract(.auto);

    try stdout.writeAll("optimized OIR:\n");
    try recv.print(stdout);
    try stdout.writeAll("end OIR\n");

    return recv;
}

fn buildFn(cg: *CodeGen, decl: Tree.Node.Index) !void {
    const tree = cg.tree;

    switch (decl.get(tree)) {
        // TODO: Oir should only represent one function - currently all functions
        // are put into the same Oir, which would easily create an invalid graph.
        .function => |func| {
            const func_ty = func.qt.base(tree.comp).type.func;

            // project(0, start) is the input memory state, with arguments following at 1..n.
            cg.mem_state = try cg.oir.add(.project(0, .start, .data));
            for (func_ty.params, 0..) |param, i| {
                const name = cg.tree.tokSlice(param.name_tok);
                const node = try cg.oir.add(.project(@intCast(i + 1), .start, .data));

                const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
                try latest.put(cg.gpa, name, node);
            }

            // The function body, or lambda, produces an optional return value
            // plus the final memory state.
            const value = try cg.buildStmt(func.body.?);
            const is_void = func_ty.return_type.is(tree.comp, .void);

            var results: std.ArrayList(Oir.Class.Index) = .empty;
            defer results.deinit(cg.gpa);
            try results.append(cg.gpa, cg.mem_state);
            if (!is_void) {
                const ret = value orelse @panic("TODO: non-void function falls through");
                try results.append(cg.gpa, ret);
            }

            const span = try cg.oir.listToSpan(results.items);
            const ret = try cg.oir.add(.ret(span));
            try cg.exits.append(cg.gpa, ret);
        },
        .typedef => {},
        else => |t| std.debug.panic("TODO: {s}", .{@tagName(t)}),
    }
}

/// Lowers a statement, returning the function's return value if this statment
/// (or one of its sub-statements) definitely returns, or `null` if control
/// falls through. We represent an `if` whos arms both return as a `gamma` node
/// that multiplexes over the two return values.
fn buildStmt(cg: *CodeGen, stmt: Tree.Node.Index) Error!?Oir.Class.Index {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    switch (stmt.get(tree)) {
        .return_stmt => |ret| return switch (ret.operand) {
            .expr => |idx| try cg.buildExpr(idx),
            // A valueless return (`return;`, or the implicit end of a void function)
            // contributes no return value. The memory state carries the effects.
            .none, .implicit => null,
        },
        .if_stmt => |cond_br| {
            const predicate = try cg.buildExpr(cond_br.cond);

            // Each arm gets its own copy of the incoming memory state so a store
            // in one arm doesn't leak into another (or out of the `if`). The
            // arms' resulting states are merged back with a gamma below.
            const mem_before = cg.mem_state;

            cg.mem_state = mem_before;
            const then_value = try cg.buildStmt(cond_br.then_body);
            const then_mem = cg.mem_state;

            cg.mem_state = mem_before;
            const else_value = if (cond_br.else_body) |else_body|
                try cg.buildStmt(else_body)
            else
                null;
            const else_mem = cg.mem_state;

            // Merge the memory effects of the two arms with a gamma node.
            // If no memory-related operations happened within, we can just skip
            // it, applying the `same-gamma` rewrite.
            cg.mem_state = if (then_mem == else_mem)
                then_mem
            else
                try cg.oir.add(.gamma(predicate, then_mem, else_mem));

            if (then_value) |then_class| {
                if (else_value) |else_class| {
                    return try cg.oir.add(.gamma(predicate, then_class, else_class));
                }
            }
            if (then_value == null and else_value == null) return null;

            @panic("TODO: if where only one arm returns");
        },
        .compound_stmt => |compound| {
            for (compound.body) |s| {
                if (try cg.buildStmt(s)) |value| return value; // rest is unreachable
            }
            return null;
        },
        .variable => |variable| {
            const rvalue = try cg.buildExpr(variable.initializer.?);
            const ident = tree.tokSlice(variable.name_tok);

            if (cg.findIdentifier(ident)) |existing| {
                existing.* = rvalue;
            } else {
                const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
                try latest.put(cg.gpa, ident, rvalue);
            }
            return null;
        },
        .assign_expr => |assign| {
            _ = try cg.buildAssign(assign.lhs, assign.rhs);
            return null;
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(stmt)])}),
    }
}

/// Lowers an assignment `lhs = rhs`, returning the assigned value. A store through a
/// pointer (`*p = v`) advances the memory state. Assigning a scalar local just rebinds
/// its SSA value in the symbol table.
fn buildAssign(cg: *CodeGen, lhs: Tree.Node.Index, rhs: Tree.Node.Index) !Oir.Class.Index {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);
    const value = try cg.buildExpr(rhs);

    switch (lhs.get(tree)) {
        .deref_expr => |deref| {
            // `*p = value`, store through the pointer, advancing the memory state.
            const address = try cg.buildExpr(deref.operand);
            const new_state = try cg.oir.add(.store(cg.mem_state, address, value));
            cg.mem_state = new_state;
        },
        .decl_ref_expr => |decl_ref| {
            // A scalar assignment just rebinds the SSA value.
            const name = tree.tokSlice(decl_ref.name_tok);
            if (cg.findIdentifier(name)) |existing| {
                existing.* = value;
            } else {
                const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
                try latest.put(cg.gpa, name, value);
            }
        },
        else => std.debug.panic("TODO: assign to {s}", .{@tagName(node_tags[@intFromEnum(lhs)])}),
    }

    return value;
}

fn buildExpr(cg: *CodeGen, expr: Tree.Node.Index) Error!Oir.Class.Index {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    if (cg.node_to_class.get(expr)) |c| return c;
    if (tree.value_map.get(expr)) |val| {
        return cg.buildConstant(expr, val);
    }

    const class = switch (expr.get(tree)) {
        .add_expr,
        .equal_expr,
        => |bin, t| bin: {
            const tag: Oir.Node.Tag = switch (t) {
                .add_expr => .add,
                .equal_expr => .cmp_eq,
                else => unreachable,
            };

            const lhs = try cg.buildExpr(bin.lhs);
            const rhs = try cg.buildExpr(bin.rhs);
            break :bin try cg.oir.add(.binOp(tag, lhs, rhs));
        },
        .int_literal => unreachable, // handled in the value_map above
        .cast => |cast| switch (cast.kind) {
            .lval_to_rval => try cg.buildLval(cast.operand),
            else => std.debug.panic("TODO: cast {s}", .{@tagName(cast.kind)}),
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(expr)])}),
    };

    try cg.node_to_class.put(cg.gpa, expr, class);
    return class;
}

fn buildLval(cg: *CodeGen, idx: Tree.Node.Index) Error!Oir.Class.Index {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    if (cg.node_to_class.get(idx)) |c| return c;

    const class = switch (idx.get(tree)) {
        .decl_ref_expr => |decl_ref| ref: {
            const name = tree.tokSlice(decl_ref.name_tok);
            if (cg.findIdentifier(name)) |ref_idx| {
                break :ref ref_idx.*;
            } else {
                @panic("TODO");
            }
        },
        .deref_expr => |deref| deref: {
            // Reading `*p`, load from the pointer using the current memory state.
            const address = try cg.buildExpr(deref.operand);
            break :deref try cg.oir.add(.load(cg.mem_state, address));
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(idx)])}),
    };

    // Loads must not be memoized as their value depends on the memory state at
    // the point of evaluation, which a later store may advance.
    if (node_tags[@intFromEnum(idx)] != .deref_expr) {
        try cg.node_to_class.put(cg.gpa, idx, class);
    }
    return class;
}

fn findIdentifier(cg: *CodeGen, ident: []const u8) ?*Oir.Class.Index {
    for (0..cg.symbol_table.items.len) |i| {
        const rev = cg.symbol_table.items.len - i - 1;
        if (cg.symbol_table.items[rev].getPtr(ident)) |class| return class;
    }
    return null;
}

fn buildConstant(cg: *CodeGen, idx: Tree.Node.Index, val: aro.Value) !Oir.Class.Index {
    const tree = cg.tree;
    const key = tree.comp.interner.get(val.ref());

    const class = switch (key) {
        .int => if (val.toInt(i64, tree.comp)) |int|
            try cg.oir.add(.constant(int))
        else {
            @panic("TODO");
        },
        else => @panic("TODO"),
    };

    try cg.node_to_class.put(cg.gpa, idx, class);
    return class;
}

pub fn deinit(cg: *CodeGen, allocator: std.mem.Allocator) void {
    cg.node_to_class.deinit(allocator);
    for (cg.symbol_table.items) |*table| {
        table.deinit(allocator);
    }
    cg.symbol_table.deinit(allocator);
}
