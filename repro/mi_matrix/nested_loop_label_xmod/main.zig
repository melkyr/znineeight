// nested_loop_label_xmod — Task 10B positive runtime fixture (defect B): an
// unlabeled nested loop must NOT inherit the enclosing labeled loop's label.
// Pre-fix, `current_label` leaked into nested unlabeled loops, so a labeled
// `break`/`continue` matched the INNER loop first (silent wrong result, or a
// hang when combined with the for-`continue` step defect). Post-fix, labeled
// transfers target the loop that actually carries the label, matching Zig
// 0.15.2. Unlabeled transfers still target the innermost loop.
//
// Covers (both loop kinds, both transfer kinds, and labeled blocks):
//   * `outer: while` + inner unlabeled `while` + `continue :outer` (p14)
//   * `outer: while` + inner unlabeled `while` + `break :outer`    (p15)
//   * `outer: for`   + inner unlabeled `for`   + `continue :outer` (p16)
//   * `outer: for`   + inner unlabeled `for`   + `break :outer`    (p17)
//   * `blk:` labeled block + inner unlabeled `while` + `break :blk`
//   * `outer: for`   + inner unlabeled `while` + `break :outer` (mixed kinds)
//   * `outer: while` + inner unlabeled `for`   + `continue :outer` (mixed)
//   * nested labeled loops: an inner label must win for its own transfers
//   * a plain nested unlabeled pair: unlabeled `break`/`continue` still target
//     the innermost loop
//
// Every aggregate is `@panic`-guarded. Contract: stdout
// `6 3 3 1 3 6 2 3 2 6 2 6 3 7 3 7 3 6 4 3 103\n`, rc 0, byte-exact 3x.
const std = @import("std");

pub fn main() void {
    var c1: u32 = 0;
    var i1: u32 = 0;
    outer1: while (i1 < 3) : (i1 += 1) {
        var j1: u32 = 0;
        while (j1 < 3) : (j1 += 1) {
            if (i1 == 1 and j1 == 0) continue :outer1;
            c1 += 1;
        }
    }
    if (i1 != 3 or c1 != 6) {
        @panic("while continue :outer guard failed");
    }

    var l2: u32 = 0;
    var i2: u32 = 0;
    outer2: while (i2 < 3) : (i2 += 1) {
        var j2: u32 = 0;
        while (j2 < 3) : (j2 += 1) {
            if (i2 == 1 and j2 == 0) break :outer2;
            l2 += 1;
        }
    }
    if (i2 != 1 or l2 != 3) {
        @panic("while break :outer guard failed");
    }

    var it3: u32 = 0;
    var ct3: u32 = 0;
    outer3: for (0..3) |i3| {
        it3 += 1;
        for (0..3) |j3| {
            if (i3 == 1 and j3 == 0) continue :outer3;
            ct3 += 1;
        }
    }
    if (it3 != 3 or ct3 != 6) {
        @panic("for continue :outer guard failed");
    }

    var it4: u32 = 0;
    var lg4: u32 = 0;
    outer4: for (0..3) |i4| {
        it4 += 1;
        for (0..3) |j4| {
            if (i4 == 1 and j4 == 0) break :outer4;
            lg4 += 1;
        }
    }
    if (it4 != 2 or lg4 != 3) {
        @panic("for break :outer guard failed");
    }

    var blk5: u32 = 0;
    blk: {
        var i5: u32 = 0;
        while (i5 < 5) : (i5 += 1) {
            if (i5 == 2) break :blk;
            blk5 += 1;
        }
        blk5 += 100;
    }
    if (blk5 != 2) {
        @panic("labeled block break :blk guard failed");
    }

    var c6: u32 = 0;
    var g6: u32 = 0;
    outer6: for (0..5) |i6| {
        var j6: u32 = 0;
        while (j6 < 3) : (j6 += 1) {
            if (i6 == 2 and j6 == 0) break :outer6;
            c6 += 1;
        }
        g6 += 1;
    }
    if (c6 != 6 or g6 != 2) {
        @panic("for + while break :outer guard failed");
    }

    var c7: u32 = 0;
    var i7: u32 = 0;
    outer7: while (i7 < 3) : (i7 += 1) {
        for (0..3) |j7| {
            if (i7 == 1 and j7 == 0) continue :outer7;
            c7 += 1;
        }
    }
    if (i7 != 3 or c7 != 6) {
        @panic("while + for continue :outer guard failed");
    }

    var c8: u32 = 0;
    var i8: u32 = 0;
    outer8: while (i8 < 3) : (i8 += 1) {
        inner8: for (0..3) |j8| {
            if (i8 == 99 and j8 == 0) break :inner8;
            if (i8 == 1 and j8 == 1) continue :outer8;
            c8 += 1;
        }
    }
    if (i8 != 3 or c8 != 7) {
        @panic("nested labeled while/for guard failed");
    }

    var l9: u32 = 0;
    var h9: u32 = 0;
    outer9: for (0..3) |i9| {
        var j9: u32 = 0;
        inner9: while (j9 < 4) : (j9 += 1) {
            if (i9 == 99 and j9 == 0) continue :outer9;
            if (j9 == 1) continue :inner9;
            if (i9 == 1 and j9 == 2) break :inner9;
            l9 += 1;
        }
        h9 += 1;
    }
    if (l9 != 7 or h9 != 3) {
        @panic("nested labeled for/while guard failed");
    }

    var t10: u32 = 0;
    for (0..3) |_| {
        var j10: u32 = 0;
        while (j10 < 4) : (j10 += 1) {
            if (j10 == 1) continue;
            if (j10 == 3) break;
            t10 += 1;
        }
    }
    if (t10 != 6) {
        @panic("plain nested control guard failed");
    }

    var t12: u32 = 0;
    outer12: for (0..3) |i12| {
        mid12: for (0..3) |j12| {
            if (i12 == 99 and j12 == 0) continue :mid12;
            if (i12 == 1 and j12 == 1) break :outer12;
            t12 += 1;
        }
    }
    if (t12 != 4) {
        @panic("double nesting break :outer guard failed");
    }

    var t13: u32 = 0;
    lbl13: for (0..4) |i13| {
        if (i13 == 1) continue :lbl13;
        t13 += 1;
    }
    if (t13 != 3) {
        @panic("labeled innermost for continue guard failed");
    }

    var t14: u32 = 0;
    blk14: {
        for (0..4) |i14| {
            if (i14 == 2) continue;
            t14 += 1;
        }
        t14 += 100;
        break :blk14;
    }
    if (t14 != 103) {
        @panic("labeled block + unlabeled for continue guard failed");
    }

    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ c1, i1, l2, i2, it3, ct3, it4, lg4, blk5, c6, g6, c7, i7, c8, i8, l9, h9, t10, t12, t13, t14 });
}
