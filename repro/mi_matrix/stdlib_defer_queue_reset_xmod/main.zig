// stdlib_defer_queue_reset_xmod — FG runtime fixture for the D1 defer-queue
// corruption (repro/vol2_defects/D01_defer_segfault).
//
// DEFECT pinned (D1): the AnalyzerContext defer queue survived every
// `sandReset` of the scratch arena that holds it, and
// `deferQueueEnsureCapacity`'s capacity short-circuit let the next queued
// DeferEntry write land in recycled scratch memory that now held a live
// StateMap. A module with a plain-`defer` function followed by another
// function with a `defer` inside a nested block (for / while / nested for)
// SIGSEGV'd the compiler (rc 139) in `checkLeaksOnScopeExit` /
// `stateMapMergeStates`.
//
// FIX (FG): `resetDeferQueue` clears items/len/cap immediately after each of
// the four per-phase/per-function `sandReset` calls in `runAllAnalyzers`
// (`sf/src/analyzer.zig`); the queue is drained at every block exit, so the
// reset is a bookkeeping-only no-op that kills the stale pointer.
//
// Contract: the stdout rows below, rc 0, byte-exact 3x. The trigger family is
// `plainFirst` + `forDefer` (in-module) and `helper.plainFirst` +
// `helper.forDefer` (both shapes in helper.zig, cross-module); the while /
// nested-for siblings and the for-body `errdefer` dynamic-error case share the
// queue. The `ops` counter is @panic-guarded: defers must have executed
// exactly 9 times before `errLoop`, and the two `errLoop` calls must not run
// their `errdefer` on the success path.
//   plain-body
//   plain-defer
//   for 1
//   for-defer
//   for 2
//   for-defer
//   while 0
//   while-defer
//   while 1
//   while-defer
//   nested 1 1
//   nested-defer
//   nested 1 2
//   nested-defer
//   nested 2 1
//   nested-defer
//   nested 2 2
//   nested-defer
//   try 1
//   try 2
//   try 1
//   try 2
//   errdefer 2
//   caught
//   helpplain-body
//   helpplain-defer
//   helpfor 1
//   helpfor-defer
//   helpfor 2
//   helpfor-defer
//   done
const std = @import("std");
const helper = @import("helper.zig");

var ops: i32 = 0;

fn plainFirst() void {
    defer ops += 1;
    defer std.io.print("plain-defer\n", .{});
    std.io.print("plain-body\n", .{});
}

fn forDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer ops += 1;
        defer std.io.print("for-defer\n", .{});
        std.io.print("for {}\n", .{v});
    }
}

fn whileDefer() void {
    var i: i32 = 0;
    while (i < 2) : (i = i + 1) {
        defer ops += 1;
        defer std.io.print("while-defer\n", .{});
        std.io.print("while {}\n", .{i});
    }
}

fn nestedForDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |a| {
        for (arr) |b| {
            defer ops += 1;
            defer std.io.print("nested-defer\n", .{});
            std.io.print("nested {} {}\n", .{ a, b });
        }
    }
}

fn errLoop(fail_at: i32) !void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        errdefer std.io.print("errdefer {}\n", .{v});
        std.io.print("try {}\n", .{v});
        if (fail_at == v) return error.Boom;
    }
}

pub fn main() void {
    plainFirst();
    forDefer();
    whileDefer();
    nestedForDefer();
    if (ops != 9) { @panic("defer count after loops"); }
    errLoop(0) catch { std.io.print("unexpected\n", .{}); };
    errLoop(2) catch { std.io.print("caught\n", .{}); };
    helper.plainFirst();
    helper.forDefer();
    std.io.print("done\n", .{});
}
