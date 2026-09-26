// D10 sibling shape: `p[1]` on a single-item pointer is accepted too (reads
// past the pointee; no diagnostic).
const std = @import("std");

pub fn main() void {
    var arr = [2]i32{ 7, 8 };
    const p: *i32 = &arr[0];
    std.io.print("p[1]={}\n", .{p[1]});
}
