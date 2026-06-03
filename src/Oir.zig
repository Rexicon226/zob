//! Optimizable Intermediate Representation

allocator: std.mem.Allocator,

/// The list of all E-Nodes in the graph. Each E-Node represents a potential state of the E-Class
/// they are in. After all optimizations we want have completed, the extractor will be used to
/// iterate through all E-Classes and extract the best node within.
nodes: std.AutoArrayHashMapUnmanaged(Node, void),

/// Used for storing dynamic and temporary data. Things like the Node `list` payload are stored
/// on this array. We can assume that it'll live as long as the OIR does.
extra: std.ArrayList(u32),

/// Represents the list of all E-Classes in the graph.
///
/// Each E-Class contains a bundle of nodes which are equivalent to each other.
classes: std.AutoHashMapUnmanaged(Class.Index, Class),

/// A map relating nodes to the classes they are in. Used as a fast way to determine
/// what "parent" class a node is in.
node_to_class: std.HashMapUnmanaged(
    Node.Index,
    Class.Index,
    NodeContext,
    std.hash_map.default_max_load_percentage,
),

union_find: UnionFind,

/// A list of pending `Pair`s which have made the E-Graph unclean. This is a part of incremental
/// rebuilding and lets the graph process faster. `add` and `union` dirty the graph, marking `clean`
/// as false, and then `rebuild` will iterate through the pending items to analyze and mark `clean`
/// as true.
pending: std.ArrayList(Pair),

/// Indicates whether or not reading type operations are allowed on the E-Graph.
///
/// Mutating operations set this to `false`, and `rebuild` will set it back to `true`.
clean: bool,
trace: Trace,

/// A list of classes/nodes which act as exits from the function. This will usually
/// be `ret` nodes. We use it later in the extraction to understand where to start
/// looking for the best path.
exit_list: std.ArrayList(Class.Index),

const UnionFind = struct {
    parents: std.ArrayList(Class.Index) = .empty,

    fn makeSet(f: *UnionFind, gpa: std.mem.Allocator) !Class.Index {
        const id: Class.Index = @enumFromInt(f.parents.items.len);
        try f.parents.append(gpa, id);
        return id;
    }

    pub fn find(f: *const UnionFind, idx: Class.Index) Class.Index {
        var current = idx;
        while (current != f.parent(current)) {
            current = f.parent(current);
        }
        return current;
    }

    /// Same thing as `find` but performs path-compression.
    fn findMutable(f: *UnionFind, idx: Class.Index) Class.Index {
        var current = idx;
        while (current != f.parent(current)) {
            const grandparent = f.parent(f.parent(current));
            f.parents.items[@intFromEnum(idx)] = grandparent;
            current = grandparent;
        }
        return current;
    }

    fn @"union"(f: *UnionFind, a: Class.Index, b: Class.Index) Class.Index {
        f.parents.items[@intFromEnum(b)] = a;
        return a;
    }

    fn parent(f: *const UnionFind, idx: Class.Index) Class.Index {
        return f.parents.items[@intFromEnum(idx)];
    }

    fn deinit(f: *UnionFind, gpa: std.mem.Allocator) void {
        f.parents.deinit(gpa);
    }
};

pub const NodeContext = struct {
    oir: *const Oir,

    pub fn hash(ctx: NodeContext, node_idx: Node.Index) u64 {
        const node = ctx.oir.getNode(node_idx);
        var hasher = std.hash.XxHash3.init(0);
        std.hash.autoHash(&hasher, node);
        return hasher.final();
    }

    pub fn eql(ctx: NodeContext, a_idx: Node.Index, b_idx: Node.Index) bool {
        const oir = ctx.oir;
        const a = oir.getNode(a_idx);
        const b = oir.getNode(b_idx);

        if (a.tag != b.tag) return false;
        if (std.meta.activeTag(a.data) != std.meta.activeTag(b.data)) return false;

        switch (a.data) {
            .constant => |p| {
                return p == b.data.constant;
            },
            .project => |p| {
                if (p.index != b.data.project.index) return false;
                if (p.type != b.data.project.type) return false;
                if (p.bits != b.data.project.bits) return false;
            },
            .loopvar => |p| {
                return p.loop == b.data.loopvar.loop and
                    p.index == b.data.loopvar.index and
                    p.bits == b.data.loopvar.bits;
            },
            .cast => |p| {
                if (p.bits != b.data.cast.bits) return false;
            },
            .load => |p| {
                if (p.bits != b.data.load.bits) return false;
            },
            .store => |p| {
                if (p.bits != b.data.store.bits) return false;
            },
            .alloca => |p| {
                // Unique allocation id: distinct allocas never compare equal.
                return p.id == b.data.alloca.id;
            },
            .loop => |p| {
                if (p.id != b.data.loop.id) return false;
                if (p.count != b.data.loop.count) return false;
            },
            .lambda => |p| {
                // Each function has a unique id; same id == same lambda.
                return p.id == b.data.lambda.id;
            },
            .param => |p| {
                return p.lambda == b.data.param.lambda and p.index == b.data.param.index and
                    p.bits == b.data.param.bits;
            },
            .call => |p| {
                if (p.callee != b.data.call.callee) return false;
            },
            else => {},
        }

        for (a.operands(oir), b.operands(oir)) |a_class, b_class| {
            if (a_class != b_class) {
                return false;
            }
        }

        return true;
    }

    fn lessThanClass(_: void, a: Class.Index, b: Class.Index) bool {
        return @intFromEnum(a) < @intFromEnum(b);
    }
};

