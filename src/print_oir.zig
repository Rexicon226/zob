//! Prints OIR to graphviz

const std = @import("std");
const Oir = @import("Oir.zig");

pub fn dumpGraphViz(
    oir: *Oir,
    file_writer: anytype,
) !void {
    try file_writer.writeAll(
        \\digraph G {
        \\  compound=true
        \\  clusterrank=local
        \\  graph [fontsize=14 compound=true]
        \\  node [shape=box, stlye=filled];
        \\
    );

    for (oir.classes.items, 0..) |class, class_idx| {
        try file_writer.print(
            \\  subgraph cluster_{d} {{
            \\    style=dotted
            \\
        , .{class_idx});

        for (class.bag.items, 0..) |node_idx, i| {
            const node = oir.getNode(node_idx);
            try file_writer.print("    {}.{} [label=\"", .{ class_idx, i });
            switch (node.tag) {
                .constant => {
                    const val = node.data.constant;
                    try file_writer.print("constant:{d}", .{val});
                },
                .arg => {
                    try file_writer.print(
                        "arg({d})",
                        .{@intFromEnum(node_idx)},
                    );
                },
                else => try file_writer.writeAll(@tagName(node.tag)),
            }
            try file_writer.writeAll("\", color=\"grey\"];\n");
        }
        try file_writer.writeAll("  }\n");
    }

    for (oir.classes.items, 0..) |class, class_idx| {
        for (class.bag.items, 0..) |node_idx, i| {
            var arg_i: usize = 0;
            const node = oir.getNode(node_idx);
            for (node.out.items) |child_idx| {
                try file_writer.print(
                    "  {}.{} -> {}.0 [lhead = cluster_{}]\n",
                    .{
                        class_idx,
                        i,
                        @intFromEnum(child_idx),
                        @intFromEnum(child_idx),
                    },
                );
                arg_i += 1;
            }
        }
    }

    try file_writer.writeAll("}\n");
}
