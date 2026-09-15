// opt_payload_str_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21, `?[]const u8` analogue of errunion_payload_str_xmod: a string literal as
// the PAYLOAD of an optional return. The optional wrap records a wrap_optional coercion
// but `materializeInto`'s payload path (sf/src/lower.zig:2032-2043) never applies the
// inner `string_to_slice`, so the emitted payload is a bare `char*` assigned to the slice
// field.
//
// RED = gcc FAIL. Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes the shared payload path. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

fn f(b: bool) ?[]const u8 {
    if (!b) return null;
    return "alpha\r\n";
}

pub fn main() void {
    var r: ?[]const u8 = f(true);
    var s: []const u8 = r orelse "NULL";
    std.io.write(s);
}