pub const Node = struct {
    tag: Tag,
    data: Data = .none,

    pub const Index = enum(u32) {
        /// The singular `start` node should always be the first node.
        start,
        _,
    };

    const Type = enum {
        ctrl,
        data,
    };

    pub const Tag = enum(u8) {
        /// Constant integer.
        constant,
        /// Projection extracts a field from a tuple.
        project,

        // Control flow
        /// There can only ever be one `start` node in the function.
        /// The inputs to the start node is a list of the return values.
        /// The output of the start node is a list of the arguments to the function.
        start,
        /// The return nodes are input to the `start` node in the function
        ///
        /// The return node is the single exit of the function. There is no
        /// control flow to be represented in RVSDG, so this uses the `list`
        /// payload to hold the function's result values. By convention,
        /// element 0 is the final memory state. A value-returning function
        /// adds its return value at element 1.
        ret,
        /// A conditional ("if"). Uses the `tri_op` payload, `(predicate, then, else)`.
        /// Selects either of the operands based on the predicate.
        gamma,
        /// A test-first loop over N loop-carried values. Uses the `loop` payload.
        /// ```
        /// v = inits;
        /// while (pred(v) != 0)
        ///     v = nexts(v);
        /// ```
        /// and the final value of carried slot` i` is read with `project(theta, i)`.
        /// Inside the body, the current value of slot `i` is `loopvar(id, i)`.
        theta,
        /// A loop-carried value referenced inside a `theta` body.
        /// A leaf carrying `(loop id, slot index)`.
        loopvar,

        /// A function definition. Uses the `lambda` payload, whose `body` span
        /// holds the function's results.
        lambda,
        /// A function argument or incoming memory state.
        param,
        /// A function call. Uses the `call` payload, whose `body` span
        /// is `(mem_state, args...)` and which produces a tuple `(mem_state', result)`.
        /// `callee` is the id of the target `lambda`.
        call,

        // Integer arthimatics.
        add,
        @"and",
        @"or",
        sub,
        mul,
        shl,
        shr,
        sar,
        div_trunc,
        udiv,
        div_exact,

        cmp_eq,
        cmp_lt,
        cmp_gt,
        cmp_ult,
        cmp_ugt,

        /// Truncate to a narrower width (keeps the low bits).
        trunc,
        /// Sign-extend to a wider width.
        sext,
        /// Zero-extend to a wider width.
        zext,

        /// Memory load. Uses the `load` payload `(mem_state, address)` and produces
        /// the loaded value. Takes the memory state purely to order it against stores.
        load,
        /// Memory store. Uses the `store` payload `(mem_state, address, value)` and
        /// produces a new memory state.
        store,
        /// Allocates a unique stack slot and produces its address.
        /// Uses the `alloca` payload `(id, size, align)`.
        alloca,

        pub fn isCanonical(tag: Tag) bool {
            return switch (tag) {
                .constant,
                .start,
                => true,
                else => false,
            };
        }

        pub fn isCommutative(tag: Tag) bool {
            return switch (tag) {
                .add,
                .mul,
                .@"and",
                .@"or",
                .cmp_eq,
                => true,
                else => false,
            };
        }

        pub fn dataType(tag: Tag) std.meta.FieldEnum(Data) {
            return switch (tag) {
                .constant,
                => .constant,
                .start,
                .ret,
                => .list,
                .project,
                => .project,
                .gamma,
                => .tri_op,
                .store,
                => .store,
                .theta,
                => .loop,
                .loopvar,
                => .loopvar,
                .lambda,
                => .lambda,
                .call,
                => .call,
                .param,
                => .param,
                .trunc,
                .sext,
                .zext,
                => .cast,
                .load,
                => .load,
                .alloca,
                => .alloca,
                .cmp_gt,
                .cmp_lt,
                .cmp_ult,
                .cmp_ugt,
                .cmp_eq,
                .@"and",
                .@"or",
                .add,
                .sub,
                .mul,
                .shl,
                .shr,
                .sar,
                .div_trunc,
                .udiv,
                .div_exact,
                => .bin_op,
            };
        }
    };

    const Data = union(enum) {
        none: void,
        constant: i64,
        /// NOTE: For future reference, we use an array here so that the operands()
        /// function can return a slice, otherwise padding between struct elements
        /// would be undefined and it wouldn't be safe.
        bin_op: [2]Class.Index,
        tri_op: [3]Class.Index,
        un_op: Class.Index,
        project: Project,
        list: Span,
        loop: Loop,
        loopvar: Loopvar,
        lambda: Lambda,
        call: Call,
        param: Param,
        cast: Cast,
        load: Load,
        store: Store,
        alloca: Alloca,
    };

    pub const Alloca = struct {
        id: u32,
        size: u32,
        @"align": u32,
    };

    pub const Cast = struct {
        operand: Class.Index,
        bits: u16,
    };

    pub const Load = struct {
        ops: [2]Class.Index,
        bits: u16,
    };

    pub const Store = struct {
        ops: [3]Class.Index,
        bits: u16,
    };

    pub const Lambda = struct {
        id: u32,
        params: u32,
        body: Span,

        pub fn results(l: Lambda, repr: anytype) []const Class.Index {
            return @ptrCast(repr.extra.items[l.body.start..l.body.end]);
        }
    };

    pub const Call = struct {
        callee: u32,
        body: Span,

        pub fn mem(c: Call, repr: anytype) Class.Index {
            return @enumFromInt(repr.extra.items[c.body.start]);
        }
        pub fn args(c: Call, repr: anytype) []const Class.Index {
            return @ptrCast(repr.extra.items[c.body.start + 1 .. c.body.end]);
        }
    };

    pub const Param = struct {
        lambda: u32,
        index: u32,
        bits: u16,
    };

    /// Payload for `theta`. `body` holds, in order: the N loop-arg classes,
    /// the N initial values, the continue predicate, then the N next-iteration
    /// values (length 3*N+1).
    ///
    /// `id` matches the body's `loopvar`s. `count` is N. Slot 0 is the memory state
    /// and slots 1.. are scalar values.
    pub const Loop = struct {
        id: u32,
        count: u32,
        body: Span,

        pub fn args(loop: Loop, repr: anytype) []const Class.Index {
            return @ptrCast(repr.extra.items[loop.body.start..][0..loop.count]);
        }
        pub fn inits(loop: Loop, repr: anytype) []const Class.Index {
            return @ptrCast(repr.extra.items[loop.body.start + loop.count ..][0..loop.count]);
        }
        pub fn pred(loop: Loop, repr: anytype) Class.Index {
            return @enumFromInt(repr.extra.items[loop.body.start + 2 * loop.count]);
        }
        pub fn nexts(loop: Loop, repr: anytype) []const Class.Index {
            const off = loop.body.start + 2 * loop.count + 1;
            return @ptrCast(repr.extra.items[off..][0..loop.count]);
        }
    };

    pub const Loopvar = struct {
        loop: u32,
        index: u32,
        bits: u16,
    };

    /// A span in the Oir "extra" array.
    pub const Span = struct {
        start: u32,
        end: u32,

        pub const empty: Span = .{ .start = 0, .end = 0 };

        pub fn toSlice(span: Span, repr: anytype) []const u32 {
            return repr.extra.items[span.start..span.end];
        }
    };

    const Project = struct {
        tuple: Class.Index,
        index: u32,
        type: Type,
        bits: u16,
    };

    pub fn init(comptime tag: Tag, payload: anytype) Node {
        const data = @unionInit(Data, @tagName(tag.dataType()), payload);
        return .{
            .tag = tag,
            .data = data,
        };
    }

    /// Same as `init`, but for nodes that need to allocate to be initialized.
    pub fn create(comptime tag: Tag, oir: *Oir, payload: []const Class.Index) !Node {
        switch (tag) {
            .start => {
                const data = try oir.listToSpan(payload);
                return .{ .tag = .start, .data = .{ .list = data } };
            },
            else => unreachable,
        }
    }

    pub fn operands(node: *const Node, repr: anytype) []const Class.Index {
        if (node.tag == .start) return &.{}; // no real operands
        return switch (node.data) {
            .none, .constant, .loopvar, .param, .alloca => &.{},
            .bin_op => |*bin_op| bin_op,
            .tri_op => |*tri_op| tri_op,
            .un_op => |*un_op| un_op[0..1],
            .cast => |*c| (&c.operand)[0..1],
            .load => |*l| &l.ops,
            .store => |*s| &s.ops,
            .project => |*proj| (&proj.tuple)[0..1],
            .list => |span| @ptrCast(repr.extra.items[span.start..span.end]),
            .loop => |loop| @ptrCast(repr.extra.items[loop.body.start..loop.body.end]),
            .lambda => |lam| @ptrCast(repr.extra.items[lam.body.start..lam.body.end]),
            .call => |cl| @ptrCast(repr.extra.items[cl.body.start..cl.body.end]),
        };
    }

    pub fn mutableOperands(node: *Node, repr: anytype) []Class.Index {
        if (node.tag == .start) return &.{}; // no real operands
        return switch (node.data) {
            .none, .constant, .loopvar, .param, .alloca => &.{},
            .bin_op => |*bin_op| bin_op,
            .tri_op => |*tri_op| tri_op,
            .un_op => |*un_op| un_op[0..1],
            .cast => |*c| (&c.operand)[0..1],
            .load => |*l| &l.ops,
            .store => |*s| &s.ops,
            .project => |*proj| (&proj.tuple)[0..1],
            .list => |span| @ptrCast(repr.extra.items[span.start..span.end]),
            .loop => |loop| @ptrCast(repr.extra.items[loop.body.start..loop.body.end]),
            .lambda => |lam| @ptrCast(repr.extra.items[lam.body.start..lam.body.end]),
            .call => |cl| @ptrCast(repr.extra.items[cl.body.start..cl.body.end]),
        };
    }

    pub fn nodeType(node: Node) Type {
        return switch (node.tag) {
            .constant,
            .load,
            .store,
            .cmp_gt,
            .cmp_eq,
            .cmp_lt,
            .cmp_ult,
            .cmp_ugt,
            .@"and",
            .@"or",
            .add,
            .sub,
            .mul,
            .shl,
            .shr,
            .sar,
            .div_trunc,
            .udiv,
            .div_exact,
            .trunc,
            .sext,
            .zext,
            .gamma,
            .theta,
            .loopvar,
            .call,
            .param,
            .alloca,
            => .data,
            .start,
            .ret,
            .lambda,
            => .ctrl,
            .project => node.data.project.type,
        };
    }

    pub fn isVolatile(node: Node) bool {
        return switch (node.tag) {
            .start,
            .ret,
            .lambda,
            .call,
            => true,
            else => false,
        };
    }

    pub fn mapNode(
        old: Node,
        oir: *const Oir,
        map: *std.AutoHashMapUnmanaged(Class.Index, Class.Index),
    ) !Node {
        var copy = old;
        for (copy.mutableOperands(oir)) |*op| {
            op.* = map.get(oir.union_find.find(op.*)).?;
        }
        return copy;
    }

    // Helper functions
    pub fn ret(results: Span) Node {
        return .{ .tag = .ret, .data = .{ .list = results } };
    }

    /// Memory load: `(mem_state, address)` -> loaded value of width `bits`.
    pub fn load(mem_state: Class.Index, address: Class.Index, bits: u16) Node {
        return .{ .tag = .load, .data = .{ .load = .{ .ops = .{ mem_state, address }, .bits = bits } } };
    }

    pub fn trunc(operand: Class.Index, bits: u16) Node {
        return .{ .tag = .trunc, .data = .{ .cast = .{ .operand = operand, .bits = bits } } };
    }
    pub fn sext(operand: Class.Index, bits: u16) Node {
        return .{ .tag = .sext, .data = .{ .cast = .{ .operand = operand, .bits = bits } } };
    }
    pub fn zext(operand: Class.Index, bits: u16) Node {
        return .{ .tag = .zext, .data = .{ .cast = .{ .operand = operand, .bits = bits } } };
    }

    // Memory store: `(mem_state, address, value)` -> new memory state.
    pub fn store(mem_state: Class.Index, address: Class.Index, value: Class.Index, bits: u16) Node {
        return .{ .tag = .store, .data = .{ .store = .{ .ops = .{ mem_state, address, value }, .bits = bits } } };
    }

    pub fn alloca(id: u32, size: u32, alignment: u32) Node {
        return .{ .tag = .alloca, .data = .{ .alloca = .{ .id = id, .size = size, .@"align" = alignment } } };
    }

    /// Conditional: selects `then` when `pred` is non-zero, else `els`.
    pub fn gamma(pred: Class.Index, then: Class.Index, els: Class.Index) Node {
        return .{ .tag = .gamma, .data = .{ .tri_op = .{ pred, then, els } } };
    }

    pub fn theta(id: u32, count: u32, body: Span) Node {
        return .{ .tag = .theta, .data = .{ .loop = .{ .id = id, .count = count, .body = body } } };
    }
    pub fn loopvar(id: u32, index: u32, bits: u16) Node {
        return .{ .tag = .loopvar, .data = .{ .loopvar = .{ .loop = id, .index = index, .bits = bits } } };
    }

    pub fn lambda(id: u32, params: u32, body: Span) Node {
        return .{ .tag = .lambda, .data = .{ .lambda = .{ .id = id, .params = params, .body = body } } };
    }
    pub fn param(id: u32, index: u32, bits: u16) Node {
        return .{ .tag = .param, .data = .{ .param = .{ .lambda = id, .index = index, .bits = bits } } };
    }
    pub fn call(callee: u32, body: Span) Node {
        return .{ .tag = .call, .data = .{ .call = .{ .callee = callee, .body = body } } };
    }

    pub fn project(index: u32, tuple: Class.Index, ty: Type, bits: u16) Node {
        return .{
            .tag = .project,
            .data = .{ .project = .{
                .index = index,
                .tuple = tuple,
                .type = ty,
                .bits = bits,
            } },
        };
    }

    pub fn binOp(tag: Tag, lhs: Class.Index, rhs: Class.Index) Node {
        assert(tag.dataType() == .bin_op);
        return .{
            .tag = tag,
            .data = .{ .bin_op = .{ lhs, rhs } },
        };
    }

    pub fn constant(value: i64) Node {
        return .{ .tag = .constant, .data = .{ .constant = value } };
    }

    pub fn format(
        _: Node,
        _: *std.Io.Writer,
    ) !void {
        @compileError("don't format nodes directly, use Node.fmt");
    }

    pub fn fmt(node: Node, oir: *const Oir) std.fmt.Alt(FormatContext, format2) {
        return .{ .data = .{
            .node = node,
            .oir = oir,
        } };
    }

    const FormatContext = struct {
        node: Node,
        oir: *const Oir,
    };

    pub fn format2(
        ctx: FormatContext,
        stream: *std.Io.Writer,
    ) !void {
        const node = ctx.node;
        var writer: print_oir.Writer = .{ .nodes = ctx.oir.nodes.keys() };
        try writer.printNode(node, ctx.oir, stream);
    }
};

