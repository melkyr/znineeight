// opt_payload_field_xmod — GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S21, STRUCT-FIELD payload position, `?[]const u8` analogue of
// errunion_payload_field_xmod: a string literal initializing a struct field of type
// `?[]const u8` (`S{ .x = "alpha\r\n" }`). The payload wrap never applies the inner
// `string_to_slice` (sf/src/lower.zig:2032-2043), so the emitted field payload is a bare
// `char*` assigned to the slice field.
//
// FIXED in Task 0f (Track4 S21 F): the shared `materializeInto` payload path now applies
// the inner string_to_slice coercion to the payload BEFORE the wrap_optional layer.
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n`.
// Removed from EXPECTED_FAIL.md.
const std = @import("std");

const S = struct { x: ?[]const u8 };

pub fn main() void {
    var v: S = .{ .x = "alpha\r\n" };
    var s: []const u8 = v.x orelse "NULL";
    std.io.write(s);
}
