// stdlib_async_addtask_restart_cancel_xmod — restart-after-cancel contract.
//
// `addTask` is IDEMPOTENT (`sf/src/std_async.zig`): re-adding an already-
// registered `*Task` that is settled (done/cancelled) resets it IN PLACE to
// `ready`; a not-registered `*Task` is APPENDED as `ready`. The doc comment and
// the landed declaration advertise "settled (done/**cancelled**) -> reset in
// place to `ready`", but the reset never cleared `cancel_requested`. Since
// `cancel_requested` is only ever set true (`cancel`/`cancelAll`), a re-added
// CANCELLED task is immediately re-cancelled by the next `tick` and never runs.
//
// This fixture pins restart-after-cancel on BOTH reset paths:
//   Phase A (reset-in-place): add t0 -> cancel t0 -> tick (t0 cancelled) ->
//     re-add the SAME *Task -> tick -> t0 must run to completion.
//   Phase B (append): cancel a not-yet-registered t1 -> addTask(t1) appends it
//     as ready -> tick -> t1 must run to completion.
//
// RED today (fixed point 18e0de5c): `cancel_requested` survives the reset, so
// both restarted tasks are re-cancelled without running; the program prints
//   `1 1 1 2 1 1 4 1 1 1 1 4 1 4 1 1 2 1 0 4`
// and panics rc=133 (f0.resumes 1, f1.resumes 0, both states cancelled).
//
// GREEN contract (clear `t.cancel_requested` in both addTask paths): the same
// source prints
//   `1 1 1 2 1 1 4 1 1 0 2 2 3 3 1 1 2 0 1 3`
// (Phase A: t0 restarts and resumes 3x to done; Phase B: t1 restarts and
// resumes once to done) and exits rc=0.
const std = @import("std");
const sa = @import("std_async.zig");

extern "c" fn fflush(f: *void) i32;

const Frame = struct { step: sa.StepFn, remaining: u32, resumes: u32 };

fn stepFn(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    fr.resumes += 1;
    if (fr.remaining > 0) { fr.remaining -= 1; return f; }
    return null;
}

fn p(v: i32) void { std.io.printInt(v); std.io.writeByte('\n'); }

fn mkTask(fr: *Frame, ctx: *sa.Context, res: *i32) sa.Task {
    return sa.Task{
        .frame = @ptrCast(*void, fr),
        .ctx = ctx,
        .state = sa.TaskState.ready,
        .cancel_requested = false,
        .result = @ptrCast(*void, res),
        .arg = @ptrCast(*void, @intToPtr(*void, 0)),
        .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)),
        .has_waiting_on = false,
    };
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepFn, .remaining = 2, .resumes = 0 };
    var f1: Frame = Frame{ .step = stepFn, .remaining = 0, .resumes = 0 };
    var r0: i32 = 0;
    var r1: i32 = 0;
    var storage0: [2]u64 = undefined;
    var storage1: [2]u64 = undefined;
    var ctx0 = sa.contextInit(@ptrCast([*]u8, &storage0)[0..16]);
    var ctx1 = sa.contextInit(@ptrCast([*]u8, &storage1)[0..16]);
    var pt: [2]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = mkTask(&f0, ctx0, &r0);
    var t1 = mkTask(&f1, ctx1, &r1);

    // Phase A — reset-in-place restart after cancel.
    p(if (sa.addTask(&s, &t0)) 1 else 0);            // 1
    p(@intCast(i32, s.count));                        // 1
    sa.tick(&s) catch {};                             // t0: remaining 2 -> 1
    p(@intCast(i32, f0.resumes));                     // 1
    p(@intCast(i32, @intCast(u8, t0.state)));         // 2 (suspended)
    sa.cancel(&s, &t0);                               // request cancel
    p(if (t0.cancel_requested) 1 else 0);            // 1
    sa.tick(&s) catch {};                             // t0 observed cancel
    p(@intCast(i32, f0.resumes));                     // 1 (not resumed)
    p(@intCast(i32, @intCast(u8, t0.state)));         // 4 (cancelled)
    p(if (sa.addTask(&s, &t0)) 1 else 0);            // 1 (reset in place)
    p(@intCast(i32, s.count));                        // 1
    p(if (t0.cancel_requested) 1 else 0);            // RED 1 / GREEN 0
    sa.tick(&s) catch {};                             // RED re-cancels; GREEN resumes
    p(@intCast(i32, f0.resumes));                     // RED 1 / GREEN 2
    p(@intCast(i32, @intCast(u8, t0.state)));         // RED 4 / GREEN 2
    sa.tick(&s) catch {};                             // GREEN completes t0
    p(@intCast(i32, f0.resumes));                     // RED 1 / GREEN 3
    p(@intCast(i32, @intCast(u8, t0.state)));         // RED 4 / GREEN 3 (done)

    // Phase B — append-path restart after cancel (t1 never registered).
    sa.cancel(&s, &t1);                               // stale cancel on an unregistered task
    p(if (t1.cancel_requested) 1 else 0);            // 1
    p(if (sa.addTask(&s, &t1)) 1 else 0);            // 1 (append)
    p(@intCast(i32, s.count));                        // 2
    p(if (t1.cancel_requested) 1 else 0);            // RED 1 / GREEN 0
    sa.tick(&s) catch {};                             // RED re-cancels; GREEN completes
    p(@intCast(i32, f1.resumes));                     // RED 0 / GREEN 1
    p(@intCast(i32, @intCast(u8, t1.state)));         // RED 4 / GREEN 3 (done)

    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (f0.resumes != 3 or t0.state != sa.TaskState.done or
        f1.resumes != 1 or t1.state != sa.TaskState.done or s.count != 2) {
        @panic("stdlib_async_addtask_restart_cancel_xmod: restart-after-cancel re-cancelled a reset task");
    }
}
