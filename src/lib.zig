const std = @import("std");
pub const Ir = @import("Ir.zig");
pub const Oir = @import("Oir.zig");
pub const Trace = @import("Trace.zig");

pub const options: std.Options = .{
    .log_level = .err,
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
