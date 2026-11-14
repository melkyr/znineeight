// D9 in-module RED: `@offsetOf` on a bare union hits an internal compiler
// error: error[3043]: internal: comptime value unresolved for @sizeOf/@alignOf
const std = @import("std");

const Raw = union { i: i32, u: u32 };

pub fn main() void {
    std.io.print("off_i={}\n", .{@offsetOf(Raw, "i")});
}
