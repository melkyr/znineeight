extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var c = @intCast(i32, 'c');
    __bootstrap_print_int(c);
}
