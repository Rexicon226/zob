const std = @import("std");
const aro = @import("aro");
const zob = @import("zob");
const CodeGen = @This();

const Tree = aro.Tree;
const Compilation = aro.Compilation;
const Oir = zob.Oir;
const Recursive = zob.Recursive;

gpa: std.mem.Allocator,
oir: *Oir,
tree: *const Tree,
comp: *const Compilation,

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
/// Return-value width of the function currently being lowereed (0 if void).
cur_ret_bits: u16 = 0,
cur_named: u32 = 0,
cur_sret: ?Oir.Class.Index = null,
/// Names whose address is taken somewhere in the current function.
addressed: std.StringHashMapUnmanaged(void),
/// Monotonic source of unique `alloca` ids.
next_alloca: u32 = 0,
/// Locals backed by a stack slot rather than an SSA value. We always put
/// arrays/structs in here. Their `symbol_table` binding is the slot address.
mem_vars: std.StringHashMapUnmanaged(MemVar),
/// Predicate under which the currently-lowering path executes.
active: Oir.Class.Index,
/// Function-return exits captured during lowering.
returns: std.ArrayList(Return),
/// Pending `goto` arrivals keyed by label name.
labels: std.StringHashMapUnmanaged(LabelInfo),
/// Stack of enclosing breadkable scopes. `break` targets the innermost
/// frame, `continue` the inner most loop frame.
frames: std.ArrayList(Frame),
globals: std.StringHashMapUnmanaged(GlobalInfo),
// TODO: we need to store these in a non-backend specific way
global_defs: std.ArrayList(zob.rv64.Global),
compound_dummy: ?Oir.Class.Index = null,
string_pool: std.AutoHashMapUnmanaged(u32, u32),
string_names: std.ArrayList([]u8),

const Error = error{OutOfMemory};
const SymbolTable = std.ArrayList(std.StringHashMapUnmanaged(Oir.Class.Index));

const MemVar = struct {
    bits: u16,
    aggregate: bool,
};

const GlobalInfo = struct {
    id: u32,
    bits: u16,
    aggregate: bool,
};

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

const Frame = struct {
    kind: enum { loop, @"switch" },
    names: []const []const u8,
    breaks: std.ArrayList(Exit),
    continues: std.ArrayList(Exit),
    returns: std.ArrayList(Return) = .empty,
};

const SwitchLabel = struct { start: Tree.Node.Index, end: ?Tree.Node.Index };

const SwitchGroup = struct {
    labels: std.ArrayList(SwitchLabel) = .empty,
    is_default: bool = false,
    stmts: std.ArrayList(Tree.Node.Index) = .empty,
};

const GotoArrival = struct {
    pred: Oir.Class.Index,
    mem: Oir.Class.Index,
    env: SymbolTable,
    depth: usize,
};

const LabelInfo = struct {
    arrivals: std.ArrayList(GotoArrival) = .empty,
    /// Set once the label is reached.
    resolved: bool = false,
};

pub fn init(
    oir: *Oir,
    gpa: std.mem.Allocator,
    tree: *const Tree,
    comp: *const Compilation,
) !CodeGen {
    _ = try oir.add(.{
        .tag = .start,
        .data = .{ .list = .{ .start = 0, .end = 0 } },
    });

    var symbol_table: SymbolTable = .empty;
    try symbol_table.append(gpa, .empty);

    return .{
        .gpa = gpa,
        .oir = oir,
        .tree = tree,
        .comp = comp,
        .node_to_class = .empty,
        .exits = &oir.exit_list,
        .symbol_table = symbol_table,
        .mem_state = .start, // just a placeholder, we set per-function in buildFn
        .active = .start, // placeholder, set per-function in buildFn
        .returns = .empty,
        .fn_ids = .empty,
        .labels = .empty,
        .mem_vars = .empty,
        .addressed = .empty,
        .frames = .empty,
        .fn_names = .empty,
        .globals = .empty,
        .global_defs = .empty,
        .string_pool = .empty,
        .string_names = .empty,
    };
}

pub fn deinit(cg: *CodeGen, allocator: std.mem.Allocator) void {
    cg.node_to_class.deinit(allocator);
    for (cg.symbol_table.items) |*table| {
        table.deinit(allocator);
    }
    cg.symbol_table.deinit(allocator);
    cg.returns.deinit(allocator);
    cg.clearLabels();
    cg.labels.deinit(allocator);
    cg.mem_vars.deinit(allocator);
    cg.addressed.deinit(allocator);
    cg.frames.deinit(allocator);
    cg.fn_ids.deinit(allocator);
    cg.fn_names.deinit(allocator);
    cg.globals.deinit(allocator);
    for (cg.global_defs.items) |g| switch (g.data) {
        .bytes => |p| {
            allocator.free(p.bytes);
            allocator.free(p.relocs);
        },
        else => {},
    };
    cg.global_defs.deinit(allocator);
    cg.string_pool.deinit(allocator);
    for (cg.string_names.items) |n| allocator.free(n);
    cg.string_names.deinit(allocator);
}

pub fn build(
    cg: *CodeGen,
    io: std.Io,
    config: struct {
        graphs: ?[]const u8,
        verbose_oir: bool,
    },
) ![]Recursive {
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    for (cg.tree.root_decls.items) |node| {
        if (node.get(tree) == .variable) {
            try cg.registerGlobal(node.get(tree).variable);
        }
    }

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
        switch (node.get(tree)) {
            .function => |func| if (func.body != null) try cg.buildFn(node),
            // Type defintions
            .typedef,
            .struct_decl,
            .union_decl,
            .enum_decl,
            .struct_forward_decl,
            .union_forward_decl,
            .enum_forward_decl,
            .variable,
            => {},
            else => std.debug.panic("TODO: root decl {s}", .{@tagName(node_tags[@intFromEnum(node)])}),
        }
    }

    // After we've created the Oir graph, rebuild to ensure it's in a clean
    // state before we start optimizing.
    try cg.oir.rebuild();

    if (config.verbose_oir) {
        try stderr.writeAll("unoptimized OIR:\n");
        try cg.oir.print(stderr);
        try stderr.writeAll("end OIR\n");
    }

    // Run optimization passes until no new changes can be found.
    try cg.oir.optimize(io, .saturate, config.graphs);

    if (config.verbose_oir) {
        try stderr.writeAll("before extraction OIR:\n");
        try cg.oir.print(stderr);
        try stderr.writeAll("end OIR\n");
    }

    // Extract the close-to-optimal path from the E-Graph for each function.
    const recvs = try cg.oir.extract(.auto);

    if (config.verbose_oir) {
        try stderr.writeAll("optimized OIR:\n");
        for (recvs) |recv| {
            try recv.print(stderr);
            try stderr.writeAll("--\n");
        }
        try stderr.writeAll("end OIR\n");
    }

    return recvs;
}