const Pair = struct { Node.Index, Class.Index };

/// A Class contains an N amount of Nodes as children.
pub const Class = struct {
    index: Index,
    bag: std.ArrayList(Node.Index) = .empty,
    parents: std.ArrayList(Pair) = .empty,

    pub const Index = enum(u32) {
        /// The start node is always in the first class, and alone as it's canonical.
        start,
        dead = std.math.maxInt(u32),
        _,

        pub fn format(
            idx: Index,
            writer: *std.Io.Writer,
        ) !void {
            try writer.print("%{d}", .{@intFromEnum(idx)});
        }
    };

    pub fn deinit(class: *Class, allocator: std.mem.Allocator) void {
        class.bag.deinit(allocator);
        class.parents.deinit(allocator);
    }
};

const Pass = struct {
    const Error = error{ OutOfMemory, Overflow, InvalidCharacter };

    name: []const u8,
    func: *const fn (oir: *Oir) Error!bool,
};

const passes: []const Pass = &.{
    .{
        .name = "constant-fold",
        .func = @import("passes/constant_fold.zig").run,
    },
    .{
        .name = "common-rewrites",
        .func = @import("passes/rewrite.zig").run,
    },
    .{
        .name = "loop-opt",
        .func = @import("passes/loop.zig").run,
    },
};

