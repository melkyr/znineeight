extern fn __bootstrap_print_int(n: i32) void;
fn run() i32 {
    var count: i32 = 0;
    var c: u8 = 'a';
    var i: i32 = 0;
    while (i < @intCast(i32, 3)) {
        switch (c) {
            'a' => count = count + @intCast(i32, 1),
            else => {},
        }
        c = c + @intCast(u8, 1);
        i = i + @intCast(i32, 1);
    }
    return count;
}
pub fn main() void {
    __bootstrap_print_int(run());
}
