// stdlib_async_await_nonctx_xmod — Track 4 S17 rejection fixture.
//
// `awaitTask` is coroutine-internal: calling it from a non-suspending context
// (here `main`, with `in_task == false`) must trap instead of silently
// corrupting `s.tasks[s.current]`.
// Expected: dump rc=0, gcc/link rc=0, run rc!=0 with the panic text
//   std.async: awaitTask called from a non-suspending context
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32 };

fn stepNoop(f: *void, arg: ?*void) ?*void {
    _ = f;
    _ = arg;
    return null;
}

pub fn main() void {
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
