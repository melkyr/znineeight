// stdlib_for_index_range_xmod — Task 11 (Part II) positive runtime fixture for
// Zig 0.15.2's explicit index-range form:
//
//   for (iterable, start..)   |item, index| ...   // open end
//   for (iterable, start..end) |item, index| ...  // explicit end
//
// Zig semantics (oracle-checked, Zig 0.15.2):
//   * the index capture values are `start + j` (j = the 0-based iteration
//     count), NOT clamped to the iterable's bounds — `start..` walks every
//     element even when `start > len`;
//   * the iteration count is the iterable's length; `start..end` additionally
//     requires `end - start == len` (Zig compile error when known, runtime
//     trap under -fsafe otherwise) and `end < start` overflows the length
//     computation (trap);
//   * an empty iterable with the empty range `0..0` iterates zero times.
//
// This fixture pins only VALID ranges (the stdlib gate builds with -ffast, so
// the safety-mode length check is compiled out; the reject fixture
// `for_index_range_reject_xmod` pins the comptime-known rejects and the
// standalone `repro/for_index_range.z98` + probes cover the -fsafe traps).
//
// Covers: fixed-array and slice iterables; runtime and literal bounds; open
// `..` and explicit `..end`; start > len; literal offset; empty slice;
// `continue`/`break` in the new form; the `for (arr) |x, i|` and
// `for (0..n) |i|` controls. Every aggregate is `@panic`-guarded. Contract:
// stdout `60 2 6 5 60 7 11 60 1 5 60 10 60 10 60 25 0 34 3 70 6\n`, rc 0,
// byte-exact 3x, Zig-0.15.2-twin-matched.
const std = @import("std");

pub fn main() void {
    var arr: [5]u32 = [5]u32{ 10, 11, 12, 13, 14 };
    var s: []u32 = arr[0..5];
    var r1: u32 = 0; var r2: u32 = 0; var r3: u32 = 0; var r4: u32 = 0;
    var r5: u32 = 0; var r6: u32 = 0; var r7: u32 = 0; var r8: u32 = 0;
    var r9: u32 = 0; var r10: u32 = 0; var r11: u32 = 0; var r12: u32 = 0;
    var r13: u32 = 0; var r14: u32 = 0; var r15: u32 = 0; var r16: u32 = 0;
    var r17: u32 = 0; var r18: u32 = 0; var r19: u32 = 0; var r20: u32 = 0;
    var r21: u32 = 0;

    // (1) open end, runtime start: index values start..start+len-1 over all
    // elements.
    var start1: usize = 2;
    var sum1: u32 = 0;
    var n1: u32 = 0;
    var first1: usize = 999;
    var last1: usize = 999;
    for (arr, start1..) |x, i| {
        sum1 += x;
        n1 += 1;
        if (first1 == 999) {
            first1 = i;
        }
        last1 = i;
    }
    if (sum1 != 60 or n1 != 5 or first1 != 2 or last1 != 6) {
        @panic("open-end runtime-start array guard failed");
    }
    r1 = sum1; r2 = @intCast(u32, first1); r3 = @intCast(u32, last1); r4 = n1;

    // (2) open end with start > len: still every element, indices continue
    // past the length (no clamping).
    start1 = 7;
    sum1 = 0;
    n1 = 0;
    first1 = 999;
    last1 = 999;
    for (arr, start1..) |x, i| {
        sum1 += x;
        n1 += 1;
        if (first1 == 999) {
            first1 = i;
        }
        last1 = i;
    }
    if (sum1 != 60 or n1 != 5 or first1 != 7 or last1 != 11) {
        @panic("open-end start-greater-than-len guard failed");
    }
    r5 = sum1; r6 = @intCast(u32, first1); r7 = @intCast(u32, last1);

    // (3) explicit end over a slice, runtime bounds: span == len.
    var start2: usize = 1;
    var end2: usize = 6;
    var sum2: u32 = 0;
    var first2: usize = 999;
    var last2: usize = 999;
    for (s, start2..end2) |x, i| {
        sum2 += x;
        if (first2 == 999) {
            first2 = i;
        }
        last2 = i;
    }
    if (sum2 != 60 or first2 != 1 or last2 != 5) {
        @panic("explicit-end runtime-bounds slice guard failed");
    }
    r8 = sum2; r9 = @intCast(u32, first2); r10 = @intCast(u32, last2);

    // (4) literal open end `0..` (comptime fold path) over a fixed array.
    var sum3: u32 = 0;
    var idx3: usize = 0;
    for (arr, 0..) |x, i| {
        sum3 += x;
        idx3 += i;
    }
    if (sum3 != 60 or idx3 != 10) {
        @panic("literal open-end guard failed");
    }
    r11 = sum3; r12 = @intCast(u32, idx3);

    // (5) literal full range `0..5` (comptime span == length check).
    sum3 = 0;
    idx3 = 0;
    for (arr, 0..5) |x, i| {
        sum3 += x;
        idx3 += i;
    }
    if (sum3 != 60 or idx3 != 10) {
        @panic("literal full-range guard failed");
    }
    r13 = sum3; r14 = @intCast(u32, idx3);

    // (6) literal offset range `3..8`: same elements, indices offset by 3.
    sum3 = 0;
    idx3 = 0;
    for (arr, 3..8) |x, i| {
        sum3 += x;
        idx3 += i;
    }
    if (sum3 != 60 or idx3 != 25) {
        @panic("literal offset-range guard failed");
    }
    r15 = sum3; r16 = @intCast(u32, idx3);

    // (7) empty slice with the empty range `0..0`: zero iterations.
    var se: []u32 = arr[0..0];
    var sum4: u32 = 0;
    for (se, 0..0) |x, i| {
        sum4 += x + @intCast(u32, i);
    }
    if (sum4 != 0) {
        @panic("empty-range guard failed");
    }
    r17 = sum4;

    // (8) `continue`/`break` in the new form (the step must still advance).
    var sum5: u32 = 0;
    var seen5: u32 = 0;
    start1 = 2;
    for (arr, start1..) |x, i| {
        _ = i;
        if (x == 12) {
            continue;
        }
        if (x == 14) {
            break;
        }
        seen5 += 1;
        sum5 += x;
    }
    if (sum5 != 34 or seen5 != 3) {
        @panic("continue/break guard failed");
    }
    r18 = sum5; r19 = seen5;

    // (9) control: the existing Z98 `for (arr) |x, i|` index capture.
    var m: u32 = 0;
    for (arr) |x, i| {
        m += x + @intCast(u32, i);
    }
    if (m != 70) {
        @panic("plain index-capture control failed");
    }
    r20 = m;

    // (10) control: the existing `for (0..n) |i|` range form.
    var k: u32 = 0;
    for (0..4) |i| {
        k += @intCast(u32, i);
    }
    if (k != 6) {
        @panic("range control failed");
    }
    r21 = k;

    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21 });
}
