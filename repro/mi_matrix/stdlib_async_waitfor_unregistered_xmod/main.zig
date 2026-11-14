// stdlib_async_waitfor_unregistered_xmod — Track 4c std.async.waitFor hang guard.
//
// t0 is NOT registered in `s`; `s` holds a different, never-settling task t1.
// `waitFor(&s, &t0)` can never settle t0 by ticking, so without a guard it would
// loop forever. The Task 4c-F guard `@panic`s on an unsettled unregistered task,
// so this fixture terminates with a trap instead of hanging (run rc != 0, not
// rc=124 under `timeout 120`).
//
// RED-now (waitFor absent): `-ffast --dump-c89` rc=2, 0 `.c`,
//   error[3042]: non-value base expression in field access
// GREEN contract (Task 4c-F): dump rc=0, gcc clean, link rc=0,
//   run rc=133 (SIGTRAP) with stderr
//   `panic: std.async: waitFor called with an unregistered task`.
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
    var pt: [1]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    // Only t1 is registered; t0 is deliberately left unregistered.
    pt[0] = &t1;
    _ = sa.addTask(&s, &t1);

    sa.waitFor(&s, &t0) catch p(-1);
    p(1);
}
