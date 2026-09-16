// stdlib_async_await_nonctx_xmod — Track 4 S17 rejection fixture, EXTENDED for
// Task 4c (operator's requested err case).
//
// Part A (`coroutineInternalAwait`) confirms `awaitTask`'s coroutine-internal
// semantics are UNCHANGED: t1 (a running task) awaits t0 and resumes when t0
// settles; `waitAll` drives both to done and prints `10` then `20`.
//
// Part B (`nonSuspendingAwait`, the original body) confirms the err case:
// calling `awaitTask` from a non-suspending context (here `main`, with
// `in_task == false`) must trap instead of silently corrupting
// `s.tasks[s.current]`.
//
// Expected: dump rc=0, gcc/link rc=0, run rc!=0 with stdout `10` `20` and the
//   panic text
//   std.async: awaitTask called from a non-suspending context
const std = @import("std");
const sa = @import("std_async.zig");

// Part A's stdout must be flushed before Part B traps, or the buffered bytes
// are lost on the trap. Mirrors the async_frame_isparam_xmod idiom.
extern "c" fn fflush(f: *void) i32;

const Frame = struct { step: sa.StepFn, ticks: u32 };

const AwFrame = struct {
    step: sa.StepFn,
    ticks: u32,
    id: i32,
    val: i32,
    sched: *sa.Scheduler,
    do_await: bool,
};

fn stepNoop(f: *void, arg: ?*void) ?*void {
    _ = f;
    _ = arg;
    return null;
}

fn stepAwait(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*AwFrame, f);
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

fn coroutineInternalAwait() void {
    var f0: AwFrame = AwFrame{ .step = stepAwait, .ticks = 0, .id = 1, .val = 0, .sched = @ptrCast(*sa.Scheduler, @intToPtr(*void, 0)), .do_await = false };
    var f1: AwFrame = AwFrame{ .step = stepAwait, .ticks = 0, .id = 2, .val = 0, .sched = @ptrCast(*sa.Scheduler, @intToPtr(*void, 0)), .do_await = false };
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
    f1.sched = &s;
    f1.do_await = true;
    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);

    sa.waitAll(&s) catch p(-1);
    p(f0.val);
    p(f1.val);
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
}

fn nonSuspendingAwait() void {
    var fr: Frame = Frame{ .step = stepNoop, .ticks = 0 };
    // [2]u64 is exactly 16 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer.
    var storage: [2]u64 = undefined;
    var buf: []u8 = @ptrCast([*]u8, &storage)[0..16];
    var ctx = sa.contextInit(buf);

    var t = sa.Task{ .frame = @ptrCast(*void, &fr), .ctx = ctx, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &fr), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var pt: [1]*sa.Task = [1]*sa.Task{ &t };
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &t);

    sa.awaitTask(&s, s.tasks[0]);
}

pub fn main() void {
    coroutineInternalAwait();
    nonSuspendingAwait();
}
