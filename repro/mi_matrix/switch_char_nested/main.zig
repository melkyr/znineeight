extern fn __bootstrap_print_int(n: i32) void;
fn nested(outer: u8, inner: u8) i32 {
    var r: i32 = 0;
    switch (outer) {
        'a' => {
            switch (inner) {
                'x' => r = @intCast(i32, 1),
                else => r = @intCast(i32, 0),
            }
        },
        else => r = @intCast(i32, 9),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(nested('a', 'x'));
    __bootstrap_print_int(nested('a', 'y'));
    __bootstrap_print_int(nested('z', 'x'));
}
