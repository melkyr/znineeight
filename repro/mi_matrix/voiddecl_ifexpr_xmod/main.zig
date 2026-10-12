const std = @import("std");
const BIN_LT = @intCast(u8, 12);
const BIN_LE = @intCast(u8, 13);
pub fn main() void {
    var kind: u32 = 0;
    var cmp_op = if (kind == 1) BIN_LE else BIN_LT;
    std.io.printInt(cmp_op);
}
