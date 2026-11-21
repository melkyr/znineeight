// stdlib_ptrarray_for_ok_xmod — FI (operator ruling A) positive runtime fixture
// for `for` iteration over a pointer-to-array (`*[N]T`):
//
//   for (p[0..1]) |v|        the FH-probe shape (pre-FH ran sum=42; the
//                            adopted *[0]T/*[1]T slice types made it error[20]
//                            until FI);
//   for (p[0..0]) |v|        zero iterations (also `p[1..1]`);
//   for (pa) |v|             direct pointer-to-array iteration (Zig 0.15.2
//                            accepts `for` over `*[N]T`);
//   for (pa, 0..3) |v, i|    explicit index range over the pointer-to-array;
//   for (pa, 1..) |v, i|     open range (indices start + j, no clamping);
//   for (cpa) |v|            `*const [N]T` iterable;
//   for (pa[0..2], 0..2)     pointer-to-array slice iterable;
//   for (p00) |v|            `*[0]T` (zero-length) iterable;
//   for (pma) |row|          row-by-value over a pointer to a 2-D array;
//   continue/break           inside a pointer-to-array index range.
//
// Contract: stdout `42 0 0 60 63 66 60 31 0 14 40 10\n`, rc 0, byte-exact 3x
// and byte-identical to the Zig-0.15.2 `std.debug.print` twin (comparison
// only). Every observation is `@panic`-guarded.
const std = @import("std");

pub fn main() void {
    // (1) the FH probe shape: `for (p[0..1]) |v|`.
    var x: i32 = 42;
    const p: *i32 = &x;
    var sum: i32 = 0;
    for (p[0..1]) |v| { sum += v; }
    if (sum != 42) {
        @panic("p[0..1] iteration failed");
    }

    // (2) zero-iteration shapes over the zero-length `*[0]T` slices.
    var z0: i32 = 0;
    for (p[0..0]) |v| { z0 += v + 1; }
    var z1: i32 = 0;
    for (p[1..1]) |v| { z1 += v + 1; }
    if (z0 != 0 or z1 != 0) {
        @panic("zero-length pointer-to-array slice iterated");
    }

    // (3) direct pointer-to-array iteration.
    var arr: [3]i32 = [3]i32{ 10, 20, 30 };
    const pa: *[3]i32 = &arr;
    var s1: i32 = 0;
    for (pa) |v| { s1 += v; }
    if (s1 != 60) {
        @panic("direct pointer-to-array iteration failed");
    }

    // (4) explicit index range over the pointer-to-array.
    var s2: i32 = 0;
    for (pa, 0..3) |v, i| { s2 += v + @intCast(i32, i); }
    var s3: i32 = 0;
    for (pa, 1..) |v, i| { s3 += v + @intCast(i32, i); }
    if (s2 != 63 or s3 != 66) {
        @panic("pointer-to-array index range failed");
    }

    // (5) `*const [N]T`, pointer-to-array slice and `*[0]T` iterables.
    const cpa: *const [3]i32 = &arr;
    var s4: i32 = 0;
    for (cpa) |v| { s4 += v; }
    var s5: i32 = 0;
    for (pa[0..2], 0..2) |v, i| { s5 += v + @intCast(i32, i); }
    const p00 = pa[0..0];
    var s6: i32 = 0;
    for (p00) |v| { s6 += v + 7; }
    if (s4 != 60 or s5 != 31 or s6 != 0) {
        @panic("qualified/slice pointer-to-array iterable failed");
    }

    // (6) row-by-value over a pointer to a 2-D array (real Zig `for |row|`
    // copies the row; the lowerer emits the byte-wise element copy).
    var marr: [2][3]i32 = undefined;
    marr[0][0] = 1;
    marr[0][1] = 2;
    marr[0][2] = 3;
    marr[1][0] = 4;
    marr[1][1] = 5;
    marr[1][2] = 6;
    const pma: *[2][3]i32 = &marr;
    var s7: i32 = 0;
    for (pma) |row| { s7 += row[0] + row[2]; }
    if (s7 != 14) {
        @panic("row-by-value pointer-to-array iteration failed");
    }

    // (7) continue/break inside pointer-to-array index ranges.
    var s8: i32 = 0;
    for (pa, 1..) |v, i| { if (i == 2) { continue; } s8 += v; }
    var s9: i32 = 0;
    for (pa, 0..3) |v, i| { if (i == 1) { break; } s9 += v; }
    if (s8 != 40 or s9 != 10) {
        @panic("pointer-to-array loop control failed");
    }

    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {}\n", .{ sum, z0, z1, s1, s2, s3, s4, s5, s6, s7, s8, s9 });
}
