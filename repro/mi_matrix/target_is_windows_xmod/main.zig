const std = @import("std");

pub fn main() void {
    var x: i32 = 0;
    if (@isWindows()) {
        x = 111;
    } else {
        x = 222;
    }
    std.io.printInt(x);
    std.io.print("\n");
}
