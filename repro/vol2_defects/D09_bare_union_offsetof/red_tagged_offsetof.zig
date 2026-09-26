// D9 control: `@offsetOf` on a tagged union works (the bare-union ICE is
// specific to bare unions).
const std = @import("std");

const T = union(enum) { i: i32, u: u32 };

pub fn main() void {
    std.io.print("off_i={}\n", .{@offsetOf(T, "i")});
}
