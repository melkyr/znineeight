const std = @import("std.zig");
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
    std.io.printInt(nested('a', 'x'));
    std.io.printInt(nested('a', 'y'));
    std.io.printInt(nested('z', 'x'));
}
