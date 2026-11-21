const std = @import("std");
pub fn main() void {
    var a: u8 = 200;
    var b: u8 = 2;
    var x: u8 = 0;
    x = a +% b;
    x = a -% b;
    x = a *% b;
    x = a +| b;
    x = a -| b;
    x = a *| b;
    x = a <<| b;
    x = -%a;
    x +%= b;
    x -%= b;
    x *%= b;
    x +|= b;
    x -|= b;
    x *|= b;
    x <<|= b;
    std.io.printInt(x);
}
