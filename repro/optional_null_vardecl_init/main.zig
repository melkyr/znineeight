extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var p: ?*i32 = null;
    if (p == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }

    var q: ?i32 = null;
    if (q == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
