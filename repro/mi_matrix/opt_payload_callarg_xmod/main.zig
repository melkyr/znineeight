// opt_payload_callarg_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21, CALL-ARGUMENT payload position, `?[]const u8` analogue of
// errunion_payload_callarg_xmod: a string literal passed where the callee parameter type
// is `?[]const u8`. The payload wrap never applies the inner `string_to_slice`
// (sf/src/lower.zig:2032-2043), so the emitted argument payload is a bare `char*`
// assigned to the slice field.
//
// RED = gcc FAIL. Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes the shared payload path. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

fn take(x: ?[]const u8) void {
    var s: []const u8 = x orelse "NULL";
    std.io.write(s);
}

pub fn main() void {
    take("alpha\r\n");
}
