extern fn __bootstrap_print_int(n: i32) void;
fn f() !i32 {
    return error.Bad;
}
pub fn main() void {
    var r = f() catch |err| {
        switch (err) {
            error.Bad => __bootstrap_print_int(@intCast(i32, 1)),
            error.Other => __bootstrap_print_int(@intCast(i32, 2)),
            else => __bootstrap_print_int(@intCast(i32, 0)),
        }
        return;
    };
    _ = r;
}
