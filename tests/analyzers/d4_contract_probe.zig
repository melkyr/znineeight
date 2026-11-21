// d4_contract_probe.zig — Phase 3.5 Task 0 D4 contract probe.
//
// This is a SOURCE fixture for the analyzer test runner (`testFixture` in
// `sf/src/tests/test_analyzer_bin.zig`), intended to be registered by the
// Task 8 audit / Task 9 harness expansion. It records one contract hole per
// analyzer plus a clean Signature surface:
//
//   NullPointer (defect b) — parameters are not seeded, so the live
//     `p.*` condition below is a FALSE POSITIVE (WARN_6002); `return p.*`
//     is a FALSE NEGATIVE because return expressions are not walked.
//   DoubleFree (defect c) — the alias chain `q = p; free(p); free(q)` is a
//     FALSE NEGATIVE (free through the alias is untracked).
//   DoubleFree / Lifetime (defect a) — the evaluator-only dead arm
//     `if (1 == 0)` is still walked by the analyzer, so the dead double free
//     is a FALSE POSITIVE.
//   Lifetime — `return &local` is a TRUE POSITIVE that must stay reported.
//   Signature — the `?Aggregate` / `E!Aggregate` fn-ptr surface and
//     arbitrary-width ints are valid and must stay CLEAN (any diagnostic here
//     is a false positive).
//
// Task 0 could not run this fixture through `testFixture` without editing the
// harness (see the repro inventory ADJ finding); the task records `--check`
// (real pipeline) diagnostics instead.
const Sand = struct { dummy: u32 };
const Key = struct { a: u32 };
const E = error{Bad};

fn sandAlloc(s: *Sand, n: usize, a: usize) *u8 {
    _ = s;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn sandFree(s: *Sand, p: *u8) void {
    _ = s;
    _ = p;
}

// NullPointer false positive: `p` is a non-optional pointer parameter, but the
// analyzer does not seed parameters as safe.
fn np_false_positive(p: *u32) void {
    if (p.* != 0) {
    }
}

// NullPointer false negative: the return expression is not walked.
fn np_false_negative(p: *u32) u32 {
    return p.*;
}

// DoubleFree false negative: alias-chain blindness.
fn df_alias_miss(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = p;
    sandFree(s, p);
    sandFree(s, q);
}

// DoubleFree / Lifetime false positive: evaluator-only comptime-dead arm.
fn dead_arm_false_positive(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    if (1 == 0) {
        sandFree(s, p);
        sandFree(s, p);
    }
    sandFree(s, p);
}

// Lifetime true positive: must stay an error.
fn lifetime_local() *u32 {
    var x: u32 = 1;
    return &x;
}

// Signature clean surface: fn-pointer returns of wrapped aggregates and
// arbitrary-width ints are valid (D1 shapes, post-T1/T2).
const Console = struct {
    read: fn (*void) ?Key,
    readE: fn (*void) E!Key,
};

fn sig_r1(s: *void) ?Key {
    _ = s;
    return Key{ .a = 1 };
}

fn sig_r2(s: *void) E!Key {
    _ = s;
    return Key{ .a = 2 };
}

fn sig_arb(x: i7, y: u48) i3 {
    _ = x;
    _ = y;
    return 1;
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    var x: u32 = 1;
    np_false_positive(&x);
    _ = np_false_negative(&x);
    df_alias_miss(&s);
    dead_arm_false_positive(&s);
    _ = lifetime_local();
    var c: Console = Console{ .read = sig_r1, .readE = sig_r2 };
    _ = c;
    _ = sig_arb(1, 2);
}
