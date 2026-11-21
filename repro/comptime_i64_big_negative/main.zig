extern fn __bootstrap_print_int(x: i32) void;
pub fn main() void {
    var r: i64 = @intCast(i64, -5000000000);
    var s: i64 = r + @intCast(i64, 5000000001);
    __bootstrap_print_int(@intCast(i32, s));
}
