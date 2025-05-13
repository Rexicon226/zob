const std = @import("std");
pub const Oir = @import("Oir.zig");
pub const Trace = @import("Trace.zig");

pub const Recursive = Oir.extraction.Recursive;

pub const options: std.Options = .{
    .log_level = .err,
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
