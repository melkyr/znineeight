// stdlib_call_arity_types_ok_xmod — Task 14 (S2) positive runtime control.
//
// The Task 14 call-site enforcement must leave every VALID call form
// unchanged. Covers: exact-arity correct-type direct calls (`add(1, 2)`,
// negative literals); a wider parameter type with a full-width value
// (`scale(i64, i32)`); `@intCast`-based conversions into narrower and
// platform-width parameters (`takeI8(@intCast(i8, n))`,
// `takeUsize(@intCast(usize, u))`); a `bool` parameter and `bool` return; an
// indirect call through a `fn (i32, i32) i32` parameter; the Z98-established
// implicit integer widening (`u8` -> `i32` parameter) that the cross-family
// rule deliberately keeps; and the pointer/array call controls restored by the
// Task 14 fix round (`&arr` (`*[N]T`) -> `[]T` and a same-length `[N]T` ->
// `[N]T` value) whose MISMATCHED shapes must still reject. Every observation is
// `@panic`-guarded.
//
// Contract: stdout `s1=3 s2=0 i8v=100 us=4096 fp=42 s3=8 sl=6 f3=1 neg=1\n`,
// rc 0, byte-exact 3x, Zig-0.15.2-twin-matched.
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn scale(v: i64, f: i32) i64 {
    return v * @intCast(i64, f);
}

fn takeI8(x: i8) i8 {
    return x;
}

fn takeUsize(n: usize) usize {
    return n;
}

fn apply(f: fn (i32, i32) i32, a: i32, b: i32) i32 {
    return f(a, b);
}

fn isNeg(x: i32) bool {
    return x < 0;
}

fn sumSlice(s: []i32) i32 {
    var t: i32 = 0;
    for (s) |v| {
        t = t + v;
    }
    return t;
}

fn firstOf3(a: [3]i32) i32 {
    return a[0];
}

pub fn main() void {
    var s1: i32 = add(1, 2);
    if (s1 != 3) {
        @panic("exact-arity i32 call failed");
    }
    var s2: i32 = add(-5, 5);
    if (s2 != 0) {
        @panic("negative-argument call failed");
    }
    var wide: i64 = 2000000000;
    var sc: i64 = scale(wide, 2);
    if (sc != 4000000000) {
        @panic("i64 parameter call failed");
    }
    var n: i32 = 100;
    var i8v: i8 = takeI8(@intCast(i8, n));
    if (i8v != 100) {
        @panic("intCast i8 argument failed");
    }
    var u: u32 = 4096;
    var us: usize = takeUsize(@intCast(usize, u));
    if (us != 4096) {
        @panic("intCast usize argument failed");
    }
    var fp: i32 = apply(add, 20, 22);
    if (fp != 42) {
        @panic("indirect fn-pointer call failed");
    }
    if (!isNeg(-1) or isNeg(0)) {
        @panic("bool parameter/return failed");
    }
    var small: u8 = 7;
    var s3: i32 = add(small, 1);
    if (s3 != 8) {
        @panic("u8-to-i32 implicit widening call failed");
    }
    var neg_i: i32 = 0;
    if (isNeg(-1)) {
        neg_i = 1;
    }
    // Task 14 fix round: the valid pointer/array decays must keep passing while
    // the mismatched shapes reject (see call_arg_type_reject_xmod).
    var arr3: [3]i32 = [3]i32{ 1, 2, 3 };
    var sl_sum: i32 = sumSlice(&arr3);
    if (sl_sum != 6) {
        @panic("pointer-to-array slice call failed");
    }
    var f3: i32 = firstOf3(arr3);
    if (f3 != 1) {
        @panic("same-length array call failed");
    }
    std.io.print("s1={} s2={} i8v={} us={} fp={} s3={} sl={} f3={} neg={}\n", .{ s1, s2, @intCast(i32, i8v), @intCast(i32, us), fp, s3, sl_sum, f3, neg_i });
}
