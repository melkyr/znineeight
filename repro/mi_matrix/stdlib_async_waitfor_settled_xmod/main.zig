// stdlib_async_waitfor_settled_xmod — Track 4c std.async.waitFor fixture (settled).
//
// t0 is marked `done` before `waitFor`; t1 is registered and READY but its step
// never settles. `waitFor(&s, &t0)` must return immediately on the already-settled
// t0 WITHOUT ticking the scheduler (t1.ticks stays 0) and WITHOUT waiting for t1
// (i.e. it is per-task, not `waitAll`) — so it must not hang.
//
// RED-now (waitFor absent): `-ffast --dump-c89` rc=2, 0 `.c`,
//   error[3042]: non-value base expression in field access
// GREEN contract (Task 4c-F): dump rc=0, gcc clean, link+run rc=0,
//   stdout `0` then `3` (t1 never ticked, t0 TaskState.done).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32 };

fn stepLong(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    fr.ticks += 1;
    return f;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepLong, .ticks = 0 };
    var f1: Frame = Frame{ .step = stepLong, .ticks = 0 };
    var r0: i32 = 0;
    var r1: i32 = 0;
    // [2]u64 is exactly 16 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer.
    var storage0: [2]u64 = undefined;
    var storage1: [2]u64 = undefined;
    var buf0: []u8 = @ptrCast([*]u8, &storage0)[0..16];
    var buf1: []u8 = @ptrCast([*]u8, &storage1)[0..16];
    var ctx0 = sa.contextInit(buf0);
    var ctx1 = sa.contextInit(buf1);
    var pt: [2]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    pt[0] = &t0;
    pt[1] = &t1;
    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    t0.state = sa.TaskState.done;

    sa.waitFor(&s, &t0) catch p(-1);
    p(@intCast(i32, f1.ticks));
    p(@intCast(i32, @intCast(u8, t0.state)));
}
