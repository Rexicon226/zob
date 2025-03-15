const std = @import("std");

pub fn addCases(
    b: *std.Build,
    step: *std.Build.Step,
    comptime sub_path: []const u8,
    test_runner: *std.Build.Step.Compile,
) !void {
    var dir = try b.build_root.handle.openDir("test/" ++ sub_path, .{ .iterate = true });
    defer dir.close();

    var it = try dir.walk(b.allocator);
    defer it.deinit();

    var filenames = std.ArrayList([]const u8).init(b.allocator);
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        try filenames.append(try b.allocator.dupe(u8, entry.path));
    }

    for (filenames.items) |path| {
        const run = b.addRunArtifact(test_runner);
        run.setName(path);
        step.dependOn(&run.step);

        var test_input = TestInput.parse(b.allocator, dir, path) catch |err| {
            switch (err) {
                error.SkipTest => continue,
                else => |e| return e,
            }
        };
        defer test_input.deinit(b.allocator);

        const input_path = b.addWriteFile("tmp.ir", test_input.input);
        run.addFileArg(input_path.getDirectory().path(b, "tmp.ir"));
        run.expectStdOutEqual(test_input.expected);
    }
}

pub const TestInput = struct {
    input: []const u8,
    expected: []const u8,

    pub fn parse(gpa: std.mem.Allocator, dir: std.fs.Dir, sub_path: []const u8) !TestInput {
        const contents = try dir.readFileAlloc(gpa, sub_path, 100 * 1024);
        defer gpa.free(contents);
        if (contents.len == 0) return error.SkipTest;

        var input = std.ArrayList(u8).init(gpa);
        errdefer input.deinit();

        // the test input starts off with "input IR:" and ends with "end IR" line.
        var in_input: bool = false;
        var index: usize = 0;
        var line_iter = std.mem.splitScalar(u8, contents, '\n');
        while (line_iter.next()) |line| {
            index += line.len + 1;
            if (std.mem.eql(u8, line, "input IR:")) {
                in_input = true;
                continue;
            }
            if (std.mem.eql(u8, line, "end IR")) {
                in_input = false;
                break;
            }
            if (in_input) {
                try input.appendSlice(line);
                try input.append('\n');
            }
        }

        if (input.items.len == 0) {
            std.debug.panic("{s} had no input section", .{sub_path});
        }

        return .{
            .input = try input.toOwnedSlice(),
            .expected = try gpa.dupe(u8, contents[index..]),
        };
    }

    pub fn deinit(input: *TestInput, gpa: std.mem.Allocator) void {
        gpa.free(input.input);
        gpa.free(input.expected);
    }
};
