gpa: std.mem.Allocator,

liveins: std.ArrayListUnmanaged(Register) = .{},
instructions: std.MultiArrayList(Instruction) = .{},
frame_allocs: std.MultiArrayList(bits.FrameAlloc) = .{},

/// The number of virtual registers allocated.
///
/// TODO: we should copy the basic register allocator from Zig
/// and use it here instead. only difference is that we can in theory
/// have an infinite amount of virtual registers allocated at once.
virt_regs: u32 = 1,

/// The number of argument registers already used.
///
/// TODO: this is a very crude solution to basic livein tracking.
arg_regs: u32 = 0,

const Instruction = struct {
    tag: Tag,
    data: Data,

    const Data = union(enum) {
        /// A RISC-V Register.
        ///
        /// Preferable to use in cases where an instruction *only* takes a RISC-V Register
        /// and not any Value.
        reg: Register,
        /// Two values.
        bin_op: BinOp,
        /// One value.
        un_op: Value,
    };

    const Index = enum(u32) {
        _,
    };

    const BinOp = struct {
        lhs: Value,
        rhs: Value,
    };

    pub const Tag = enum {
        copy,
        pseudo_ret,

        add,
    };
};

const Value = union(enum) {
    none: void,
    register: Register,
    virtual: bits.VirtualRegister,

    pub fn format(
        value: Value,
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        assert(fmt.len == 0);

        switch (value) {
            .register => |reg| try writer.print("${s}", .{@tagName(reg)}),
            .virtual => |vreg| try writer.print("%{d}:{s}", .{ @intFromEnum(vreg.index), @tagName(vreg.class) }),
            else => try writer.print("TODO: Value.format {s}", .{@tagName(value)}),
        }
    }
};

pub const Extractor = struct {
    oir: *Oir,
    mir: *Mir,
    cost_strategy: Oir.CostStrategy,

    /// Extracts the best pattern of Oir from the E-Graph given a cost model.
    pub fn extract(e: *Extractor) !void {
        // First we need to find what the root class is. This will usually be the class containing a `ret`,
        // or something similar.
        const ret_node_idx = e.findLeafNode();

        std.debug.print("leaf: {}\n", .{ret_node_idx});

        // Walk from that return node and extract the best classes.
        _ = try e.extractNode(ret_node_idx);
    }

    /// TODO: don't just search for a `ret` node,
    /// instead compute the mathematical leaves of the graph
    fn findLeafNode(e: *Extractor) Node.Index {
        const oir = e.oir;
        const ret_node_idx: Node.Index = idx: for (oir.classes.items) |class| {
            for (class.bag.items) |node_idx| {
                const node = oir.getNode(node_idx);
                if (node.tag == .ret) break :idx node_idx;
            }
        } else @panic("no `ret` in extract() input IR");
        return ret_node_idx;
    }

    /// Given a `Node.Index`, walk the edges of that node to find the optimal
    /// linear nodes to make up the graph. Converts the normal "node-class" relationship
    /// into a "node-node" one, where the child node is extracted from its class using
    /// the given cost model.
    fn extractNode(
        e: *Extractor,
        node_idx: Node.Index,
    ) !Value {
        const gpa = e.mir.gpa;
        const oir = e.oir;
        const mir = e.mir;
        const node = oir.getNode(node_idx);

        switch (node.tag) {
            .arg => {
                assert(node.out.items.len == 0);
                // TODO: we're just assuming each argument takes 1 input register for now
                defer {
                    mir.arg_regs += 1;
                    mir.virt_regs += 1;
                }

                const arg_reg: Register = bits.Registers.Integer.function_arg_regs[mir.arg_regs];
                try mir.liveins.append(gpa, arg_reg);

                const arg_value: Value = .{ .register = arg_reg };
                const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.gpr) };

                try mir.copyValue(dst_value, arg_value);

                return dst_value;
            },
            .ret => {
                assert(node.out.items.len == 1);
                const class_idx = node.out.items[0];

                const arg_idx = e.extractClass(class_idx);
                const arg_value = try e.extractNode(arg_idx);

                try mir.copyValue(.{ .register = .a0 }, arg_value);

                _ = try mir.addUnOp(.{
                    .tag = .pseudo_ret,
                    .data = .{ .reg = .a0 },
                });
                return .none;
            },
            else => std.debug.panic("TODO: mir extractNode {s}", .{@tagName(node.tag)}),
        }
    }

    /// Given a class, extract the "best" node from it.
    fn extractClass(e: *Extractor, class_idx: Class.Index) Node.Index {
        // for now, just select the first node in the class bag
        const class = e.oir.getClass(class_idx);
        const index: usize = if (class.bag.items.len > 1) 1 else 0;
        return class.bag.items[index];
    }
};

