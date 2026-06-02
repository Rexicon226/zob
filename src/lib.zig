const std = @import("std");
pub const Oir = @import("Oir.zig");
pub const Trace = @import("trace.zig").Trace;

pub const Recursive = Oir.extraction.Recursive;

pub const rv64 = @import("codegen/rv64.zig");

pub const options: std.Options = .{
    .log_level = .err,
};

test {
    _ = Oir;
    _ = Trace;
    _ = Recursive;
    _ = rv64;
}
