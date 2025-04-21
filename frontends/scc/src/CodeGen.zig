const std = @import("std");
const zob = @import("zob");
const Ast = @import("Ast.zig");
const CodeGen = @This();

const Oir = zob.Oir;
const Recursive = zob.Recursive;

gpa: std.mem.Allocator,
oir: *Oir,
ast: *const Ast,
ctrl_class: ?Oir.Class.Index,
exits: *std.ArrayListUnmanaged(Oir.Class.Index),
node_to_class: std.AutoHashMapUnmanaged(Ast.Node.Index, Oir.Class.Index),
symbol_table: SymbolTable,
scratch: std.ArrayListUnmanaged(Oir.Class.Index),

const Error = error{OutOfMemory};
const SymbolTable = std.ArrayListUnmanaged(std.StringHashMapUnmanaged(Oir.Class.Index));

pub fn init(oir: *Oir, gpa: std.mem.Allocator, ast: *const Ast) !CodeGen {
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
        .ast = ast,
        .ctrl_class = ctrl_class,
        .node_to_class = .{},
        .exits = &oir.exit_list,
        .scratch = .{},
        .symbol_table = symbol_table,
    };
}

pub fn build(cg: *CodeGen) !Recursive {
    const stdout = std.io.getStdOut().writer();

    try cg.buildBlock(.root);
    try cg.oir.rebuild();

    try stdout.writeAll("unoptimized OIR:\n");
    try cg.oir.print(stdout);
    try stdout.writeAll("end OIR\n");

    try cg.oir.optimize(.saturate, false);
    try cg.oir.dump("test.dot");

    const extracted = try cg.oir.extract(.auto);

    try stdout.writeAll("optimized OIR:\n");
    try extracted.print(stdout);
    try stdout.writeAll("end OIR\n");

    return extracted;
}

fn buildStatement(cg: *CodeGen, idx: Ast.Node.Index) Error!void {
    const ast = cg.ast;
    const tag = ast.nodes.items(.tag)[@intFromEnum(idx)];

    switch (tag) {
        .block => try cg.buildBlock(idx),
        .@"return" => try cg.buildReturn(idx),
        .@"if" => try cg.buildIf(idx),
        .assign => try cg.buildAssign(idx),
        else => std.debug.panic("TODO: buildStatement {s}", .{@tagName(tag)}),
    }
}

fn buildExpression(cg: *CodeGen, idx: Ast.Node.Index) Error!Oir.Class.Index {
    const ast = cg.ast;
    const tag = ast.nodes.items(.tag)[@intFromEnum(idx)];
    const main_token = ast.nodes.items(.main_token)[@intFromEnum(idx)];
    const data = ast.nodes.items(.data)[@intFromEnum(idx)];

    if (cg.node_to_class.get(idx)) |c| return c;

    const class = switch (tag) {
        .add,
        .sub,
        .mul,
        .div,
        .equal,
        .greater_than,
        => c: {
            const bin_op = data.bin_op;
            const lhs = try cg.buildExpression(bin_op.lhs);
            const rhs = try cg.buildExpression(bin_op.rhs);
            const class = try cg.oir.add(.binOp(
                switch (tag) {
                    .add => .add,
                    .sub => .sub,
                    .mul => .mul,
                    .div => .div_trunc,
                    .equal => .cmp_eq,
                    .greater_than => .cmp_gt,
                    else => unreachable,
                },
                lhs,
                rhs,
            ));
            break :c class;
        },
        .group => try cg.buildExpression(data.un_op),
        .number_literal => try cg.oir.add(.constant(data.int)),
        .identifier => c: {
            const ident = cg.ast.ident(main_token.unwrap().?);
            const class = cg.findIdentifier(ident) orelse
                std.debug.panic("couldn't find identifier '{s}'", .{ident});
            break :c class.*;
        },
        else => std.debug.panic("TODO: buildExpression {s}", .{@tagName(tag)}),
    };

    try cg.node_to_class.put(cg.gpa, idx, class);
    return class;
}

fn findIdentifier(cg: *CodeGen, ident: []const u8) ?*Oir.Class.Index {
    for (0..cg.symbol_table.items.len) |i| {
        const rev = cg.symbol_table.items.len - i - 1;
        if (cg.symbol_table.items[rev].getPtr(ident)) |class| return class;
    }
    return null;
}

fn buildBlock(cg: *CodeGen, idx: Ast.Node.Index) Error!void {
    const ast = cg.ast;
    const items = ast.spanToList(idx);
    try cg.symbol_table.append(cg.gpa, .{});
    for (items) |item| {
        try cg.buildStatement(item);
    }
    var old = cg.symbol_table.pop().?;
    old.deinit(cg.gpa);
}

fn buildReturn(cg: *CodeGen, idx: Ast.Node.Index) Error!void {
    const operand = cg.ast.getNode(idx).data.un_op;
    const operand_class = try cg.buildExpression(operand);

    const node = try cg.oir.add(.binOp(
        .ret,
        cg.ctrl_class.?,
        operand_class,
    ));

    try cg.exits.append(cg.gpa, node);
    try cg.node_to_class.put(cg.gpa, idx, node);
    cg.ctrl_class = null;
}

fn buildIf(cg: *CodeGen, idx: Ast.Node.Index) Error!void {
    const scratch_top = cg.scratch.items.len;
    defer cg.scratch.shrinkRetainingCapacity(scratch_top);

    const cond_br = cg.ast.getNode(idx).data.cond_br;

    const predicate = try cg.buildExpression(cond_br.pred);

    const branch = try cg.oir.add(.branch(cg.ctrl_class.?, predicate));
    const then_project = try cg.oir.add(.project(0, branch, .ctrl));
    const else_project = try cg.oir.add(.project(1, branch, .ctrl));

    cg.ctrl_class = then_project;
    try cg.buildBlock(cond_br.then);
    const latest_then_ctrl = cg.ctrl_class;

    cg.ctrl_class = else_project;
    try cg.buildBlock(cond_br.@"else");
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
}

fn buildAssign(cg: *CodeGen, idx: Ast.Node.Index) Error!void {
    const ident_token, const rvalue_node = cg.ast.getNode(idx).data.token_and_node;

    const rvalue = try cg.buildExpression(rvalue_node);
    const ident = cg.ast.ident(ident_token);

    if (cg.findIdentifier(ident)) |existing| {
        existing.* = rvalue;
    } else {
        const latest = &cg.symbol_table.items[cg.symbol_table.items.len - 1];
        try latest.put(cg.gpa, ident, rvalue);
    }
}

pub fn deinit(cg: *CodeGen, allocator: std.mem.Allocator) void {
    cg.node_to_class.deinit(allocator);
    cg.scratch.deinit(allocator);
    for (cg.symbol_table.items) |*table| {
        table.deinit(allocator);
    }
    cg.symbol_table.deinit(allocator);
}