fn buildFn(cg: *CodeGen, decl: Tree.Node.Index) !void {
    const tree = cg.tree;

    switch (decl.get(tree)) {
        .function => |func| {
            const func_ty = func.qt.base(tree.comp).type.func;
            const id = cg.fn_ids.get(tree.tokSlice(func.name_tok)).?;
            cg.cur_fn = id;
            cg.cur_named = @intCast(func_ty.params.len);
            const returns_aggregate = !func_ty.return_type.is(tree.comp, .void) and
                cg.isAggregate(func_ty.return_type);
            cg.cur_ret_bits = if (func_ty.return_type.is(tree.comp, .void) or returns_aggregate)
                0
            else
                cg.widthOf(func_ty.return_type);

            for (cg.symbol_table.items) |*s| s.deinit(cg.gpa);
            cg.symbol_table.clearRetainingCapacity();
            try cg.symbol_table.append(cg.gpa, .{});
            cg.node_to_class.clearRetainingCapacity();
            cg.returns.clearRetainingCapacity();
            cg.clearLabels();
            cg.mem_vars.clearRetainingCapacity();
            cg.addressed.clearRetainingCapacity();

            const body = func.body.?;
            try cg.scanAddressed(body);

            // param(id, 0) is the input memory state (width 0); arguments follow at 1..n.
            cg.mem_state = try cg.oir.add(.param(id, 0, 0));
            for (func_ty.params, 0..) |param, i| {
                const name = cg.tree.tokSlice(param.name_tok);
                if (cg.isAggregate(param.qt)) {
                    // Binds the name to the pointer of the copy the caller passed in.
                    const ptr = try cg.oir.add(.param(id, @intCast(i + 1), 64));
                    try cg.bindVar(name, ptr);
                    const elem_bits: u16 = if (param.qt.get(tree.comp, .array)) |arr| cg.widthOf(arr.elem) else 0;
                    try cg.mem_vars.put(cg.gpa, name, .{ .bits = elem_bits, .aggregate = true });
                    continue;
                }
                const incoming = try cg.oir.add(.param(id, @intCast(i + 1), cg.widthOf(param.qt)));
                if (cg.addressed.contains(name)) {
                    const bits = cg.widthOf(param.qt);
                    const id_a = cg.next_alloca;
                    cg.next_alloca += 1;
                    const addr = try cg.oir.add(.alloca(id_a, @intCast(param.qt.sizeof(tree.comp)), param.qt.alignof(tree.comp)));
                    cg.mem_state = try cg.oir.add(.store(cg.mem_state, addr, incoming, bits));
                    try cg.bindVar(name, addr);
                    try cg.mem_vars.put(cg.gpa, name, .{ .bits = bits, .aggregate = false });
                } else {
                    try cg.bindVar(name, incoming);
                }
            }

            cg.cur_sret = if (returns_aggregate)
                try cg.oir.add(.param(id, @intCast(func_ty.params.len + 1), 64))
            else
                null;

            // The function body produces an optional return value plus the final
            // memory state.
            cg.active = try cg.oir.add(.constant(1));
            const falls_through = switch (body.get(tree)) {
                .compound_stmt => |c| try cg.buildSeq(c.body),
                else => try cg.buildSeq(&.{body}),
            };
            const produces_value = !func_ty.return_type.is(tree.comp, .void) and !returns_aggregate;

            if (falls_through) {
                const value: ?Oir.Class.Index =
                    if (produces_value) try cg.oir.add(.constant(0)) else null;
                try cg.returns.append(cg.gpa, .{
                    .pred = cg.active,
                    .mem = cg.mem_state,
                    .value = value,
                });
            }

            const mem, const value = try cg.mergeReturns();
            var results: std.ArrayList(Oir.Class.Index) = .empty;
            defer results.deinit(cg.gpa);
            try results.append(cg.gpa, mem);
            if (produces_value) try results.append(cg.gpa, value.?);

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
    var reachable = true;
    for (stmts) |stmt| {
        // Peel any leading labels (`A: B: real_stmt`), merging arrivals at each.
        var node = stmt;
        while (node.get(tree) == .labeled_stmt) {
            const l = node.get(tree).labeled_stmt;
            reachable = try cg.resolveLabel(l.label_tok, reachable);
            node = l.body;
        }
        if (!reachable) continue; // unreachable, non-labelled code is dropped
        reachable = try cg.buildStmt(node);
    }
    return reachable;
}

/// Lowers a single statement, returning whether control falls through past it.
fn buildStmt(cg: *CodeGen, stmt: Tree.Node.Index) Error!bool {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    switch (stmt.get(tree)) {
        .return_stmt => |ret| {
            const value: ?Oir.Class.Index = switch (ret.operand) {
                .expr => |idx| if (cg.cur_sret) |sret| copy: {
                    try cg.copyAggregate(sret, try cg.buildExpr(idx), idx.qt(tree));
                    break :copy null;
                } else try cg.buildExpr(idx),
                .none, .implicit => null,
            };
            const r: Return = .{ .pred = cg.active, .mem = cg.mem_state, .value = value };
            if (cg.innermostLoop()) |loop|
                try loop.returns.append(cg.gpa, r)
            else
                try cg.returns.append(cg.gpa, r);
            return false;
        },
        .break_stmt => {
            const frame = &cg.frames.items[cg.frames.items.len - 1];
            try frame.breaks.append(cg.gpa, try cg.captureExit(frame.names));
            return false;
        },
        .continue_stmt => {
            const frame = cg.innermostLoop().?;
            try frame.continues.append(cg.gpa, try cg.captureExit(frame.names));
            return false;
        },
        .goto_stmt => |g| {
            try cg.recordGoto(g.label_tok);
            return false;
        },
        .switch_stmt => |s| return cg.buildSwitch(s),
        .compound_stmt => |compound| return cg.buildSeq(compound.body),
        .if_stmt => |cond_br| return cg.buildIf(cond_br),
        .while_stmt => |w| return cg.buildLoop(w.cond, w.body, null, false),
        .do_while_stmt => |d| return cg.buildLoop(d.cond, d.body, null, true),
        .for_stmt => |f| {
            // The init clause runs once, in the current scope, before the loop.
            switch (f.init) {
                .decls => |decls| _ = try cg.buildSeq(decls),
                .expr => |maybe| if (maybe) |e| try cg.buildExprStmt(e),
            }
            return cg.buildLoop(f.cond, f.body, f.incr, false);
        },
        .variable => |variable| {
            try cg.buildVariable(variable);
            return true;
        },
        .assign_expr => |assign| {
            _ = try cg.buildAssign(assign.lhs, assign.rhs);
            return true;
        },
        .call_expr,
        .pre_inc_expr,
        .pre_dec_expr,
        .post_inc_expr,
        .post_dec_expr,
        .add_assign_expr,
        .sub_assign_expr,
        .mul_assign_expr,
        .div_assign_expr,
        .mod_assign_expr,
        .shl_assign_expr,
        .shr_assign_expr,
        .bit_and_assign_expr,
        .bit_or_assign_expr,
        .bit_xor_assign_expr,
        .comma_expr,
        .paren_expr,
        .builtin_call_expr,
        => {
            _ = try cg.buildExpr(stmt);
            return true;
        },
        .labeled_stmt => |l| return cg.buildStmt(l.body),
        .null_stmt => return true, // empty statement `;`
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(stmt)])}),
    }
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
    const pred = try cg.toBool(try cg.buildExpr(cond_br.cond));
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
    post_test: bool,
) Error!bool {
    const gpa = cg.gpa;

    var name_list: std.ArrayList([]const u8) = .empty;
    defer name_list.deinit(gpa);
    try cg.collectScopeNames(&name_list);
    const names = name_list.items;
    const nvars = names.len;
    // A loop that can `return` (itself, or a nested loop) carries the early
    // return out flag, plus for a value-returning function, a `retval` slot.
    const has_return = cg.containsReturn(body);
    const has_retval = has_return and cg.cur_ret_bits != 0;

    // TODO: cleanup bad slot logic, getting really messy
    var next_slot: u32 = @intCast(nvars + 1);
    const exited = next_slot;
    next_slot += 1;
    const returned = next_slot;
    if (has_return) next_slot += 1;
    const retval_slot = next_slot;
    if (has_retval) next_slot += 1;
    const first_slot = next_slot;
    if (post_test) next_slot += 1;
    const count = next_slot;

    const loop_id = cg.next_loop;
    cg.next_loop += 1;

    const inits = try gpa.alloc(Oir.Class.Index, count);
    defer gpa.free(inits);
    inits[0] = cg.mem_state;
    for (names, 0..) |name, j| inits[j + 1] = cg.findIdentifier(name).?.*;
    inits[exited] = try cg.oir.add(.constant(0));
    if (has_return) inits[returned] = try cg.oir.add(.constant(0));
    if (has_retval) inits[retval_slot] = try cg.oir.add(.constant(0));
    if (post_test) inits[first_slot] = try cg.oir.add(.constant(1));

    const widths = try gpa.alloc(u16, count);
    defer gpa.free(widths);
    widths[0] = 0;
    for (names, 0..) |_, j| widths[j + 1] = cg.oir.typeOf(inits[j + 1]);
    widths[exited] = 1;
    if (has_return) widths[returned] = 1;
    if (has_retval) widths[retval_slot] = cg.cur_ret_bits;
    if (post_test) widths[first_slot] = 1;

    const args = try gpa.alloc(Oir.Class.Index, count);
    defer gpa.free(args);
    for (args, 0..) |*a, slot| a.* = try cg.oir.add(.loopvar(loop_id, @intCast(slot), widths[slot]));

    // Rebind every carried slot to its loopvar for the body and predicate.
    cg.mem_state = args[0];
    for (names, 0..) |name, j| cg.findIdentifier(name).?.* = args[j + 1];

    // Predicate continues while non-zero, and only while not yet broken.
    cg.node_to_class.clearRetainingCapacity();
    const cond_pred = if (cond) |c| try cg.toBool(try cg.buildExpr(c)) else try cg.oir.add(.constant(1));
    const gated = if (post_test)
        try cg.oir.add(.gamma(args[first_slot], try cg.oir.add(.constant(1)), cond_pred))
    else
        cond_pred;
    var pred = try cg.andNot(gated, args[exited]);
    if (has_return) pred = try cg.andNot(pred, args[returned]);

    try cg.frames.append(gpa, .{ .kind = .loop, .names = names, .breaks = .empty, .continues = .empty });

    // The body's path predicate is relative to the iteration's start.
    cg.node_to_class.clearRetainingCapacity();
    const saved_active = cg.active;
    cg.active = try cg.oir.add(.constant(1));
    const body_falls = try cg.buildBlock(body);

    const frame = &cg.frames.items[cg.frames.items.len - 1];
    // Falling off the body bottom loops back, exactly like `continue`.
    if (body_falls) try frame.continues.append(gpa, try cg.captureExit(names));
    var popped = cg.frames.pop().?;
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

    var returned_flag = try cg.oir.add(.constant(0));
    var retval_value = if (has_retval) try cg.oir.add(.constant(0)) else undefined;
    if (popped.returns.items.len > 0) {
        const ret_mem, const ret_value = try cg.mergeReturnList(popped.returns.items);
        returned_flag = popped.returns.items[0].pred;
        for (popped.returns.items[1..]) |r| {
            returned_flag = try cg.oir.add(.binOp(.add, returned_flag, r.pred));
        }
        next_mem = try cg.gammaIfNe(returned_flag, ret_mem, next_mem);
        if (has_retval) retval_value = ret_value.?;
    }

    // theta body = args ++ inits ++ [pred] ++ nexts.
    const buf = try gpa.alloc(Oir.Class.Index, count * 3 + 1);
    defer gpa.free(buf);
    @memcpy(buf[0..count], args);
    @memcpy(buf[count .. 2 * count], inits);
    buf[2 * count] = pred;
    const nexts = buf[2 * count + 1 ..][0..count];
    nexts[0] = next_mem;
    @memcpy(nexts[1 .. 1 + nvars], next_vals);
    nexts[exited] = broke;
    if (has_return) nexts[returned] = returned_flag;
    if (has_retval) nexts[retval_slot] = retval_value;
    if (post_test) nexts[first_slot] = try cg.oir.add(.constant(0));

    const span = try cg.oir.listToSpan(buf);
    const theta = try cg.oir.add(.theta(loop_id, count, span));

    cg.mem_state = try cg.oir.add(.project(0, theta, .data, 0));
    for (names, 0..) |name, j| {
        cg.findIdentifier(name).?.* = try cg.oir.add(.project(@intCast(j + 1), theta, .data, widths[j + 1]));
    }
    cg.node_to_class.clearRetainingCapacity();

    if (popped.returns.items.len > 0) {
        const proj_returned = try cg.oir.add(.project(returned, theta, .data, 1));
        const proj_retval: ?Oir.Class.Index = if (has_retval)
            try cg.oir.add(.project(retval_slot, theta, .data, cg.cur_ret_bits))
        else
            null;
        const ret = Return{
            .pred = try cg.andPred(saved_active, proj_returned),
            .mem = cg.mem_state,
            .value = proj_retval,
        };
        if (cg.innermostLoop()) |outer|
            try outer.returns.append(gpa, ret)
        else
            try cg.returns.append(gpa, ret);
        cg.active = try cg.andNot(saved_active, proj_returned);
    }
    return true;
}

/// Lowers a `switch` as a set of mutally-exlusive predicated arms.
///
/// The controlling value is compared against each case label, the matching arm
/// runs on its own copy of the environment, and the arms' fall-through ends
/// plus every captured `break` are merged into this contiuation.
///
/// TODO: doesn't support fallthrough between non-empty cases, they must all
/// break or be the last group. unsure how to do cleanly yet.
fn buildSwitch(cg: *CodeGen, sw: anytype) Error!bool {
    const gpa = cg.gpa;
    const value = try cg.buildExpr(sw.cond);
    const uns = cg.unsignedQt(sw.cond.qt(cg.tree));

    var groups: std.ArrayList(SwitchGroup) = .empty;
    defer {
        for (groups.items) |*g| {
            g.labels.deinit(gpa);
            g.stmts.deinit(gpa);
        }
        groups.deinit(gpa);
    }
    switch (sw.body.get(cg.tree)) {
        .compound_stmt => |c| for (c.body) |item| try cg.flattenSwitch(item, &groups),
        else => try cg.flattenSwitch(sw.body, &groups),
    }

    var name_list: std.ArrayList([]const u8) = .empty;
    defer name_list.deinit(gpa);
    try cg.collectScopeNames(&name_list);
    const names = name_list.items;

    // In the first pass, each group's match predicate plus the disjunction of
    // all case labels, which we use for the `default` and the no-match fall-through.
    const preds = try gpa.alloc(Oir.Class.Index, groups.items.len);
    defer gpa.free(preds);
    var any_case = try cg.oir.add(.constant(0));
    for (groups.items, preds) |g, *p| {
        var acc = try cg.oir.add(.constant(0));
        for (g.labels.items) |label| {
            const m = try cg.switchLabelPred(value, label, uns);
            acc = try cg.oir.add(.binOp(.add, acc, m));
            any_case = try cg.oir.add(.binOp(.add, any_case, m));
        }
        p.* = acc;
    }
    const not_any = try cg.notPred(any_case);

    // Snapshot that each arm will be running on.
    var env0 = try cg.snapshotEnv();
    defer cg.freeEnv(&env0);
    const mem0 = cg.mem_state;
    const active0 = cg.active;

    try cg.frames.append(gpa, .{ .kind = .@"switch", .names = names, .breaks = .empty, .continues = .empty });

    // Lower each arm under its predicate on a copy of the environment.
    for (groups.items, preds, 0..) |g, p, i| {
        const arm_pred = if (g.is_default)
            try cg.oir.add(.binOp(.add, p, not_any))
        else
            p;

        cg.freeEnv(&cg.symbol_table);
        cg.symbol_table = try cg.cloneEnv(env0);
        cg.node_to_class.clearRetainingCapacity();
        cg.mem_state = mem0;
        cg.active = try cg.andPred(active0, arm_pred);

        const falls = try cg.buildSeq(g.stmts.items);
        if (falls) {
            if (i + 1 != groups.items.len) @panic("TODO: switch case fall-through");
            const frame = &cg.frames.items[cg.frames.items.len - 1];
            try frame.breaks.append(gpa, try cg.captureExit(names));
        }
    }

    var popped = cg.frames.pop().?;
    defer cg.freeFrame(&popped);

    const has_default = blk: {
        for (groups.items) |g| if (g.is_default) break :blk true;
        break :blk false;
    };
    // Without a `default`, values matching no case skip the switch entirely,
    // carrying the entry state through unchanged.
    if (!has_default) {
        const vals = try gpa.alloc(Oir.Class.Index, names.len);
        for (names, vals) |name, *v| v.* = findIn(&env0, name).?;
        try popped.breaks.append(gpa, .{
            .pred = try cg.andPred(active0, not_any),
            .mem = mem0,
            .vals = vals,
        });
    }

    // Merge every exit (breaks + fall-throughs + no-match) into the continuation.
    cg.freeEnv(&cg.symbol_table);
    cg.symbol_table = try cg.cloneEnv(env0);
    if (popped.breaks.items.len == 0) {
        cg.mem_state = mem0;
        cg.active = active0;
        return false; // every path returns; nothing leaves the switch
    }
    const out_vals = try gpa.alloc(Oir.Class.Index, names.len);
    defer gpa.free(out_vals);
    cg.mem_state = try cg.chainMerge(popped.breaks.items, out_vals);
    for (names, out_vals) |name, v| cg.findIdentifier(name).?.* = v;
    cg.active = try cg.sumPreds(popped.breaks.items);
    cg.node_to_class.clearRetainingCapacity();
    return true;
}

