// stdlib_intcast_range_xmod — Task 11S positive regression guard.
//
// Pins the ACCEPTED side of the three Task 11S range/length gates, so the new
// rejections cannot over-reject valid programs:
//   - `[@intCast(u8, 200)]` / `[@intCast(u16, 1000)]` array sizes (in-range
//     narrow targets);
//   - a function-local `const N = 7` operand (`[@intCast(u32, N)]`) — this is
//     why the array-size arm must fold the operand with the U32 evaluator;
//   - `@intCast(u8, 200)` and `@intCast(i32, -1)` comptime values (the second
//     pins a signed negative that fits);
//   - `.len` on an array and a slice (must stay accepted, unlike `[*]T`);
//   - `for (0..sl.len)` (the range-end `.len` shape).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   narrow-u8-ok
//   narrow-u16-ok
//   local-const-ok
//   comptime-in-range-ok
//   signed-negative-ok
//   array-len-ok
//   slice-len-ok
//   range-len-ok
//   done
const std = @import("std");

var g_a: [@intCast(u8, 200)]u8 = undefined;
var g_b: [@intCast(u16, 1000)]u8 = undefined;

pub fn main() void {
    var arr: [4]u8 = undefined;
    var sl: []u8 = arr[0..];
    const N = 7;
    var local: [@intCast(u32, N)]u8 = undefined;
    const Y = @intCast(u8, 200);
    const Z = @intCast(i32, -1);

    if (g_a.len == 200) { std.io.print("narrow-u8-ok\n"); } else { std.io.print("narrow-u8-bad\n"); }
    if (g_b.len == 1000) { std.io.print("narrow-u16-ok\n"); } else { std.io.print("narrow-u16-bad\n"); }
    if (local.len == 7) { std.io.print("local-const-ok\n"); } else { std.io.print("local-const-bad\n"); }
    if (Y == 200) { std.io.print("comptime-in-range-ok\n"); } else { std.io.print("comptime-in-range-bad\n"); }
    if (Z == -1) { std.io.print("signed-negative-ok\n"); } else { std.io.print("signed-negative-bad\n"); }
    if (arr.len == 4) { std.io.print("array-len-ok\n"); } else { std.io.print("array-len-bad\n"); }
    if (sl.len == 4) { std.io.print("slice-len-ok\n"); } else { std.io.print("slice-len-bad\n"); }

    var c: u32 = 0;
    for (0..sl.len) |i| { _ = i; c += 1; }
    if (c == 4) { std.io.print("range-len-ok\n"); } else { std.io.print("range-len-bad\n"); }

    std.io.print("done\n");
}