pub fn optimize(
    oir: *Oir,
    io: std.Io,
    mode: enum { saturate },
    graphs: ?[]const u8,
) !void {
    std.debug.assert(mode == .saturate); // only mode for now

    try oir.rebuild();
    assert(oir.clean);
    var i: u32 = 0;
    while (true) : (i += 1) {
        var new_change: bool = false;
        for (passes) |pass| {
            if (graphs) |path| {
                var buffer: [std.fs.max_path_bytes]u8 = undefined;
                const name = try std.fmt.bufPrint(&buffer, "{s}/pre_{s}_{}.dot", .{ path, pass.name, i });
                try oir.dump(io, name);
            }

            const trace = oir.trace.start(@src(), "{s}", .{pass.name});
            defer trace.end();

            const result = try pass.func(oir);
            if (result) new_change = true;

            // TODO: in theory we don't actually need to rebuild after every pass
            // maybe we should look into rebuilding on-demand?
            if (!oir.clean) try oir.rebuild();
        }

        if (!new_change) {
            if (graphs) |path| {
                var buffer: [std.fs.max_path_bytes]u8 = undefined;
                const name = try std.fmt.bufPrint(&buffer, "{s}/final.dot", .{path});
                try oir.dump(io, name);
            }
            break;
        }
    }
}

