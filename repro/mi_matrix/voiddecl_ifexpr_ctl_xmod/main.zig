const std = @import("std");
pub fn main() void {
    var kind: u32 = 0;
    var cmp_op = if (kind == 1) 13 else 12;
    std.io.printInt(cmp_op);
}
