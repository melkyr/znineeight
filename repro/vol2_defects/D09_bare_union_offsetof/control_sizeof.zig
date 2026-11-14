// D9 sibling shape: `@sizeOf` on a bare union is fine (contrast with
// @offsetOf).
const std = @import("std");

const Raw = union { i: i32, u: u32 };

pub fn main() void {
    std.io.print("size={}\n", .{@sizeOf(Raw)});
}
