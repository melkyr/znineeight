// opt_payload_str_xmod — GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S21, `?[]const u8` analogue of errunion_payload_str_xmod: a string literal as
// the PAYLOAD of an optional return. The optional wrap records a wrap_optional coercion
// but `materializeInto`'s payload path (sf/src/lower.zig:2032-2043) never applies the
// inner `string_to_slice`, so the emitted payload is a bare `char*` assigned to the slice
// field.
//
// FIXED in Task 0f (Track4 S21 F): the shared `materializeInto` payload path now applies
// the inner string_to_slice coercion to the payload BEFORE the wrap_optional layer.
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n`.
// Removed from EXPECTED_FAIL.md.
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