pub fn init(allocator: std.mem.Allocator) Oir {
    return .{
        .allocator = allocator,
        .nodes = .{},
        .node_to_class = .{},
        .classes = .{},
        .extra = .empty,
        .union_find = .{},
        .pending = .empty,
        .trace = .init(),
        .exit_list = .empty,
        .clean = true,
    };
}

pub fn dump(oir: *Oir, io: std.Io, name: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, name, .{});
    defer file.close(io);

    var file_writer = file.writer(io, &.{});
    const writer = &file_writer.interface;

    try print_oir.dumpOirGraph(oir, writer);
}

pub fn print(oir: *Oir, stream: anytype) !void {
    try print_oir.print(oir, stream);
}

/// Reference becomes invalid when new classes are added to the graph.
pub fn getClassPtr(oir: *Oir, idx: Class.Index) *Class {
    const found = oir.union_find.findMutable(idx);
    return oir.classes.getPtr(found).?;
}

pub fn getClass(oir: *const Oir, idx: Class.Index) Class {
    const found = oir.union_find.find(idx);
    return oir.classes.get(found).?;
}

/// Whether the class `idx` belongs to contains a constant node.
fn classHasConstant(oir: *const Oir, idx: Class.Index) bool {
    const found = oir.union_find.find(idx);
    const class = oir.classes.get(found) orelse return false;
    for (class.bag.items) |node_idx| {
        if (oir.getNode(node_idx).tag == .constant) return true;
    }
    return false;
}

