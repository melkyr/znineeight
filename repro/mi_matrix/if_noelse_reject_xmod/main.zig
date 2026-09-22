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

pub fn main() void {
    var a: i32 = 1;
    var x: i32 = if (a == 1) 1;
    take(if (a == 1) 1);
    _ = if (a == 1) 1;
    std.io.print("{}\n", .{pick(1)});
    _ = capPick(null);
    _ = x;
}
