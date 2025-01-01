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
                try stream.writeAll("\", color=\"grey\"];\n");
            }
            try stream.writeAll("  }\n");
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
                try stream.print(
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
        for (node.operands()) |child| {
            try stream.print("    {d} -> {d};\n", .{ i, @intFromEnum(child) });
        }
    }

    try stream.writeAll("}\n");
}

pub fn printRecv(
    recv: Extractor.Recursive,
    stream: anytype,
) !void {
    for (recv.nodes.items, 0..) |node, i| {
        try stream.print("%{d} = {s}(", .{ i, @tagName(node.tag) });
        try printNode(node, stream);
        try stream.writeAll(")\n");
    }
}

fn printNode(node: Oir.Node, stream: anytype) !void {
    switch (node.tag) {
        .arg => try stream.print("{d}", .{node.data.constant}),
        else => try stream.print("TODO: {s}", .{@tagName(node.tag)}),
    }
}

fn printNodeLabel(
    stream: anytype,
    node: Oir.Node,
) !void {
    switch (node.tag) {
        .constant => {
            const val = node.data.constant;
            try stream.print("constant:{d}", .{val});
        },
        .arg => {
            try stream.print(
                "arg({d})",
                .{node.data.constant},
            );
        },
        else => try stream.writeAll(@tagName(node.tag)),
    }
}
