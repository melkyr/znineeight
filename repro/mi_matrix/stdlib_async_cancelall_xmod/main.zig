// stdlib_async_cancelall_xmod — Track 3 std.async cancelAll fixture.
// Three never-completing tasks are resumed once, then cancelAll is requested;
// waitAll settles every task to cancelled (state 4).
// GREEN: exact stdout 4 4 4 (RUNRC=0).
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
    var f2: Frame = Frame{ .step = stepLong, .ticks = 0 };
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
    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    _ = sa.addTask(&s, &t2);
    sa.tick(&s) catch p(-1);
    sa.cancelAll(&s);
    sa.waitAll(&s) catch p(-1);
    p(@intCast(i32, @intCast(u8, s.tasks[0].state)));
    p(@intCast(i32, @intCast(u8, s.tasks[1].state)));
    p(@intCast(i32, @intCast(u8, s.tasks[2].state)));
}
