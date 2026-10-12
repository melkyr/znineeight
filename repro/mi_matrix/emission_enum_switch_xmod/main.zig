const std = @import("std.zig");
const Kind = enum(u16) { plus, minus, star };
fn pick(k: Kind) u32 {
    var r: u32 = 0;
    switch (k) {
        Kind.plus => r = 1,
        Kind.minus => r = 2,
        Kind.star => r = 3,
        else => {},
    }
    return r;
}
pub fn main() void {
    std.io.printInt(pick(Kind.minus));
}