fn addUnOp(mir: *Mir, op: Instruction) !Instruction.Index {
    const idx: Instruction.Index = @enumFromInt(mir.instructions.len);
    try mir.instructions.append(mir.gpa, op);
    return idx;
}

// fn allocFrameIndex(mir: *Mir, alloc: bits.FrameAlloc) !FrameIndex {
//     const frame_index: FrameIndex = @enumFromInt(mir.frame_allocs.len);
//     try mir.frame_allocs.append(mir.gpa, alloc);
//     log.debug("allocated frame {}", .{frame_index});
//     return frame_index;
// }

fn allocVirtualReg(mir: *Mir, class: VirtualRegister.Class) !VirtualRegister {
    defer mir.virt_regs += 1;
    return .{
        .class = class,
        .index = @enumFromInt(mir.virt_regs),
    };
}

fn copyValue(mir: *Mir, dst: Value, src: Value) !void {
    switch (dst) {
        .virtual,
        .register,
        => {
            const instruction: Instruction = .{
                .tag = .copy,
                .data = .{ .bin_op = .{
                    .lhs = dst,
                    .rhs = src,
                } },
            };
            _ = try mir.addUnOp(instruction);
        },
        else => std.debug.panic("TODO: copyValue {s} -> {s}", .{ @tagName(dst), @tagName(src) }),
    }
}

pub fn deinit(mir: *Mir) void {
    const gpa = mir.gpa;
    mir.instructions.deinit(gpa);
    mir.liveins.deinit(gpa);
}

pub fn dump(mir: *Mir, s: anytype) !void {
    var w: Writer = .{
        .mir = mir,
        .indent = 0,
    };

    // print the liveins
    try s.writeAll("liveins: { ");
    for (mir.liveins.items, 0..) |reg, i| {
        try s.writeAll(@tagName(reg));
        if (i != mir.liveins.items.len - 1) try s.writeAll(",");
        try s.writeAll(" ");
    }
    try s.writeAll("}\n");

    w.indent = 4;
    for (0..mir.instructions.len) |i| {
        try w.printInst(@enumFromInt(i), s);
        try s.writeByte('\n');
    }
}

const Writer = struct {
    mir: *const Mir,
    indent: usize,

    pub fn printInst(
        w: *Writer,
        inst: Instruction.Index,
        s: anytype,
    ) @TypeOf(s).Error!void {
        const instructions = w.mir.instructions;
        const tag = instructions.items(.tag)[@intFromEnum(inst)];
        const data = instructions.items(.data)[@intFromEnum(inst)];

        try s.writeByteNTimes(' ', w.indent);
        switch (tag) {
            .pseudo_ret => try s.print("RET ${s}", .{@tagName(data.reg)}),
            .copy => {
                const copy = data.bin_op;
                try s.print("{} = COPY {}", .{
                    copy.lhs,
                    copy.rhs,
                });
            },
            else => try s.print("TODO: Writer.printInst {s}", .{@tagName(tag)}),
        }
    }
};

const Mir = @This();
const std = @import("std");
const Oir = @import("Oir.zig");
const bits = @import("bits.zig");

const Class = Oir.Class;
const Node = Oir.Node;

const Register = bits.Register;
const VirtualRegister = bits.VirtualRegister;
const Memory = bits.Memory;
const FrameIndex = bits.FrameIndex;

const log = std.log.scoped(.mir);
const assert = std.debug.assert;
