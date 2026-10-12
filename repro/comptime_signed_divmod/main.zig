extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i32 = @intCast(i32, -6 / 2);
    __bootstrap_print_int(r);
}
