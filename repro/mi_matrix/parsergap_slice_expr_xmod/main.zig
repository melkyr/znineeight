const std = @import("std");

pub fn main() void {
    var n: u32 = 7;
    var s = n[1..];
    std.io.printInt(@intCast(i32, s.len));
}