/// Recursively flattens a switch-body statement into `groups`: `case`/`default`
/// labels open (or extend) the current group, and any other statement is appended
/// to it. Consecutive labels with no intervening statements share one group.
fn flattenSwitch(cg: *CodeGen, node: Tree.Node.Index, groups: *std.ArrayList(SwitchGroup)) Error!void {
    switch (node.get(cg.tree)) {
        .case_stmt => |c| {
            try cg.openLabel(groups, .{ .start = c.start, .end = c.end }, false);
            try cg.flattenSwitch(c.body, groups);
        },
        .default_stmt => |d| {
            try cg.openLabel(groups, undefined, true);
            try cg.flattenSwitch(d.body, groups);
        },
        else => {
            const g = try cg.currentGroup(groups);
            try g.stmts.append(cg.gpa, node);
        },
    }
}

/// Opens a new group when the current one already has statements (a new label run
/// begins), else extends it (consecutive labels share a body).
fn openLabel(cg: *CodeGen, groups: *std.ArrayList(SwitchGroup), label: SwitchLabel, is_default: bool) !void {
    const need_new = groups.items.len == 0 or groups.items[groups.items.len - 1].stmts.items.len > 0;
    if (need_new) try groups.append(cg.gpa, .{});
    const g = &groups.items[groups.items.len - 1];
    if (is_default) g.is_default = true else try g.labels.append(cg.gpa, label);
}

fn currentGroup(cg: *CodeGen, groups: *std.ArrayList(SwitchGroup)) !*SwitchGroup {
    if (groups.items.len == 0) try groups.append(cg.gpa, .{}); // statements before any label
    return &groups.items[groups.items.len - 1];
}

/// The (0/1) predicate that `value` matches a single case label or `lo ... hi` range.
fn switchLabelPred(cg: *CodeGen, value: Oir.Class.Index, label: SwitchLabel, uns: bool) !Oir.Class.Index {
    const lo = try cg.buildExpr(label.start);
    if (label.end) |end_node| {
        const hi = try cg.buildExpr(end_node);
        const lt = try cg.oir.add(.binOp(if (uns) .cmp_ult else .cmp_lt, value, lo));
        const gt = try cg.oir.add(.binOp(if (uns) .cmp_ugt else .cmp_gt, value, hi));
        return cg.andPred(try cg.notPred(lt), try cg.notPred(gt)); // lo <= value <= hi
    }
    return cg.oir.add(.binOp(.cmp_eq, value, lo));
}

/// Logical negation of a boolean class: `p == 0`.
fn notPred(cg: *CodeGen, p: Oir.Class.Index) !Oir.Class.Index {
    const zero = try cg.oir.add(.constant(0));
    return cg.oir.add(.binOp(.cmp_eq, p, zero));
}

fn toBool(cg: *CodeGen, v: Oir.Class.Index) !Oir.Class.Index {
    const zero = try cg.oir.add(.constant(0));
    return cg.oir.add(.binOp(.cmp_ult, zero, v));
}

fn captureExit(cg: *CodeGen, names: []const []const u8) !Exit {
    const vals = try cg.gpa.alloc(Oir.Class.Index, names.len);
    for (names, vals) |name, *v| v.* = cg.findIdentifier(name).?.*;
    return .{ .pred = cg.active, .mem = cg.mem_state, .vals = vals };
}

