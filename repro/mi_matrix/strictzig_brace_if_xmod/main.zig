const std = @import("std");
pub fn main() void {
    var x: u32 = 2;
    var kind: u32 = 0;
    if (kind == 0) x = x + 1;
    else x = x - 1;
    std.io.printInt(@intCast(i32, x));
}
