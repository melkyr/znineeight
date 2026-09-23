// stdlib_comptime_coerce_typed_slots_xmod — Task 4 (coercion into typed slots)
// positive runtime fixture.
//
// Pins the IN-RANGE materialisation of folded comptime integers into every
// target kind: typed local/module decls, function parameters, optional
// parameters, returns, `@intCast`/`@as`, array sizes, and an enum backing.
// Every shape was checked against the official Zig 0.15.2 oracle twin; the
// committed stdout is the oracle's stdout byte-for-byte.
//
// Covered:
//   * the Task 3 carry-item local bare-negate i64 min
//     (`const imin: i64 = -9223372036854775808;` printed exactly; before Task 4
//     the negate HIT forced an i32 temp and printed 0);
//   * typed narrow slots at their exact bounds (`u8` 255, `i8` -128);
//   * an unsigned slot above i32 max (`u32` 3000000000) and the UNTYPED
//     value-based temp selection: `2000000000 + 1000000000` -> u32,
//     `(1 << 63) + 7` -> u64, `0 - 3000000000` -> i64 (Task 1 §5.2 untyped row;
//     before Task 4 these truncated to `int`, printing 0/0/0-class values);
//   * in-range `@intCast(i8, -128)` and `@as(u64, 18446744073709551615)`;
//   * non-negative array sizes (`[4 * 8]u8`, `[10 - 3]u8`) — the size fold is
//     exact and accepts 0..0xFFFFFFFE (Task 1 §9.3);
//   * an enum(u8) backing member at its bound (`A = 250 + 5`);
//   * a typed module const fold (`const MU8: u8 = 100 + 50;`);
//   * a folded argument into a `u8` parameter and a folded return from a `u8`
//     function, plus the optional-payload variant.
//
// Oracle output (Zig 0.15.2 twin, `/tmp/task4/oracle/pos.zig`):
//   -9223372036854775808 255 -128 3000000000 3000000000 9223372036854775815 -3000000000 -128 18446744073709551615 32 7 255 200 200
//   150 600
//
// Contract: stdout below, rc 0, byte-exact 3x.
const std = @import("std");

const MU8: u8 = 100 + 50;
const E8 = enum(u8) { A = 250 + 5, B = 0 };

fn takeU8(x: u8) i32 {
    return @intCast(i32, x);
}

fn takeOptU8(x: ?u8) i32 {
    if (x) |v| {
        return @intCast(i32, v);
    }
    return 0 - 1;
}

fn retU8() u8 {
    return @as(u8, 200);
}

pub fn main() void {
    const imin: i64 = -9223372036854775808;
    const lu8: u8 = 200 + 55;
    const li8: i8 = -100 - 28;
    const lu32: u32 = 2000000000 + 1000000000;
    const bigu = 2000000000 + 1000000000;
    const bigu64 = (1 << 63) + 7;
    const negi64 = 0 - 3000000000;
    const ci8: i8 = @intCast(i8, -128);
    const cu64: u64 = @as(u64, 18446744073709551615);
    var a1: [4 * 8]u8 = undefined;
    const M = 10 - 3;
    var a2: [M]u8 = undefined;
    const en: i32 = @enumToInt(E8.A);
    const take1: i32 = takeU8(@as(u8, 200));
    const take2: i32 = takeOptU8(@as(u8, 200));
    const ret1: u8 = retU8();
    if (imin != @as(i64, -9223372036854775808)) { @panic("imin"); }
    if (lu8 != 255) { @panic("lu8"); }
    if (li8 != -128) { @panic("li8"); }
    if (lu32 != 3000000000) { @panic("lu32"); }
    if (bigu != 3000000000) { @panic("bigu"); }
    if (bigu64 != 9223372036854775815) { @panic("bigu64"); }
    if (negi64 != @as(i64, 0 - 3000000000)) { @panic("negi64"); }
    if (ci8 != -128) { @panic("ci8"); }
    if (cu64 != 18446744073709551615) { @panic("cu64"); }
    if (a1.len != 32) { @panic("a1"); }
    if (a2.len != 7) { @panic("a2"); }
    if (en != 255) { @panic("en"); }
    if (MU8 != 150) { @panic("MU8"); }
    if (take1 != 200) { @panic("take1"); }
    if (take2 != 200) { @panic("take2"); }
    if (ret1 != 200) { @panic("ret1"); }
    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ imin, lu8, li8, lu32, bigu, bigu64, negi64, ci8, cu64, a1.len, a2.len, en, take1, ret1 });
    std.io.print("{} {}\n", .{ MU8, take1 + take2 + @intCast(i32, ret1) });
}