fn freeFrame(cg: *CodeGen, frame: *Frame) void {
    for (frame.breaks.items) |e| cg.gpa.free(e.vals);
    for (frame.continues.items) |e| cg.gpa.free(e.vals);
    frame.breaks.deinit(cg.gpa);
    frame.continues.deinit(cg.gpa);
    frame.returns.deinit(cg.gpa);
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

/// The innermost enclosing loop frame (skipping switches), or null. `continue`
/// targets this; the `return`-in-loop guard checks it.
fn innermostLoop(cg: *CodeGen) ?*Frame {
    var i = cg.frames.items.len;
    while (i > 0) {
        i -= 1;
        if (cg.frames.items[i].kind == .loop) return &cg.frames.items[i];
    }
    return null;
}

/// Records a `goto`: captures the live state under the current predicate as an
/// arrival at the target label. A jump to an already-resolved label is backward
/// (would form a loop) and is not yet supported.
fn recordGoto(cg: *CodeGen, label_tok: anytype) !void {
    const name = cg.tree.tokSlice(label_tok);
    const gop = try cg.labels.getOrPut(cg.gpa, name);
    if (!gop.found_existing) gop.value_ptr.* = .{};
    if (gop.value_ptr.resolved) @panic("TODO: backward goto");
    try gop.value_ptr.arrivals.append(cg.gpa, .{
        .pred = cg.active,
        .mem = cg.mem_state,
        .env = try cg.snapshotEnv(),
        .depth = cg.frames.items.len,
    });
}

/// Resolves a label: merges every `goto` arrival (and the fall-through path, if
/// `reachable`) into the live state, and returns whether the label is reachable.
/// Gotos crossing a loop/switch boundary (different frame depth) are unsupported.
fn resolveLabel(cg: *CodeGen, label_tok: anytype, reachable: bool) !bool {
    const gpa = cg.gpa;
    const name = cg.tree.tokSlice(label_tok);
    // Ensure an entry exists and mark it resolved, so a later `goto` to this label
    // is recognized as a backward jump even if nothing targeted it yet.
    const gop = try cg.labels.getOrPut(gpa, name);
    if (!gop.found_existing) gop.value_ptr.* = .{};
    const info = gop.value_ptr;
    info.resolved = true;
    const arrivals = info.arrivals.items;
    for (arrivals) |a| {
        if (a.depth != cg.frames.items.len) @panic("TODO: goto across a loop/switch boundary");
    }
    if (arrivals.len == 0) return reachable;

    var name_list: std.ArrayList([]const u8) = .empty;
    defer name_list.deinit(gpa);
    try cg.collectScopeNames(&name_list);
    const names = name_list.items;

    // Build a contributor per incoming edge (fall-through + each arrival), then
    // chain-merge them. The edges are mutually exclusive control paths.
    var exits: std.ArrayList(Exit) = .empty;
    defer {
        for (exits.items) |e| gpa.free(e.vals);
        exits.deinit(gpa);
    }
    if (reachable) try exits.append(gpa, try cg.captureExit(names));
    for (arrivals) |a| {
        const vals = try gpa.alloc(Oir.Class.Index, names.len);
        for (names, vals) |nm, *v| v.* = findIn(&a.env, nm) orelse cg.findIdentifier(nm).?.*;
        try exits.append(gpa, .{ .pred = a.pred, .mem = a.mem, .vals = vals });
    }

    const out = try gpa.alloc(Oir.Class.Index, names.len);
    defer gpa.free(out);
    cg.mem_state = try cg.chainMerge(exits.items, out);
    for (names, out) |nm, v| cg.findIdentifier(nm).?.* = v;
    cg.active = try cg.sumPreds(exits.items);
    cg.node_to_class.clearRetainingCapacity();

    for (info.arrivals.items) |*a| cg.freeEnv(&a.env);
    info.arrivals.clearRetainingCapacity();
    return true;
}

/// Frees and clears all pending label arrivals (per-function reset / teardown).
fn clearLabels(cg: *CodeGen) void {
    var it = cg.labels.iterator();
    while (it.next()) |entry| {
        for (entry.value_ptr.arrivals.items) |*a| cg.freeEnv(&a.env);
        entry.value_ptr.arrivals.deinit(cg.gpa);
    }
    cg.labels.clearRetainingCapacity();
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
    return cg.mergeReturnList(cg.returns.items);
}

fn mergeValue(cg: *CodeGen, r: Return, want: bool) !?Oir.Class.Index {
    if (!want) return null;
    return r.value orelse try cg.oir.add(.constant(0));
}

fn mergeReturnList(cg: *CodeGen, rs: []const Return) !struct { Oir.Class.Index, ?Oir.Class.Index } {
    // If any path returns a value, the function is value-producing.
    const wants_value = for (rs) |r| {
        if (r.value != null) break true;
    } else false;

    var mem = rs[rs.len - 1].mem;
    var value = try cg.mergeValue(rs[rs.len - 1], wants_value);
    var i = rs.len - 1;
    while (i > 0) : (i -= 1) {
        mem = try cg.gammaIfNe(rs[i].pred, rs[i].mem, mem);
        if (wants_value) {
            const new = try cg.mergeValue(rs[i], wants_value);
            value = try cg.oir.add(.gamma(rs[i].pred, new.?, value.?));
        }
    }
    return .{ mem, value };
}

/// Whether a statement subtree contains a `return`.
fn containsReturn(cg: *CodeGen, node: Tree.Node.Index) bool {
    return switch (node.get(cg.tree)) {
        .return_stmt => true,
        .compound_stmt => |c| {
            for (c.body) |s| if (cg.containsReturn(s)) return true;
            return false;
        },
        .if_stmt => |i| cg.containsReturn(i.then_body) or
            (i.else_body != null and cg.containsReturn(i.else_body.?)),
        .while_stmt => |w| cg.containsReturn(w.body),
        .do_while_stmt => |d| cg.containsReturn(d.body),
        .for_stmt => |f| cg.containsReturn(f.body),
        .switch_stmt => |s| cg.containsReturn(s.body),
        .case_stmt => |c| cg.containsReturn(c.body),
        .default_stmt => |d| cg.containsReturn(d.body),
        .labeled_stmt => |l| cg.containsReturn(l.body),
        else => false,
    };
}

fn snapshotEnv(cg: *CodeGen) !SymbolTable {
    return cg.cloneEnv(cg.symbol_table);
}

fn cloneEnv(cg: *CodeGen, src: SymbolTable) !SymbolTable {
    var copy: SymbolTable = .empty;
    errdefer freeEnv(cg, &copy);
    for (src.items) |scope| {
        try copy.append(cg.gpa, try scope.clone(cg.gpa));
    }
    return copy;
}

fn findIn(env: *const SymbolTable, name: []const u8) ?Oir.Class.Index {
    var i = env.items.len;
    while (i > 0) {
        i -= 1;
        if (env.items[i].get(name)) |c| return c;
    }
    return null;
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
    const value = try cg.buildExpr(rhs);

    const lhs_qt = lhs.qt(tree);
    if (cg.isAggregate(lhs_qt)) {
        const dst = try cg.buildAddress(lhs);
        try cg.copyAggregate(dst, value, lhs_qt);
        return value;
    }

    try cg.storeToScalarLval(lhs, value);
    return value;
}

fn storeToScalarLval(cg: *CodeGen, lhs: Tree.Node.Index, value: Oir.Class.Index) Error!void {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    if (try cg.bitFieldOf(lhs)) |bf| {
        try cg.storeBitField(bf, value);
        return;
    }

    // Stores narrow the (possibly width-polymorphic) value to the destination
    // width, so e.g. `s.f = 1` writes only the field's bytes rather than 8.
    const store_bits = cg.widthOf(lhs.qt(tree));
    const stored = try cg.coerceTo(value, store_bits);

    switch (lhs.get(tree)) {
        // A scalar SSA local just rebinds its value; a stack-backed scalar is stored.
        .decl_ref_expr => |decl_ref| {
            const name = tree.tokSlice(decl_ref.name_tok);
            if (cg.mem_vars.get(name) == null and cg.globals.get(name) == null) {
                if (cg.findIdentifier(name)) |existing| {
                    existing.* = value;
                } else {
                    const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
                    try latest.put(cg.gpa, name, value);
                }
                return;
            }
            const address = try cg.buildAddress(lhs);
            cg.mem_state = try cg.oir.add(.store(cg.mem_state, address, stored, store_bits));
        },
        // Stores through a computed address (`*p`, `a[i]`, `s.f`), advancing memory.
        .deref_expr,
        .array_access_expr,
        .member_access_expr,
        .member_access_ptr_expr,
        .paren_expr,
        => {
            const address = try cg.buildAddress(lhs);
            cg.mem_state = try cg.oir.add(.store(cg.mem_state, address, stored, store_bits));
        },
        else => std.debug.panic("TODO: assign to {s}", .{@tagName(node_tags[@intFromEnum(lhs)])}),
    }
}

fn buildIncDec(cg: *CodeGen, operand: Tree.Node.Index, is_inc: bool, is_pre: bool) Error!Oir.Class.Index {
    const tree = cg.tree;
    const qt = operand.qt(tree);

    const old = try cg.buildLval(operand);

    const step: i64 = if (qt.get(tree.comp, .pointer)) |p| @intCast(cg.sizeOfBytes(p.child)) else 1;
    const delta = try cg.oir.add(.constant(step));
    const new = try cg.oir.add(.binOp(if (is_inc) .add else .sub, old, delta));

    try cg.storeToScalarLval(operand, new);
    return if (is_pre) new else old;
}

fn buildVariable(cg: *CodeGen, variable: anytype) Error!void {
    const tree = cg.tree;
    const comp = cg.tree.comp;
    const ident = tree.tokSlice(variable.name_tok);
    const qt = variable.qt;

    if (cg.isAggregate(qt)) {
        const total: u32 = @intCast(qt.sizeof(comp));
        const alignment: u32 = qt.alignof(comp);
        const elem_bits: u16 = if (qt.get(comp, .array)) |arr| cg.widthOf(arr.elem) else 0;
        const id = cg.next_alloca;
        cg.next_alloca += 1;
        const addr = try cg.oir.add(.alloca(id, total, alignment));
        try cg.bindVar(ident, addr);
        try cg.mem_vars.put(cg.gpa, ident, .{ .bits = elem_bits, .aggregate = true });
        if (variable.initializer) |init_node| try cg.buildAggregateInit(addr, qt, init_node);
        return;
    }

    if (cg.addressed.contains(ident)) {
        const bits = cg.widthOf(qt);
        const id = cg.next_alloca;
        cg.next_alloca += 1;
        const addr = try cg.oir.add(.alloca(id, @intCast(qt.sizeof(comp)), qt.alignof(comp)));
        try cg.bindVar(ident, addr);
        try cg.mem_vars.put(cg.gpa, ident, .{ .bits = bits, .aggregate = false });
        if (variable.initializer) |init_node| {
            const v = try cg.coerceTo(try cg.buildExpr(init_node), bits);
            cg.mem_state = try cg.oir.add(.store(cg.mem_state, addr, v, bits));
        }
        return;
    }

    const rvalue = if (variable.initializer) |init_node|
        try cg.buildExpr(init_node)
    else
        // TODO: undefined here?
        try cg.oir.add(.constantTyped(0, cg.widthOf(qt)));
    try cg.bindVar(ident, rvalue);
}

fn scanAddressed(cg: *CodeGen, node: Tree.Node.Index) Error!void {
    const tree = cg.tree;
    switch (node.get(tree)) {
        .addr_of_expr => |u| {
            if (cg.lvalueName(u.operand)) |name| try cg.addressed.put(cg.gpa, name, {});
            try cg.scanAddressed(u.operand);
        },
        .compound_stmt => |c| for (c.body) |s| try cg.scanAddressed(s),
        .if_stmt => |i| {
            try cg.scanAddressed(i.cond);
            try cg.scanAddressed(i.then_body);
            if (i.else_body) |e| try cg.scanAddressed(e);
        },
        .while_stmt => |w| {
            try cg.scanAddressed(w.cond);
            try cg.scanAddressed(w.body);
        },
        .do_while_stmt => |d| {
            try cg.scanAddressed(d.cond);
            try cg.scanAddressed(d.body);
        },
        .for_stmt => |f| {
            switch (f.init) {
                .decls => |ds| for (ds) |d| try cg.scanAddressed(d),
                .expr => |m| if (m) |e| try cg.scanAddressed(e),
            }
            if (f.cond) |c| try cg.scanAddressed(c);
            if (f.incr) |i| try cg.scanAddressed(i);
            try cg.scanAddressed(f.body);
        },
        .switch_stmt => |s| {
            try cg.scanAddressed(s.cond);
            try cg.scanAddressed(s.body);
        },
        .case_stmt => |c| {
            try cg.scanAddressed(c.body);
        },
        .default_stmt => |d| try cg.scanAddressed(d.body),
        .labeled_stmt => |l| try cg.scanAddressed(l.body),
        .return_stmt => |r| switch (r.operand) {
            .expr => |e| try cg.scanAddressed(e),
            else => {},
        },
        .variable => |v| if (v.initializer) |i| try cg.scanAddressed(i),
        .call_expr => |c| {
            try cg.scanAddressed(c.callee);
            for (c.args) |a| try cg.scanAddressed(a);
        },
        .cond_expr => |c| {
            try cg.scanAddressed(c.cond);
            try cg.scanAddressed(c.then_expr);
            try cg.scanAddressed(c.else_expr);
        },
        .cast => |c| try cg.scanAddressed(c.operand),
        .paren_expr,
        .deref_expr,
        .plus_expr,
        .negate_expr,
        .bit_not_expr,
        .bool_not_expr,
        .pre_inc_expr,
        .pre_dec_expr,
        .post_inc_expr,
        .post_dec_expr,
        => |u| try cg.scanAddressed(u.operand),
        .array_access_expr => |acc| {
            try cg.scanAddressed(acc.base);
            try cg.scanAddressed(acc.index);
        },
        .member_access_expr, .member_access_ptr_expr => |m| try cg.scanAddressed(m.base),
        .add_expr,
        .sub_expr,
        .mul_expr,
        .div_expr,
        .mod_expr,
        .bit_and_expr,
        .bit_or_expr,
        .bit_xor_expr,
        .shl_expr,
        .shr_expr,
        .equal_expr,
        .not_equal_expr,
        .less_than_expr,
        .less_than_equal_expr,
        .greater_than_expr,
        .greater_than_equal_expr,
        .bool_and_expr,
        .bool_or_expr,
        .comma_expr,
        .assign_expr,
        .add_assign_expr,
        .sub_assign_expr,
        .mul_assign_expr,
        .div_assign_expr,
        .mod_assign_expr,
        .shl_assign_expr,
        .shr_assign_expr,
        .bit_and_assign_expr,
        .bit_or_assign_expr,
        .bit_xor_assign_expr,
        => |b| {
            try cg.scanAddressed(b.lhs);
            try cg.scanAddressed(b.rhs);
        },
        else => {},
    }
}

fn lvalueName(cg: *CodeGen, node: Tree.Node.Index) ?[]const u8 {
    return switch (node.get(cg.tree)) {
        .decl_ref_expr => |d| cg.tree.tokSlice(d.name_tok),
        .paren_expr => |p| cg.lvalueName(p.operand),
        else => null,
    };
}

fn isAggregate(cg: *CodeGen, qt: aro.QualType) bool {
    const comp = cg.tree.comp;
    return qt.is(comp, .array) or qt.is(comp, .@"struct") or qt.is(comp, .@"union");
}

fn recordOf(cg: *CodeGen, qt: aro.QualType) aro.Type.Record {
    return switch (qt.base(cg.tree.comp).type) {
        .@"struct", .@"union" => |r| r,
        else => std.debug.panic("not a record type", .{}),
    };
}

fn fieldByteOffset(cg: *CodeGen, record_qt: aro.QualType, member_index: u32) u64 {
    const field = cg.recordOf(record_qt).fields[member_index];
    if (field.bit_width.unpack() != null) std.debug.panic("TODO: bit-field member", .{});
    return field.layout.offset_bits / 8;
}

fn addByteOffset(cg: *CodeGen, base: Oir.Class.Index, byte_offset: u64) Error!Oir.Class.Index {
    if (byte_offset == 0) return base;
    return cg.oir.add(.binOp(.add, base, try cg.oir.add(.constant(@intCast(byte_offset)))));
}

const BitField = struct {
    container: Oir.Class.Index,
    cbits: u16,
    shift: u6,
    width: u16,
    signed: bool,
};

fn makeBitField(cg: *CodeGen, struct_addr: Oir.Class.Index, record_qt: aro.QualType, member_index: u32) Error!BitField {
    const field = cg.recordOf(record_qt).fields[member_index];
    const width = field.bit_width.unpack().?;
    const cbits = cg.widthOf(field.qt);
    const off = field.layout.offset_bits;
    const unit = off / cbits;
    return .{
        .container = try cg.addByteOffset(struct_addr, unit * (cbits / 8)),
        .cbits = cbits,
        .shift = @intCast(off - unit * cbits),
        .width = @intCast(width),
        .signed = !cg.unsignedQt(field.qt),
    };
}

/// If `idx` is a member access naming a bit-field, returns its descriptor.
fn bitFieldOf(cg: *CodeGen, idx: Tree.Node.Index) Error!?BitField {
    const tree = cg.tree;
    switch (idx.get(tree)) {
        .member_access_expr => |m| {
            const rec_qt = m.base.qt(tree);
            if (cg.recordOf(rec_qt).fields[m.member_index].bit_width.unpack() == null) return null;
            return try cg.makeBitField(try cg.buildAddress(m.base), rec_qt, m.member_index);
        },
        .member_access_ptr_expr => |m| {
            const rec_qt = m.base.qt(tree).childType(tree.comp);
            if (cg.recordOf(rec_qt).fields[m.member_index].bit_width.unpack() == null) return null;
            return try cg.makeBitField(try cg.buildExpr(m.base), rec_qt, m.member_index);
        },
        .paren_expr => |p| return cg.bitFieldOf(p.operand),
        else => return null,
    }
}

fn widen64(cg: *CodeGen, value: Oir.Class.Index) Error!Oir.Class.Index {
    if (cg.oir.typeOf(value) == 64) return value;
    return cg.oir.add(.sext(value, 64));
}

fn loadBitField(cg: *CodeGen, bf: BitField) Error!Oir.Class.Index {
    const raw = try cg.widen64(try cg.oir.add(.load(cg.mem_state, bf.container, bf.cbits)));
    const left = try cg.oir.add(.constant(64 - @as(i64, bf.shift) - bf.width));
    const right = try cg.oir.add(.constant(64 - @as(i64, bf.width)));
    const hi = try cg.oir.add(.binOp(.shl, raw, left));
    const ext = try cg.oir.add(.binOp(if (bf.signed) .sar else .shr, hi, right));
    return cg.coerceTo(ext, bf.cbits);
}

fn storeBitField(cg: *CodeGen, bf: BitField, value: Oir.Class.Index) Error!void {
    const field_mask: u64 = if (bf.width >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(bf.width)) - 1;
    const old = try cg.widen64(try cg.oir.add(.load(cg.mem_state, bf.container, bf.cbits)));
    const clear = try cg.oir.add(.constant(@bitCast(~(field_mask << bf.shift))));
    const cleared = try cg.oir.add(.binOp(.@"and", old, clear));
    const masked = try cg.oir.add(.binOp(.@"and", try cg.widen64(value), try cg.oir.add(.constant(@bitCast(field_mask)))));
    const shifted = try cg.oir.add(.binOp(.shl, masked, try cg.oir.add(.constant(bf.shift))));
    const merged = try cg.oir.add(.binOp(.@"or", cleared, shifted));
    cg.mem_state = try cg.oir.add(.store(cg.mem_state, bf.container, merged, bf.cbits));
}

/// Binds `ident` to `value`, rebinding an existing scope entry or adding a new one.
fn bindVar(cg: *CodeGen, ident: []const u8, value: Oir.Class.Index) !void {
    if (cg.findIdentifier(ident)) |existing| {
        existing.* = value;
    } else {
        const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
        try latest.put(cg.gpa, ident, value);
    }
}

fn buildAggregateInit(cg: *CodeGen, base: Oir.Class.Index, qt: aro.QualType, init_node: Tree.Node.Index) Error!void {
    switch (init_node.get(cg.tree)) {
        .array_init_expr => return cg.buildArrayInit(base, cg.widthOf(qt.get(cg.tree.comp, .array).?.elem), init_node),
        .struct_init_expr => return cg.buildStructInit(base, qt, init_node),
        .string_literal_expr => return cg.buildStringInit(base, qt, init_node),
        else => {
            const src = try cg.buildExpr(init_node);
            return cg.copyAggregate(base, src, qt);
        },
    }
}

fn buildStringInit(cg: *CodeGen, base: Oir.Class.Index, qt: aro.QualType, init_node: Tree.Node.Index) Error!void {
    const tree = cg.tree;
    const val = tree.value_map.get(init_node).?;
    const bytes = tree.comp.interner.get(val.ref()).bytes;
    const size: u64 = qt.sizeof(tree.comp);
    for (0..size) |i| {
        const b: i64 = if (i < bytes.len) bytes[i] else 0;
        const addr = try cg.addByteOffset(base, i);
        const v = try cg.oir.add(.constantTyped(b, 8));
        cg.mem_state = try cg.oir.add(.store(cg.mem_state, addr, v, 8));
    }
}

fn copyToTemp(cg: *CodeGen, src: Oir.Class.Index, qt: aro.QualType) Error!Oir.Class.Index {
    const id = cg.next_alloca;
    cg.next_alloca += 1;
    const tmp = try cg.oir.add(.alloca(id, @intCast(qt.sizeof(cg.tree.comp)), qt.alignof(cg.tree.comp)));
    try cg.copyAggregate(tmp, src, qt);
    return tmp;
}

fn copyAggregate(cg: *CodeGen, dst: Oir.Class.Index, src: Oir.Class.Index, qt: aro.QualType) Error!void {
    var off: u64 = 0;
    var remaining: u64 = qt.sizeof(cg.tree.comp);
    while (remaining > 0) {
        const bytes: u16 = if (remaining >= 8) 8 else if (remaining >= 4) 4 else if (remaining >= 2) 2 else 1;
        const bits: u16 = bytes * 8;
        const v = try cg.oir.add(.load(cg.mem_state, try cg.addByteOffset(src, off), bits));
        cg.mem_state = try cg.oir.add(.store(cg.mem_state, try cg.addByteOffset(dst, off), v, bits));
        off += bytes;
        remaining -= bytes;
    }
}

/// Lowers a `struct`/`union` initializer, storing each field at its offset.
fn buildStructInit(cg: *CodeGen, base: Oir.Class.Index, record_qt: aro.QualType, init_node: Tree.Node.Index) Error!void {
    const tree = cg.tree;
    switch (init_node.get(tree)) {
        .struct_init_expr => |ci| {
            const rec = cg.recordOf(record_qt);
            for (ci.items, 0..) |item, i| {
                const field = rec.fields[i];
                if (field.bit_width.unpack() != null) {
                    const bf = try cg.makeBitField(base, record_qt, @intCast(i));
                    const v = switch (item.get(tree)) {
                        .default_init_expr => try cg.oir.add(.constant(0)),
                        else => try cg.buildExpr(item),
                    };
                    try cg.storeBitField(bf, v);
                    continue;
                }
                const off = field.layout.offset_bits / 8;
                const addr = try cg.addByteOffset(base, off);
                const fbits = cg.widthOf(field.qt);
                switch (item.get(tree)) {
                    .default_init_expr => {
                        const v = try cg.coerceTo(try cg.oir.add(.constant(0)), fbits);
                        cg.mem_state = try cg.oir.add(.store(cg.mem_state, addr, v, fbits));
                    },
                    else => {
                        if (cg.isAggregate(field.qt)) {
                            try cg.buildAggregateInit(addr, field.qt, item);
                        } else {
                            const v = try cg.coerceTo(try cg.buildExpr(item), fbits);
                            cg.mem_state = try cg.oir.add(.store(cg.mem_state, addr, v, fbits));
                        }
                    },
                }
            }
        },
        else => std.debug.panic("TODO: struct initializer {s}", .{@tagName(init_node.get(tree))}),
    }
}

fn coerceTo(cg: *CodeGen, value: Oir.Class.Index, bits: u16) Error!Oir.Class.Index {
    if (cg.oir.typeOf(value) == bits) return value;
    return cg.oir.add(.trunc(value, bits));
}

/// Lowers an array initializer by storing each element into the stack slot.
fn buildArrayInit(cg: *CodeGen, base: Oir.Class.Index, elem_bits: u16, init_node: Tree.Node.Index) Error!void {
    const tree = cg.tree;
    switch (init_node.get(tree)) {
        .array_init_expr => |ci| {
            var index: u64 = 0;
            for (ci.items) |item| switch (item.get(tree)) {
                // A trailing `{...}` filler zeroes the remaining elements.
                .array_filler_expr => |f| {
                    const zero = try cg.oir.add(.constant(0));
                    var k: u64 = 0;
                    while (k < f.count) : (k += 1) {
                        try cg.storeElem(base, elem_bits, index, zero);
                        index += 1;
                    }
                },
                .default_init_expr => {
                    try cg.storeElem(base, elem_bits, index, try cg.oir.add(.constant(0)));
                    index += 1;
                },
                else => {
                    try cg.storeElem(base, elem_bits, index, try cg.buildExpr(item));
                    index += 1;
                },
            };
        },
        else => std.debug.panic("TODO: array initializer {s}", .{@tagName(init_node.get(tree))}),
    }
}

/// Stores `value` (coerced to `elem_bits`) into element `index` of an array slot.
fn storeElem(cg: *CodeGen, base: Oir.Class.Index, elem_bits: u16, index: u64, value: Oir.Class.Index) Error!void {
    const off = index * (elem_bits / 8);
    const addr = if (off == 0)
        base
    else
        try cg.oir.add(.binOp(.add, base, try cg.oir.add(.constant(@intCast(off)))));
    const v = if (cg.oir.typeOf(value) == elem_bits) value else try cg.oir.add(.trunc(value, elem_bits));
    cg.mem_state = try cg.oir.add(.store(cg.mem_state, addr, v, elem_bits));
}

fn buildExpr(cg: *CodeGen, expr: Tree.Node.Index) Error!Oir.Class.Index {
    const tree = cg.tree;
    const oir = cg.oir;
    const node_tags = tree.nodes.items(.tag);

    if (cg.node_to_class.get(expr)) |c| return c;
    if (tree.value_map.get(expr)) |val| {
        if (tree.comp.interner.get(val.ref()) == .int) return cg.buildConstant(expr, val);
    }

    // Calls advance the memory state, so they must never be memoized. `.get`
    // normalizes the `call_expr`/`call_expr_one` raw tags into one `.call_expr`.
    switch (node_tags[@intFromEnum(expr)]) {
        .call_expr, .call_expr_one => return cg.buildCall(expr.get(tree).call_expr),
        .pre_inc_expr => return cg.buildIncDec(expr.get(tree).pre_inc_expr.operand, true, true),
        .pre_dec_expr => return cg.buildIncDec(expr.get(tree).pre_dec_expr.operand, false, true),
        .post_inc_expr => return cg.buildIncDec(expr.get(tree).post_inc_expr.operand, true, false),
        .post_dec_expr => return cg.buildIncDec(expr.get(tree).post_dec_expr.operand, false, false),
        .assign_expr => {
            const a = expr.get(tree).assign_expr;
            return cg.buildAssign(a.lhs, a.rhs);
        },
        .add_assign_expr,
        .sub_assign_expr,
        .mul_assign_expr,
        .div_assign_expr,
        .mod_assign_expr,
        .shl_assign_expr,
        .shr_assign_expr,
        .bit_and_assign_expr,
        .bit_or_assign_expr,
        .bit_xor_assign_expr,
        => return cg.buildCompoundAssign(expr),
        .paren_expr => return cg.buildExpr(expr.get(tree).paren_expr.operand),
        .stmt_expr => return cg.buildStmtExpr(expr),
        .bool_and_expr => return cg.buildLogical(expr.get(tree).bool_and_expr, .@"and"),
        .bool_or_expr => return cg.buildLogical(expr.get(tree).bool_or_expr, .@"or"),
        .cond_expr => return cg.buildCond(expr.get(tree).cond_expr),
        else => {},
    }

    const class = switch (expr.get(tree)) {
        // Handled seperately, as they may be scaled by the pointee size.
        .add_expr, .sub_expr => |bin, t| try cg.buildAddSub(t, bin),
        .mul_expr,
        .div_expr,
        .mod_expr,
        .bit_and_expr,
        .bit_or_expr,
        .bit_xor_expr,
        .shl_expr,
        .shr_expr,
        .equal_expr,
        .not_equal_expr,
        .greater_than_expr,
        .greater_than_equal_expr,
        .less_than_expr,
        .less_than_equal_expr,
        => |bin, t| bin: {
            const lhs = try cg.buildExpr(bin.lhs);
            const rhs = try cg.buildExpr(bin.rhs);
            const uns = cg.unsignedQt(bin.lhs.qt(tree));
            break :bin switch (t) {
                .mul_expr => try oir.add(.binOp(.mul, lhs, rhs)),
                .div_expr => try oir.add(.binOp(if (uns) .udiv else .div_trunc, lhs, rhs)),
                .mod_expr => try oir.add(.binOp(if (uns) .urem else .rem, lhs, rhs)),
                .bit_and_expr => try oir.add(.binOp(.@"and", lhs, rhs)),
                .bit_or_expr => try oir.add(.binOp(.@"or", lhs, rhs)),
                .bit_xor_expr => try oir.add(.binOp(.xor, lhs, rhs)),
                .shl_expr => try oir.add(.binOp(.shl, lhs, rhs)),
                .shr_expr => try oir.add(.binOp(if (uns) .shr else .sar, lhs, rhs)),
                .equal_expr => try oir.add(.binOp(.cmp_eq, lhs, rhs)),
                .not_equal_expr => try cg.notPred(try oir.add(.binOp(.cmp_eq, lhs, rhs))),
                .greater_than_expr => try oir.add(.binOp(if (uns) .cmp_ugt else .cmp_gt, lhs, rhs)),
                .less_than_expr => try oir.add(.binOp(if (uns) .cmp_ult else .cmp_lt, lhs, rhs)),
                .greater_than_equal_expr => try cg.notPred(try oir.add(.binOp(if (uns) .cmp_ult else .cmp_lt, lhs, rhs))),
                .less_than_equal_expr => try cg.notPred(try oir.add(.binOp(if (uns) .cmp_ugt else .cmp_gt, lhs, rhs))),
                else => unreachable,
            };
        },
        // `a, b`. Evalute `a` for its side effects, yield `b`.
        .comma_expr => |bin| comma: {
            _ = try cg.buildExpr(bin.lhs);
            break :comma try cg.buildExpr(bin.rhs);
        },
        .plus_expr => |un| try cg.buildExpr(un.operand),
        // TODO: add binary/bitwise negate variants to IR?
        .negate_expr => |un| neg: {
            const v = try cg.buildExpr(un.operand);
            const zero = try oir.add(.constant(0));
            break :neg try oir.add(.binOp(.sub, zero, v));
        },
        .bit_not_expr => |un| not: {
            // ~x == -1 - x
            const v = try cg.buildExpr(un.operand);
            const ones = try oir.add(.constant(-1));
            break :not try oir.add(.binOp(.sub, ones, v));
        },
        .bool_not_expr => |un| try cg.notPred(try cg.buildExpr(un.operand)),

        .addr_of_expr => |un| try cg.buildAddress(un.operand),
        .paren_expr => |p| try cg.buildExpr(p.operand),
        .decl_ref_expr,
        .member_access_expr,
        .member_access_ptr_expr,
        .deref_expr,
        .array_access_expr,
        .compound_literal_expr,
        .compound_assign_dummy_expr,
        .string_literal_expr,
        => try cg.buildLval(expr),
        .int_literal => unreachable, // handled in the value_map above
        .sizeof_expr => |ti| try oir.add(.constantTyped(@intCast(ti.operand_qt.sizeof(tree.comp)), cg.widthOf(ti.qt))),
        .alignof_expr => |ti| try oir.add(.constantTyped(@intCast(ti.operand_qt.alignof(tree.comp)), cg.widthOf(ti.qt))),
        .cast => |cast| try cg.buildCast(cast),
        .builtin_call_expr => |call| b: {
            const name = cg.tree.tokSlice(call.builtin_tok);
            const builtin = cg.comp.builtins.lookup(name);
            // TODO: if the aro.Builtins namespace was accessible, we'd have a wrapper
            // can ask Vexu to fix later
            switch (builtin.tag.common) {
                // TODO: implement these in a better way, probably want to have a bswap Oir instruction
                .__builtin_bswap16 => {
                    std.debug.assert(call.args.len == 1);
                    const operand = try cg.buildExpr(call.args[0]);

                    const lo = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x00FF, 16))));
                    const hi = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0xFF00, 16))));

                    const slo = try oir.add(.binOp(.shl, lo, try oir.add(.constantTyped(8, 16))));
                    const shi = try oir.add(.binOp(.shr, hi, try oir.add(.constantTyped(8, 16))));

                    break :b try oir.add(.binOp(.@"or", slo, shi));
                },
                .__builtin_bswap32 => {
                    std.debug.assert(call.args.len == 1);
                    const operand = try cg.buildExpr(call.args[0]);

                    const b0 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x000000FF, 32))));
                    const b1 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x0000FF00, 32))));
                    const b2 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x00FF0000, 32))));
                    const b3 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0xFF000000, 32))));

                    const c0 = try oir.add(.binOp(.shl, b0, try oir.add(.constantTyped(24, 32))));
                    const c1 = try oir.add(.binOp(.shl, b1, try oir.add(.constantTyped(8, 32))));
                    const c2 = try oir.add(.binOp(.shr, b2, try oir.add(.constantTyped(8, 32))));
                    const c3 = try oir.add(.binOp(.shr, b3, try oir.add(.constantTyped(24, 32))));

                    const t0 = try oir.add(.binOp(.@"or", c0, c1));
                    const t1 = try oir.add(.binOp(.@"or", c2, c3));

                    break :b try oir.add(.binOp(.@"or", t0, t1));
                },
                .__builtin_bswap64 => {
                    std.debug.assert(call.args.len == 1);
                    const operand = try cg.buildExpr(call.args[0]);

                    const b0 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x00000000000000FF, 64))));
                    const b1 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x000000000000FF00, 64))));
                    const b2 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x0000000000FF0000, 64))));
                    const b3 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x00000000FF000000, 64))));
                    const b4 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x000000FF00000000, 64))));
                    const b5 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x0000FF0000000000, 64))));
                    const b6 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(0x00FF000000000000, 64))));
                    // TODO: constants rework plz
                    const b7 = try oir.add(.binOp(.@"and", operand, try oir.add(.constantTyped(@bitCast(@as(u64, 0xFF00000000000000)), 64))));

                    const c0 = try oir.add(.binOp(.shl, b0, try oir.add(.constantTyped(56, 64))));
                    const c1 = try oir.add(.binOp(.shl, b1, try oir.add(.constantTyped(40, 64))));
                    const c2 = try oir.add(.binOp(.shl, b2, try oir.add(.constantTyped(24, 64))));
                    const c3 = try oir.add(.binOp(.shl, b3, try oir.add(.constantTyped(8, 64))));

                    const c4 = try oir.add(.binOp(.shr, b4, try oir.add(.constantTyped(8, 64))));
                    const c5 = try oir.add(.binOp(.shr, b5, try oir.add(.constantTyped(24, 64))));
                    const c6 = try oir.add(.binOp(.shr, b6, try oir.add(.constantTyped(40, 64))));
                    const c7 = try oir.add(.binOp(.shr, b7, try oir.add(.constantTyped(56, 64))));

                    const t0 = try oir.add(.binOp(.@"or", c0, c1));
                    const t1 = try oir.add(.binOp(.@"or", c2, c3));
                    const t2 = try oir.add(.binOp(.@"or", c4, c5));
                    const t3 = try oir.add(.binOp(.@"or", c6, c7));

                    const d0 = try oir.add(.binOp(.@"or", t0, t1));
                    const d1 = try oir.add(.binOp(.@"or", t2, t3));

                    break :b try oir.add(.binOp(.@"or", d0, d1));
                },
                // `va_start(ap, last)`
                // Point the `va_list` at the first variadic argument
                // in the function's save area.
                // TODO: this is riscv specific, uhh, i dunno how varargs work
                .__builtin_va_start, .__builtin_c23_va_start => {
                    const area = try oir.add(.vaStart(cg.cur_named));
                    try cg.storeToScalarLval(cg.lvalNode(call.args[0]), area);
                    break :b area;
                },
                // `va_end`/`va_copy` need no cleanup for a pointer `va_list`.
                // TODO: also riscv specific
                .__builtin_va_end, .__builtin_va_copy => break :b try oir.add(.constant(0)),
                else => |t| std.debug.panic("TODO: implement builtin: {t}", .{t}),
            }
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(expr)])}),
    };

    try cg.node_to_class.put(cg.gpa, expr, class);
    return class;
}

