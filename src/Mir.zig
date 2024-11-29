gpa: std.mem.Allocator,

instructions: std.MultiArrayList(Instruction) = .{},
frame_allocs: std.MultiArrayList(bits.FrameAlloc) = .{},

pass_data: std.StringHashMapUnmanaged(PassMetadata) = .{},

/// The number of virtual registers allocated.
///
/// TODO: we should copy the basic register allocator from Zig
/// and use it here instead. only difference is that we can in theory
/// have an infinite amount of virtual registers allocated at once.
virt_regs: u32 = 1,

pub const Instruction = struct {
    tag: Tag,
    data: Data,

    pub const Data = union(enum) {
        /// A RISC-V Register.
        ///
        /// Preferable to use in cases where an instruction *only* takes a RISC-V Register
        /// and not any Value. An example is `pseudo_ret`.
        register: Register,
        /// Two inputs + One output,
        bin_op: BinOp,
        /// One input + One output,
        un_op: UnOp,
        none: void,
    };

    pub const Index = enum(u32) {
        _,
    };

    pub const BinOp = struct {
        lhs: Value,
        rhs: Value,
        dst: Value,
    };

    pub const UnOp = struct {
        src: Value,
        dst: Value,
    };

    pub const Tag = enum {
        // Pseudo instructions. Will be expanded before instruction encoded.
        copy,
        pseudo_ret,

        /// Add
        add,
        /// Add Immediate
        addi,
        /// Load Double
        ld,
        /// Shift-left
        sll,
        /// Shift-left Immediate
        slli,
        /// Shift-right
        srl,
        /// Shift-right Immediate
        srli,
        /// Divide
        div,
        /// Multiply
        mul,

        /// An instruction that is considered a tombstone.
        /// Ignored by MIR printers, analysis passes, and other things.
        /// TODO: write some sort of rebuilder that removes these and
        /// recomputes other instruction's references.
        tombstone,

        pub fn canHaveVRegOperand(tag: Tag) bool {
            return switch (tag) {
                .pseudo_ret,
                .tombstone,
                => false,
                else => true,
            };
        }

        /// Returns the number of operands an instruction has.
        ///
        /// Mainly used in cases where we want to simply iterate
        /// over all operands.
        ///
        /// NOTE: this does include the destination operand.
        pub fn numOperands(tag: Tag) u32 {
            return switch (tag) {
                .tombstone,
                => 0,
                .pseudo_ret,
                => 1,
                .copy,
                .ld,
                => 2,
                .add,
                .addi,
                .sll,
                .slli,
                => 3,
            };
        }

        pub fn immediateVersion(tag: Tag) Tag {
            return switch (tag) {
                .sll => .slli,
                .srl => .srli,
                .add => .addi,
                else => unreachable,
            };
        }
    };
};

/// Machine Code Value
pub const Value = union(enum) {
    none: void,
    register: Register,
    virtual: bits.VirtualRegister,
    immediate: i64,

    pub fn format(
        value: Value,
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        comptime assert(fmt.len == 0);

        switch (value) {
            inline .register, .virtual => |reg| try writer.print("{}", .{reg}),
            .immediate => |imm| try writer.print("{}", .{imm}),
            else => try writer.print("TODO: Value.format {s}", .{@tagName(value)}),
        }
    }
};

