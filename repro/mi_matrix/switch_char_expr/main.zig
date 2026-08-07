extern fn __bootstrap_print_int(n: i32) void;
fn score(c: u8) i32 {
    return switch (c) {
        'a' => @intCast(i32, 1),
        'b' => @intCast(i32, 2),
        else => @intCast(i32, 0),
    };
}
pub fn main() void {
    __bootstrap_print_int(score('a'));
    __bootstrap_print_int(score('b'));
    __bootstrap_print_int(score('q'));
}
