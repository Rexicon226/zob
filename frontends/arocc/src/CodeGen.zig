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
/// Monotonic source of unique `theta` loop ids.
next_loop: u32 = 0,

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

            // The function body produces an optional return value plus the final
            // memory state. Early returns are merged into a single exit via gammas.
            const body = func.body.?;
            const value = switch (body.get(tree)) {
                .compound_stmt => |c| try cg.buildSeq(c.body),
                else => try cg.buildSeq(&.{body}),
            };
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

/// Lowers a sequence of statments, returning the function's return value if the
/// sequence definitely returns, or `null` if control falls off the end.
///
/// Early returns are handled with continuation-style lowering. When a branch
/// statement is reached, the statements *after* it become the continuation that
/// runs on whichever arm falls through. Each arm therefore produces a value for
/// the whole tail, and the two are merged with a `gamma`.
fn buildSeq(cg: *CodeGen, stmts: []const Tree.Node.Index) Error!?Oir.Class.Index {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    for (stmts, 0..) |stmt, i| {
        const rest = stmts[i + 1 ..];
        switch (stmt.get(tree)) {
            .return_stmt => |ret| return switch (ret.operand) {
                .expr => |idx| try cg.buildExpr(idx),
                // A valueless return (`return;`, or the implicit end of a void function)
                // contributes no return value. The memory state carries the effects.
                .none, .implicit => null,
            },
            // A nested block and everything after it is just a longer sequence.
            .compound_stmt => |compound| return cg.buildConcat(compound.body, rest),
            .if_stmt => |cond_br| return cg.buildIf(cond_br, rest),
            .while_stmt => |w| return cg.buildLoop(w.cond, w.body, null, rest),
            .for_stmt => |f| {
                // The init clause runs once, in the current scope, before the loop.
                switch (f.init) {
                    .decls => |decls| _ = try cg.buildSeq(decls),
                    .expr => |maybe| if (maybe) |e| try cg.buildExprStmt(e),
                }
                return cg.buildLoop(f.cond, f.body, f.incr, rest);
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
            },
            .assign_expr => |assign| _ = try cg.buildAssign(assign.lhs, assign.rhs),
            else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(stmt)])}),
        }
    }
    return null;
}

/// Lowers `head ++ rest` as one sequence.
fn buildConcat(
    cg: *CodeGen,
    head: []const Tree.Node.Index,
    rest: []const Tree.Node.Index,
) Error!?Oir.Class.Index {
    var buf: std.ArrayList(Tree.Node.Index) = .empty;
    defer buf.deinit(cg.gpa);
    try buf.appendSlice(cg.gpa, head);
    try buf.appendSlice(cg.gpa, rest);
    return cg.buildSeq(buf.items);
}

/// Lowers an `if`, folding the continuation `rest` into both arms. Each arm
/// runs its own copy of the memory state and variable environment so effects in
/// one arm don't leak into the other. The arms' resulting memory states and
/// return values are merged with gammas.
fn buildIf(
    cg: *CodeGen,
    cond_br: anytype,
    rest: []const Tree.Node.Index,
) Error!?Oir.Class.Index {
    const predicate = try cg.buildExpr(cond_br.cond);
    const mem_before = cg.mem_state;
    const env_before = try cg.snapshotEnv();

    // The then arm runs on the live environment.
    cg.node_to_class.clearRetainingCapacity();
    cg.mem_state = mem_before;
    const then_value = try cg.buildArm(cond_br.then_body, rest);
    const then_mem = cg.mem_state;
    var then_env = cg.symbol_table;

    // The else arm runs on a fresh copy of the pre-if environment.
    cg.symbol_table = env_before;
    cg.node_to_class.clearRetainingCapacity();
    cg.mem_state = mem_before;
    const else_value = try cg.buildArm(cond_br.else_body, rest);
    const else_mem = cg.mem_state;

    // `cg.symbol_table` now holds the else arm's environment, which we keep live;
    // the then arm's copy is no longer needed.
    cg.freeEnv(&then_env);

    cg.mem_state = if (then_mem == else_mem)
        then_mem
    else
        try cg.oir.add(.gamma(predicate, then_mem, else_mem));

    if (then_value) |t| {
        if (else_value) |e| return try cg.oir.add(.gamma(predicate, t, e));
        return t; // else fell off the end (missing return on that path)
    }
    return else_value;
}

/// Lowers `arm ++ rest`, where `arm` may be absent (a missing `else`).
fn buildArm(
    cg: *CodeGen,
    arm: ?Tree.Node.Index,
    rest: []const Tree.Node.Index,
) Error!?Oir.Class.Index {
    const arm_stmt = arm orelse return cg.buildSeq(rest);
    return switch (arm_stmt.get(cg.tree)) {
        .compound_stmt => |compound| cg.buildConcat(compound.body, rest),
        else => cg.buildConcat(&.{arm_stmt}, rest),
    };
}

fn snapshotEnv(cg: *CodeGen) !SymbolTable {
    var copy: SymbolTable = .empty;
    errdefer freeEnv(cg, &copy);
    for (cg.symbol_table.items) |scope| {
        try copy.append(cg.gpa, try scope.clone(cg.gpa));
    }
    return copy;
}

fn freeEnv(cg: *CodeGen, env: *SymbolTable) void {
    for (env.items) |*s| s.deinit(cg.gpa);
    env.deinit(cg.gpa);
}

