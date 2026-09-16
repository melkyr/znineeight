// stdlib_async_waitfor_helper_xmod — Track 4c std.async.waitFor control.
//
// Same shape as stdlib_async_waitfor_xmod but `waitFor` is invoked from a plain
// non-suspending helper function (`drive`), not from `main`, proving the
// primitive is valid from any non-suspending context (no `s.in_task`, no caller
// frame, no `@asyncSuspend`).
//
// RED-now (waitFor absent): `-ffast --dump-c89` rc=2, 0 `.c`,
//   error[3042]: non-value base expression in field access
// GREEN contract (Task 4c-F): dump rc=0, gcc clean, link+run rc=0,
//   stdout `10` then `3` (f0.val, TaskState.done).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32, id: i32, val: i32 };

fn stepInc(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    if (fr.ticks < 2) {
        fr.ticks += 1;
        return f;
    }
    fr.val = fr.id * 10;
    return null;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn drive(s: *sa.Scheduler, t: *sa.Task) void {
    sa.waitFor(s, t) catch {};
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 1, .val = 0 };
    var r0: i32 = 0;
    // [2]u64 is exactly 16 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer.
    var storage0: [2]u64 = undefined;
    var buf0: []u8 = @ptrCast([*]u8, &storage0)[0..16];
    var ctx0 = sa.contextInit(buf0);
    var pt: [1]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    pt[0] = &t0;
    _ = sa.addTask(&s, &t0);

    drive(&s, &t0);
    p(f0.val);
    p(@intCast(i32, @intCast(u8, t0.state)));
}
