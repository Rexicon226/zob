const std = @import("std");
const build_options = @import("build_options");

pub const Trace = if (build_options.enable_trace) struct {
    buffered: std.io.BufferedWriter(4096, std.fs.File.Writer),
    start_time: std.time.Instant,
    stream: std.fs.File,

    pub fn init() Trace {
        errdefer @panic("failed to init trace");
        const file = try std.fs.cwd().createFile("trace.json", .{});
        try file.writer().writeByte('[');
        return .{
            .stream = file,
            .buffered = std.io.bufferedWriter(file.writer()),
            .start_time = try std.time.Instant.now(),
        };
    }

    pub fn start(
        t: *Trace,
        src: std.builtin.SourceLocation,
        comptime fmt: []const u8,
        args: anytype,
    ) Event {
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
        };
    }

    pub fn deinit(t: *Trace) void {
        t.buffered.writer().writeAll("]\n") catch @panic("failed to print");
        t.buffered.flush() catch @panic("failed to flush");
        t.stream.close();
    }
} else struct {
    pub fn init() Trace {
        return .{};
    }

    pub fn start(
        _: *Trace,
        _: std.builtin.SourceLocation,
        comptime _: []const u8,
        _: anytype,
    ) Event {
        return undefined;
    }

    pub fn deinit(_: *Trace) void {}
};

const Event = struct {
    src: std.builtin.SourceLocation,
    trace: *Trace,

    pub fn end(e: Event) void {
        if (!build_options.enable_trace) return;
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
