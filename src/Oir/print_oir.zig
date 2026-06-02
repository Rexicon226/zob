//! Prints OIR to graphviz

const std = @import("std");
const Oir = @import("../Oir.zig");
const Recursive = @import("extraction.zig").Recursive;

pub fn dumpOirGraph(
    oir: *const Oir,
    stream: anytype,
) !void {
    try stream.writeAll(
        \\digraph G {
        \\  compound=true
        \\  clusterrank=local
        \\  graph [fontsize=14 compound=true]
        \\  node [shape=box, style=filled];
        \\  rankdir=BT;
        \\  ordering="in";
        // https://gitlab.com/graphviz/graphviz/-/issues/1949
        // \\  concentrate=true;
        \\
        \\
    );

    {
        var class_iter = oir.classes.iterator();
        while (class_iter.next()) |entry| {
            const class_idx: u32 = @intFromEnum(entry.key_ptr.*);
            const class = entry.value_ptr.*;
            try stream.print(
                \\  subgraph cluster_{d} {{
                \\    style=dotted
                \\
            , .{class_idx});

            for (class.bag.items, 0..) |node_idx, i| {
                const node = oir.getNode(node_idx);
                try stream.print("    {}.{} [label=\"", .{ class_idx, i });
                try printNodeLabel(stream, node);
                try stream.print(" {}", .{class_idx});
                const color = switch (node.nodeType()) {
                    .ctrl => "orange",
                    .data => "grey",
                };
                try stream.print("\", color=\"{s}\"];\n", .{color});
            }
            try stream.writeAll("  }\n");
        }
    }

    var class_iter = oir.classes.iterator();
    while (class_iter.next()) |entry| {
        const class_idx = entry.key_ptr.*;
        const class = entry.value_ptr.*;
        for (class.bag.items, 0..) |node_idx, i| {
            const node = oir.getNode(node_idx);
            switch (node.tag) {
                .project,
                => {
                    const project = node.data.project;
                    const target = project.tuple;
                    try printClassEdge(stream, class_idx, i, target, switch (project.type) {
                        .ctrl => .red,
                        .data => .black,
                    });
                },
                else => for (node.operands(oir)) |child_idx| {
                    try printClassEdge(stream, class_idx, i, child_idx, .black);
                },
            }
        }
    }

    try stream.writeAll("}\n");
}

fn printClassEdge(
    stream: anytype,
    class_idx: Oir.Class.Index,
    i: usize,
    idx: Oir.Class.Index,
    color: enum { black, red },
) !void {
    if (class_idx == idx) return; // We can't print arrows inside of a class.
    try stream.print(
        "  {}.{} -> {}.0 [lhead = cluster_{} color=\"{s}\"]\n",
        .{
            @intFromEnum(class_idx),
            i,
            @intFromEnum(idx),
            @intFromEnum(idx),
            @tagName(color),
        },
    );
}

fn printEdge(
    stream: anytype,
    i: usize,
    child: Oir.Class.Index,
    color: enum { black, red },
) !void {
    try stream.print("  {d} -> {d} [color=\"{s}\"];\n", .{
        i,
        @intFromEnum(child),
        @tagName(color),
    });
}

pub fn dumpRecvGraph(
    recv: Recursive,
    stream: anytype,
) !void {
    try stream.writeAll(
        \\digraph G {
        \\  compound=true
        \\  clusterrank=local
        \\  graph [fontsize=14 compound=true]
        \\  node [shape=box, style=filled];
        \\  rankdir=BT;
        \\  ordering="in";
        \\  concentrate="true";
        \\
        \\
    );

    for (recv.nodes.items, 0..) |node, i| {
        try stream.print("  {} [label=\"", .{i});
        try printNodeLabel(stream, node);
        const color = switch (node.nodeType()) {
            .ctrl => "orange",
            .data => "grey",
        };
        try stream.print("\", color=\"{s}\"];\n", .{color});
    }
    try stream.writeAll("\n");

    for (recv.nodes.items, 0..) |node, i| {
        switch (node.tag) {
            .project => {
                const project = node.data.project;
                const target = project.tuple;
                try printEdge(stream, i, target, switch (project.type) {
                    .ctrl => .red,
                    .data => .black,
                });
            },
            else => for (node.operands(recv)) |idx| {
                try printEdge(stream, i, idx, .black);
            },
        }
    }

    try stream.writeAll("}\n");
}

/// NOTE: Printing this with a "full" OIR graph is basically useless, since it just iterates
/// through the node list. It only makes sense to use on recursive expressions and just created
/// OIR graphs, for debugging.
pub fn print(
    repr: anytype,
    stream: anytype,
) !void {
    var writer: Writer = .{ .nodes = repr.getNodes() };
    try writer.printBody(repr, stream);
}

pub const Writer = struct {
    indent: u32 = 0,
    nodes: []const Oir.Node,

    fn printBody(w: *Writer, repr: anytype, stream: *std.Io.Writer) !void {
        for (0..w.nodes.len) |i| {
            try stream.print("%{d} = ", .{i});
            try w.printNode(w.nodes[i], repr, stream);
            try stream.writeByte('\n');
        }
    }

    pub fn printNode(w: *Writer, node: Oir.Node, repr: anytype, stream: *std.Io.Writer) !void {
        try stream.print("{s}(", .{@tagName(node.tag)});
        switch (node.tag) {
            .@"and",
            .sub,
            .shl,
            .shr,
            .mul,
            .div_exact,
            .div_trunc,
            .add,
            .cmp_gt,
            .cmp_lt,
            .cmp_eq,
            .load,
            => try w.printBinOp(node, stream),
            .gamma,
            .store,
            => try w.printTriOp(node, stream),
            .theta => try w.printTheta(node, repr, stream),
            .loopvar => try w.printLoopvar(node, stream),
            .ret => try w.printCtrlList(node, repr, stream),
            .project => try w.printProject(node, stream),
            .constant => try w.printConstant(node, stream),
            .start => try w.printStart(node, repr, stream),
        }
        try stream.writeAll(")");
    }

    fn printTheta(_: *Writer, node: Oir.Node, repr: anytype, stream: *std.Io.Writer) !void {
        const loop = node.data.loop;
        try stream.print("#{d}", .{loop.id});
        for (loop.inits(repr)) |c| try stream.print(", init {f}", .{c});
        try stream.print(", pred {f}", .{loop.pred(repr)});
        for (loop.nexts(repr)) |c| try stream.print(", next {f}", .{c});
    }

    fn printLoopvar(_: *Writer, node: Oir.Node, stream: *std.Io.Writer) !void {
        const lv = node.data.loopvar;
        try stream.print("#{d}[{d}]", .{ lv.loop, lv.index });
    }

    fn printUnOp(_: *Writer, node: Oir.Node, stream: *std.Io.Writer) !void {
        const op = node.data.un_op;
        try stream.print("{f}", .{op});
    }

    fn printBinOp(_: *Writer, node: Oir.Node, stream: *std.Io.Writer) !void {
        const bin_op = node.data.bin_op;
        try stream.print("{f}, {f}", .{ bin_op[0], bin_op[1] });
    }

    fn printProject(_: *Writer, node: Oir.Node, stream: *std.Io.Writer) !void {
        const project = node.data.project;
        try stream.print("{d} {f}", .{ project.index, project.tuple });
    }

    fn printConstant(_: *Writer, node: Oir.Node, stream: *std.Io.Writer) !void {
        const constant = node.data.constant;
        try stream.print("{d}", .{constant});
    }

    fn printTriOp(_: *Writer, node: Oir.Node, stream: *std.Io.Writer) !void {
        const tri_op = node.data.tri_op;
        try stream.print("{f}, {f}, {f}", .{ tri_op[0], tri_op[1], tri_op[2] });
    }

    fn printStart(_: *Writer, _: Oir.Node, repr: anytype, stream: *std.Io.Writer) !void {
        for (repr.exit_list.items, 0..) |exit, i| {
            try stream.writeAll(if (i == 0) "" else ", ");
            try stream.print("{f}", .{exit});
        }
    }

    fn printCtrlList(_: *Writer, node: Oir.Node, repr: anytype, stream: *std.Io.Writer) !void {
        const span = node.data.list;
        for (repr.extra.items[span.start..span.end], 0..) |item, i| {
            try stream.writeAll(if (i == 0) "" else ", ");
            try stream.print("%{d}", .{item});
        }
    }
};

fn printNodeLabel(
    stream: anytype,
    node: Oir.Node,
) !void {
    switch (node.tag) {
        .constant => {
            const val = node.data.constant;
            try stream.print("constant:{d}", .{val});
        },
        .project => {
            const project = node.data.project;
            try stream.print("project({d})", .{project.index});
        },
        else => try stream.writeAll(@tagName(node.tag)),
    }
}
