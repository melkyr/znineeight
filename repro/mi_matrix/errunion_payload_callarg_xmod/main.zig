// errunion_payload_callarg_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21, CALL-ARGUMENT payload position: a string literal passed where the callee
// parameter type is `E![]const u8`. The wrap_error_success coercion is recorded
// (semantic_analyzer.zig:1420) but `materializeInto`'s payload path
// (sf/src/lower.zig:2032-2043) never applies the inner `string_to_slice`, so the emitted
// argument payload is a bare `char*` assigned to the slice field.
//
// RED = gcc FAIL. Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes the shared payload path. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

const E = error{Bad};

fn take(x: E![]const u8) void {
    var s: []const u8 = x catch "ERR";
    std.io.write(s);
}

pub fn main() void {
    take("alpha\r\n");
}
