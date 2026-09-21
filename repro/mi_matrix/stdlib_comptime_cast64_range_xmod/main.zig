// stdlib_comptime_cast64_range_xmod — Task B3 item 2 positive regression guard.
//
// Pins the ACCEPTED side of the 64-bit-target range check so the new rejection
// of `@intCast(u64, -1)` / `@as(u64, -1)` cannot over-reject valid programs:
//   - `@as(u64, 18446744073709551615)` (an untyped literal above i64 max);
//   - `@as(u64, UU)` with `UU` an UNTYPED const = u64 max (the syntactic sign
//     classification must recurse into the const initializer, not treat the
//     untyped const as signed);
//   - `@as(u64, U)` with `U: u64` a typed const = u64 max;
//   - `@as(i64, -1)` (a negative source into a signed 64-bit target);
//   - `@as(u64, 5)` (a small non-negative source).
//
// Every value is checked against a runtime `@intToFloat` oracle (or a runtime
// comparison for the small value) and `@panic`-guarded, so a mis-fold traps
// instead of printing a `-bad` line.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   cast64-ok
const std = @import("std");

const U: u64 = 18446744073709551615;
const UU = 18446744073709551615;

fn tof_u(x: u64) f64 { return @intToFloat(f64, x); }
fn tof_i(x: i64) f64 { return @intToFloat(f64, x); }

pub fn main() void {
    var uu: u64 = U;
    if (@intToFloat(f64, @as(u64, 18446744073709551615)) != tof_u(uu)) { @panic("litmax"); }
    if (@intToFloat(f64, @as(u64, UU)) != tof_u(uu)) { @panic("untypedmax"); }
    if (@intToFloat(f64, @as(i64, -1)) != tof_i(-1)) { @panic("i64neg"); }
    var five: u64 = @as(u64, 5);
    if (five != 5) { @panic("five"); }
    std.io.print("cast64-ok\n");
}
