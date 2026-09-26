// FF (D9) cross-module reject site: a union `@offsetOf` in the helper file
// rejects with `error[3072]` in the helper's own file (the same clean code as
// the in-module shapes).
const std = @import("std");

pub const RU = union {
    i: i32,
    u: u32,
};

pub fn badOffset() void {
    std.io.print("x={}\n", .{@offsetOf(RU, "i")});
}