/// Lowers a GNU statement expression `({ stmts...; value })`.
/// Run the leading statements, then yields the last one's value.
fn buildStmtExpr(cg: *CodeGen, expr: Tree.Node.Index) Error!Oir.Class.Index {
    const tree = cg.tree;
    const un = expr.get(tree).stmt_expr;
    const body = un.operand.get(tree).compound_stmt.body;
    if (body.len == 0 or un.qt.is(tree.comp, .void)) {
        _ = try cg.buildSeq(body);
        return cg.oir.add(.constant(0));
    }
    _ = try cg.buildSeq(body[0 .. body.len - 1]);
    return cg.buildExpr(body[body.len - 1]);
}

/// Lowers `a && b` / `a || b` with the short-circuit semantics.
/// The RHS is evaluated on its own memory chain, then merged with a gamma on
/// the LHS so the RHS's side effects are conditional.
fn buildLogical(cg: *CodeGen, bin: anytype, op: enum { @"and", @"or" }) Error!Oir.Class.Index {
    const la = try cg.toBool(try cg.buildExpr(bin.lhs));
    const mem0 = cg.mem_state;
    const rb = try cg.toBool(try cg.buildExpr(bin.rhs));
    const mem_rhs = cg.mem_state;
    switch (op) {
        .@"and" => {
            cg.mem_state = try cg.gammaIfNe(la, mem_rhs, mem0);
            cg.node_to_class.clearRetainingCapacity();
            return cg.gammaIfNe(la, rb, try cg.oir.add(.constant(0)));
        },
        .@"or" => {
            cg.mem_state = try cg.gammaIfNe(la, mem0, mem_rhs);
            cg.node_to_class.clearRetainingCapacity();
            return cg.gammaIfNe(la, try cg.oir.add(.constant(1)), rb);
        },
    }
}

