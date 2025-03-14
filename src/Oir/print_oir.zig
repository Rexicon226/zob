//! Prints OIR to graphviz

const std = @import("std");
const Oir = @import("../Oir.zig");
const Extractor = @import("Extractor.zig");

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
        \\  concentrate="true";
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

                const color = switch (node.tag.nodeType()) {
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
        const class_idx: u32 = @intFromEnum(entry.key_ptr.*);
        const class = entry.value_ptr.*;
        for (class.bag.items, 0..) |node_idx, i| {
            const node = oir.getNode(node_idx);
            switch (node.tag) {
                .ret => {
                    const ctrl, const data = node.data.bin_op;
                    try stream.print(
                        "  {}.{} -> {}.0 [lhead = cluster_{} color=\"red\"]\n",
                        .{
                            class_idx,
                            i,
                            @intFromEnum(ctrl),
                            @intFromEnum(ctrl),
                        },
                    );
                    try stream.print(
                        "  {}.{} -> {}.0 [lhead = cluster_{}]\n",
                        .{
                            class_idx,
                            i,
                            @intFromEnum(data),
                            @intFromEnum(data),
                        },
                    );
                },
                else => for (node.operands(oir)) |child_idx| {
                    try stream.print(
                        "  {}.{} -> {}.0 [lhead = cluster_{}]\n",
                        .{
                            class_idx,
                            i,
                            @intFromEnum(child_idx),
                            @intFromEnum(child_idx),
                        },
                    );
                },
            }
        }
    }

    try stream.writeAll("}\n");
}

pub fn dumpRecvGraph(
    recv: Extractor.Recursive,
    stream: anytype,
) !void {
    try stream.writeAll(
        \\digraph G {
        \\  compound=true
        \\  clusterrank=local
        \\  graph [fontsize=14 compound=true]
        \\  node [shape=box, style=filled];
        \\
    );

    for (recv.nodes.items, 0..) |node, i| {
        try stream.print("  {} [label=\"", .{i});
        try printNodeLabel(stream, node);
        try stream.writeAll("\", color=\"grey\"];\n");
    }
    try stream.writeAll("\n");

    for (recv.nodes.items, 0..) |node, i| {
        for (node.operands(recv)) |child| {
            try stream.print("    {d} -> {d};\n", .{ i, @intFromEnum(child) });
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
    var writer: Writer = .{ .nodes = repr.nodes.items };
    try writer.printBody(repr, stream);
}

pub const Writer = struct {
    indent: u32 = 0,
    nodes: []const Oir.Node,

    fn printBody(w: *Writer, repr: anytype, stream: anytype) !void {
        for (0..w.nodes.len) |i| {
            try stream.print("%{d} = ", .{i});
            try w.printNode(w.nodes[i], repr, stream);
            try stream.writeByte('\n');
        }
    }

    pub fn printNode(w: *Writer, node: Oir.Node, repr: anytype, stream: anytype) !void {
        try stream.print("{s}(", .{@tagName(node.tag)});
        switch (node.tag) {
            .ret,
            .add,
            .cmp_gt,
            => try w.printBinOp(node, stream),
            .project => try w.printProject(node, stream),
            .constant => try w.printConstant(node, stream),
            .branch => try w.printCtrlDataOp(node, stream),
            .region, .start => try w.printCtrlList(node, repr, stream),
            else => try stream.print("TODO: {s}", .{@tagName(node.tag)}),
        }
        try stream.writeAll(")");
    }

    fn printUnOp(_: *Writer, node: Oir.Node, stream: anytype) !void {
        const op = node.data.un_op;
        try stream.print("{}", .{op});
    }

    fn printBinOp(_: *Writer, node: Oir.Node, stream: anytype) !void {
        const bin_op = node.data.bin_op;
        try stream.print("{}, {}", .{ bin_op[0], bin_op[1] });
    }

    fn printProject(_: *Writer, node: Oir.Node, stream: anytype) !void {
        const project = node.data.project;
        try stream.print("{d} {}", .{ project.index, project.tuple });
    }

    fn printConstant(_: *Writer, node: Oir.Node, stream: anytype) !void {
        const constant = node.data.constant;
        try stream.print("{d}", .{constant});
    }

    fn printCtrlDataOp(_: *Writer, node: Oir.Node, stream: anytype) !void {
        const bin_op = node.data.bin_op;
        try stream.print("{}, {}", .{ bin_op[0], bin_op[1] });
    }

    fn printCtrlList(_: *Writer, node: Oir.Node, repr: anytype, stream: anytype) !void {
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
        else => try stream.writeAll(@tagName(node.tag)),
    }
}
