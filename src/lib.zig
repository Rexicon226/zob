const std = @import("std");
pub const Oir = @import("Oir.zig");
pub const Trace = @import("trace.zig").Trace;

pub const Recursive = Oir.extraction.Recursive;

pub const p2 = @import("codegen/p2.zig");
pub const rv64 = @import("codegen/rv64.zig");

pub const options: std.Options = .{
    .log_level = .err,
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
