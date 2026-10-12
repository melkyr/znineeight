extern fn __bootstrap_print_int(x: i32) void;
fn set(p: *i32) void {
    (p.*) = @intCast(i32, 7);
}
fn setNested(p: *i32) void {
    ((p.*)) = @intCast(i32, 9);
}
pub fn main() void {
    var a: i32 = @intCast(i32, 0);
    var b: i32 = @intCast(i32, 0);
    set(&a);
    setNested(&b);
    __bootstrap_print_int(a + b);
}
