// stdlib_for_continue_xmod — Task 10B positive runtime fixture (defect A): a
// `continue` in a `for` loop must run the loop's implicit step before the next
// condition test (mirroring Zig 0.15.2 / spec §3.2). Pre-fix, `continue`
// jumped straight to the condition, so the range/index never advanced and the
// loop hung (silent miscompile: emit/build rc 0, no diagnostic).
//
// Covers (stdlib pin 215 -> 216):
//   * range `for (0..N)` + `continue` (step must run: all N iterations happen)
//   * fixed-array and slice iterables + `continue` (index step must advance)
//   * `for |x, i|` index capture + `continue`
//   * nested `for` with an inner `continue` (inner step only)
//   * `continue` inside a nested `if`/`else` in the body
//   * a body side effect before `continue` (effects persist; count still runs)
//   * a body whose only statement is `continue` (always-continue: the step
//     block must still be emitted, else the loop never advances)
//   * `defer` + `continue` (the defer runs before the step, once per iteration)
// Controls that must stay unchanged:
//   * `break` in a `for`
//   * `continue` in a plain `while` and in `while (c) : (step)`
//
// Every aggregate is `@panic`-guarded. Contract: stdout
// `8 5 70 80 5 6 103 5 4 3 4 6 5 5\n`, rc 0, byte-exact 3x.
const std = @import("std");

pub fn main() void {
    var range_sum: u32 = 0;
    var range_iters: u32 = 0;
    for (0..5) |n| {
        range_iters += 1;
        if (n == 2) continue;
        range_sum += n;
    }
    if (range_iters != 5 or range_sum != 8) {
        @panic("range continue guard failed");
    }

    var arr: [4]i32 = [4]i32{ 10, 20, 30, 40 };
    var arr_sum: i32 = 0;
    for (arr) |x| {
        if (x == 30) continue;
        arr_sum += x;
    }
    if (arr_sum != 70) {
        @panic("array continue guard failed");
    }

    var arr2: [4]i32 = [4]i32{ 10, 20, 30, 40 };
    var sl: []i32 = arr2[0..4];
    var sl_sum: i32 = 0;
    for (sl) |x| {
        if (x == 20) continue;
        sl_sum += x;
    }
    if (sl_sum != 80) {
        @panic("slice continue guard failed");
    }

    var idx_sum: u32 = 0;
    for (arr) |x, i| {
        _ = x;
        if (i == 1) continue;
        idx_sum += i;
    }
    if (idx_sum != 5) {
        @panic("index capture continue guard failed");
    }

    var nested: u32 = 0;
    for (0..3) |i| {
        _ = i;
        for (0..3) |j| {
            if (j == 1) continue;
            nested += 1;
        }
    }
    if (nested != 6) {
        @panic("nested for continue guard failed");
    }

    var kept: u32 = 0;
    for (0..6) |n| {
        if (n % 2 == 0) {
            if (n != 0) {
                continue;
            } else {
                kept += 100;
            }
        } else {
            kept += 1;
        }
    }
    if (kept != 103) {
        @panic("nested if continue guard failed");
    }

    var side: u32 = 0;
    var count: u32 = 0;
    for (0..5) |n| {
        side += 1;
        if (n == 2) continue;
        count += 1;
    }
    if (side != 5 or count != 4) {
        @panic("side effect before continue guard failed");
    }

    var never: u32 = 0;
    for (0..3) |n| {
        _ = n;
        never += 1;
        continue;
    }
    if (never != 3) {
        @panic("always-continue step guard failed");
    }

    var defers: u32 = 0;
    for (arr2) |x, i| {
        _ = x;
        _ = i;
        defer defers += 1;
        if (i == 1) continue;
    }
    if (defers != 4) {
        @panic("defer continue guard failed");
    }

    var found: u32 = 0;
    for (0..10) |n| {
        if (n == 7) break;
        found = n;
    }
    if (found != 6) {
        @panic("break in for guard failed");
    }

    var w: u32 = 0;
    var odds: u32 = 0;
    while (w < 10) {
        if (w % 2 == 1) {
            w += 1;
            continue;
        }
        odds += 1;
        w += 1;
    }
    if (odds != 5) {
        @panic("plain while continue guard failed");
    }

    var s: u32 = 0;
    var evens: u32 = 0;
    while (s < 10) : (s += 1) {
        if (s % 2 == 1) continue;
        evens += 1;
    }
    if (evens != 5) {
        @panic("while step continue guard failed");
    }

    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ range_sum, range_iters, arr_sum, sl_sum, idx_sum, nested, kept, side, count, never, defers, found, odds, evens });
}
