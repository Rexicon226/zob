const std = @import("std");
const build_options = @import("build_options");

pub const Trace = if (build_options.enable_trace) struct {
    stream: std.Io.File.Writer,
    file: std.Io.File,
    start_time: std.Io.Timestamp,
    io: std.Io,

    pub fn init(io: std.Io) Trace {
        errdefer @panic("failed to init trace");
        const file = try std.Io.Dir.cwd().createFile(io, "trace.json", .{});
        errdefer file.close(io);

        var stream = file.writer(io, &.{});
        try stream.interface.writeByte('[');
        return .{
            .stream = stream,
            .file = file,
            .start_time = std.Io.Clock.now(.real, io),
            .io = io,
        };
    }

    pub fn start(
        t: *Trace,
        src: std.builtin.SourceLocation,
        comptime fmt: []const u8,
        args: anytype,
    ) Event {
        t.writer().print(
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
            t.start_time.untilNow(t.io, .real).nanoseconds,
        }) catch @panic("failed to write");

        return .{
            .src = src,
            .trace = t,
        };
    }

    pub fn deinit(t: *Trace) void {
        t.writer().writeAll("]\n") catch @panic("failed to print");
        t.writer().flush() catch @panic("failed to flush");
        t.file.close(t.io);
    }

    fn writer(t: *Trace) *std.Io.Writer {
        return &t.stream.interface;
    }
} else struct {
    pub fn init(_: void) Trace {
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
        const trace = e.trace;
        trace.writer().print(
            \\{{"cat":"function", "ph":"E", "ts":{d}, "pid":0, "tid":0}},
            \\
        ,
            .{trace.start_time.untilNow(trace.io, .real).nanoseconds},
        ) catch @panic("failed to write");
    }
};
