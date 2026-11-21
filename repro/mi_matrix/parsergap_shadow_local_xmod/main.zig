const std = @import("std");
pub fn main() void {
    var x: i32 = 1;
    {
        var x: i32 = 2;
        std.io.printInt(x);
    }
    std.io.printInt(x);
}