/// Lowers `c ? t : e`.
/// Each arm is evaluated on its own memory chain from the pre-condition state,
/// then merged with a gamma so only the taken arm's side effects run.
fn buildCond(cg: *CodeGen, c: anytype) Error!Oir.Class.Index {
    const pc = try cg.toBool(try cg.buildExpr(c.cond));
    const mem0 = cg.mem_state;
    const t = try cg.buildExpr(c.then_expr);
    const mem_t = cg.mem_state;
    cg.mem_state = mem0;
    cg.node_to_class.clearRetainingCapacity();
    const e = try cg.buildExpr(c.else_expr);
    const mem_e = cg.mem_state;
    cg.mem_state = try cg.gammaIfNe(pc, mem_t, mem_e);
    cg.node_to_class.clearRetainingCapacity();
    return cg.gammaIfNe(pc, t, e);
}

/// Lowers `foo(args...)` into a `call` node. The call reads the current memory
/// state and produces a tuple `(mem', result)`; we advance `mem_state` to `mem'`
/// and return `result`.
fn buildCall(cg: *CodeGen, call: Tree.Node.Call) Error!Oir.Class.Index {
    const callee = try cg.resolveCallee(cg.calleeName(call.callee));

    const returns_aggregate = !call.qt.is(cg.tree.comp, .void) and cg.isAggregate(call.qt);

    var body: std.ArrayList(Oir.Class.Index) = .empty;
    defer body.deinit(cg.gpa);
    try body.append(cg.gpa, undefined); // slot 0 reserved for the memory state
    for (call.args) |arg| {
        const aqt = arg.qt(cg.tree);
        if (cg.isAggregate(aqt)) {
            try body.append(cg.gpa, try cg.copyToTemp(try cg.buildExpr(arg), aqt));
        } else {
            try body.append(cg.gpa, try cg.buildExpr(arg));
        }
    }
    const sret: ?Oir.Class.Index = if (returns_aggregate) sret: {
        const id_a = cg.next_alloca;
        cg.next_alloca += 1;
        const slot = try cg.oir.add(.alloca(id_a, @intCast(call.qt.sizeof(cg.tree.comp)), call.qt.alignof(cg.tree.comp)));
        try body.append(cg.gpa, slot);
        break :sret slot;
    } else null;
    body.items[0] = cg.mem_state; // captured after args (and their copies) are evaluated

    const span = try cg.oir.listToSpan(body.items);
    const node = try cg.oir.add(.call(callee, span));
    cg.mem_state = try cg.oir.add(.project(0, node, .data, 0));
    if (sret) |slot| return slot;
    const ret_bits: u16 = if (call.qt.is(cg.tree.comp, .void)) 0 else cg.widthOf(call.qt);
    return cg.oir.add(.project(1, node, .data, ret_bits));
}

