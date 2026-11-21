// stdlib_async_waitfor_oom_xmod — Track 4c std.async.waitFor fixture (FrameError).
//
// The task's step exhausts its 16-byte child-frame pool via `contextAlloc`,
// which sets the sticky `ctx.oom` flag and returns `error.OutOfFrame`; the next
// `tick` (inside `waitFor`) observes `ctx.oom` and returns `error.OutOfFrame`,
// which `waitFor` propagates (FrameError = error{OutOfFrame} only). No crash.
//
// RED-now (waitFor absent): `-ffast --dump-c89` rc=2, 0 `.c`,
//   error[3042]: non-value base expression in field access
// GREEN contract (Task 4c-F): dump rc=0, gcc clean, link+run rc=0,
//   stdout `1` then `1` then `1` (waitFor caught OutOfFrame, ctx.oom, t0.state
//   == running because tick returned before it could mark the task done).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32, ctx: *sa.Context };

fn stepOom(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    _ = sa.contextAlloc(fr.ctx, 1000) catch 0;
    fr.ticks += 1;
    return null;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    // [2]u64 is exactly 16 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer. The 16-byte buffer leaves a 0-byte pool.
    var storage0: [2]u64 = undefined;
    var buf0: []u8 = @ptrCast([*]u8, &storage0)[0..16];
    var ctx0 = sa.contextInit(buf0);
    var f0: Frame = Frame{ .step = stepOom, .ticks = 0, .ctx = ctx0 };
    var r0: i32 = 0;
    var pt: [1]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    pt[0] = &t0;
    _ = sa.addTask(&s, &t0);

    sa.waitFor(&s, &t0) catch {
        p(1);
    };
    p(@intCast(i32, if (ctx0.oom) 1 else 0));
    p(@intCast(i32, @intCast(u8, t0.state)));
}
