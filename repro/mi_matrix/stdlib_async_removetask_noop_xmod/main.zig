// stdlib_async_removetask_noop_xmod — `std.async.removeTask` no-op control.
//
// Control for `stdlib_async_removetask_xmod`: `removeTask(s, t)` on a task
// that is NOT registered is a no-op. The contract pinned here is:
//   - removing from an empty scheduler leaves `count` at 0;
//   - removing the same task twice: the second call is a no-op;
//   - removing a task that was never added is a no-op.
// No state is mutated and no task is cancelled by a no-op removal.
//
// RED today (fixed point 18e0de5c): `sa.removeTask` does not exist, so the
// frontend rejects it with `error[3042]`, dump rc=2, 0 `.c`.
//
// GREEN contract (Task 5a-F adds `removeTask`): dump/gcc/link/run rc=0, stdout
//   `0 1 0 0 0`
// (remove on empty count=0; addTask=true; count=0 after remove; count=0 after
// the second remove; count=0 after removing a never-added task) and rc=0.
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
    var t0 = sa.Task{
        .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready,
        .cancel_requested = false, .result = @ptrCast(*void, &r0),
        .arg = @ptrCast(*void, @intToPtr(*void, 0)),
        .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false,
    };
    var t1 = sa.Task{
        .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready,
        .cancel_requested = false, .result = @ptrCast(*void, &r1),
        .arg = @ptrCast(*void, @intToPtr(*void, 0)),
        .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false,
    };

    sa.removeTask(&s, &t0);                  // empty scheduler: no-op
    p(@intCast(i32, s.count));               // 0
    p(if (sa.addTask(&s, &t0)) 1 else 0);   // 1
    sa.removeTask(&s, &t0);
    p(@intCast(i32, s.count));               // 0
    sa.removeTask(&s, &t0);                  // already removed: no-op
    p(@intCast(i32, s.count));               // 0
    sa.removeTask(&s, &t1);                  // never added: no-op
    p(@intCast(i32, s.count));               // 0

    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (s.count != 0 or t0.state != sa.TaskState.ready) {
        @panic("stdlib_async_removetask_noop_xmod: removeTask no-op contract broken");
    }
}
