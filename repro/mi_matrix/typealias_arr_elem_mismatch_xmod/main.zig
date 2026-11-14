// typealias_arr_elem_mismatch_xmod — GREEN diagnostic guard (A9F-a). A genuine
// element-type mismatch between the inferred-length literal and the declared
// array MUST still emit `warning[3000]` (the annotation-derived element type is
// u8, the target is i32). Proves the Q2 fix does not blanket-suppress.
// Contract: dump rc0, exactly ONE warning[3000]; run prints 1\n.
const std = @import("std");

pub fn main() void {
    var b: [3]i32 = [_]u8{ 1, 2, 3 };
    std.io.printInt(b[0]);
    std.io.writeByte('\n');
}
