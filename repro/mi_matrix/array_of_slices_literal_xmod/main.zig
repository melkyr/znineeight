// array_of_slices_literal_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Task 0c-reported residual gap (declared here per the standing declare-every-gap rule):
// an ARRAY-OF-SLICES literal `var a: [2][]const u8 = .{ "alpha\r\n", "beta\r\n" };` is
// emitted as a bare C array assignment and gcc rejects it. Expected gcc diagnostic:
//   assignment to expression with array type
//
// RED = gcc FAIL. This is a DISTINCT emission gap (not the string->slice coercion gaps);
// it is declared (not fixed) here. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

var a: [2][]const u8 = .{ "alpha\r\n", "beta\r\n" };

pub fn main() void {
    std.io.write(a[0]);
    std.io.writeByte('|');
    std.io.write(a[1]);
}
