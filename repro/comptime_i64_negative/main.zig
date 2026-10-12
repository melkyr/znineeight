extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i64 = @intCast(i64, -1);
    __bootstrap_print_int(@intCast(i32, r));
}
