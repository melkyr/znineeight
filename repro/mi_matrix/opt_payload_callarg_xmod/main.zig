// opt_payload_callarg_xmod — GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S21, CALL-ARGUMENT payload position, `?[]const u8` analogue of
// errunion_payload_callarg_xmod: a string literal passed where the callee parameter type
// is `?[]const u8`. The payload wrap never applies the inner `string_to_slice`
// (sf/src/lower.zig:2032-2043), so the emitted argument payload is a bare `char*`
// assigned to the slice field.
//
// FIXED in Task 0f (Track4 S21 F): the shared `materializeInto` payload path now applies
// the inner string_to_slice coercion to the payload BEFORE the wrap_optional layer.
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n`.
// Removed from EXPECTED_FAIL.md.
const std = @import("std");

fn take(x: ?[]const u8) void {
    var s: []const u8 = x orelse "NULL";
    std.io.write(s);
}

pub fn main() void {
    take("alpha\r\n");
}
