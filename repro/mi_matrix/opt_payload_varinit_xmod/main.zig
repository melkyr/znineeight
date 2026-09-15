// opt_payload_varinit_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21, VARIABLE-INITIALIZER payload position, `?[]const u8` analogue of
// errunion_payload_varinit_xmod: `var x: ?[]const u8 = "alpha\r\n";`. The payload wrap
// never applies the inner `string_to_slice` (sf/src/lower.zig:2032-2043), so the emitted
// payload is a bare `char*` assigned to the slice field.
//
// RED = gcc FAIL. Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes the shared payload path. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

pub fn main() void {
    var x: ?[]const u8 = "alpha\r\n";
    var s: []const u8 = x orelse "NULL";
    std.io.write(s);
}