/// Lowers a `while`/`for` loop into a test-first `theta`, then folds the
/// continuation `rest` into the post-loop tail. Conservatively carries the
/// memory state (slot 0) plus every in-scope variable.
fn buildLoop(
    cg: *CodeGen,
    cond: ?Tree.Node.Index,
    body: Tree.Node.Index,
    incr: ?Tree.Node.Index,
    rest: []const Tree.Node.Index,
) Error!?Oir.Class.Index {
    const gpa = cg.gpa;

    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(gpa);
    try cg.collectScopeNames(&names);
    const count: u32 = @intCast(names.items.len + 1); // + memory state (slot 0)
    const total = count * 3 + 1;

    // TODO: cleanup pretty bad slice handling here, both in binding string
    // interning and with just placing directly into `extra`.

    // theta body = args ++ inits ++ [pred] ++ nexts.
    const buf = try gpa.alloc(Oir.Class.Index, total);
    defer gpa.free(buf);

    var inits: std.ArrayList(Oir.Class.Index) = .initBuffer(buf[count..][0..count]);
    try inits.appendBounded(cg.mem_state);
    for (names.items) |name| try inits.appendBounded(cg.findIdentifier(name).?.*);

    const loop_id = cg.next_loop;
    cg.next_loop += 1;

    var args: std.ArrayList(Oir.Class.Index) = .initBuffer(buf[0..count]);
    for (0..count) |slot| {
        const v = try cg.oir.add(.loopvar(loop_id, @intCast(slot)));
        try args.appendBounded(v);
    }

    cg.mem_state = args.items[0];
    for (names.items, 0..) |name, j| cg.findIdentifier(name).?.* = args.items[j + 1];

    // Predicate, the loop continues while it is non-zero.
    cg.node_to_class.clearRetainingCapacity();
    const pred = if (cond) |c| try cg.buildExpr(c) else try cg.oir.add(.constant(1));
    buf[count * 2] = pred;

    // Body, then the `for` increment.
    cg.node_to_class.clearRetainingCapacity();
    if (try cg.buildArm(body, &.{})) |_| @panic("TODO: return/break inside a loop");
    if (incr) |inc| try cg.buildExprStmt(inc);

    // Next-iteration values.
    var nexts: std.ArrayList(Oir.Class.Index) = .initBuffer(buf[count * 2 + 1 ..][0..count]);
    try nexts.appendBounded(cg.mem_state);
    for (names.items) |name| try nexts.appendBounded(cg.findIdentifier(name).?.*);

    const span = try cg.oir.listToSpan(buf);
    const theta = try cg.oir.add(.theta(loop_id, count, span));

    // The continuation runs on the loop's outputs (final value of each slot).
    cg.mem_state = try cg.oir.add(.project(0, theta, .data));
    for (names.items, 0..) |name, j| {
        cg.findIdentifier(name).?.* = try cg.oir.add(.project(@intCast(j + 1), theta, .data));
    }

    cg.node_to_class.clearRetainingCapacity();
    return cg.buildSeq(rest);
}

/// Evaluates an expression for its side effects.
fn buildExprStmt(cg: *CodeGen, expr: Tree.Node.Index) Error!void {
    switch (expr.get(cg.tree)) {
        .assign_expr => |a| _ = try cg.buildAssign(a.lhs, a.rhs),
        else => _ = try cg.buildExpr(expr),
    }
}

/// Collects every in-scope variable name (innermost scope first, deduped).
fn collectScopeNames(cg: *CodeGen, out: *std.ArrayList([]const u8)) !void {
    var i = cg.symbol_table.items.len;
    while (i > 0) {
        i -= 1;
        var it = cg.symbol_table.items[i].keyIterator();
        while (it.next()) |key| {
            const name = key.*;
            for (out.items) |existing| {
                if (std.mem.eql(u8, existing, name)) break;
            } else try out.append(cg.gpa, name);
        }
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
        .sub_expr,
        .mul_expr,
        .div_expr,
        .bit_and_expr,
        .shl_expr,
        .shr_expr,
        .equal_expr,
        .greater_than_expr,
        .less_than_expr,
        => |bin, t| bin: {
            const lhs = try cg.buildExpr(bin.lhs);
            const rhs = try cg.buildExpr(bin.rhs);
            break :bin switch (t) {
                .add_expr => try cg.oir.add(.binOp(.add, lhs, rhs)),
                .sub_expr => try cg.oir.add(.binOp(.sub, lhs, rhs)),
                .mul_expr => try cg.oir.add(.binOp(.mul, lhs, rhs)),
                .div_expr => try cg.oir.add(.binOp(.div_trunc, lhs, rhs)),
                .bit_and_expr => try cg.oir.add(.binOp(.@"and", lhs, rhs)),
                .shl_expr => try cg.oir.add(.binOp(.shl, lhs, rhs)),
                .shr_expr => try cg.oir.add(.binOp(.shr, lhs, rhs)),
                .equal_expr => try cg.oir.add(.binOp(.cmp_eq, lhs, rhs)),
                .greater_than_expr => try cg.oir.add(.binOp(.cmp_gt, lhs, rhs)),
                .less_than_expr => try cg.oir.add(.binOp(.cmp_lt, lhs, rhs)),
                else => unreachable,
            };
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