pub const Extractor = struct {
    oir: *Oir,
    mir: *Mir,
    cost_strategy: Oir.CostStrategy,
    virt_map: std.AutoHashMapUnmanaged(Register, VirtualRegister) = .{},

    /// Relates class indicies to the best node in them. Since the classes
    /// are immutable after the OIR optimization passes, we can confidently
    /// reuse the extraction. This amortization makes our extraction strategy
    /// just barely usable.
    memo: std.AutoHashMapUnmanaged(Class.Index, NodeCost) = .{},

    const NodeCost = struct {
        u32,
        Node.Index,
    };

    /// Extracts the best pattern of Oir from the E-Graph given a cost model.
    pub fn extract(e: *Extractor) !void {
        // First we need to find what the root class is. This will usually be the class containing a `ret`,
        // or something similar.
        const ret_node_idx = e.findLeafNode();

        // Walk from that return node and extract the best classes.
        _ = try e.extractNode(ret_node_idx);
    }

    /// TODO: don't just search for a `ret` node, there can be multiple
    fn findLeafNode(e: *Extractor) Node.Index {
        const oir = e.oir;
        const ret_node_idx: Node.Index = idx: {
            var class_iter = oir.classes.valueIterator();
            while (class_iter.next()) |class| {
                for (class.bag.items) |node_idx| {
                    const node = oir.getNode(node_idx);
                    if (node.tag == .ret) break :idx node_idx;
                }
            }
            @panic("no ret node found!");
        };

        return ret_node_idx;
    }

    /// Given a `Node`, walk the edges of that node to find the optimal
    /// linear nodes to make up the graph. Converts the normal "node-class" relationship
    /// into a "node-node" one, where the child node is extracted from its class using
    /// the given cost model.
    fn extractNode(
        e: *Extractor,
        node_idx: Node.Index,
    ) !Value {
        const oir = e.oir;
        const mir = e.mir;
        const node = oir.getNode(node_idx);

        switch (node.tag) {
            .arg => {
                const arg_reg: Register = bits.Registers.Integer.function_arg_regs[@intCast(node.data.constant)];
                const arg_value: Value = .{ .register = arg_reg };
                const gop = try e.virt_map.getOrPut(oir.allocator, arg_reg);
                const virt_reg: VirtualRegister = blk: {
                    if (gop.found_existing) {
                        break :blk gop.value_ptr.*;
                    } else {
                        const virt_reg: VirtualRegister = try mir.allocVirtualReg(.int);
                        gop.value_ptr.* = virt_reg;
                        break :blk virt_reg;
                    }
                };
                const dst_value: Value = .{ .virtual = virt_reg };

                try mir.copyValue(dst_value, arg_value);

                return dst_value;
            },
            .ret => {
                const class_idx = node.data.un_op;

                const arg_idx = try e.getClass(class_idx);
                const arg_value = try e.getNode(arg_idx);

                try mir.copyValue(.{ .register = .a0 }, arg_value);

                _ = try mir.addUnOp(.{
                    .tag = .pseudo_ret,
                    .data = .{ .register = .a0 },
                });
                return .none;
            },
            // memory operations
            .load => {
                const class_idx = node.data.un_op;

                const arg_idx = try e.getClass(class_idx);
                const arg_value = try e.getNode(arg_idx);

                const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.int) };

                _ = try mir.addUnOp(.{
                    .tag = .ld, // just assuming 8-bytes for now
                    .data = .{ .un_op = .{
                        .dst = dst_value,
                        .src = arg_value,
                    } },
                });

                return dst_value;
            },
            // non-commutative instructions
            .div_exact,
            .mul, // putting mul here for now even though it's commutative
            => {
                const rhs_class_idx, const lhs_class_idx = node.data.bin_op;

                const rhs_idx = try e.getClass(rhs_class_idx);
                const lhs_idx = try e.getClass(lhs_class_idx);

                var rhs_value = try e.getNode(rhs_idx);
                var lhs_value = try e.getNode(lhs_idx);

                const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.int) };

                const tag: Mir.Instruction.Tag = switch (node.tag) {
                    .div_exact => .div,
                    .mul => .mul,
                    else => unreachable,
                };

                if (lhs_value == .immediate) {
                    // we want the immediate value to be rhs, uh because it looks nice!
                    std.mem.swap(Value, &rhs_value, &lhs_value);
                }

                _ = try mir.addUnOp(.{
                    .tag = tag,
                    .data = .{ .bin_op = .{
                        .rhs = rhs_value,
                        .lhs = lhs_value,
                        .dst = dst_value,
                    } },
                });

                return dst_value;
            },

            // commutative instructions with immediate versions
            .add,
            .shl,
            .shr,
            => {
                const rhs_class_idx, const lhs_class_idx = node.data.bin_op;

                const rhs_idx = try e.getClass(rhs_class_idx);
                const lhs_idx = try e.getClass(lhs_class_idx);

                var rhs_value = try e.getNode(rhs_idx);
                var lhs_value = try e.getNode(lhs_idx);

                var tag: Mir.Instruction.Tag = switch (node.tag) {
                    .add => .add,
                    .shl => .sll,
                    .shr => .srl,
                    else => unreachable,
                };

                if (rhs_value == .immediate) {
                    tag = tag.immediateVersion();
                } else if (lhs_value == .immediate) {
                    // we want the immediate value to be rhs
                    tag = tag.immediateVersion();
                    std.mem.swap(Value, &rhs_value, &lhs_value);
                }

                const dst_value: Value = .{ .virtual = try mir.allocVirtualReg(.int) };

                _ = try mir.addUnOp(.{
                    .tag = tag,
                    .data = .{ .bin_op = .{
                        .rhs = rhs_value,
                        .lhs = lhs_value,
                        .dst = dst_value,
                    } },
                });

                return dst_value;
            },
            .constant => {
                const value: Value = .{ .immediate = node.data.constant };
                return value;
            },
            else => std.debug.panic("TODO: mir extractNode {s}", .{@tagName(node.tag)}),
        }
    }

    fn getNode(e: *Extractor, node: Node.Index) error{OutOfMemory}!Value {
        return e.extractNode(node);
    }

    fn getClass(e: *Extractor, class_idx: Class.Index) !Node.Index {
        _, const best_node = try e.extractClass(class_idx);

        log.debug("best node for class {} is {s}", .{
            class_idx,
            @tagName(e.oir.getNode(best_node).tag),
        });

        return best_node;
    }

    /// Given a class, extract the "best" node from it.
    fn extractClass(e: *Extractor, class_idx: Class.Index) !NodeCost {
        const oir = e.oir;
        const class = oir.classes.get(class_idx).?;
        assert(class.bag.items.len > 0);

        const gop = try e.memo.getOrPut(oir.allocator, class_idx);
        if (gop.found_existing) return gop.value_ptr.*;

        switch (e.cost_strategy) {
            .simple_latency => {
                var best_cost: u32 = std.math.maxInt(u32);
                var best_node: Node.Index = class.bag.items[0];

                for (class.bag.items) |node_idx| {
                    const node = oir.getNode(node_idx);

                    const base_cost = cost.getCost(node.tag);
                    var child_cost: u32 = 0;
                    for (node.operands()) |sub_class_idx| {
                        if (sub_class_idx == class_idx) break;

                        const extracted_cost, _ = try e.extractClass(sub_class_idx);
                        child_cost += extracted_cost;
                    }

                    const node_cost = base_cost + child_cost;
                    if (node_cost < best_cost) {
                        best_cost = node_cost;
                        best_node = node_idx;
                    }
                }

                gop.value_ptr.* = .{ best_cost, best_node };
                return .{ best_cost, best_node };
            },
        }
    }

    pub fn deinit(e: *Extractor) void {
        const allocator = e.oir.allocator;
        e.virt_map.deinit(allocator);
        e.memo.deinit(allocator);
    }
};

