// errunion_payload_varinit_xmod — GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S21, VARIABLE-INITIALIZER payload position: `var x: E![]const u8 = "alpha\r\n";`
// The wrap_error_success coercion is recorded (semantic_analyzer.zig:1420) but
// `materializeInto`'s payload path (sf/src/lower.zig:2032-2043) never applies the inner
// `string_to_slice`, so the emitted payload is a bare `char*` assigned to the slice
// field.
//
// FIXED in Task 0f (Track4 S21 F): the shared `materializeInto` payload path now applies
// the inner string_to_slice coercion to the payload BEFORE the wrap_error_ok layer.
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n`.
// Removed from EXPECTED_FAIL.md.
const std = @import("std");

const E = error{Bad};

pub fn main() void {
    var x: E![]const u8 = "alpha\r\n";
    var s: []const u8 = x catch "ERR";
    std.io.write(s);
}
