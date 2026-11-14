// stdlib_async_addtask_reuse_xmod — slot reuse re-adds the same *Task.
//
// The mud_server lifecycle (Task 5, E4) frees a client slot by setting the
// task state to `.done` (it never removes the entry from the scheduler) and
// reuses that slot for the next accepted client, calling
// `std.async.addTask` again with the SAME `*Task`. `addTask`
// (`sf/src/std_async.zig:135-142`) appends unconditionally, so:
//   (a) the scheduler list holds the same pointer twice (`count` grows by one
//       per reconnect), and `tick` resumes that task once per duplicate entry
//       in a single pass;
//   (b) after `capacity` reconnects `count` saturates and `addTask` returns
//       false for a genuinely free slot.
//
// RED today (fixed point 18e0de5c): the program prints the hazard trace
//   `1 1 1 2 2 2 0 2`
// (addTask=true, count=1, re-add=true, count=2, occurrences=2, one-tick
// resumes=2, addTask(t1)=false, count=2) and then panics rc=133.
//
// GREEN contract (Task 5a-F: `addTask` must not register the same *Task
// twice — reset a settled task to ready instead): the same source prints
//   `1 1 1 1 1 1 1 2`
// (re-add does not append; `count` stays 1; `tick` resumes once; the free
// slot `t1` is admitted) and exits rc=0.
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

fn mkTask(fr: *Frame, ctx: *sa.Context, res: *i32) sa.Task {
    return sa.Task{
        .frame = @ptrCast(*void, fr),
        .ctx = ctx,
        .state = sa.TaskState.ready,
        .cancel_requested = false,
        .result = @ptrCast(*void, res),
        .arg = @ptrCast(*void, @intToPtr(*void, 0)),
        .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)),
        .has_waiting_on = false,
    };
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepFn, .remaining = 5, .resumes = 0 };
    var f1: Frame = Frame{ .step = stepFn, .remaining = 5, .resumes = 0 };
    var r0: i32 = 0;
    var r1: i32 = 0;
    var storage0: [2]u64 = undefined;
    var storage1: [2]u64 = undefined;
    var ctx0 = sa.contextInit(@ptrCast([*]u8, &storage0)[0..16]);
    var ctx1 = sa.contextInit(@ptrCast([*]u8, &storage1)[0..16]);
    // capacity 2: one live client slot + the saturation probe.
    var pt: [2]*sa.Task = undefined;
    var s = sa.schedulerInit(pt[0..]);
    var t0 = mkTask(&f0, ctx0, &r0);
    var t1 = mkTask(&f1, ctx1, &r1);

    p(if (sa.addTask(&s, &t0)) 1 else 0);        // RED 1 / GREEN 1
    p(@intCast(i32, s.count));                    // RED 1 / GREEN 1
    // mud_server frees the slot by marking the task done (no remove).
    t0.state = sa.TaskState.done;
    // the reconnecting client reuses the slot: re-add the SAME *Task.
    p(if (sa.addTask(&s, &t0)) 1 else 0);        // RED 1 / GREEN 1
    p(@intCast(i32, s.count));                    // RED 2 / GREEN 1
    var occ: i32 = 0;
    var i: usize = 0;
    while (i < s.count) : (i += 1) { if (s.tasks[i] == &t0) occ += 1; }
    p(occ);                                       // RED 2 / GREEN 1
    sa.tick(&s) catch {};                         // one pass over the list
    p(@intCast(i32, f0.resumes));                 // RED 2 / GREEN 1
    // t1 is genuinely free; saturation rejects it once count == capacity.
    p(if (sa.addTask(&s, &t1)) 1 else 0);        // RED 0 / GREEN 1
    p(@intCast(i32, s.count));                    // RED 2 / GREEN 2

    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (occ != 1 or f0.resumes != 1 or s.count != 2) {
        @panic("stdlib_async_addtask_reuse_xmod: addTask registered the same *Task twice");
    }
}
