const std = @import("std");
pub const Ir = @import("Ir.zig");
pub const Oir = @import("Oir.zig");

pub const options: std.Options = .{
    .log_level = .err,
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
