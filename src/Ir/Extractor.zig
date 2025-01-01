//! Translates IR into OIR.

const Extractor = @This();
const std = @import("std");
const Oir = @import("../Oir.zig");
const Ir = @import("../Ir.zig");
const Inst = Ir.Inst;

oir: *Oir,
ir: *const Ir,
ir_to_class: std.AutoHashMapUnmanaged(Inst.Index, Class.Index) = .{},
block_info: std.AutoHashMapUnmanaged(Inst.Index, BlockInfo) = .{},

const Class = Oir.Class;
const Node = Oir.Node;

const BlockInfo = struct {
    branch: Class.Index,
};

pub fn extract(ir: Ir, allocator: std.mem.Allocator) !Oir {
    var oir: Oir = .{
        .allocator = allocator,
        .nodes = .{},
        .classes = .{},
        .node_to_class = .{},
        .union_find = .{},
        .pending = .{},
        .clean = true,
    };

    var extractor: Extractor = .{
        .oir = &oir,
        .ir = &ir,
        .ir_to_class = .{},
    };
    defer extractor.deinit();

    try extractor.selectBody(ir.main_body);

    try oir.rebuild();
    return oir;
}

fn selectBody(e: *Extractor, insts: []const Inst.Index) error{OutOfMemory}!void {
    for (insts) |inst| {
        try e.select(inst);
    }
}

fn select(e: *Extractor, inst: Inst.Index) !void {
    const oir = e.oir;
    const ir = e.ir;
    const allocator = oir.allocator;
    const ir_to_class = &e.ir_to_class;

    const tag = ir.instructions.items(.tag)[@intFromEnum(inst)];
    const data = ir.instructions.items(.data)[@intFromEnum(inst)];

    switch (tag) {
        .ret,
        .load,
        .store,
        => {
            const op = data.un_op;
            const node: Node = .{
                .tag = switch (tag) {
                    .ret => .ret,
                    .load => .load,
                    .store => .store,
                    else => unreachable,
                },
                .data = .{ .un_op = try e.matOrGet(op) },
            };

            const idx = try oir.add(node);
            try ir_to_class.put(allocator, inst, idx);
        },
        .add,
        .sub,
        .div_exact,
        .mul,
        .cmp_gt,
        => {
            var node: Node = .{
                .tag = switch (tag) {
                    .add => .add,
                    .sub => .sub,
                    .div_exact => .div_exact,
                    .mul => .mul,
                    .cmp_gt => .cmp_gt,
                    else => unreachable,
                },
                .data = .{ .bin_op = undefined },
            };

            const bin_op = data.bin_op;
            inline for (.{ bin_op.lhs, bin_op.rhs }, 0..) |operand, sub_i| {
                node.data.bin_op[sub_i] = try e.matOrGet(operand);
            }

            const idx = try oir.add(node);
            try ir_to_class.put(allocator, inst, idx);
        },
        .arg,
        => {
            const node: Node = .{
                .tag = switch (tag) {
                    .arg => .arg,
                    else => unreachable,
                },
                .data = .{ .constant = data.un_op.value },
            };
            const idx = try oir.add(node);
            try ir_to_class.put(allocator, inst, idx);
        },
        .block => {
            const body = data.list;
            try e.selectBody(body);

            const block_info = e.block_info.get(inst).?;
            try ir_to_class.put(allocator, inst, block_info.branch);
        },
        .cond_br => {
            const cond_br: Inst.Data.CondBr = data.cond_br;

            const then_br_inst = for (cond_br.then) |then_inst| {
                if (ir.instructions.get(@intFromEnum(then_inst)).tag == .br) break then_inst;
            } else @panic("no then br");

            const else_br_inst = for (cond_br.@"else") |else_inst| {
                if (ir.instructions.get(@intFromEnum(else_inst)).tag == .br) break else_inst;
            } else @panic("no else br");

            const then_br = ir.instructions.get(@intFromEnum(then_br_inst));
            const else_br = ir.instructions.get(@intFromEnum(else_br_inst));

            var exit_values: std.ArrayListUnmanaged(Class.Index) = .{};
            try exit_values.appendSlice(allocator, &.{
                try e.matOrGet(then_br.data.bin_op.rhs),
                try e.matOrGet(else_br.data.bin_op.rhs),
            });

            var map: std.AutoHashMapUnmanaged(Class.Index, Class.Index) = .{};
            _ = &map;
            for (cond_br.then) |then_inst| {
                std.debug.print("then_inst: {}\n", .{then_inst});
            }

            const gamma: Node = .{
                .tag = .gamma,
                .data = .{ .gamma = .{
                    .predicate = ir_to_class.get(cond_br.pred).?,
                    .map = map,
                    .exit_values = exit_values,
                } },
            };

            const idx = try oir.add(gamma);
            try ir_to_class.put(allocator, inst, idx);

            if (then_br.data.bin_op.lhs.index != else_br.data.bin_op.lhs.index) {
                @panic("TODO: nested blocks");
            }
            const parent_block = then_br.data.bin_op.lhs.index;
            try e.block_info.put(allocator, parent_block, .{ .branch = idx });
        },
        else => std.debug.panic("TODO: find {s}", .{@tagName(tag)}),
    }
}

fn matOrGet(e: *Extractor, op: Inst.Operand) !Class.Index {
    switch (op) {
        .index => |idx| return e.ir_to_class.get(idx).?,
        .value => |val| {
            const const_node: Node = .{
                .tag = .constant,
                .data = .{ .constant = val },
            };
            return e.oir.add(const_node);
        },
    }
}

fn deinit(e: *Extractor) void {
    const allocator = e.oir.allocator;
    e.ir_to_class.deinit(allocator);
    e.block_info.deinit(allocator);
}
