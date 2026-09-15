// errunion_payload_str_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21 (left behind by Task 0d): a string literal as the SUCCESS payload of an
// error-union return `E![]const u8`. `return` records a `wrap_error_success` coercion
// (sf/src/semantic_analyzer.zig:1420), but `materializeInto`'s payload path
// (sf/src/lower.zig:2032-2043) never applies the inner `string_to_slice` coercion before
// wrapping, so the emitted payload is a bare `char*` assigned to the slice field.
//
// RED = gcc FAIL (the Task 0d fix does not trigger: its classify() sees
// wrap_error_success, not string_to_slice). Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes this by applying the inner string_to_slice coercion to the
// payload BEFORE the wrap_error_ok layer. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

const E = error{Bad};

fn f(b: bool) E![]const u8 {
    if (b) return error.Bad;
    return "alpha\r\n";
}

pub fn main() void {
    var r: E![]const u8 = f(false);
    var s: []const u8 = r catch "ERR";
    std.io.write(s);
}
