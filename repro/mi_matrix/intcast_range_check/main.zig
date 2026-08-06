extern fn __bootstrap_print_int(v: i32) void;
pub fn main() void {
    var i: i64 = 2147483647;
    i = i + 1;
    __bootstrap_print_int(@intCast(i32, i));
}
