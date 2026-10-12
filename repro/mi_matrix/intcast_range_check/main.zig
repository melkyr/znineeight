const std = @import("std");
pub fn main() void {
    var i: i64 = 2147483647;
    i = i + 1;
    std.io.printInt(@intCast(i32, i));
}