/// Describes information about passes that have already been ran.
///
/// Can be access via the `pass_data` map from other passes.
const PassMetadata = struct {
    /// Has the pass this metadata is related to completed?
    /// TODO: not sure if we need this field yet,
    /// should we create the metadata before or after the pass has been ran?
    // complete: bool,

    /// Has this data been outdated by another pass?
    ///
    /// We don't re-run passes when they're outdated eagerly,
    /// since that information may never be needed again.
    outdated: bool,
    /// Holding a reference to this data in another metadata struct
    /// is a bad idea, since that pass may become outdated and you'll have
    /// no easy way of checking that. Cloning is the best policy here.
    data: *anyopaque,
};

/// Runs passes on the MIR.
///
/// After `run` is called, the MIR will have no pseudo instructions
/// and will be ready for encoding.
pub fn run(mir: *Mir) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("\nMIR before passes:\n-----------\n");
    try mir.dump(stdout);
    try stdout.writeAll("-----------\n");

    inline for (
        passes.map.values(),
        passes.map.keys(),
    ) |pass_type, name| {
        const pass = try pass_type.init(mir);
        const metadata: PassMetadata = .{
            .outdated = false,
            .data = pass,
        };
        try mir.pass_data.put(mir.gpa, name, metadata);

        try pass.run(mir);

        try stdout.print("\nMIR after {s}:\n-----------\n", .{name});
        try mir.dump(stdout);
        try stdout.writeAll("-----------\n");

        try pass.verify(mir);
    }

    inline for (comptime passes.map.keys()) |name| {
        const data = mir.getPassData(name).?;
        data.deinit(mir);
    }
}

