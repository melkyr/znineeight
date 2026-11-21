// stdlib_async_suspenduntil_stress_xmod — STDLIB std.async (Plan D Task 4
// revised) suspendUntil stress. No PRNG and no wall-clock sleep: the driver
// ticks a fixed 7 times (Model C cooperative-yield; the caller drives `tick`,
// no executor, no poll loop) with six coroutines, each blocked on its own named
// predicate. The predicates flip at varied ticks {3,1,6,2,7,4}, so the six
// coroutines resume at six different ticks and their predicate-call counts are
// exactly the flip ticks. Every task must be done at the end and every observed
// resume tick / predicate-call count is asserted.
//
// GREEN (contract, deterministic stdout, rc 0):
//   resume 0 3
//   resume 1 1
//   resume 2 6
//   resume 3 2
//   resume 4 7
//   resume 5 4
//   predcalls 0 3
//   predcalls 1 1
//   predcalls 2 6
//   predcalls 3 2
//   predcalls 4 7
//   predcalls 5 4
//   suspenduntil stress ok
const sa = @import("std_async.zig");
const io = @import("std_io.zig");

var g_tick: u32 = 0;
var g_flip: [6]u32 = undefined;
var g_resume: [6]u32 = undefined;
var g_predcalls: [6]u32 = undefined;

// Named predicates: Z98 has no anonymous function literals. Non-suspending.
fn ready0() bool {
    g_predcalls[0] += 1;
    return g_tick >= g_flip[0];
}
fn ready1() bool {
    g_predcalls[1] += 1;
    return g_tick >= g_flip[1];
}
fn ready2() bool {
    g_predcalls[2] += 1;
    return g_tick >= g_flip[2];
}
fn ready3() bool {
    g_predcalls[3] += 1;
    return g_tick >= g_flip[3];
}
fn ready4() bool {
    g_predcalls[4] += 1;
    return g_tick >= g_flip[4];
}
fn ready5() bool {
    g_predcalls[5] += 1;
    return g_tick >= g_flip[5];
}

const CoCtx = struct { seen: u32 };

fn worker0(c: *CoCtx) void {
    _ = c;
    sa.suspendUntil(ready0);
    g_resume[0] = g_tick;
}
fn worker1(c: *CoCtx) void {
    _ = c;
    sa.suspendUntil(ready1);
    g_resume[1] = g_tick;
}
fn worker2(c: *CoCtx) void {
    _ = c;
    sa.suspendUntil(ready2);
    g_resume[2] = g_tick;
}
fn worker3(c: *CoCtx) void {
    _ = c;
    sa.suspendUntil(ready3);
    g_resume[3] = g_tick;
}
fn worker4(c: *CoCtx) void {
    _ = c;
    sa.suspendUntil(ready4);
    g_resume[4] = g_tick;
}
fn worker5(c: *CoCtx) void {
    _ = c;
    sa.suspendUntil(ready5);
    g_resume[5] = g_tick;
}

