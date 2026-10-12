extern fn __bootstrap_print_int(x: i32) void;
fn bump(p: *i32) void {
    p.* += @intCast(i32, 5);
}
fn outer(x: i32) i32 {
    bump(&x);
    return x;
}
pub fn main() void {
    __bootstrap_print_int(outer(@intCast(i32, 10)));
}
