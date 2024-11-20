export fn foo(x: u32, y: u32) u32 {
    return x << @intCast(y);
}
