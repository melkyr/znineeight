// stdlib_async_waitfor_cancel_xmod — Track 4c std.async.waitFor fixture (cancel).
//
// The registered task's step never returns null; `cancel(&s, &t0)` is requested
// from main BEFORE `waitFor`. The first `tick` inside `waitFor` observes the
// request at the tick boundary, marks t0 `cancelled` (settled), and does NOT
// resume the step; `waitFor` then returns.
//
// RED-now (waitFor absent): `-ffast --dump-c89` rc=2, 0 `.c`,
//   error[3042]: non-value base expression in field access
// GREEN contract (Task 4c-F): dump rc=0, gcc clean, link+run rc=0,
//   stdout `0` then `4` (step never resumed, TaskState.cancelled).
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
    sa.cancel(&s, &t0);

    sa.waitFor(&s, &t0) catch p(-1);
    p(@intCast(i32, f0.ticks));
    p(@intCast(i32, @intCast(u8, t0.state)));
}
