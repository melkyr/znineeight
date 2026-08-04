const E = error{ Bad };
extern fn __bootstrap_print_int(n: i32) void;
fn f() E!i32 {
    return error.Bad;
}
pub fn main() void {
    var r = f() catch |err| {
        if (err == error.Bad) { __bootstrap_print_int(@intCast(i32, 1)); }
        else { __bootstrap_print_int(@intCast(i32, 0)); }
        return;
    };
    _ = r;
}
