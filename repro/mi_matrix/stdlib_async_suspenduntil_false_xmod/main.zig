// stdlib_async_suspenduntil_false_xmod — Plan D hardening Task 3 probe.
//
// Single-failure-per-process probe for std.async.suspendUntil (Plan D Task 4
// revised; Model C). The predicate never becomes true, so over a bounded tick
// count the coroutine must stay suspended and never resume past the
// suspension point. The observed resume count must be 0 and the predicate must
// be invoked exactly once per tick.
//
// The driver ticks a fixed 4 times and asserts after every tick that the task
// is still suspended (never done). No wall-clock sleep, no executor, no poll
// loop — the caller drives `tick`.
//
// GREEN contract (declared expected.rc 0):
//   resume-count 0
//   pred-calls 4
//   suspenduntil-false ok
const std = @import("std");

var g_pred_calls: u32 = 0;
var g_resume_count: u32 = 0;

// Named predicate: Z98 has no anonymous function literals. Never ready.
fn neverReady() bool {
    g_pred_calls += 1;
    return false;
}

const CoCtx = struct { seen: u32 };

fn worker(c: *CoCtx) void {
    _ = c;
    std.async.suspendUntil(neverReady);
    g_resume_count += 1;
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

    const TICKS: u32 = 4;
    var i: u32 = 0;
    while (i < TICKS) : (i += 1) {
        std.async.tick(&s) catch @panic("tick");
        if (task.state != std.async.TaskState.suspended) @panic("task left suspended");
    }

    if (g_resume_count != 0) @panic("resume count nonzero");
    if (g_pred_calls != TICKS) @panic("pred calls");
    if (task.state != std.async.TaskState.suspended) @panic("not suspended");

    std.io.print("resume-count 0\n", .{});
    std.io.print("pred-calls 4\n", .{});
    std.io.print("suspenduntil-false ok\n", .{});
}
