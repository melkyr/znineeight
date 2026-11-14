extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i32 = @intCast(i32, -1);
    __bootstrap_print_int(r);
}
