// stdlib_async_removetask_xmod — `std.async.removeTask` lifecycle contract.
//
// `mud_server` (Task 5, E4) frees a client slot by setting the task state to
// `.done` but never unregisters the `*Task`, so a reconnecting client's
// `addTask` appends a duplicate entry (`count` saturates). The operator ruling
// for Task 5a-F adds an explicit `pub fn removeTask(s: *Scheduler, t: *Task)`
// primitive so a caller can retire a finished task; this fixture pins its
// contract:
//   - after `removeTask(s, t)`, `t` is no longer registered: `s.count` drops,
//     a subsequent `tick` does not resume `t`;
//   - a later `addTask(s, t)` of the same task succeeds and the slot is
//     reusable;
//   - `removeTask` of an already-removed or never-added task is a no-op
//     (`count` unchanged).
//
// RED today (fixed point 18e0de5c): the primitive does not exist, so the
// frontend rejects `sa.removeTask` with `error[3042]` (non-value base
// expression in field access), dump rc=2, 0 `.c` emitted.
//
// GREEN contract (Task 5a-F adds `removeTask`): dump/gcc/link/run rc=0, stdout
//   `1 1 0 0 1 1 0 0 1 1 1`
// (addTask=true; count=1; count=0 after remove; tick resumes nothing; re-add
// true; count=1; remove-again no-op count=0; remove-never-added no-op count=0;
// addTask(t1)=true; count=1; one tick resumes t1 once) and run rc=0.
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
    var f0: Frame = Frame{ .step = stepFn, .remaining = 5, .resumes = 0 };
    var f1: Frame = Frame{ .step = stepFn, .remaining = 5, .resumes = 0 };
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

    p(if (sa.addTask(&s, &t0)) 1 else 0);   // 1
    p(@intCast(i32, s.count));               // 1
    sa.removeTask(&s, &t0);                  // retire t0
    p(@intCast(i32, s.count));               // 0
    sa.tick(&s) catch {};                    // t0 is gone: no resume
    p(@intCast(i32, f0.resumes));            // 0
    p(if (sa.addTask(&s, &t0)) 1 else 0);   // 1 (slot reusable)
    p(@intCast(i32, s.count));               // 1
    sa.removeTask(&s, &t0);
    sa.removeTask(&s, &t0);                  // already removed: no-op
    p(@intCast(i32, s.count));               // 0
    sa.removeTask(&s, &t1);                  // never added: no-op
    p(@intCast(i32, s.count));               // 0
    p(if (sa.addTask(&s, &t1)) 1 else 0);   // 1
    p(@intCast(i32, s.count));               // 1
    sa.tick(&s) catch {};
    p(@intCast(i32, f1.resumes));            // 1

    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (s.count != 1 or f0.resumes != 0 or f1.resumes != 1) {
        @panic("stdlib_async_removetask_xmod: removeTask lifecycle contract broken");
    }
}
