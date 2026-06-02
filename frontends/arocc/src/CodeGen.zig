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
/// Map of function names to lambda id.
/// TODO: make into a unique enum
fn_ids: std.StringHashMapUnmanaged(u32),
/// Function names indexed by lambda id, used for asm labels in the backend.
fn_names: std.ArrayList([]const u8),
/// The id of the `lambda` currently being lowered, used to build its `param`s.
cur_fn: u32 = 0,
/// Predicate under which the currently-lowering path executes, relative to the
/// enclosing function/loop entry. Branches refine it. `return`/`break`/`continue`
/// capture it so multiple exists can be merged with gammas.
active: Oir.Class.Index,
/// Function-return exits captured during lowering.
returns: std.ArrayList(Return),
/// Stack of enclosing loops, holding their `break`/`continue` exits.
loops: std.ArrayList(LoopFrame),

const Error = error{OutOfMemory};
const SymbolTable = std.ArrayList(std.StringHashMapUnmanaged(Oir.Class.Index));

/// A `return` reached under path predicate `pred`, with its memory state and value.
const Return = struct {
    pred: Oir.Class.Index,
    mem: Oir.Class.Index,
    value: ?Oir.Class.Index,
};

/// A `break`/`continue` reached under `pred`, capturing the loop-carried values
/// (`vals[j]` is the value of the frame's `names[j]`) and the memory state.
const Exit = struct {
    pred: Oir.Class.Index,
    mem: Oir.Class.Index,
    vals: []Oir.Class.Index,
};

const LoopFrame = struct {
    names: []const []const u8,
    breaks: std.ArrayList(Exit),
    continues: std.ArrayList(Exit),
};

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
        .active = .start, // placeholder, set per-function in buildFn
        .returns = .empty,
        .loops = .empty,
        .fn_ids = .empty,
        .fn_names = .empty,
    };
}

pub fn build(cg: *CodeGen, io: std.Io, graphs: ?[]const u8) ![]Recursive {
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    // Assign every function an Id before lowering any body, so a `call` can name
    // its callee by Id even for forward references / recursion.
    for (cg.tree.root_decls.items) |node| {
        if (node_tags[@intFromEnum(node)] != .fn_def) continue;
        const func = node.get(tree).function;
        const name = tree.tokSlice(func.name_tok);
        if (cg.fn_ids.contains(name)) continue; // a prototype already reserved it
        try cg.fn_ids.put(cg.gpa, name, @intCast(cg.fn_names.items.len));
        try cg.fn_names.append(cg.gpa, name);
    }

    for (cg.tree.root_decls.items) |node| {
        switch (node_tags[@intFromEnum(node)]) {
            .fn_def => try cg.buildFn(node),
            .fn_proto, .typedef => {},
            else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(node)])}),
        }
    }

    try cg.oir.rebuild();

    try stdout.writeAll("unoptimized OIR:\n");
    try cg.oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    try cg.oir.optimize(io, .saturate, graphs);

    try stdout.writeAll("before extraction OIR:\n");
    try cg.oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    const recvs = try cg.oir.extract(.auto);

    try stdout.writeAll("optimized OIR:\n");
    for (recvs) |recv| {
        try recv.print(stdout);
        try stdout.writeAll("--\n");
    }
    try stdout.writeAll("end OIR\n");

    return recvs;
}

