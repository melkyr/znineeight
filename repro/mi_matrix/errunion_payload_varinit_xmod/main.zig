// errunion_payload_varinit_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21, VARIABLE-INITIALIZER payload position: `var x: E![]const u8 = "alpha\r\n";`
// The wrap_error_success coercion is recorded (semantic_analyzer.zig:1420) but
// `materializeInto`'s payload path (sf/src/lower.zig:2032-2043) never applies the inner
// `string_to_slice`, so the emitted payload is a bare `char*` assigned to the slice
// field.
//
// RED = gcc FAIL. Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes the shared payload path. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

const E = error{Bad};

pub fn main() void {
    var x: E![]const u8 = "alpha\r\n";
    var s: []const u8 = x catch "ERR";
    std.io.write(s);
}
