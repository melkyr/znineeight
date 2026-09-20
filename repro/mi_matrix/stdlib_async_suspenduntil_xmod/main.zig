// stdlib_async_suspenduntil_xmod — Plan D Task 4 (REVISED): std.async.suspendUntil.
//
// Model C pin for the residual risk of the revised Task 4: a NON-suspending
// function pointer (`pred: fn() bool`) passed as a parameter into the suspending
// primitive `std.async.suspendUntil`, stored in the coroutine frame across a
// `@asyncSuspend`, and invoked indirectly once per tick. `suspendUntil` is called
// directly by name (the allowed direction); the predicate itself never suspends.
//
// The driver runs a single coroutine that calls `std.async.suspendUntil(isReady)`.
// `isReady` increments the per-tick predicate-call counter and returns the global
// `g_flag`. The driver ticks 3x with the flag clear (pred calls 1..3, each tick
// suspends), then sets `g_flag = true` and ticks once more: the coroutine resumes
// on tick 4, records `g_resume_tick`, and returns (task done).
//
// GREEN contract (deterministic stdout, rc 0):
//   resume-tick 4
//   pred-calls 4
//   suspenduntil ok
const std = @import("std");

var g_flag: bool = false;
var g_pred_calls: u32 = 0;
var g_tick: u32 = 0;
var g_resume_tick: u32 = 0;

// Named predicate: Z98 has no anonymous function literals. Non-suspending.
fn isReady() bool {
    g_pred_calls += 1;
    return g_flag;
}

const CoCtx = struct { seen: u32 };

fn worker(c: *CoCtx) void {
    _ = c;
    std.async.suspendUntil(isReady);
    g_resume_tick = g_tick;
}

pub fn main() void {
    var storage: [4096]u64 = undefined;
    var ctx = std.async.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
    var cc = CoCtx{ .seen = 0 };
    var frame_store: [1024]u8 = undefined;
    var task: std.async.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &frame_store, worker, @ptrCast(*const void, &cc));
    task.ctx = ctx;
    task.arg = @ptrCast(*void, &cc);
    task.result = @ptrCast(*void, &cc);
    task.cancel_requested = false;
    task.waiting_on = &task;
    task.has_waiting_on = false;
    var pt: [1]*std.async.Task = undefined;
    pt[0] = &task;
    var s = std.async.schedulerInit(pt[0..]);
    _ = std.async.addTask(&s, &task);

    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        g_tick = i + 1;
        std.async.tick(&s) catch @panic("tick");
    }
    if (task.state != std.async.TaskState.suspended) @panic("expected suspended");
    if (g_pred_calls != 3) @panic("pred calls before flag");

    g_flag = true;
    g_tick = 4;
    std.async.tick(&s) catch @panic("tick");

    if (g_resume_tick != 4) @panic("resume tick");
    if (g_pred_calls != 4) @panic("pred calls");
    if (task.state != std.async.TaskState.done) @panic("not done");

    std.io.print("resume-tick 4\n", .{});
    std.io.print("pred-calls 4\n", .{});
    std.io.print("suspenduntil ok\n", .{});
}