fn resolveCallee(cg: *CodeGen, name: []const u8) Error!u32 {
    if (cg.fn_ids.get(name)) |id| return id;
    const id: u32 = @intCast(cg.fn_names.items.len);
    try cg.fn_ids.put(cg.gpa, name, id);
    try cg.fn_names.append(cg.gpa, name);
    return id;
}

/// Lowers the aro `cast` into `trunc`/`sext`/`zext` for the target.
fn buildCast(cg: *CodeGen, cast: Tree.Node.Cast) Error!Oir.Class.Index {
    const tree = cg.tree;
    return switch (cast.kind) {
        .lval_to_rval => try cg.buildLval(cast.operand),
        // Pointers are just 64-bit values, so these conversions are no-ops.
        .no_op, .bitcast, .pointer_to_int, .int_to_pointer => try cg.buildExpr(cast.operand),
        // Array decays to a pointer to its first element: its base address.
        .array_to_pointer => try cg.buildAddress(cast.operand),
        .pointer_to_bool => blk: {
            const v = try cg.buildExpr(cast.operand);
            break :blk try cg.notPred(try cg.oir.add(.binOp(.cmp_eq, v, try cg.oir.add(.constant(0)))));
        },
        .int_cast => blk: {
            const v = try cg.buildExpr(cast.operand);
            const src_qt = cast.operand.qt(tree);
            const src_bits = cg.widthOf(src_qt);
            const dst_bits = cg.widthOf(cast.qt);
            if (dst_bits == src_bits) break :blk v;
            if (dst_bits < src_bits) break :blk try cg.oir.add(.trunc(v, dst_bits));
            break :blk if (cg.unsignedQt(src_qt))
                try cg.oir.add(.zext(v, dst_bits))
            else
                try cg.oir.add(.sext(v, dst_bits));
        },
        .bool_to_int => blk: {
            const v = try cg.buildExpr(cast.operand);
            break :blk try cg.oir.add(.zext(v, cg.widthOf(cast.qt)));
        },
        .int_to_bool => blk: {
            // (v != 0), as an i1, via the unsigned compare `0 < v`.
            const v = try cg.buildExpr(cast.operand);
            const zero = try cg.oir.add(.constant(0));
            break :blk try cg.oir.add(.binOp(.cmp_ult, zero, v));
        },
        // `(void)expr`.
        // Evaluate for side effects, then value is discarded.
        .to_void => blk: {
            _ = try cg.buildExpr(cast.operand);
            break :blk try cg.oir.add(.constant(0));
        },
        // `NULL`, simply zero address for us
        .null_to_pointer => try cg.oir.add(.constant(0)),
        else => std.debug.panic("TODO: cast {s}", .{@tagName(cast.kind)}),
    };
}

fn widthOf(cg: *CodeGen, qt: aro.QualType) u16 {
    return @intCast(qt.bitSizeof(cg.tree.comp));
}

fn canonValue(value: i64, bits: u16) i64 {
    if (bits == 1) return value & 1;
    if (bits == 0 or bits >= 64) return value;
    const s: u6 = @intCast(64 - bits);
    const u: u64 = @bitCast(value);
    return @as(i64, @bitCast(u << s)) >> s;
}

