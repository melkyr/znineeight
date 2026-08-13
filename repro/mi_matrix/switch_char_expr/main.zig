const std = @import("std.zig");
fn score(c: u8) i32 {
    return switch (c) {
        'a' => @intCast(i32, 1),
        'b' => @intCast(i32, 2),
        else => @intCast(i32, 0),
    };
}
pub fn main() void {
    std.io.printInt(score('a'));
    std.io.printInt(score('b'));
    std.io.printInt(score('q'));
}
