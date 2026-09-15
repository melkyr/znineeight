// opt_payload_field_xmod — compile-FAIL fixture (dump rc=0, emitted .c fails gcc).
//
// Residual S21, STRUCT-FIELD payload position, `?[]const u8` analogue of
// errunion_payload_field_xmod: a string literal initializing a struct field of type
// `?[]const u8` (`S{ .x = "alpha\r\n" }`). The payload wrap never applies the inner
// `string_to_slice` (sf/src/lower.zig:2032-2043), so the emitted field payload is a bare
// `char*` assigned to the slice field.
//
// RED = gcc FAIL. Expected gcc diagnostic:
//   incompatible types when assigning to type 'Slice_..' from type 'char *'
//
// Task 0f Step 2 fixes the shared payload path. Recorded in EXPECTED_FAIL.md.
const std = @import("std");

const S = struct { x: ?[]const u8 };

pub fn main() void {
    var v: S = .{ .x = "alpha\r\n" };
    var s: []const u8 = v.x orelse "NULL";
    std.io.write(s);
}
