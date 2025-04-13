const std = @import("std");
const build_options = @import("build_options");
const Oir = @import("../Oir.zig");

const SimpleExtractor = @import("SimpleExtractor.zig");
const z3 = @import("z3.zig");

const log = std.log.scoped(.extraction);
const Node = Oir.Node;
const Class = Oir.Class;

/// A form of OIR where nodes reference other nodes.
pub const Recursive = struct {
    nodes: std.ArrayListUnmanaged(Node) = .{},
    extra: std.ArrayListUnmanaged(u32) = .{},

    // TODO: Explore making this its own unique type. Currently we can't do that because
    // the Node data payload types use Class.Index to reference other Classes, which isn't
    // compatible with this. Maybe we can bitcast safely between them?
    // pub const Index = enum(u32) {
    //     start,
    //     _,
    // };

    pub fn getNode(r: *const Recursive, idx: Class.Index) Node {
        return r.nodes.items[@intFromEnum(idx)];
    }

    pub fn getNodes(r: *const Recursive) []const Node {
        return r.nodes.items;
    }

    pub fn addNode(r: *Recursive, allocator: std.mem.Allocator, node: Node) !Class.Index {
        const idx: Class.Index = @enumFromInt(r.nodes.items.len);
        try r.nodes.append(allocator, node);
        return idx;
    }

    pub fn dump(recv: Recursive, name: []const u8) !void {
        const graphviz_file = try std.fs.cwd().createFile(name, .{});
        defer graphviz_file.close();
        try @import("print_oir.zig").dumpRecvGraph(recv, graphviz_file.writer());
    }

    pub fn deinit(r: *Recursive, allocator: std.mem.Allocator) void {
        r.nodes.deinit(allocator);
        r.extra.deinit(allocator);
    }

    pub fn listToSpan(
        r: *Recursive,
        list: []const Class.Index,
        gpa: std.mem.Allocator,
    ) !Oir.Node.Span {
        try r.extra.appendSlice(gpa, @ptrCast(list));
        return .{
            .start = @intCast(r.extra.items.len - list.len),
            .end = @intCast(r.extra.items.len),
        };
    }

    pub fn print(recv: Recursive, writer: anytype) !void {
        try @import("print_oir.zig").print(recv, writer);
    }
};

pub const CostStrategy = enum {
    /// A super basic cost strategy that simply looks at the number of child nodes
    /// a particular node has to determine its cost.
    simple_latency,
    /// Uses Z3 and a column approach to find the optimal solution.
    z3,

    pub const auto: CostStrategy = if (build_options.has_z3) .z3 else .simple_latency;
};

pub fn extract(oir: *const Oir, strat: CostStrategy) !Recursive {
    const trace = oir.trace.start(@src(), "extracting", .{});
    defer trace.end();

    switch (strat) {
        .simple_latency => return SimpleExtractor.extract(oir),
        .z3 => return z3.extract(oir),
    }
}
