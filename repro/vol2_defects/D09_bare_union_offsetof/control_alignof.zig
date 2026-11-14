// D9 sibling shape: `@alignOf` on a bare union (does it hit the same internal
// error as `@offsetOf`?).
const std = @import("std");

const Raw = union { i: i32, u: u32 };

pub fn main() void {
    std.io.print("align={}\n", .{@alignOf(Raw)});
}
