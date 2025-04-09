//! Implements tracing utilities for outputting spall. TODO: Probably want to
//! move this over to a built option to not pull in tracing without an option
//! enabled, but for now I'm trying out with runtime toggling.

const std = @import("std");
const Trace = @This();

buffered: std.io.BufferedWriter(4096, std.fs.File.Writer),
start_time: std.time.Instant,
stream: std.fs.File,
enabled: bool,

pub fn init() Trace {
    return .{
        .stream = undefined,
        .buffered = undefined,
        .start_time = undefined,
        .enabled = false,
    };
}

pub fn enable(t: *Trace, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    try file.writer().writeByte('[');
    t.* = .{
        .stream = file,
        .buffered = std.io.bufferedWriter(file.writer()),
        .start_time = try std.time.Instant.now(),
        .enabled = true,
    };
}

pub fn deinit(t: *Trace) void {
    if (!t.enabled) return;
    t.buffered.writer().writeAll("]\n") catch @panic("failed to print");
    t.buffered.flush() catch @panic("failed to flush");
    t.stream.close();
}

const Event = struct {
    src: std.builtin.SourceLocation,
    trace: *Trace,
    enabled: bool,

    const disabled: Event = .{
        .src = undefined,
        .trace = undefined,
        .enabled = false,
    };

    pub fn end(e: Event) void {
        if (!e.enabled) return;
        const writer = e.trace.buffered.writer();
        const now = std.time.Instant.now() catch @panic("failed to now()");
        writer.print(
            \\{{"cat":"function", "ph":"E", "ts":{d}, "pid":0, "tid":0}},
            \\
        ,
            .{now.since(e.trace.start_time) / 1_000},
        ) catch @panic("failed to write");
    }
};

pub fn start(t: *Trace, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) Event {
    if (!t.enabled) return .disabled;
    const now = std.time.Instant.now() catch @panic("failed to now()");
    const writer = t.buffered.writer();

    writer.print(
        \\{{"cat":"function", "name":"{s}:{d}:{d} (
    ++ fmt ++
        \\)", "ph": "B", "pid": 0, "tid": 0, "ts": {d}}},
        \\
    , .{
        std.fs.path.basename(src.file),
        src.line,
        src.column,
    } ++
        args ++ .{
        now.since(t.start_time) / 1_000,
    }) catch @panic("failed to write");

    return .{
        .src = src,
        .trace = t,
        .enabled = true,
    };
}