pub fn findClass(oir: *const Oir, node_idx: Node.Index) Class.Index {
    const memo_idx = oir.node_to_class.getContext(
        node_idx,
        .{ .oir = oir },
    ).?;
    return oir.union_find.find(memo_idx);
}

pub fn findNode(oir: *const Oir, node: Node) ?Node.Index {
    const idx = oir.nodes.getIndex(node) orelse return null;
    return @enumFromInt(idx);
}

pub fn getNode(oir: *const Oir, idx: Node.Index) Node {
    return oir.nodes.keys()[@intFromEnum(idx)];
}

pub fn getNodes(oir: *const Oir) []const Node {
    return oir.nodes.keys();
}

/// Reference becomes invalid when new nodes are added to the graph.
fn getNodePtr(oir: *const Oir, idx: Node.Index) *Node {
    return &oir.nodes.keys()[@intFromEnum(idx)];
}

/// Returns the type of the class.
/// If the class contains a ctrl node, all other nodes must also be control.
pub fn getClassType(oir: *const Oir, idx: Class.Index) Node.Type {
    const class = oir.classes.get(idx).?;
    const first = class.bag.items[0];
    return oir.getNode(first).nodeType();
}

pub fn typeOf(oir: *const Oir, idx: Class.Index) u16 {
    return oir.typeOfDepth(idx, 0) orelse 64;
}
pub fn typeOfOpt(oir: *const Oir, idx: Class.Index) ?u16 {
    return oir.typeOfDepth(idx, 0);
}

fn typeOfDepth(oir: *const Oir, idx: Class.Index, depth: u8) ?u16 {
    if (depth > 32) return null;
    const class = oir.classes.get(oir.union_find.find(idx)) orelse return null;
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        switch (node.tag) {
            .param => return node.data.param.bits,
            .loopvar => return node.data.loopvar.bits,
            .project => return node.data.project.bits,
            .load => return node.data.load.bits,
            .trunc, .sext, .zext => return node.data.cast.bits,
            .cmp_eq, .cmp_lt, .cmp_gt, .cmp_ult, .cmp_ugt => return 1,
            .alloca => return 64, // TODO: depends on the target
            else => {},
        }
    }
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        switch (node.tag) {
            .add, .sub, .mul, .@"and", .@"or", .shl, .shr, .sar, .div_trunc, .udiv, .div_exact => {
                const ops = node.data.bin_op;
                if (oir.typeOfDepth(ops[0], depth + 1)) |w| return w;
                if (oir.typeOfDepth(ops[1], depth + 1)) |w| return w;
            },
            .gamma => {
                const t = node.data.tri_op;
                if (oir.typeOfDepth(t[1], depth + 1)) |w| return w;
                if (oir.typeOfDepth(t[2], depth + 1)) |w| return w;
            },
            else => {},
        }
    }
    return null;
}

/// Adds an ENode to the EGraph, giving the node its own class.
/// Returns the EClass index the ENode was placed in.
pub fn add(oir: *Oir, node: Node) !Class.Index {
    const gop = try oir.nodes.getOrPut(oir.allocator, node);
    if (gop.found_existing) {
        const class_idx = oir.findClass(@enumFromInt(gop.index));
        return oir.union_find.find(class_idx);
    } else {
        const node_idx: Node.Index = @enumFromInt(gop.index);

        log.debug("adding node {} {}", .{ node.fmt(oir), node_idx });

        const class_idx = try oir.addInternal(node_idx);
        return oir.union_find.find(class_idx);
    }
}

