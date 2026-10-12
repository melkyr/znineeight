pub fn main() void {
    var x: usize = 42;
    // @as() is not supported in zig0
    var y = @as(u32, x);
    _ = y;
}
