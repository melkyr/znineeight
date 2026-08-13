const std = @import("std.zig");
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
    std.io.printInt(@intCast(i32, classify('a')));
    std.io.printInt(@intCast(i32, classify('b')));
    std.io.printInt(@intCast(i32, classify('z')));
}
