extern fn __bootstrap_print_int(n: i32) void;
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 9);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, classify('a')));
    __bootstrap_print_int(@intCast(i32, classify('q')));
}
