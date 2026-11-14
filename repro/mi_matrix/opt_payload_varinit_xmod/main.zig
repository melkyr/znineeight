// opt_payload_varinit_xmod — GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S21, VARIABLE-INITIALIZER payload position, `?[]const u8` analogue of
// errunion_payload_varinit_xmod: `var x: ?[]const u8 = "alpha\r\n";`. The payload wrap
// never applies the inner `string_to_slice` (sf/src/lower.zig:2032-2043), so the emitted
// payload is a bare `char*` assigned to the slice field.
//
// FIXED in Task 0f (Track4 S21 F): the shared `materializeInto` payload path now applies
// the inner string_to_slice coercion to the payload BEFORE the wrap_optional layer.
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n`.
// Removed from EXPECTED_FAIL.md.
const std = @import("std");

pub fn main() void {
    var x: ?[]const u8 = "alpha\r\n";
    var s: []const u8 = x orelse "NULL";
    std.io.write(s);
}
