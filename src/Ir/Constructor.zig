//! Constructs OIR from IR.

const Extractor = @This();
const std = @import("std");
const Oir = @import("../Oir.zig");
const Ir = @import("../Ir.zig");
const Trace = @import("../Trace.zig");
const Inst = Ir.Inst;

oir: *Oir,
ir: *const Ir,
start_class: Class.Index,
ctrl_class: ?Class.Index,
ir_to_class: std.AutoHashMapUnmanaged(Inst.Index, Class.Index) = .{},
block_info: std.AutoHashMapUnmanaged(Inst.Index, BlockInfo) = .{},
exits: std.ArrayListUnmanaged(Class.Index) = .{},
scratch: std.ArrayListUnmanaged(Class.Index) = .{},

const Class = Oir.Class;
const Node = Oir.Node;

const BlockInfo = struct {
    branch: Class.Index,
};

pub fn extract(
    ir: Ir,
    allocator: std.mem.Allocator,
) !Oir {
    var oir: Oir = .init(allocator);

    const start_class = try oir.add(.{
        .tag = .start,
        .data = .{ .list = .{ .start = 0, .end = 0 } },
    });

    // We can guarntee that the start node will never move,
    // since the `start` node is absorbant.
    const ctrl_class = try oir.add(.project(0, start_class, .ctrl));

    var extractor: Extractor = .{
        .oir = &oir,
        .ir = &ir,
        .start_class = start_class,
        .ctrl_class = ctrl_class,
        .ir_to_class = .{},
    };
    defer extractor.deinit();

    try extractor.extractBody(ir.main_body);

    try oir.rebuild();

    // Update the `start` node, now that we've generated all exits.
    const exit_list = try oir.listToSpan(extractor.exits.items);
    try oir.modifyNode(.start, .{
        .tag = .start,
        .data = .{ .list = exit_list },
    });

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

    const scratch_top = e.scratch.items.len;
    defer e.scratch.shrinkRetainingCapacity(scratch_top);

    const tag = ir.instructions.items(.tag)[@intFromEnum(inst)];
    const data = ir.instructions.items(.data)[@intFromEnum(inst)];

    switch (tag) {
        .arg => {
            const arg_idx = try oir.add(.project(
                data.arg + 1,
                e.start_class,
                .data,
            ));
            try e.ir_to_class.put(allocator, inst, arg_idx);
        },
        .ret => {
            const un_op = data.un_op;
            const node: Node = .binOp(
                .ret,
                e.ctrl_class.?,
                try e.matOrGet(un_op),
            );

            const idx = try oir.add(node);
            try e.exits.append(allocator, idx);
            try e.ir_to_class.put(allocator, inst, idx);
            // nothing further in this block could mutate the control edge
            // another region will need to re-set it.
            e.ctrl_class = null;
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
        .div_trunc,
        .mul,
        .cmp_gt,
        => {
            var node: Node = .{
                .tag = switch (tag) {
                    .add => .add,
                    .sub => .sub,
                    .div_exact => .div_exact,
                    .div_trunc => .div_trunc,
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
        .block => {
            const payload = data.list;
            try e.extractBody(payload);
        },
        .cond_br => {
            const cond_br = data.cond_br;
            const pred = e.ir_to_class.get(cond_br.pred).?;

            const branch = try oir.add(.branch(e.ctrl_class.?, pred));
            const true_project = try oir.add(.project(0, branch, .ctrl));
            const false_project = try oir.add(.project(1, branch, .ctrl));

            e.ctrl_class = true_project;
            try e.extractBody(cond_br.then);
            const latest_true_ctrl = e.ctrl_class;

            e.ctrl_class = false_project;
            try e.extractBody(cond_br.@"else");
            const latest_false_ctrl = e.ctrl_class;

            if (latest_false_ctrl == null and
                latest_true_ctrl == null)
            {
                // this region is completely dead, we can ignore it
                return;
            }

            if (latest_true_ctrl) |ctrl| {
                try e.scratch.append(allocator, ctrl);
            }
            if (latest_false_ctrl) |ctrl| {
                try e.scratch.append(allocator, ctrl);
            }

            const items = e.scratch.items[scratch_top..];
            const list = try oir.listToSpan(items);
            e.ctrl_class = try oir.add(.region(list));
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
    e.exits.deinit(allocator);
    e.scratch.deinit(allocator);
}
