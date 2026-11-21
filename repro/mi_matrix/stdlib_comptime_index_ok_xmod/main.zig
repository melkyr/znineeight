// stdlib_comptime_index_ok_xmod — Task 17 (F) positive runtime control (no
// over-rejection).
//
// The compile-time bounds check must reject ONLY provably out-of-bounds
// comptime-known indexes / slice ranges. Every read below is legal Zig and
// must keep compiling and running:
//   * in-range comptime-known indexes: a literal, `scores.len - 1` (constant
//     arithmetic over `.len` is NOT folded by the check, so it stays on the
//     runtime path), a typed `const`, a `*[5]i32` pointer, and a struct array
//     field (`st.arr[2]`);
//   * a runtime index (`var ri: usize = 2`), which under `-fsafe` keeps the
//     A5F `check_trap{kind=5}` guard and runs it (in range: no trap);
//   * every legal slice-range boundary: `[0..5]`, `[5..]`, `[5..5]`, `[1..3]`
//     (plus an element read of the result), a struct field `[0..3]`, a
//     pointer-to-array `[1..4]`, and the Task 17 fix-round runtime-END control
//     `scores[1..re]` (re runtime) whose start is comptime-known and in range.
//
// Contract: stdout `50 50 40 10 3 30 5 0 0 2 3 3 3\n`, rc 0, byte-exact 3x,
// Zig-0.15.2-twin-matched.
const std = @import("std");

const S = struct { arr: [3]i32 };

pub fn main() void {
    var scores: [5]i32 = .{ 10, 20, 30, 40, 50 };
    var p: *[5]i32 = &scores;
    var st: S = S{ .arr = [_]i32{ 1, 2, 3 } };

    var a: i32 = scores[4];
    if (a != 50) {
        @panic("comptime_index_ok: scores[4]");
    }
    var b: i32 = scores[scores.len - 1];
    if (b != 50) {
        @panic("comptime_index_ok: scores[len - 1]");
    }
    const ci: u32 = 3;
    var c: i32 = scores[ci];
    if (c != 40) {
        @panic("comptime_index_ok: scores[ci]");
    }
    var d: i32 = p[0];
    if (d != 10) {
        @panic("comptime_index_ok: p[0]");
    }
    var e: i32 = st.arr[2];
    if (e != 3) {
        @panic("comptime_index_ok: st.arr[2]");
    }

    var ri: usize = 2;
    var f: i32 = scores[ri];
    if (f != 30) {
        @panic("comptime_index_ok: runtime index");
    }

    var s0: []i32 = scores[0..5];
    if (s0.len != 5) {
        @panic("comptime_index_ok: [0..5]");
    }
    var s1: []i32 = scores[5..];
    if (s1.len != 0) {
        @panic("comptime_index_ok: [5..]");
    }
    var s2: []i32 = scores[5..5];
    if (s2.len != 0) {
        @panic("comptime_index_ok: [5..5]");
    }
    var s3: []i32 = scores[1..3];
    if (s3.len != 2) {
        @panic("comptime_index_ok: [1..3] len");
    }
    if (s3[0] != 20) {
        @panic("comptime_index_ok: [1..3][0]");
    }
    var s4: []i32 = st.arr[0..3];
    if (s4.len != 3) {
        @panic("comptime_index_ok: field [0..3]");
    }
    var s5: []i32 = p[1..4];
    if (s5.len != 3) {
        @panic("comptime_index_ok: ptr [1..4]");
    }

    // Task 17 fix round (review Important 1): a CLOSED range whose end is
    // RUNTIME must not be bound-checked against the start (there is no comptime
    // end); the runtime result is the ordinary `end - start`.
    var re: usize = 4;
    var s6: []i32 = scores[1..re];
    if (s6.len != 3) {
        @panic("comptime_index_ok: runtime-end [1..re]");
    }
    if (s6[0] != 20) {
        @panic("comptime_index_ok: runtime-end [1..re][0]");
    }

    std.io.printInt(a);
    std.io.writeByte(' ');
    std.io.printInt(b);
    std.io.writeByte(' ');
    std.io.printInt(c);
    std.io.writeByte(' ');
    std.io.printInt(d);
    std.io.writeByte(' ');
    std.io.printInt(e);
    std.io.writeByte(' ');
    std.io.printInt(f);
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s0.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s1.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s2.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s3.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s4.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s5.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s6.len));
    std.io.writeByte('\n');
}
