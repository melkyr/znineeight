// stdlib_print_untyped_lit_xmod — final whole-branch review fix-wave fixture
// (Finding 1: big untyped integer literals silently printed wrong values).
//
// DEFECT pinned here (v85 compiler): `printFnSourceName` forced the
// `integer_literal` route to 32-bit signed while the emitted C carrier is
// value-chosen (`intConstTypeForValue` -> `unsigned int`/`u64`), so a value
// outside i32 printed a truncated/re-interpreted number, and the literal-only
// arithmetic expression ran as 32-bit unsigned wrap:
//   print("{}", .{3000000000})           -> -1294967296  (Zig 3000000000)
//   print("{x}", .{3000000000})          -> -4d2fa200   (Zig b2d05e00)
//   print("{}", .{0 - 3000000000})       -> 1294967296  (Zig -3000000000)
//   print("{}", .{18446744073709551615}) -> -1          (Zig 18446744073709551615)
//
// FIX (final-review fix wave): `lowerPrintArgExact` (sf/src/lower.zig)
// materialises an exact untyped integer print argument into the carrier of its
// value (`comptimeIntUntypedType`: i32/u32/i64/u64) and the emitter dispatches
// on that carrier. A value that fits i32 keeps the legacy `integer_literal`
// temp, so in-range literals emit byte-identical C.
//
// Contract: stdout (13 lines) below, rc 0, byte-exact 3x, Zig-0.15.2 twin
// (`std.debug.print`) byte-compared 2026-09-25:
//   ud=3000000000
//   ux=b2d05e00
//   nd=-3000000000
//   nx=-b2d05e00
//   u64=18446744073709551615
//   u64x=ffffffffffffffff
//   p31=2147483648
//   u32max=4294967295
//   p32=4294967296
//   i32max=2147483647
//   nd2=-2147483648
//   in1=-1
//   in2=3
const std = @import("std");

pub fn main() void {
    std.io.print("ud={}\n", .{3000000000});
    std.io.print("ux={x}\n", .{3000000000});
    std.io.print("nd={}\n", .{0 - 3000000000});
    std.io.print("nx={x}\n", .{0 - 3000000000});
    std.io.print("u64={}\n", .{18446744073709551615});
    std.io.print("u64x={x}\n", .{18446744073709551615});
    std.io.print("p31={}\n", .{2147483648});
    std.io.print("u32max={}\n", .{4294967295});
    std.io.print("p32={}\n", .{4294967296});
    std.io.print("i32max={}\n", .{2147483647});
    std.io.print("nd2={}\n", .{0 - 2147483648});
    std.io.print("in1={}\n", .{0 - 1});
    std.io.print("in2={}\n", .{1 + 2});
}
