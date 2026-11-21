const std = @import("std");
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a', 'b' => r = @intCast(u8, 1),
        'c' => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
pub fn main() void {
    std.io.printInt(@intCast(i32, classify('a')));
    std.io.printInt(@intCast(i32, classify('b')));
    std.io.printInt(@intCast(i32, classify('c')));
    std.io.printInt(@intCast(i32, classify('q')));
}
