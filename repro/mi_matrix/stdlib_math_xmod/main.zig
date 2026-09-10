// stdlib_math_xmod — STDLIB std_math scalar helpers GREEN fixture.
//
// std_math.zig is a PURE (no externs, no cstdio) Z98 module re-exported from
// std.zig as `math`; this fixture imports it via a BARE `@import("std")` and
// exercises every public function: min / max / minU / maxU / abs / clamp /
// clampU / isPowerOfTwoU32 / alignUp / alignDown.
//
// SHIPPED COMPILER FEATURES pinned alongside the module:
//   - u32 integer width with TRUE unsigned semantics: `all1 = ~all1` is all
//     32 bits set (4294967295). clampU(all1, 0, 100) must return 100 and
//     `all1 > 100` must be true — if the u32 were ever compared as i32
//     (-1) these two lines would print 0, so they discriminate signed vs
//     unsigned comparison (the whole point of the minU/maxU/clampU family).
//   - bitwise not / and / shift on u32, 32-bit two's-complement i32 negative
//     literal handling in printInt (line "-5")
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0), one
// result per line (std.io.printInt + '\n'):
//   3       min(3, 7)
//   -5      min(-5, 2)
//   7       max(3, 7)
//   2       max(-5, 2)
//   2       minU(9, 2)
//   0       minU(0, all1)
//   9       maxU(9, 2)
//   1       maxU(5, all1) == all1  (all1 = 0xFFFFFFFF)
//   5       abs(-5)
//   5       abs(5)
//   10      clamp(50, 0, 10)
//   0       clamp(-3, 0, 10)
//   7       clamp(7, 0, 10)
//   8       clampU(3, 8, 20)
//   20      clampU(25, 8, 20)
//   15      clampU(15, 8, 20)
//   100     clampU(0xFFFFFFFF, 0, 100)  [unsigned-comparison discriminator]
//   1       0xFFFFFFFF > 100            [unsigned-comparison discriminator]
//   1       isPowerOfTwoU32(16)
//   0       isPowerOfTwoU32(3)
//   0       isPowerOfTwoU32(0)
//   1       isPowerOfTwoU32(1)
//   16      alignUp(13, 8)
//   16      alignUp(16, 8)
//   0       alignUp(0, 8)
//   8       alignDown(13, 8)
//   16      alignDown(16, 8)
const std = @import("std");

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn pb(cond: bool) void {
    if (cond) {
        p(1);
    } else {
        p(0);
    }
}

pub fn main() void {
    var all1: u32 = 0;
    all1 = ~all1;

    p(std.math.min(@intCast(i32, 3), @intCast(i32, 7)));
    p(std.math.min(@intCast(i32, -5), @intCast(i32, 2)));
    p(std.math.max(@intCast(i32, 3), @intCast(i32, 7)));
    p(std.math.max(@intCast(i32, -5), @intCast(i32, 2)));

    p(@intCast(i32, std.math.minU(@intCast(u32, 9), @intCast(u32, 2))));
    p(@intCast(i32, std.math.minU(@intCast(u32, 0), all1)));
    p(@intCast(i32, std.math.maxU(@intCast(u32, 9), @intCast(u32, 2))));
    pb(std.math.maxU(@intCast(u32, 5), all1) == all1);

    p(std.math.abs(@intCast(i32, -5)));
    p(std.math.abs(@intCast(i32, 5)));

    p(std.math.clamp(@intCast(i32, 50), @intCast(i32, 0), @intCast(i32, 10)));
    p(std.math.clamp(@intCast(i32, -3), @intCast(i32, 0), @intCast(i32, 10)));
    p(std.math.clamp(@intCast(i32, 7), @intCast(i32, 0), @intCast(i32, 10)));

    p(@intCast(i32, std.math.clampU(@intCast(u32, 3), @intCast(u32, 8), @intCast(u32, 20))));
    p(@intCast(i32, std.math.clampU(@intCast(u32, 25), @intCast(u32, 8), @intCast(u32, 20))));
    p(@intCast(i32, std.math.clampU(@intCast(u32, 15), @intCast(u32, 8), @intCast(u32, 20))));
    p(@intCast(i32, std.math.clampU(all1, @intCast(u32, 0), @intCast(u32, 100))));
    pb(all1 > @intCast(u32, 100));

    pb(std.math.isPowerOfTwoU32(@intCast(u32, 16)));
    pb(std.math.isPowerOfTwoU32(@intCast(u32, 3)));
    pb(std.math.isPowerOfTwoU32(@intCast(u32, 0)));
    pb(std.math.isPowerOfTwoU32(@intCast(u32, 1)));

    p(@intCast(i32, std.math.alignUp(@intCast(u32, 13), @intCast(u32, 8))));
    p(@intCast(i32, std.math.alignUp(@intCast(u32, 16), @intCast(u32, 8))));
    p(@intCast(i32, std.math.alignUp(@intCast(u32, 0), @intCast(u32, 8))));
    p(@intCast(i32, std.math.alignDown(@intCast(u32, 13), @intCast(u32, 8))));
    p(@intCast(i32, std.math.alignDown(@intCast(u32, 16), @intCast(u32, 8))));
}
