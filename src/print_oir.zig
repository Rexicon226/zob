//! Prints OIR to graphviz

const std = @import("std");
const Oir = @import("Oir.zig");

pub fn dumpGraphViz(
    oir: *const Oir,
    file_writer: anytype,
) !void {
    try file_writer.writeAll(
        \\digraph G {
        \\  compound=true
        \\  clusterrank=local
        \\  graph [fontsize=14 compound=true]
        \\  node [shape=box, style=filled];
        \\
    );

    {
        var class_iter = oir.classes.iterator();
        while (class_iter.next()) |entry| {
            const class_idx: u32 = @intFromEnum(entry.key_ptr.*);
            const class = entry.value_ptr.*;
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
                            .{node.data.constant},
                        );
                    },
                    else => try file_writer.writeAll(@tagName(node.tag)),
                }
                try file_writer.writeAll("\", color=\"grey\"];\n");
            }
            try file_writer.writeAll("  }\n");
        }
    }

    var class_iter = oir.classes.iterator();
    while (class_iter.next()) |entry| {
        const class_idx: u32 = @intFromEnum(entry.key_ptr.*);
        const class = entry.value_ptr.*;
        for (class.bag.items, 0..) |node_idx, i| {
            var arg_i: usize = 0;
            const node = oir.getNode(node_idx);
            for (node.operands()) |child_idx| {
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
