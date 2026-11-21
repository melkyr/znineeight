extern fn __bootstrap_print_int(x: i32) void;
pub fn main() void {
    var a: [1]i32 = [1]i32{ @intCast(i32, 10) };
    a[0] += @intCast(i32, 5);
    __bootstrap_print_int(a[0]);
}
