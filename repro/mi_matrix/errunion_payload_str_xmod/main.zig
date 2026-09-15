// errunion_payload_str_xmod — GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S21 (left behind by Task 0d): a string literal as the SUCCESS payload of an
// error-union return `E![]const u8`. `return` records a `wrap_error_success` coercion
// (sf/src/semantic_analyzer.zig:1420), but `materializeInto`'s payload path
// (sf/src/lower.zig:2032-2043) never applies the inner `string_to_slice` coercion before
// wrapping, so the emitted payload is a bare `char*` assigned to the slice field.
//
// FIXED in Task 0f (Track4 S21 F): `materializeInto`'s payload path now applies the
// inner string_to_slice coercion to the payload BEFORE the wrap_error_ok layer.
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n`.
// Removed from EXPECTED_FAIL.md.
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
