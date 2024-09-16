//! Prints OIR to graphviz

const std = @import("std");
const Oir = @import("Oir.zig");

pub fn dumpGraphViz(
    oir: *Oir,
    file_writer: anytype,
) !void {
    try file_writer.writeAll(
        \\digraph G {
        \\  graph [fontsize=14 compound=true]
        \\  node [shape=box, stlye=filled];
        \\
    );

    for (oir.classes.items, 0..) |class, i| {
        try file_writer.print(
            \\  subgraph cluster_{d} {{
            \\    style=dotted
            \\
        ,
            .{i},
        );

        for (class.bag.items) |node_idx| {
            const node = oir.getNode(node_idx);
            try file_writer.print("    node{d} [label=\"", .{@intFromEnum(node_idx)});
            switch (node.tag) {
                .constant => {
                    const val = node.data.constant;
                    try file_writer.print("constant:{d}", .{val});
                },
                .arg => {
                    try file_writer.print("arg({d})", .{@intFromEnum(node_idx)});
                },
                else => try file_writer.writeAll(@tagName(node.tag)),
            }
            try file_writer.writeAll("\", color=\"grey\"];\n");
        }

        try file_writer.writeAll("  }\n");
    }

    for (oir.nodes.items, 0..) |node, i| {
        for (node.out.items) |class_idx| {
            const class = oir.getClass(class_idx);
            if (class.bag.items.len == 0) std.debug.panic(
                "node %{d} connects to empty class %{d} empty for some reason",
                .{ i, @intFromEnum(class_idx) },
            );
            const node_idx = class.bag.items[0];
            try file_writer.print(
                "  node{d} -> node{d} [lhead=\"cluster_{d}\"];\n",
                .{ i, @intFromEnum(node_idx), @intFromEnum(class_idx) },
            );
        }
    }

    try file_writer.writeAll("}\n");
}
