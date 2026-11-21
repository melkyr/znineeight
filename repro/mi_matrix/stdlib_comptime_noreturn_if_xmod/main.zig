// stdlib_comptime_noreturn_if_xmod — Task 3 fix round 1 (Critical) regression:
// the condition-fold store + `if_expr` `ie_fold` sub-path must not mishandle a
// noreturn then-arm.
//
// `sf/src/main.zig` stores the condition of every capture-free no-`else`
// `if_expr` (Task 1 §7), and `lower.zig`'s `ie_fold` path handled `void` but
// not `noreturn`: `const x: i32 = if (<comptime-true>) return N;` is accepted
// by sema (the no-`else` gate skips the comptime-true check when the then-type
// is noreturn), took the fold shortcut, lowered the `return` arm as a VALUE and
// left `x` uninitialised (the pre-fix compiler emitted `int zT_1; int x;
// zT_1 = x; x = zT_1; return x;` and printed garbage; official Zig prints N).
//
// Fix (`sf/src/lower.zig`): the fold shortcut is bypassed when the if_expr's
// resolved type is noreturn, so the normal path (`lowerIfArmValue` + the
// `ie_noreturn` guard) runs. The condition forms cover a bool literal, a
// function-local const, a folded comparison, a folded arithmetic comparison,
// and a module-scope const (the last exercises the stored condition).
//
// Every value is `@panic`-guarded. Oracle: official Zig 0.15.2 twin, prints
// these exact values.
//
// Contract: stdout below, rc 0, byte-exact 3x.
//
//   5 6 7 8 9
const std = @import("std");

const MT: bool = true;

fn noretTrue() i32 {
    const x: i32 = if (true) return 5;
    return x;
}

fn noretConst() i32 {
    const T: bool = true;
    const x: i32 = if (T) return 6;
    return x;
}

fn noretCmp() i32 {
    const x: i32 = if (1 < 2) return 7;
    return x;
}

fn noretArith() i32 {
    const x: i32 = if ((1 + 1) == 2) return 8;
    return x;
}

fn noretMod() i32 {
    const x: i32 = if (MT) return 9;
    return x;
}

pub fn main() void {
    var a: i32 = noretTrue();
    var b: i32 = noretConst();
    var c: i32 = noretCmp();
    var d: i32 = noretArith();
    var e: i32 = noretMod();
    if (a != 5 or b != 6 or c != 7 or d != 8 or e != 9) {
        @panic("comptime_noreturn_if guard failed");
    }
    std.io.print("{} {} {} {} {}\n", .{ a, b, c, d, e });
}
