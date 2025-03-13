//! Translates an IR function into OIR.

const Extractor = @This();
const std = @import("std");
const Oir = @import("../Oir.zig");
const Ir = @import("../Ir.zig");
const Inst = Ir.Inst;

oir: *Oir,
ir: *const Ir,
start_class: Class.Index,
ir_to_class: std.AutoHashMapUnmanaged(Inst.Index, Class.Index) = .{},
block_info: std.AutoHashMapUnmanaged(Inst.Index, BlockInfo) = .{},
start_args: std.ArrayListUnmanaged(Class.Index) = .{},

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
        .extra = .{},
        .clean = true,
    };

    const start_class = try oir.add(.{ .tag = .start });

    var extractor: Extractor = .{
        .oir = &oir,
        .ir = &ir,
        .start_class = start_class,
        .ir_to_class = .{},
    };
    defer extractor.deinit();

    try extractor.extractBody(ir.main_body);
    try oir.rebuild();

    return oir;
}

fn extractBody(e: *Extractor, insts: []const Inst.Index) error{OutOfMemory}!void {
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
        .arg => {
            const index = data.arg;
            const node: Node = .{
                .tag = .project,
                .data = .{ .project = .{
                    .index = index,
                    .tuple = e.start_class,
                } },
            };

            const arg_idx = try oir.add(node);
            try e.ir_to_class.put(allocator, inst, arg_idx);
        },
        .ret => {
            const un_op = data.un_op;
            const node: Node = .{
                .tag = .ret,
                .data = .{
                    .bin_op = .{
                        e.start_class,
                        try e.matOrGet(un_op),
                    },
                },
            };

            const idx = try oir.add(node);
            try e.start_args.append(allocator, idx);
            try e.ir_to_class.put(allocator, inst, idx);
        },
        .load,
        .store,
        => {
            const un_op = data.un_op;
            const node: Node = .{
                .tag = switch (tag) {
                    .load => .load,
                    .store => .store,
                    else => unreachable,
                },
                .data = .{ .un_op = try e.matOrGet(un_op) },
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
    e.start_args.deinit(allocator);
}
