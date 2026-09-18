// lexer_float_exponent_xmod — Plan C Task 2b-F RED pin (the I half of the
// lexer-exponent I/F pair) for the f64 exponent-after-decimal-point bug found
// while replacing `gcvt` with the self-contained dtoa.
//
// TRIGGER. A float literal whose mantissa has a decimal point AND a trailing
// exponent:
//
//     var big: f64 = 1.0e300;   // exponent silently dropped: parses as 1.0
//     var small: f64 = 1.5e-3;  // exponent silently dropped: parses as 1.5
//
// ROOT CAUSE (`sf/src/lexer.zig` `parseF64`): the fraction loop advances `i`
// past the `e`/`E` before breaking, so the exponent block at `:643` sees the
// character *after* the `e` and is skipped. Literals without a decimal point
// (`1e300`) decrement `i` first and parse correctly, so the bug is specific to
// a decimal-point mantissa followed by an exponent.
//
// RED today (fixed point b0e7042a26e74d7b744a0a49546149b4): `big` is 1.0 and
// `small` is 1.5, so the asserts trap (SIGTRAP, rc 133). The emitted C is
// gcc-clean, so the corpus `-ffast` dump+gcc classifier buckets this dir OK;
// the RED is RUNTIME-only.
//
// RED -> GREEN contract. The exponent is parsed, so this program runs and
// prints exactly `lexer float exp ok` with exit code 0. The committed goldens
// (`expected.txt`/`expected.rc`) encode this DESIRED GREEN behaviour.
//
// This is a compiler-class fixture (no `stdlib_` prefix), so it is NOT in
// `scripts/stdlib/expected_dirs.txt` and the runtime gate never discovers it;
// run it explicitly.
const std = @import("std");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    // Decimal-point mantissa + exponent. The no-dot reference literal always
    // parsed correctly, so equality pins the fix.
    var big: f64 = 1.0e300;
    var big_ref: f64 = 1e300;
    ck(big == big_ref, "1.0e300 parses with its exponent");

    // Small negative exponent (the reference here is the same literal with no
    // decimal point, which parses correctly).
    var small: f64 = 1.5e-3;
    ck(small > 0.0014 and small < 0.0016, "1.5e-3 parses with its exponent");

    // Exact-integer case: both sides are exactly representable.
    var mid: f64 = 2.5e10;
    var mid_ref: f64 = 25e9;
    ck(mid == mid_ref, "2.5e10 parses with its exponent");

    if (g_fail == 0) {
        std.io.write("lexer float exp ok\n");
    } else {
        std.io.write("lexer float exp FAIL\n");
    }
}