fn buildFn(cg: *CodeGen, decl: Tree.Node.Index) !void {
    const tree = cg.tree;

    switch (decl.get(tree)) {
        .function => |func| {
            const func_ty = func.qt.base(tree.comp).type.func;
            const id = cg.fn_ids.get(tree.tokSlice(func.name_tok)).?;
            cg.cur_fn = id;

            for (cg.symbol_table.items) |*s| s.deinit(cg.gpa);
            cg.symbol_table.clearRetainingCapacity();
            try cg.symbol_table.append(cg.gpa, .{});
            cg.node_to_class.clearRetainingCapacity();

            // param(id, 0) is the input memory state; arguments follow at 1..n.
            cg.mem_state = try cg.oir.add(.param(id, 0));
            for (func_ty.params, 0..) |param, i| {
                const name = cg.tree.tokSlice(param.name_tok);
                const node = try cg.oir.add(.param(id, @intCast(i + 1)));

                const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
                try latest.put(cg.gpa, name, node);
            }

            // The function body produces an optional return value plus the final
            // memory state.
            cg.active = try cg.oir.add(.constant(1));
            cg.returns.clearRetainingCapacity();
            const body = func.body.?;
            const falls_through = switch (body.get(tree)) {
                .compound_stmt => |c| try cg.buildSeq(c.body),
                else => try cg.buildSeq(&.{body}),
            };
            const is_void = func_ty.return_type.is(tree.comp, .void);

            // A fall-through end of the body is an implicit `return`.
            if (falls_through) {
                if (!is_void and cg.returns.items.len == 0)
                    @panic("TODO: non-void function falls through");
                if (is_void) try cg.returns.append(cg.gpa, .{
                    .pred = cg.active,
                    .mem = cg.mem_state,
                    .value = null,
                });
            }

            const mem, const value = try cg.mergeReturns();
            var results: std.ArrayList(Oir.Class.Index) = .empty;
            defer results.deinit(cg.gpa);
            try results.append(cg.gpa, mem);
            if (!is_void) try results.append(cg.gpa, value.?);

            const span = try cg.oir.listToSpan(results.items);
            const lambda = try cg.oir.add(.lambda(id, @intCast(func_ty.params.len), span));
            try cg.exits.append(cg.gpa, lambda);
        },
        .typedef => {},
        else => |t| std.debug.panic("TODO: {s}", .{@tagName(t)}),
    }
}

