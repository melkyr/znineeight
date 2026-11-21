// stdlib_async_handle_xmod — Track 4 std.async caller-handle identity fixture.
//
// addTask stores the CALLER's *Task (S14): the caller handle `t0` and the
// scheduler slot `s.tasks[0]` are the SAME object. So `cancel(&s, &t0)` is
// observed by `tick` (t0 -> cancelled), and `t1`'s `awaitTask(&s, &t0)` (called
// from inside its coroutine body, S17) unblocks only once t0 settles.
// GREEN: exact stdout 4 4 20 (RUNRC=0). FAILS against the old by-value addTask
// copy (which would print 0 3 20: the caller handle never sees the scheduler's
// state and vice versa).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct {
    step: sa.StepFn,
    ticks: u32,
    id: i32,
    val: i32,
    sched: *sa.Scheduler,
    do_await: bool,
};

fn stepInc(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    if (fr.do_await and fr.ticks == 0) {
        fr.do_await = false;
        sa.awaitTask(fr.sched, fr.sched.tasks[0]);
    }
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

pub fn main() void {
    var f0: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 1, .val = 0, .sched = @ptrCast(*sa.Scheduler, @intToPtr(*void, 0)), .do_await = false };
    var f1: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 2, .val = 0, .sched = @ptrCast(*sa.Scheduler, @intToPtr(*void, 0)), .do_await = false };
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

    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var pt: [2]*sa.Task = [2]*sa.Task{ &t0, &t1 };
    var s = sa.schedulerInit(pt[0..]);
    f1.sched = &s;
    f1.do_await = true;

    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    sa.cancel(&s, &t0);

    sa.waitAll(&s) catch p(-1);
    p(@intCast(i32, @intCast(u8, t0.state)));
    p(@intCast(i32, @intCast(u8, s.tasks[0].state)));
    p(f1.val);
}
