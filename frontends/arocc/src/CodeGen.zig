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
ctrl_class: ?Oir.Class.Index,
exits: *std.ArrayListUnmanaged(Oir.Class.Index),
node_to_class: std.AutoHashMapUnmanaged(Tree.Node.Index, Oir.Class.Index),
symbol_table: SymbolTable,
scratch: std.ArrayListUnmanaged(Oir.Class.Index),

const Error = error{OutOfMemory};
const SymbolTable = std.ArrayListUnmanaged(std.StringHashMapUnmanaged(Oir.Class.Index));

pub fn init(
    oir: *Oir,
    gpa: std.mem.Allocator,
    tree: *const Tree,
) !CodeGen {
    const start_class = try oir.add(.{
        .tag = .start,
        .data = .{ .list = .{ .start = 0, .end = 0 } },
    });
    const ctrl_class = try oir.add(.project(0, start_class, .ctrl));

    var symbol_table: SymbolTable = .{};
    try symbol_table.append(gpa, .{});

    return .{
        .gpa = gpa,
        .oir = oir,
        .tree = tree,
        .ctrl_class = ctrl_class,
        .node_to_class = .{},
        .exits = &oir.exit_list,
        .scratch = .{},
        .symbol_table = symbol_table,
    };
}

pub fn build(cg: *CodeGen) !Recursive {
    const stdout = std.io.getStdOut().writer();

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

    return .{};
}

fn buildFn(cg: *CodeGen, decl: Tree.Node.Index) !void {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    switch (decl.get(tree)) {
        .fn_def => |def| {
            const func_ty = def.qt.base(tree.comp).type.func;
            for (func_ty.params) |param| {
                std.debug.print("TODO: param: {}\n", .{param});
            }
            try cg.buildStmt(def.body);
        },
        .typedef => {},
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(decl)])}),
    }
}

fn buildStmt(cg: *CodeGen, stmt: Tree.Node.Index) !void {
    const scratch_top = cg.scratch.items.len;
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    switch (stmt.get(tree)) {
        .return_stmt => |ret| {
            const operand: Oir.Class.Index = switch (ret.operand) {
                .expr => |idx| try cg.buildExpr(idx),
                .implicit => |zeroes| {
                    _ = zeroes;
                    @panic("TODO");
                },
                .none => @panic("TODO"),
            };

            const node = try cg.oir.add(.binOp(
                .ret,
                cg.ctrl_class.?,
                operand,
            ));

            try cg.exits.append(cg.gpa, node);
            try cg.node_to_class.put(cg.gpa, stmt, node);
            cg.ctrl_class = null; // nothing can exist after return
        },
        .if_stmt => |cond_br| {
            const predicate = try cg.buildExpr(cond_br.cond);

            const branch = try cg.oir.add(.branch(cg.ctrl_class.?, predicate));
            const then_project = try cg.oir.add(.project(0, branch, .ctrl));
            const else_project = try cg.oir.add(.project(1, branch, .ctrl));

            cg.ctrl_class = then_project;
            try cg.buildStmt(cond_br.then_body);
            const latest_then_ctrl = cg.ctrl_class;

            cg.ctrl_class = else_project;
            try cg.buildStmt(cond_br.else_body orelse @panic("TODO"));
            const latest_else_ctrl = cg.ctrl_class;

            if (latest_then_ctrl == null and latest_else_ctrl == null) {
                // this region is dead, we can ignore it
                return;
            }

            if (latest_then_ctrl) |ctrl| {
                try cg.scratch.append(cg.gpa, ctrl);
            }
            if (latest_else_ctrl) |ctrl| {
                try cg.scratch.append(cg.gpa, ctrl);
            }

            const items = cg.scratch.items[scratch_top..];
            const list = try cg.oir.listToSpan(items);
            cg.ctrl_class = try cg.oir.add(.region(list));
        },
        .compound_stmt => |compound| {
            for (compound.body) |s| try cg.buildStmt(s);
            return; // nothing to add to the oir
        },
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(stmt)])}),
    }
}

fn buildExpr(cg: *CodeGen, expr: Tree.Node.Index) !Oir.Class.Index {
    const tree = cg.tree;
    const node_tags = tree.nodes.items(.tag);

    if (cg.node_to_class.get(expr)) |c| return c;
    if (tree.value_map.get(expr)) |val| {
        return cg.buildConstant(expr, val);
    }

    switch (expr.get(tree)) {
        .int_literal => unreachable, // handled in the value_map above
        else => std.debug.panic("TODO: {s}", .{@tagName(node_tags[@intFromEnum(expr)])}),
    }
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
    cg.scratch.deinit(allocator);
    for (cg.symbol_table.items) |*table| {
        table.deinit(allocator);
    }
    cg.symbol_table.deinit(allocator);
}