/// An internal function to simplify adding nodes to the Oir.
///
/// It should be used carefully as it invalidates the equality invariance of the graph.
fn addInternal(oir: *Oir, node: Node.Index) !Class.Index {
    if (oir.node_to_class.getContext(
        node,
        .{ .oir = oir },
    )) |class_idx| {
        return class_idx;
    } else {
        const id = try oir.makeClass(node);
        oir.clean = false;
        return id;
    }
}

fn makeClass(oir: *Oir, node_idx: Node.Index) !Class.Index {
    const id = try oir.union_find.makeSet(oir.allocator);
    log.debug("adding {} to {}", .{ node_idx, id });

    var class: Class = .{
        .index = id,
        .bag = .empty,
    };

    try class.bag.append(oir.allocator, node_idx);

    const node = oir.getNode(node_idx);
    for (node.operands(oir)) |child| {
        const class_ptr = oir.getClassPtr(child);
        try class_ptr.parents.append(oir.allocator, .{ node_idx, id });
    }

    try oir.classes.put(oir.allocator, id, class);
    try oir.node_to_class.putNoClobberContext(oir.allocator, node_idx, id, .{ .oir = oir });

    return id;
}

/// Performs the "union" operation on the graph.
///
/// Returns whether a union needs to happen. `true` is they are already equivalent
///
/// This can be thought of as "merging" two classes when they were proven to be equivalent.
pub fn @"union"(oir: *Oir, a_idx: Class.Index, b_idx: Class.Index) !bool {
    var a = oir.union_find.findMutable(a_idx);
    var b = oir.union_find.findMutable(b_idx);
    if (a == b) return false;
    oir.clean = false;

    log.debug("union on {} -> {}", .{ b, a });

    assert(oir.getClassType(a) == oir.getClassType(b));

    const a_parents = oir.classes.get(a).?.parents.items.len;
    const b_parents = oir.classes.get(b).?.parents.items.len;

    if (a_parents < b_parents) {
        std.mem.swap(Class.Index, &a, &b);
    }

    // make `a` the leader class
    _ = oir.union_find.@"union"(a, b);

    var b_class = oir.classes.fetchRemove(b).?.value;
    defer b_class.deinit(oir.allocator);

    const a_class = oir.classes.getPtr(a).?;
    assert(a == a_class.index);

    try a_class.bag.appendSlice(oir.allocator, b_class.bag.items);
    try a_class.parents.appendSlice(oir.allocator, b_class.parents.items);

    return true;
}

/// Performs a rebuild of the E-Graph to restore its invariants.
pub fn rebuild(oir: *Oir) !void {
    const trace = oir.trace.start(@src(), "rebuilding", .{});
    defer trace.end();
    log.debug("rebuilding", .{});

    var merges: std.ArrayList([2]Class.Index) = .empty;
    defer merges.deinit(oir.allocator);

    while (true) {
        oir.node_to_class.clearRetainingCapacity();
        merges.clearRetainingCapacity();

        var iter = oir.classes.iterator();
        while (iter.next()) |entry| {
            const leader = entry.key_ptr.*;
            for (entry.value_ptr.bag.items) |node_idx| {
                const node = oir.getNodePtr(node_idx);
                for (node.mutableOperands(oir)) |*op| {
                    op.* = oir.union_find.findMutable(op.*);
                }
                if (node.tag.isCommutative()) {
                    const ops = node.mutableOperands(oir);
                    const a_const = oir.classHasConstant(ops[0]);
                    const b_const = oir.classHasConstant(ops[1]);
                    const swap = if (a_const != b_const)
                        a_const // a constant must move to the second slot
                    else
                        @intFromEnum(ops[0]) > @intFromEnum(ops[1]);
                    if (swap) std.mem.swap(Class.Index, &ops[0], &ops[1]);
                }

                const gop = try oir.node_to_class.getOrPutContext(
                    oir.allocator,
                    node_idx,
                    .{ .oir = oir },
                );
                if (gop.found_existing) {
                    const existing = gop.value_ptr.*;
                    if (existing != leader) {
                        try merges.append(oir.allocator, .{ existing, leader });
                    }
                } else {
                    gop.value_ptr.* = leader;
                }
            }
        }

        if (merges.items.len == 0) break;
        for (merges.items) |pair| {
            _ = try oir.@"union"(pair[0], pair[1]);
        }
    }

    if (builtin.mode == .Debug) try oir.verifyNodes();
    oir.clean = true;
}