fn unsignedQt(cg: *CodeGen, qt: aro.QualType) bool {
    return qt.signedness(cg.tree.comp) == .unsigned;
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

/// Reads an lvalue (the operand of `lval_to_rval`). A plain SSA local returns its
/// bound value; everything backed by memory (stack-scalar, `*p`, `a[i]`) loads.
fn buildLval(cg: *CodeGen, idx: Tree.Node.Index) Error!Oir.Class.Index {
    const tree = cg.tree;

    switch (idx.get(tree)) {
        .decl_ref_expr => |decl_ref| {
            const name = tree.tokSlice(decl_ref.name_tok);
            if (cg.mem_vars.get(name)) |info| {
                // Stack-backed: a scalar loads its value; an aggregate yields its
                // address (it decays rather than being loaded).
                const addr = cg.findIdentifier(name).?.*;
                if (info.aggregate) return addr;
                return cg.oir.add(.load(cg.mem_state, addr, info.bits));
            }
            if (cg.findIdentifier(name)) |ref_idx| {
                const c = ref_idx.*;
                try cg.node_to_class.put(cg.gpa, idx, c);
                return c;
            }
            if (cg.globals.get(name)) |g| {
                const addr = try cg.oir.add(.globalAddr(g.id));
                // A scalar loads its value, while an aggregate decays to its address.
                if (g.aggregate) return addr;
                return cg.oir.add(.load(cg.mem_state, addr, g.bits));
            }
            @panic("TODO: unknown identifier");
        },
        .deref_expr, .array_access_expr, .member_access_expr, .member_access_ptr_expr => {
            if (try cg.bitFieldOf(idx)) |bf| return cg.loadBitField(bf);
            const address = try cg.buildAddress(idx);
            const fqt = idx.qt(tree);
            if (cg.isAggregate(fqt)) return address;
            return cg.oir.add(.load(cg.mem_state, address, cg.widthOf(fqt)));
        },
        .paren_expr => |p| return cg.buildLval(p.operand),
        // A string literal is an array lvalue.
        .string_literal_expr => return cg.oir.add(.globalAddr(try cg.internString(idx))),
        .compound_assign_dummy_expr => return cg.compound_dummy.?,
        .compound_literal_expr => |lit| {
            const comp = cg.tree.comp;
            const id = cg.next_alloca;
            cg.next_alloca += 1;
            const slot = try cg.oir.add(.alloca(id, @intCast(lit.qt.sizeof(comp)), lit.qt.alignof(comp)));
            if (cg.isAggregate(lit.qt)) {
                try cg.buildAggregateInit(slot, lit.qt, lit.initializer);
                return slot;
            }
            const bits = cg.widthOf(lit.qt);
            const v = try cg.coerceTo(try cg.buildExpr(lit.initializer), bits);
            cg.mem_state = try cg.oir.add(.store(cg.mem_state, slot, v, bits));
            return cg.oir.add(.load(cg.mem_state, slot, bits));
        },
        else => std.debug.panic("TODO: lval {s}", .{@tagName(idx.get(tree))}),
    }
}

/// Computes the address of an lvalue as a 64-bit pointer.
fn buildAddress(cg: *CodeGen, idx: Tree.Node.Index) Error!Oir.Class.Index {
    const tree = cg.tree;
    switch (idx.get(tree)) {
        .decl_ref_expr => |decl_ref| {
            const name = tree.tokSlice(decl_ref.name_tok);
            // Only memory-backed locals have an address; the binding *is* it.
            if (cg.mem_vars.get(name) != null) return cg.findIdentifier(name).?.*;
            if (cg.globals.get(name)) |g| return cg.oir.add(.globalAddr(g.id));
            std.debug.panic("TODO: address of non-stack local '{s}'", .{name});
        },
        // `&*p` is just `p`.
        .deref_expr => |deref| return cg.buildExpr(deref.operand),
        .array_access_expr => |acc| {
            const base = try cg.buildPointer(acc.base);
            const index = try cg.buildExpr(acc.index);
            return cg.scaleAdd(base, index, cg.sizeOfBytes(idx.qt(tree)));
        },
        // `s.f`, the struct is an lvalue
        .member_access_expr => |m| {
            const base = try cg.buildAddress(m.base);
            return cg.addByteOffset(base, cg.fieldByteOffset(m.base.qt(tree), m.member_index));
        },
        // `p->f`, the base is a pointer value
        .member_access_ptr_expr => |m| {
            const base = try cg.buildExpr(m.base);
            const rec_qt = m.base.qt(tree).childType(cg.tree.comp);
            return cg.addByteOffset(base, cg.fieldByteOffset(rec_qt, m.member_index));
        },
        .paren_expr => |p| return cg.buildAddress(p.operand),
        .string_literal_expr => return cg.oir.add(.globalAddr(try cg.internString(idx))),
        .compound_literal_expr => return cg.buildLval(idx),
        .call_expr => return cg.buildExpr(idx),
        else => std.debug.panic("TODO: address of {s}", .{@tagName(idx.get(tree))}),
    }
}

/// Evaluates `node` to a pointer value, decaying an array operand to its address.
fn buildPointer(cg: *CodeGen, node: Tree.Node.Index) Error!Oir.Class.Index {
    if (node.qt(cg.tree).is(cg.tree.comp, .array)) return cg.buildAddress(node);
    return cg.buildExpr(node);
}

/// `base + index * elem_bytes`, with the index widened to 64-bit pointer width.
fn scaleAdd(cg: *CodeGen, base: Oir.Class.Index, index: Oir.Class.Index, elem_bytes: u64) Error!Oir.Class.Index {
    const idx64 = try cg.to64(index);
    const scaled = if (elem_bytes == 1)
        idx64
    else
        try cg.oir.add(.binOp(.mul, idx64, try cg.oir.add(.constant(@intCast(elem_bytes)))));
    return cg.oir.add(.binOp(.add, base, scaled));
}

/// Widens a value to 64-bit (pointer width) by sign extension, if narrower.
fn to64(cg: *CodeGen, v: Oir.Class.Index) Error!Oir.Class.Index {
    if (cg.oir.typeOf(v) >= 64) return v;
    return cg.oir.add(.sext(v, 64));
}

fn sizeOfBytes(cg: *CodeGen, qt: aro.QualType) u64 {
    return qt.sizeof(cg.tree.comp);
}

fn buildAddSub(cg: *CodeGen, t: anytype, bin: anytype) Error!Oir.Class.Index {
    const tree = cg.tree;
    const comp = cg.tree.comp;
    const is_add = t == .add_expr;
    const lptr = bin.lhs.qt(tree).get(comp, .pointer);
    const rptr = bin.rhs.qt(tree).get(comp, .pointer);

    if (lptr) |lp| {
        if (rptr) |_| {
            const a = try cg.buildExpr(bin.lhs);
            const b = try cg.buildExpr(bin.rhs);
            const diff = try cg.oir.add(.binOp(.sub, a, b));
            const elem = cg.sizeOfBytes(lp.child);
            return cg.oir.add(.binOp(.div_trunc, diff, try cg.oir.add(.constant(@intCast(elem)))));
        }
        const base = try cg.buildExpr(bin.lhs);
        const index = try cg.buildExpr(bin.rhs);
        const elem = cg.sizeOfBytes(lp.child);
        const idx64 = try cg.to64(index);
        const scaled = if (elem == 1)
            idx64
        else
            try cg.oir.add(.binOp(.mul, idx64, try cg.oir.add(.constant(@intCast(elem)))));
        return cg.oir.add(.binOp(if (is_add) .add else .sub, base, scaled));
    }
    if (rptr) |rp| {
        const base = try cg.buildExpr(bin.rhs);
        const index = try cg.buildExpr(bin.lhs);
        return cg.scaleAdd(base, index, cg.sizeOfBytes(rp.child));
    }

    const lhs = try cg.buildExpr(bin.lhs);
    const rhs = try cg.buildExpr(bin.rhs);
    return cg.oir.add(.binOp(if (is_add) .add else .sub, lhs, rhs));
}

fn findIdentifier(cg: *CodeGen, ident: []const u8) ?*Oir.Class.Index {
    for (0..cg.symbol_table.items.len) |i| {
        const rev = cg.symbol_table.items.len - i - 1;
        if (cg.symbol_table.items[rev].getPtr(ident)) |class| return class;
    }
    return null;
}

/// Registers a variable in the global table and records how we should emit it.
fn registerGlobal(cg: *CodeGen, v: Tree.Node.Variable) Error!void {
    const tree = cg.tree;
    const comp = tree.comp;
    const name = tree.tokSlice(v.name_tok);
    const qt = v.qt;
    const aggregate = cg.isAggregate(qt);
    const size = qt.sizeof(comp);
    const alignment: u32 = @intCast(qt.alignof(comp));
    // `static` has internal linkage, everything else is externally visible.
    const external = v.storage_class != .static;

    const data: zob.rv64.Global.Data = blk: {
        if (v.initializer) |i| {
            const buf = try cg.gpa.alloc(u8, @intCast(size));
            @memset(buf, 0);
            var relocs: std.ArrayList(zob.rv64.Global.Reloc) = .empty;
            errdefer relocs.deinit(cg.gpa);
            try cg.lowerInitBytes(buf, &relocs, 0, qt, i);
            break :blk .{ .bytes = .{
                .bytes = buf,
                .relocs = try relocs.toOwnedSlice(cg.gpa),
                .@"align" = alignment,
            } };
        }
        if (v.storage_class == .@"extern") break :blk .declared;
        break :blk .{ .bss = .{ .size = size, .@"align" = alignment } };
    };

    if (cg.globals.get(name)) |info| {
        // (defined > tentative > declared).
        const slot = &cg.global_defs.items[info.id];
        if (strength(data) > strength(slot.data)) slot.* = .{ .name = name, .external = external, .data = data };
        return;
    }

    const id: u32 = @intCast(cg.global_defs.items.len);
    try cg.global_defs.append(cg.gpa, .{ .name = name, .external = external, .data = data });
    try cg.globals.put(cg.gpa, name, .{
        .id = id,
        .bits = if (aggregate) 0 else cg.widthOf(qt),
        .aggregate = aggregate,
    });
}

fn strength(data: zob.rv64.Global.Data) u8 {
    return switch (data) {
        .declared => 0,
        .bss => 1,
        .bytes => 2,
    };
}

fn internString(cg: *CodeGen, node: Tree.Node.Index) Error!u32 {
    const tree = cg.tree;
    const comp = tree.comp;
    const val = tree.value_map.get(node).?;
    const ref: u32 = @intFromEnum(val.ref());
    if (cg.string_pool.get(ref)) |id| return id;

    const bytes = comp.interner.get(val.ref()).bytes;
    const size: usize = @intCast(node.qt(tree).sizeof(comp));
    const buf = try cg.gpa.alloc(u8, size);
    @memset(buf, 0);
    const n = @min(size, bytes.len);
    @memcpy(buf[0..n], bytes[0..n]);

    const id: u32 = @intCast(cg.global_defs.items.len);
    const name = try std.fmt.allocPrint(cg.gpa, ".Lstr{d}", .{id});
    try cg.string_names.append(cg.gpa, name);
    try cg.global_defs.append(cg.gpa, .{
        .name = name,
        .external = false,
        .data = .{ .bytes = .{ .bytes = buf, .relocs = &.{}, .@"align" = 1 } },
    });
    try cg.string_pool.put(cg.gpa, ref, id);
    return id;
}

const Relocs = std.ArrayList(zob.rv64.Global.Reloc);

fn lowerInitBytes(cg: *CodeGen, buf: []u8, relocs: *Relocs, off: u64, qt: aro.QualType, init_node: Tree.Node.Index) Error!void {
    const tree = cg.tree;
    const comp = tree.comp;
    switch (init_node.get(tree)) {
        .array_init_expr => |ci| {
            const elem_qt = qt.get(comp, .array).?.elem;
            const elem_size = elem_qt.sizeof(comp);
            var index: u64 = 0;
            for (ci.items) |item| switch (item.get(tree)) {
                .array_filler_expr => |f| index += f.count, // remaining stay zero
                .default_init_expr => index += 1, // zero
                else => {
                    try cg.lowerInitElem(buf, relocs, off + index * elem_size, elem_qt, item);
                    index += 1;
                },
            };
        },
        .struct_init_expr => |ci| {
            const rec = cg.recordOf(qt);
            for (ci.items, 0..) |item, i| {
                const field = rec.fields[i];
                if (field.bit_width.unpack() != null) @panic("TODO: bit-field global initializer");
                if (item.get(tree) == .default_init_expr) continue; // zero
                try cg.lowerInitElem(buf, relocs, off + field.layout.offset_bits / 8, field.qt, item);
            }
        },
        // `char g[] = "abs"`. Copy the literal's bytes into the object.
        .string_literal_expr => {
            const val = tree.value_map.get(init_node).?;
            const bytes = comp.interner.get(val.ref()).bytes;
            const n = @min(buf.len - off, bytes.len);
            @memcpy(buf[off..][0..n], bytes[0..n]);
        },
        else => try cg.lowerInitScalar(buf, relocs, off, qt, init_node),
    }
}

fn lowerInitElem(cg: *CodeGen, buf: []u8, relocs: *Relocs, off: u64, qt: aro.QualType, node: Tree.Node.Index) Error!void {
    if (cg.isAggregate(qt)) return cg.lowerInitBytes(buf, relocs, off, qt, node);
    return cg.lowerInitScalar(buf, relocs, off, qt, node);
}

fn lowerInitScalar(cg: *CodeGen, buf: []u8, relocs: *Relocs, off: u64, qt: aro.QualType, node: Tree.Node.Index) Error!void {
    if (try cg.globalReloc(node)) |r| {
        try relocs.append(cg.gpa, .{ .offset = off, .target = r.target, .addend = r.addend });
        return;
    }
    return cg.writeScalarInit(buf, off, qt, node);
}

fn globalReloc(cg: *CodeGen, node: Tree.Node.Index) Error!?struct { target: u32, addend: i64 } {
    const tree = cg.tree;
    var n = node;
    while (true) switch (n.get(tree)) {
        .cast => |c| n = c.operand,
        .paren_expr => |p| n = p.operand,
        .addr_of_expr => |u| n = u.operand,
        .string_literal_expr => return .{ .target = try cg.internString(n), .addend = 0 },
        .decl_ref_expr => |d| {
            const name = tree.tokSlice(d.name_tok);
            if (cg.globals.get(name)) |g| return .{ .target = g.id, .addend = 0 };
            return null;
        },
        else => return null,
    };
}

fn writeScalarInit(cg: *CodeGen, buf: []u8, off: u64, qt: aro.QualType, node: Tree.Node.Index) Error!void {
    const comp = cg.tree.comp;
    const nbytes: u64 = @max(1, cg.widthOf(qt) / 8);
    const val = cg.constValueOf(node) orelse @panic("TODO: non-constant global initializer");
    const raw: u64 = val.toInt(u64, comp) orelse
        @bitCast(val.toInt(i64, comp) orelse @panic("TODO: huge global initializer"));
    for (0..nbytes) |k| buf[off + k] = @truncate(raw >> @intCast(k * 8));
}

fn constValueOf(cg: *CodeGen, node: Tree.Node.Index) ?aro.Value {
    var n = node;
    while (true) {
        if (cg.tree.value_map.get(n)) |v| return v;
        n = switch (n.get(cg.tree)) {
            .cast => |c| c.operand,
            .paren_expr => |p| p.operand,
            else => return null,
        };
    }
}

fn buildConstant(cg: *CodeGen, idx: Tree.Node.Index, val: aro.Value) !Oir.Class.Index {
    const tree = cg.tree;
    const key = tree.comp.interner.get(val.ref());

    const class = switch (key) {
        .int => int: {
            const raw: i64 = val.toInt(i64, tree.comp) orelse
                @bitCast(val.toInt(u64, tree.comp) orelse @panic("TODO: huge literal"));
            const bits = cg.widthOf(idx.qt(tree));
            break :int try cg.oir.add(.constantTyped(canonValue(raw, bits), bits));
        },
        else => std.debug.panic("TODO: constant {s} (node {s})", .{ @tagName(key), @tagName(idx.get(tree)) }),
    };

    try cg.node_to_class.put(cg.gpa, idx, class);
    return class;
}
