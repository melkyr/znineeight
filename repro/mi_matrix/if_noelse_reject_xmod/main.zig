// if_noelse_reject_xmod — Task 9B (b): a value `if` expression without an
// `else` branch is invalid Z98/Zig unless its then-branch is void/noreturn or
// its condition is comptime-known-true. Official Zig 0.15.2 types a no-`else`
// `if` as `void`, so using it as a value is "incompatible types: ... and void".
// Task 9B adds the check in `semanticAnalyzerResolveIfExpr`'s `child_2 == 0`
// branch (`sf/src/semantic_analyzer.zig`): reject with error[3059] when the
// then-type is not void/noreturn/undefined and the condition does not fold to a
// comptime-true bool (m1240 ruling 3). The gate accepts a `bool` condition
// (no capture) OR an optional/error-union condition (capture), so a
// capture-condition value `if` without `else` (`if (o) |v| v`) is rejected too
// (fix round 1) — previously it was silently accepted because the condition's
// resolved kind was optional, not `bool`.
//
// Contract: rc=2, 0 emitted `.c`, `error[3059]` per value-`if` site.
const std = @import("std");

fn take(x: i32) void {
    _ = x;
}

fn pick(a: i32) i32 {
    return if (a == 1) 1;
}

fn capPick(o: ?i32) i32 {
    var x: i32 = if (o) |v| v;
    return x;
}

// Task 9D: a runtime `false and <runtime>` condition does not fold (the fold
// short-circuits to false), so the no-`else` value `if` stays rejected.
fn andFalse(run: bool) i32 {
    var x: i32 = if (false and run) 1;
    return x;
}

// Task 9D fix round 1: a `u64` const above i64 max compared `< 0` folds FALSE
// by its DECLARED (unsigned) type, so this no-`else` value `if` is rejected
// (pre-fix it folded `true` and was silently accepted with an uninitialised
// result — official Zig 0.15.2 rejects it).
fn u64Lt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if (umax < 0) 3;
    return x;
}

// Task 9D fix round 1: rhs-decisive / non-decisive runtime-lhs logical forms
// (all Zig-rejected; a runtime lhs cannot be folded away).
fn rhsAndFalse(run: bool) i32 {
    var x: i32 = if (run and false) 1;
    return x;
}

fn rhsAndTrue(run: bool) i32 {
    var x: i32 = if (run and true) 1;
    return x;
}

fn rhsOrFalse(run: bool) i32 {
    var x: i32 = if (false or run) 1;
    return x;
}

pub fn main() void {
    var a: i32 = 1;
    var x: i32 = if (a == 1) 1;
    take(if (a == 1) 1);
    _ = if (a == 1) 1;
    std.io.print("{}\n", .{pick(1)});
    _ = capPick(null);
    _ = andFalse(true);
    _ = u64Lt0();
    _ = rhsAndFalse(true);
    _ = rhsAndTrue(true);
    _ = rhsOrFalse(true);
    _ = x;
}

