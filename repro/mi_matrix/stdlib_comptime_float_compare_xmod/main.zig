// stdlib_comptime_float_compare_xmod — Task 9 (Part II) positive runtime
// fixture for comptime float comparison folding.
//
// DEFECT (pre-Task-9). `comptimeEvalCompare` returned null whenever an operand
// was float-valued, so a comptime-true float condition never folded and a
// no-`else` value `if` was rejected (`error[3059]`), while official Zig 0.15.2
// folds it (`var x: i32 = if (0.5 < 1.0) 1;` is accepted there).
//
// FIX (Task 9). `comptimeEvalCompare` keeps the exact integer `ciCmp` path for
// all-integer/bool comparisons and adds `comptimeEvalCompareFloat`: the float
// sub-evaluator supplies each float operand at the established f64 precision
// (a typed `f32` rounds through f32 first), and an integer operand participates
// only when it is exactly representable in the comparison's peer significand
// (<= 53 bits for an f64/comptime_float peer, <= 24 for an f32 peer), so the
// folded verdict is the mathematical comparison Zig folds and cannot disagree
// with the emitted runtime comparison of the same values. The phase pass
// stores the folded bool condition of every capture-free no-`else` value `if`,
// so lowering elides the untaken branch.
//
// Covered:
//   * literal vs literal (all six operators, exponent literal, `-0.0`/`0.0`);
//   * untyped int vs float (`2.0 == 2`, `1 != 2.0`) and an arithmetic-derived
//     int (`(1 + 1) == 2.0`);
//   * module f64 consts and function-local f64 consts (the sema local-const
//     scope; the runtime branch stays and agrees with the fold);
//   * typed f32: f32-vs-f32, f32-vs-f32-exact literal (`HF == 0.5`),
//     f32-vs-int (`HF > 0`);
//   * `@intToFloat(f64, ...)` and `@floatCast(f64, <f32>)`;
//   * logical combinations over folded float comparisons;
//   * an integer-comparison control (`(2 + 3) == 5`);
//   * false conditions in runtime `if` statements (control: never taken).
// Every folded value is `@panic`-guarded.
//
// Oracle: official Zig 0.15.2 twin (`/tmp/task9/oracle/fixture.zig`) accepts
// every shape and prints these exact values (3x).
//
// Contract: stdout below, rc 0, byte-exact 3x.
//
//   101 102 103 104 105 106 107 108 109 110 111 112
//   113 114 115 116 117 118 119 120 121 122 123
//   f1=0
//   float compare ok
const std = @import("std");

const MSIX: f64 = 1.5;
const MTHIRD: f64 = 0.3;
const MNEG: f64 = -2.5;
const HF: f32 = 0.5;
const QF: f32 = 0.25;

pub fn main() void {
    const lsix: f64 = 1.5;
    const lq: f64 = 0.25;
    const a1: i32 = if (0.5 < 1.0) 101;
    const a2: i32 = if (1.5 <= 1.5) 102;
    const a3: i32 = if (0.25 > -0.5) 103;
    const a4: i32 = if (-0.0 == 0.0) 104;
    const a5: i32 = if (1.5e1 == 15.0) 105;
    const a6: i32 = if (2.0 == 2) 106;
    const a7: i32 = if (1 != 2.0) 107;
    const a8: i32 = if (MSIX > 1.0) 108;
    const a9: i32 = if (MTHIRD < 0.5) 109;
    const a10: i32 = if (MNEG < 0.0) 110;
    const a11: i32 = if (lsix >= 1.5) 111;
    const a12: i32 = if (lq != 0.5) 112;
    const a13: i32 = if (HF > QF) 113;
    const a14: i32 = if (HF == 0.5) 114;
    const a15: i32 = if (HF > 0) 115;
    const a16: i32 = if (@intToFloat(f64, 3) < 3.5) 116;
    const a17: i32 = if (@intToFloat(f64, 4) == 4.0) 117;
    const a18: i32 = if (@floatCast(f64, HF) == 0.5) 118;
    const a19: i32 = if ((0.5 < 1.0) and (2.0 > 1.5)) 119;
    const a20: i32 = if (!(0.5 < 0.25)) 120;
    const a21: i32 = if (!((HF > 1.0) or (0.25 != 0.25))) 121;
    const a22: i32 = if (2.0 >= 2) 122;
    const a23: i32 = if ((2 + 3) == 5) 123;
    var f1: i32 = 0;
    if (0.5 > 1.0) { f1 = 999; }
    if (1.0 == 2.0) { f1 = f1 + 1; }
    if (-1.0 < -2.0) { f1 = f1 + 1; }
    if (HF != 0.5) { f1 = f1 + 1; }

    if (a1 != 101 or a2 != 102 or a3 != 103 or a4 != 104 or a5 != 105 or a6 != 106) {
        @panic("float compare guard A failed");
    }
    if (a7 != 107 or a8 != 108 or a9 != 109 or a10 != 110 or a11 != 111 or a12 != 112) {
        @panic("float compare guard B failed");
    }
    if (a13 != 113 or a14 != 114 or a15 != 115 or a16 != 116 or a17 != 117 or a18 != 118) {
        @panic("float compare guard C failed");
    }
    if (a19 != 119 or a20 != 120 or a21 != 121 or a22 != 122 or a23 != 123) {
        @panic("float compare guard D failed");
    }
    if (f1 != 0) {
        @panic("float compare runtime-false guard failed");
    }
    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {}\n", .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 });
    std.io.print("{} {} {} {} {} {} {} {} {} {} {}\n", .{ a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23 });
    std.io.print("f1={}\n", .{f1});
    std.io.print("float compare ok\n", .{});
}
