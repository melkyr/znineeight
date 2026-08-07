extern fn __bootstrap_print_int(n: i32) void;
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, classify('a')));
    __bootstrap_print_int(@intCast(i32, classify('b')));
    __bootstrap_print_int(@intCast(i32, classify('z')));
}
