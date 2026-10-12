const std = @import("std");
fn f(a: i32, b: i32) i32 { return a + b; }
pub fn main() void {
    var r1 = f(1 2);
    std.io.printInt(r1);
}