pub fn findCycles(oir: *const Oir) !std.AutoHashMapUnmanaged(Node.Index, Class.Index) {
    const allocator = oir.allocator;

    const Color = enum {
        white,
        gray,
        black,
    };

    var stack = try std.ArrayList(struct {
        bool,
        Class.Index,
    }).initCapacity(allocator, oir.classes.size);
    defer stack.deinit(allocator);

    var color = std.AutoHashMap(Class.Index, Color).init(allocator);
    defer color.deinit();

    var iter = oir.classes.valueIterator();
    while (iter.next()) |class| {
        stack.appendAssumeCapacity(.{ true, class.index });
        try color.put(class.index, .white);
    }

    var cycles: std.AutoHashMapUnmanaged(Node.Index, Class.Index) = .{};
    while (stack.pop()) |entry| {
        const enter, const id = entry;
        if (enter) {
            color.getPtr(id).?.* = .gray;
            try stack.append(allocator, .{ false, id });

            const class_ptr = oir.getClass(id);
            for (class_ptr.bag.items) |node_idx| {
                const node = oir.getNode(node_idx);
                for (node.operands(oir)) |child| {
                    const child_color = color.get(child).?;
                    switch (child_color) {
                        .white => try stack.append(allocator, .{ true, child }),
                        .gray => try cycles.put(allocator, node_idx, id),
                        .black => {},
                    }
                }
            }
        } else color.getPtr(id).?.* = .black;
    }

    return cycles;
}

fn verifyNodes(oir: *Oir) !void {
    var found_start: bool = false;

    var temporary: std.HashMapUnmanaged(
        Node.Index,
        Class.Index,
        NodeContext,
        std.hash_map.default_max_load_percentage,
    ) = .{};
    defer temporary.deinit(oir.allocator);

    var iter = oir.classes.iterator();
    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const class = entry.value_ptr.*;
        for (class.bag.items) |node| {
            if (oir.getNode(node).tag == .start) {
                if (found_start == true) @panic("second start node found in OIR");
                found_start = true;
            }

            const gop = try temporary.getOrPutContext(
                oir.allocator,
                node,
                .{ .oir = oir },
            );
            if (gop.found_existing) {
                const found_id = oir.union_find.find(id);
                const found_old = oir.union_find.find(gop.value_ptr.*);
                if (found_id != found_old) {
                    std.debug.panic(
                        "found unexpected equivalence for {}\n{any}\nvs\n{any}",
                        .{
                            node,
                            oir.getClassPtr(found_id).bag.items,
                            oir.getClassPtr(found_old).bag.items,
                        },
                    );
                }
            } else gop.value_ptr.* = id;
        }
    }

    if (!found_start) @panic("no start node found in OIR");

    var temp_iter = temporary.iterator();
    while (temp_iter.next()) |entry| {
        const e = entry.value_ptr.*;
        assert(e == oir.union_find.find(e));
    }
}

pub fn extract(oir: *Oir, strat: extraction.CostStrategy) ![]extraction.Recursive {
    return extraction.extract(oir, strat);
}

pub fn deinit(oir: *Oir) void {
    const allocator = oir.allocator;

    {
        var iter = oir.classes.valueIterator();
        while (iter.next()) |class| class.deinit(allocator);
        oir.classes.deinit(allocator);
    }

    oir.trace.deinit();
    oir.node_to_class.deinit(allocator);
    oir.nodes.deinit(allocator);

    oir.union_find.deinit(allocator);
    oir.extra.deinit(allocator);
    oir.exit_list.deinit(allocator);
}

/// Checks if a class contains a constant equivalence node, and returns it.
/// Otherwise returns `null`.
///
/// Can only return canonical element types such as `constant`.
pub fn classContains(oir: *const Oir, idx: Class.Index, comptime tag: Node.Tag) ?Node.Index {
    comptime assert(tag.isCanonical());
    assert(oir.clean);

    const class = oir.classes.get(idx) orelse return null;
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        // Since the node is aborbing, we can return early as no other
        // instances of it are allowed in the same class.
        if (node.tag == tag) return node_idx;
    }

    return null;
}

/// Similar to `classContains` but instead of returning a specific node that matches
/// the tag, it just tells us whether the class in general contains a node of that tag.
pub fn classContainsAny(oir: *const Oir, idx: Class.Index, tag: Node.Tag) bool {
    assert(oir.clean);
    const class = oir.classes.get(idx).?;
    for (class.bag.items) |node_idx| {
        const node = oir.getNode(node_idx);
        if (node.tag == tag) return true;
    }
    return false;
}

pub fn listToSpan(oir: *Oir, list: []const Class.Index) !Node.Span {
    try oir.extra.appendSlice(oir.allocator, @ptrCast(list));
    return .{
        .start = @intCast(oir.extra.items.len - list.len),
        .end = @intCast(oir.extra.items.len),
    };
}

const Oir = @This();
const std = @import("std");
const builtin = @import("builtin");
const print_oir = @import("Oir/print_oir.zig");
pub const extraction = @import("Oir/extraction.zig");
const Trace = @import("trace.zig").Trace;

const log = std.log.scoped(.oir);
const assert = std.debug.assert;
