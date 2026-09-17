// stdlib_async_addtask_single_xmod — canonical single-task lifecycle control.
//
// One task is registered exactly once (no slot reuse), resumed to completion
// by `tick`. This is the single-client control for the slot-reuse finding: it
// pins that the ordinary addTask/tick lifecycle is correct, so the RED in
// `stdlib_async_addtask_reuse_xmod` is caused by re-adding a freed slot, not
// by registration itself.
//
// GREEN today and after Task 5a-F: dump/link/run rc=0, stdout `1 1 3 3`:
// addTask=true, count=1, resumes=3 (two yields + the terminal call), state=3
// (done).
const std = @import("std");
const sa = @import("std_async.zig");

extern "c" fn fflush(f: *void) i32;

const Frame = struct { step: sa.StepFn, remaining: u32, resumes: u32 };

fn stepFn(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    fr.resumes += 1;
    if (fr.remaining > 0) { fr.remaining -= 1; return f; }
    return null;
}

fn p(v: i32) void { std.io.printInt(v); std.io.writeByte('\n'); }

pub fn main() void {
    var f0: Frame = Frame{ .step = stepFn, .remaining = 2, .resumes = 0 };
    var r0: i32 = 0;
    var storage0: [2]u64 = undefined;
    var ctx0 = sa.contextInit(@ptrCast([*]u8, &storage0)[0..16]);
    var pt: [1]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = sa.Task{
        .frame = @ptrCast(*void, &f0),
        .ctx = ctx0,
        .state = sa.TaskState.ready,
        .cancel_requested = false,
        .result = @ptrCast(*void, &r0),
        .arg = @ptrCast(*void, @intToPtr(*void, 0)),
        .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)),
        .has_waiting_on = false,
    };

    p(if (sa.addTask(&s, &t0)) 1 else 0);
    p(@intCast(i32, s.count));
    sa.tick(&s) catch {};
    sa.tick(&s) catch {};
    sa.tick(&s) catch {};
    p(@intCast(i32, f0.resumes));
    p(@intCast(i32, @intCast(u8, t0.state)));

    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (f0.resumes != 3 or t0.state != sa.TaskState.done or s.count != 1) {
        @panic("stdlib_async_addtask_single_xmod: canonical single-task lifecycle broken");
    }
}