fn PassData(comptime name: []const u8) type {
    return passes.map.get(name).?;
}

pub fn getPassData(mir: *const Mir, comptime name: []const u8) ?*PassData(name) {
    const ptr = mir.pass_data.get(name) orelse return null;
    return @alignCast(@ptrCast(ptr.data));
}

fn addUnOp(mir: *Mir, op: Instruction) !Instruction.Index {
    const idx: Instruction.Index = @enumFromInt(mir.instructions.len);
    try mir.instructions.append(mir.gpa, op);
    return idx;
}

fn allocFrameIndex(mir: *Mir, alloc: bits.FrameAlloc) !FrameIndex {
    const frame_index: FrameIndex = @enumFromInt(mir.frame_allocs.len);
    try mir.frame_allocs.append(mir.gpa, alloc);
    log.debug("allocated frame {}", .{frame_index});
    return frame_index;
}

fn allocVirtualReg(mir: *Mir, class: Register.Class) !VirtualRegister {
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
                .data = .{ .un_op = .{
                    .dst = dst,
                    .src = src,
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
    mir.pass_data.deinit(gpa);
}

pub fn dump(mir: *Mir, s: anytype) !void {
    var w: Writer = .{
        .mir = mir,
        .indent = 0,
    };

    const instructions = mir.instructions;
    for (0..instructions.len) |i| {
        try w.printInst(@enumFromInt(i), s);
        if (instructions.get(i).tag != .tombstone) try s.writeByte('\n');
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
        const mir = w.mir;
        const instructions = mir.instructions;
        const tag = instructions.items(.tag)[@intFromEnum(inst)];
        const data = instructions.items(.data)[@intFromEnum(inst)];

        // doesn't exist, we can simply skip it
        if (tag == .tombstone) return;

        try s.writeByteNTimes(' ', w.indent);
        switch (tag) {
            .pseudo_ret,
            => try s.print("{s} ${s}", .{
                @tagName(tag),
                @tagName(data.register),
            }),
            .copy,
            .ld,
            => {
                const un_op = data.un_op;

                try s.print("{}", .{un_op.dst});
                try printLiveness(mir, un_op.dst, inst, s);
                try s.print(" = {s} ", .{@tagName(tag)});
                try s.print("{}", .{un_op.src});
                try printLiveness(mir, un_op.src, inst, s);
            },
            .addi,
            .add,
            .sll,
            .slli,
            .srl,
            .srli,
            .mul,
            .div,
            => {
                const bin_op = data.bin_op;

                try s.print("{}", .{bin_op.dst});
                try printLiveness(mir, bin_op.dst, inst, s);
                try s.print(" = {s} ", .{@tagName(tag)});
                try s.print("{}", .{bin_op.lhs});
                try printLiveness(mir, bin_op.lhs, inst, s);
                try s.print(", {}", .{bin_op.rhs});
                try printLiveness(mir, bin_op.rhs, inst, s);
            },
            .tombstone => unreachable,
            // else => try s.print("TODO: Writer.printInst {s}", .{@tagName(tag)}),
        }
    }

    fn printLiveness(
        mir: *const Mir,
        value: Value,
        inst: Mir.Instruction.Index,
        writer: anytype,
    ) !void {
        if (mir.getPassData("liveVars")) |meta| {
            switch (value) {
                .virtual => |vreg| {
                    const info = meta.virtinfo.get(vreg.index).?; // is liveness info broken?
                    if (info.last_usage == inst) {
                        try writer.print(" killed", .{});
                    }
                },
                else => {},
            }
        }
    }
};

const Mir = @This();
const std = @import("std");
const Oir = @import("Oir.zig");
const bits = @import("bits.zig");
const passes = @import("Mir/passes.zig");
const cost = @import("cost.zig");

const Class = Oir.Class;
const Node = Oir.Node;

const Register = bits.Register;
const VirtualRegister = bits.VirtualRegister;
const Memory = bits.Memory;
const FrameIndex = bits.FrameIndex;

const log = std.log.scoped(.mir);
const assert = std.debug.assert;
