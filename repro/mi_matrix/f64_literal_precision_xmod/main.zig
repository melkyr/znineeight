// f64_literal_precision_xmod — Plan C Task 2b-I RED pin (the I half of the
// Task 2b I/F pair, operator ruling m1703) for the f64-literal precision
// limitation found in Plan C Task 2.
//
// TRIGGER. An f64 literal whose value needs more than ~6 significant digits,
// compared against the same value computed at runtime:
//
//     var lit: f64 = 0.3333333333333333;   // 16 sig digits
//     var third: f64 = 1.0 / 3.0;          // same value, computed at runtime
//
// RED today (fixed point ab7187cc988e39dc5907b95ccc182f9f): the literal emits
// at ~6 significant digits — `(double)(3.33333e-1)` — so `lit` is 0.333333,
// `lit - (1.0/3.0)` is ~3.33e-7, and the `ck` assert traps (SIGTRAP, rc 133).
// The emitted C is gcc-clean, so the corpus `-ffast` dump+gcc classifier
// buckets this dir OK; the RED is RUNTIME-only.
//
// WORKAROUND (used by `sf/src/std_parse.zig`): `parseFloat`'s overflow guard
// uses the `value != 0.0 and value * 2.0 == value` (inf) test instead of an
// f64-max literal, because `1.7976931348623157e308` emits as `(double)(1.79769)`.
//
// RED -> GREEN contract (Task 2b-F). The f64 literal emits with enough
// significant digits; this program runs and prints exactly `f64 lit ok` with
// exit code 0. The committed goldens (`expected.txt`/`expected.rc`) encode this
// DESIRED GREEN behaviour, so this pin is RED until Task 2b-F.
//
// This is a compiler-graph pin only: no `sf/src` change here, and the fixed
// point stays UNMOVED at ab7187cc988e39dc5907b95ccc182f9f.
const std = @import("std");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    // Needs 16 significant digits; today emits as `(double)(3.33333e-1)`.
    var lit: f64 = 0.3333333333333333;
    // The same value, computed at runtime.
    var third: f64 = 1.0 / 3.0;
    var d: f64 = lit - third;
    if (d < 0.0) d = -d;
    ck(d < 1e-15, "f64 literal carries full precision");

    if (g_fail == 0) {
        std.io.write("f64 lit ok\n");
    } else {
        std.io.write("f64 lit FAIL\n");
    }
}