/// Lowers a statement sequence in order. Returns whether control can
/// fall through the following statement, false once a path definitely returns,
/// breaks or continues.
fn buildSeq(cg: *CodeGen, stmts: []const Tree.Node.Index) Error!bool {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    for (stmts) |stmt| {
        switch (stmt.get(tree)) {
            .return_stmt => |ret| {
                if (cg.loops.items.len != 0) @panic("TODO: return inside a loop");
                const value: ?Oir.Class.Index = switch (ret.operand) {
                    .expr => |idx| try cg.buildExpr(idx),
                    .none, .implicit => null,
                };
                try cg.returns.append(cg.gpa, .{ .pred = cg.active, .mem = cg.mem_state, .value = value });
                return false;
            },
            .break_stmt => {
                const frame = &cg.loops.items[cg.loops.items.len - 1];
                try frame.breaks.append(cg.gpa, try cg.captureExit(frame.names));
                return false;
            },
            .continue_stmt => {
                const frame = &cg.loops.items[cg.loops.items.len - 1];
                try frame.continues.append(cg.gpa, try cg.captureExit(frame.names));
                return false;
            },
            .compound_stmt => |compound| if (!try cg.buildSeq(compound.body)) return false,
            .if_stmt => |cond_br| if (!try cg.buildIf(cond_br)) return false,
            .while_stmt => |w| if (!try cg.buildLoop(w.cond, w.body, null)) return false,
            .for_stmt => |f| {
                // The init clause runs once, in the current scope, before the loop.
                switch (f.init) {
                    .decls => |decls| _ = try cg.buildSeq(decls),
                    .expr => |maybe| if (maybe) |e| try cg.buildExprStmt(e),
                }
                if (!try cg.buildLoop(f.cond, f.body, f.incr)) return false;
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
    return true;
}

/// Lowers a single statement that may be a `{ ... }` block.
fn buildBlock(cg: *CodeGen, node: Tree.Node.Index) Error!bool {
    return switch (node.get(cg.tree)) {
        .compound_stmt => |compound| cg.buildSeq(compound.body),
        else => cg.buildSeq(&.{node}),
    };
}

/// Lowers an `if`. Each arm runs on its own copy of the environmen t under
/// a refined `active` predicate, and the arms that fall through are merged with
/// gammas. Returns whether control can fall through past the `if`.
fn buildIf(cg: *CodeGen, cond_br: anytype) Error!bool {
    const pred = try cg.buildExpr(cond_br.cond);
    const outer = cg.active;
    const mem_before = cg.mem_state;
    const env_before = try cg.snapshotEnv();

    // then arm on the live environment.
    cg.node_to_class.clearRetainingCapacity();
    cg.active = try cg.andPred(outer, pred);
    const then_falls = try cg.buildBlock(cond_br.then_body);
    const then_mem = cg.mem_state;
    var then_env = cg.symbol_table;

    // else arm on a fresh copy of the pre-if environment.
    cg.symbol_table = env_before;
    cg.node_to_class.clearRetainingCapacity();
    cg.mem_state = mem_before;
    cg.active = try cg.andNot(outer, pred);
    const else_falls = if (cond_br.else_body) |e| try cg.buildBlock(e) else true;
    const else_mem = cg.mem_state; // `cg.symbol_table` is now the else environment

    if (then_falls and else_falls) {
        try cg.mergeEnvInto(pred, &then_env);
        cg.mem_state = try cg.gammaIfNe(pred, then_mem, else_mem);
        cg.active = outer;
        cg.freeEnv(&then_env);
        return true;
    }
    if (then_falls) {
        // Only the then path continues; adopt its environment.
        cg.freeEnv(&cg.symbol_table);
        cg.symbol_table = then_env;
        cg.mem_state = then_mem;
        cg.active = try cg.andPred(outer, pred);
        return true;
    }
    cg.freeEnv(&then_env);
    if (else_falls) {
        cg.active = try cg.andNot(outer, pred); // only the else path continues
        return true;
    }
    return false; // both arms terminate
}

/// Lowers a `while`/`for`. The loop carries the memory state (slot 0), every
/// in-scope variable , and an `exited` flag (last slot) that a `break` sets
/// so the test fails on the next iteration. `break`/`continue` exits are gathered
/// in a loop frame and merged into the next-iteration values. Always falls through.
fn buildLoop(
    cg: *CodeGen,
    cond: ?Tree.Node.Index,
    body: Tree.Node.Index,
    incr: ?Tree.Node.Index,
) Error!bool {
    const gpa = cg.gpa;

    var name_list: std.ArrayList([]const u8) = .empty;
    defer name_list.deinit(gpa);
    try cg.collectScopeNames(&name_list);
    const names = name_list.items;
    const nvars = names.len;
    const count: u32 = @intCast(nvars + 2); // memory (0), vars (1..nvars), exited (last)
    const exited = count - 1;

    const loop_id = cg.next_loop;
    cg.next_loop += 1;

    // TODO: terrible memory stuff, idc, cleanup later

    const args = try gpa.alloc(Oir.Class.Index, count);
    defer gpa.free(args);
    for (args, 0..) |*a, slot| a.* = try cg.oir.add(.loopvar(loop_id, @intCast(slot)));

    const inits = try gpa.alloc(Oir.Class.Index, count);
    defer gpa.free(inits);
    inits[0] = cg.mem_state;
    for (names, 0..) |name, j| inits[j + 1] = cg.findIdentifier(name).?.*;
    inits[exited] = try cg.oir.add(.constant(0));

    // Rebind every carried slot to its loopvar for the body and predicate.
    cg.mem_state = args[0];
    for (names, 0..) |name, j| cg.findIdentifier(name).?.* = args[j + 1];

    // Predicate continues while non-zero, and only while not yet broken.
    cg.node_to_class.clearRetainingCapacity();
    const cond_pred = if (cond) |c| try cg.buildExpr(c) else try cg.oir.add(.constant(1));
    const pred = try cg.andNot(cond_pred, args[exited]);

    try cg.loops.append(gpa, .{ .names = names, .breaks = .empty, .continues = .empty });

    // The body's path predicate is relative to the iteration's start.
    cg.node_to_class.clearRetainingCapacity();
    const saved_active = cg.active;
    cg.active = try cg.oir.add(.constant(1));
    const body_falls = try cg.buildBlock(body);

    const frame = &cg.loops.items[cg.loops.items.len - 1];
    // Falling off the body bottom loops back, exactly like `continue`.
    if (body_falls) try frame.continues.append(gpa, try cg.captureExit(names));
    var popped = cg.loops.pop().?;
    defer cg.freeFrame(&popped);
    cg.active = saved_active;

    const next_vals = try gpa.alloc(Oir.Class.Index, nvars);
    defer gpa.free(next_vals);
    const cont_vals = try gpa.alloc(Oir.Class.Index, nvars);
    defer gpa.free(cont_vals);

    var cont_mem: Oir.Class.Index = undefined;
    if (popped.continues.items.len > 0) {
        cont_mem = try cg.chainMerge(popped.continues.items, cont_vals);
        cg.mem_state = cont_mem;
        for (names, 0..) |name, j| cg.findIdentifier(name).?.* = cont_vals[j];
        if (incr) |inc| {
            cg.node_to_class.clearRetainingCapacity();
            try cg.buildExprStmt(inc);
        }
        cont_mem = cg.mem_state;
        for (names, 0..) |name, j| cont_vals[j] = cg.findIdentifier(name).?.*;
    } else {
        @memcpy(cont_vals, args[1..][0..nvars]);
        cont_mem = args[0];
    }

    var next_mem = cont_mem;
    @memcpy(next_vals, cont_vals);
    var broke = try cg.oir.add(.constant(0));
    if (popped.breaks.items.len > 0) {
        const brk_vals = try gpa.alloc(Oir.Class.Index, nvars);
        defer gpa.free(brk_vals);
        const brk_mem = try cg.chainMerge(popped.breaks.items, brk_vals);
        broke = try cg.sumPreds(popped.breaks.items);
        next_mem = try cg.gammaIfNe(broke, brk_mem, cont_mem);
        for (next_vals, brk_vals, cont_vals) |*n, b, c| n.* = try cg.gammaIfNe(broke, b, c);
    }

    const buf = try gpa.alloc(Oir.Class.Index, count * 3 + 1);
    defer gpa.free(buf);
    @memcpy(buf[0..count], args);
    @memcpy(buf[count .. 2 * count], inits);
    buf[2 * count] = pred;
    const nexts = buf[2 * count + 1 ..][0..count];
    nexts[0] = next_mem;
    @memcpy(nexts[1 .. 1 + nvars], next_vals);
    nexts[exited] = broke;

    const span = try cg.oir.listToSpan(buf);
    const theta = try cg.oir.add(.theta(loop_id, count, span));

    cg.mem_state = try cg.oir.add(.project(0, theta, .data));
    for (names, 0..) |name, j| {
        cg.findIdentifier(name).?.* = try cg.oir.add(.project(@intCast(j + 1), theta, .data));
    }
    cg.node_to_class.clearRetainingCapacity();
    return true;
}

fn captureExit(cg: *CodeGen, names: []const []const u8) !Exit {
    const vals = try cg.gpa.alloc(Oir.Class.Index, names.len);
    for (names, vals) |name, *v| v.* = cg.findIdentifier(name).?.*;
    return .{ .pred = cg.active, .mem = cg.mem_state, .vals = vals };
}

fn freeFrame(cg: *CodeGen, frame: *LoopFrame) void {
    for (frame.breaks.items) |e| cg.gpa.free(e.vals);
    for (frame.continues.items) |e| cg.gpa.free(e.vals);
    frame.breaks.deinit(cg.gpa);
    frame.continues.deinit(cg.gpa);
}

/// Merges a list of exits into one state by chaining gammas on their path
/// predicates. Returns the merged memory state and fills `out_vals` with the
/// merged carried values.
fn chainMerge(cg: *CodeGen, exits: []const Exit, out_vals: []Oir.Class.Index) !Oir.Class.Index {
    var mem = exits[exits.len - 1].mem;
    @memcpy(out_vals, exits[exits.len - 1].vals);
    var i = exits.len - 1;
    while (i > 0) {
        i -= 1;
        mem = try cg.gammaIfNe(exits[i].pred, exits[i].mem, mem);
        for (out_vals, exits[i].vals) |*o, v| o.* = try cg.gammaIfNe(exits[i].pred, v, o.*);
    }
    return mem;
}

/// The disjunction of exit predicates.
fn sumPreds(cg: *CodeGen, exits: []const Exit) !Oir.Class.Index {
    var acc = exits[0].pred;
    for (exits[1..]) |e| acc = try cg.oir.add(.binOp(.add, acc, e.pred));
    return acc;
}

fn mergeEnvInto(cg: *CodeGen, pred: Oir.Class.Index, then_env: *SymbolTable) !void {
    for (cg.symbol_table.items, 0..) |*else_scope, i| {
        var it = else_scope.iterator();
        while (it.next()) |entry| {
            const then_val = if (i < then_env.items.len) then_env.items[i].get(entry.key_ptr.*) else null;
            if (then_val) |tv| entry.value_ptr.* = try cg.gammaIfNe(pred, tv, entry.value_ptr.*);
        }
    }
}

fn gammaIfNe(cg: *CodeGen, pred: Oir.Class.Index, a: Oir.Class.Index, b: Oir.Class.Index) !Oir.Class.Index {
    return if (a == b) a else cg.oir.add(.gamma(pred, a, b));
}

fn andPred(cg: *CodeGen, a: Oir.Class.Index, b: Oir.Class.Index) !Oir.Class.Index {
    const one = try cg.oir.add(.constant(1));
    if (a == one) return b;
    if (b == one) return a;
    return cg.oir.add(.binOp(.@"and", a, b));
}

fn andNot(cg: *CodeGen, a: Oir.Class.Index, pred: Oir.Class.Index) !Oir.Class.Index {
    const zero = try cg.oir.add(.constant(0));
    return cg.andPred(a, try cg.oir.add(.binOp(.cmp_eq, pred, zero)));
}

fn mergeReturns(cg: *CodeGen) !struct { Oir.Class.Index, ?Oir.Class.Index } {
    const rs = cg.returns.items;
    var mem = rs[rs.len - 1].mem;
    var value = rs[rs.len - 1].value;
    var i = rs.len - 1;
    while (i > 0) {
        i -= 1;
        mem = try cg.gammaIfNe(rs[i].pred, rs[i].mem, mem);
        if (value) |v| value = try cg.oir.add(.gamma(rs[i].pred, rs[i].value.?, v));
    }
    return .{ mem, value };
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

    // Calls advance the memory state, so they must never be memoized. `.get`
    // normalizes the `call_expr`/`call_expr_one` raw tags into one `.call_expr`.
    switch (node_tags[@intFromEnum(expr)]) {
        .call_expr, .call_expr_one => return cg.buildCall(expr.get(tree).call_expr),
        else => {},
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

/// Lowers `foo(args...)` into a `call` node. The call reads the current memory
/// state and produces a tuple `(mem', result)`; we advance `mem_state` to `mem'`
/// and return `result`.
/// Lowers `foo(args...)` into a `call` node. The call reads the current memory
/// state and produces a tuple `(mem', result)`. We advance `mem_state` to `mem'`
/// and return `result`.
fn buildCall(cg: *CodeGen, call: Tree.Node.Call) Error!Oir.Class.Index {
    const callee = cg.fn_ids.get(cg.calleeName(call.callee)) orelse
        std.debug.panic("TODO: call to unknown function", .{});

    var body: std.ArrayList(Oir.Class.Index) = .empty;
    defer body.deinit(cg.gpa);
    try body.append(cg.gpa, undefined); // slot 0 reserved for the memory state
    for (call.args) |arg| try body.append(cg.gpa, try cg.buildExpr(arg));
    body.items[0] = cg.mem_state; // captured after args are evaluated

    const span = try cg.oir.listToSpan(body.items);
    const node = try cg.oir.add(.call(callee, span));
    cg.mem_state = try cg.oir.add(.project(0, node, .data));
    return cg.oir.add(.project(1, node, .data));
}

fn calleeName(cg: *CodeGen, idx: Tree.Node.Index) []const u8 {
    const tree = cg.tree;
    return switch (idx.get(tree)) {
        .cast => |c| cg.calleeName(c.operand),
        .paren_expr => |p| cg.calleeName(p.operand),
        .decl_ref_expr => |d| tree.tokSlice(d.name_tok),
        else => |t| std.debug.panic("TODO: callee {s}", .{@tagName(t)}),
    };
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
    cg.returns.deinit(allocator);
    cg.loops.deinit(allocator);
    cg.fn_ids.deinit(allocator);
    cg.fn_names.deinit(allocator);
}