pub fn main() void {
    g_flip[0] = 3;
    g_flip[1] = 1;
    g_flip[2] = 6;
    g_flip[3] = 2;
    g_flip[4] = 7;
    g_flip[5] = 4;

    var storage0: [4096]u64 = undefined;
    var storage1: [4096]u64 = undefined;
    var storage2: [4096]u64 = undefined;
    var storage3: [4096]u64 = undefined;
    var storage4: [4096]u64 = undefined;
    var storage5: [4096]u64 = undefined;
    var ctx0 = sa.contextInit(@ptrCast([*]u8, &storage0)[0..4096 * 8]);
    var ctx1 = sa.contextInit(@ptrCast([*]u8, &storage1)[0..4096 * 8]);
    var ctx2 = sa.contextInit(@ptrCast([*]u8, &storage2)[0..4096 * 8]);
    var ctx3 = sa.contextInit(@ptrCast([*]u8, &storage3)[0..4096 * 8]);
    var ctx4 = sa.contextInit(@ptrCast([*]u8, &storage4)[0..4096 * 8]);
    var ctx5 = sa.contextInit(@ptrCast([*]u8, &storage5)[0..4096 * 8]);

    var cc = CoCtx{ .seen = 0 };

    var f0: [1024]u8 = undefined;
    var f1: [1024]u8 = undefined;
    var f2: [1024]u8 = undefined;
    var f3: [1024]u8 = undefined;
    var f4: [1024]u8 = undefined;
    var f5: [1024]u8 = undefined;
    var t0: sa.Task = undefined;
    var t1: sa.Task = undefined;
    var t2: sa.Task = undefined;
    var t3: sa.Task = undefined;
    var t4: sa.Task = undefined;
    var t5: sa.Task = undefined;

    t0.frame = @asyncInit(@ptrCast(*void, ctx0), &f0, worker0, @ptrCast(*const void, &cc));
    t0.ctx = ctx0;
    t0.arg = @ptrCast(*void, &cc);
    t0.result = @ptrCast(*void, &cc);
    t0.cancel_requested = false;
    t0.waiting_on = &t0;
    t0.has_waiting_on = false;
    t1.frame = @asyncInit(@ptrCast(*void, ctx1), &f1, worker1, @ptrCast(*const void, &cc));
    t1.ctx = ctx1;
    t1.arg = @ptrCast(*void, &cc);
    t1.result = @ptrCast(*void, &cc);
    t1.cancel_requested = false;
    t1.waiting_on = &t1;
    t1.has_waiting_on = false;
    t2.frame = @asyncInit(@ptrCast(*void, ctx2), &f2, worker2, @ptrCast(*const void, &cc));
    t2.ctx = ctx2;
    t2.arg = @ptrCast(*void, &cc);
    t2.result = @ptrCast(*void, &cc);
    t2.cancel_requested = false;
    t2.waiting_on = &t2;
    t2.has_waiting_on = false;
    t3.frame = @asyncInit(@ptrCast(*void, ctx3), &f3, worker3, @ptrCast(*const void, &cc));
    t3.ctx = ctx3;
    t3.arg = @ptrCast(*void, &cc);
    t3.result = @ptrCast(*void, &cc);
    t3.cancel_requested = false;
    t3.waiting_on = &t3;
    t3.has_waiting_on = false;
    t4.frame = @asyncInit(@ptrCast(*void, ctx4), &f4, worker4, @ptrCast(*const void, &cc));
    t4.ctx = ctx4;
    t4.arg = @ptrCast(*void, &cc);
    t4.result = @ptrCast(*void, &cc);
    t4.cancel_requested = false;
    t4.waiting_on = &t4;
    t4.has_waiting_on = false;
    t5.frame = @asyncInit(@ptrCast(*void, ctx5), &f5, worker5, @ptrCast(*const void, &cc));
    t5.ctx = ctx5;
    t5.arg = @ptrCast(*void, &cc);
    t5.result = @ptrCast(*void, &cc);
    t5.cancel_requested = false;
    t5.waiting_on = &t5;
    t5.has_waiting_on = false;

    var pt: [6]*sa.Task = undefined;
    pt[0] = &t0;
    pt[1] = &t1;
    pt[2] = &t2;
    pt[3] = &t3;
    pt[4] = &t4;
    pt[5] = &t5;
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    _ = sa.addTask(&s, &t2);
    _ = sa.addTask(&s, &t3);
    _ = sa.addTask(&s, &t4);
    _ = sa.addTask(&s, &t5);

    // Tick 1..7; every predicate sees the current tick. A coroutine resumes on
    // the first tick its predicate flips.
    var tick: u32 = 1;
    while (tick <= 7) : (tick += 1) {
        g_tick = tick;
        sa.tick(&s) catch @panic("tick");
    }

    var i: usize = 0;
    while (i < 6) : (i += 1) {
        if (g_resume[i] != g_flip[i]) @panic("resume tick");
        if (g_predcalls[i] != g_flip[i]) @panic("pred calls");
        if (pt[i].state != sa.TaskState.done) @panic("not done");
    }

    i = 0;
    while (i < 6) : (i += 1) {
        io.write("resume ");
        io.printInt(@intCast(i32, i));
        io.write(" ");
        io.printInt(@intCast(i32, g_resume[i]));
        io.writeByte('\n');
    }
    i = 0;
    while (i < 6) : (i += 1) {
        io.write("predcalls ");
        io.printInt(@intCast(i32, i));
        io.write(" ");
        io.printInt(@intCast(i32, g_predcalls[i]));
        io.writeByte('\n');
    }
    io.write("suspenduntil stress ok\n");
}
