const std = @import("std");

const A: i32 = 30;
const B: i32 = A + 5;
const C: i32 = B * 2;

pub fn main() void {
    std.io.printInt(B);
    std.io.printInt(C);
}
