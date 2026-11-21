// stdlib_async_await_xmod — Track 3 std.async await + cancel fixture.
// t1 waits on t0 (dependency), t2 is cancelled before it completes:
//   t0 -> 10 (id 1), t1 -> 20 (id 2) only after t0, t2 -> state 4.
// GREEN: exact stdout 10 20 4 (RUNRC=0).
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
    var f2: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 3, .val = 0, .sched = @ptrCast(*sa.Scheduler, @intToPtr(*void, 0)), .do_await = false };
    var r0: i32 = 0;
    var r1: i32 = 0;
    var r2: i32 = 0;

    // [2]u64 is exactly 16 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer.
    var storage0: [2]u64 = undefined;
    var storage1: [2]u64 = undefined;
    var storage2: [2]u64 = undefined;
    var buf0: []u8 = @ptrCast([*]u8, &storage0)[0..16];
    var buf1: []u8 = @ptrCast([*]u8, &storage1)[0..16];
    var buf2: []u8 = @ptrCast([*]u8, &storage2)[0..16];
    var ctx0 = sa.contextInit(buf0);
    var ctx1 = sa.contextInit(buf1);
    var ctx2 = sa.contextInit(buf2);

    var pt: [3]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);

    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t2 = sa.Task{ .frame = @ptrCast(*void, &f2), .ctx = ctx2, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r2), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };

    pt[0] = &t0;
    pt[1] = &t1;
    pt[2] = &t2;
    f1.sched = &s;
    f1.do_await = true;

    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    _ = sa.addTask(&s, &t2);

    sa.cancel(&s, s.tasks[2]);

    sa.waitAll(&s) catch p(-1);
    p(f0.val);
    p(f1.val);
    p(@intCast(i32, @intCast(u8, s.tasks[2].state)));
}
