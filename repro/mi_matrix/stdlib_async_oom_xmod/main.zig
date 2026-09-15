// stdlib_async_oom_xmod — Track 3 std.async pool-exhaustion fixture.
// contextAlloc of 1000 into a 16-byte pool sets sticky oom (line 1), and tick
// surfaces error.OutOfFrame from the running task's context (line 2), not a
// crash. GREEN: exact stdout 1 1 (RUNRC=0).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32 };

fn stepNoop(f: *void, arg: ?*void) ?*void {
    _ = f;
    _ = arg;
    return null;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var fr: Frame = Frame{ .step = stepNoop, .ticks = 0 };
    // [2]u64 is exactly 16 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer.
    var storage: [2]u64 = undefined;
    var buf: []u8 = @ptrCast([*]u8, &storage)[0..16];
    var ctx = sa.contextInit(buf);
    _ = sa.contextAlloc(ctx, 1000) catch 0;
    p(@intCast(i32, if (ctx.oom) 1 else 0));

    var tasks: [1]sa.Task = undefined;
    var s = sa.schedulerInit(tasks[0..]);
    var t = sa.Task{ .frame = @ptrCast(*void, &fr), .ctx = ctx, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &fr), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    _ = sa.addTask(&s, &t);
    sa.tick(&s) catch {
        p(1);
        return;
    };
    p(0);
}
