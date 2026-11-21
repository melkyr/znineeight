// typealias_arr_len_mismatch_xmod — GREEN diagnostic guard (A9F-a). A genuine
// length mismatch between the inferred-length literal and the declared array
// MUST still emit `warning[3000]` (proves the Q2 element-derivation fix does not
// blanket-suppress mismatches). Array→array structural assignability requires
// equal length, so `[2]i32` vs `[3]i32` still warns.
// Contract: dump rc0, exactly ONE warning[3000]; run prints 1\n.
const std = @import("std");

pub fn main() void {
    var b: [3]i32 = [_]i32{ 1, 2 };
    std.io.printInt(b[0]);
    std.io.writeByte('\n');
}
