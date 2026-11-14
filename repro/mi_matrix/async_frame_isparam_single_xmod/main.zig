// async_frame_isparam_single_xmod — GREEN control: a SINGLE task, no
// interleave, does not expose the dropped-local corruption.
//
// This is the single-coroutine sibling of `async_frame_isparam_xmod`. The
// `worker` body is the same loop-carried accumulator shape, driven by a
// one-task `std.async` scheduler. Even though the uninitialized `is_param`
// buffer (`sf/src/async_frame_layout.zig:562-567`) may still drop `worker`'s
// `i`/`n` from the frame (gcc emits `warning: 'i' may be used uninitialized`),
// the step function is re-entered at the SAME C stack depth on every resume,
// so the stale C locals happen to retain their values and the runtime result is
// correct. This is exactly why a single-task shape is NOT a reliable RED and
// why the deterministic pin requires the >=2-coroutine interleave. It is the
// control for the "1-task root-frame quirk" premise that Task 4b-I disproved.
//
// GREEN today (fixed point 5c24305437629da54b4e4de1ed52e0e0): dump rc=0,
// 6 `.c`, gcc rc=0 (may warn `'i' may be used uninitialized`), link rc=0,
// run rc=0, stdout `8`.
const std = @import("std");
const sa = @import("std_async.zig");

extern "c" fn fflush(f: *void) i32;

const Out = struct { a: i32, b: i32 };
const Args = struct { out: *Out };

fn worker(out: *Out) void {
    var n: i32 = 0;
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        n += 1;
        out.a = n;
        @asyncSuspend(null);
    }
}

pub fn main() void {
    var out: Out = Out{ .a = 0, .b = 0 };
    // [2]u64 == 16 bytes and guarantees the 8-alignment contextInit requires.
    var pool: [2]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &pool)[0..16]);
    var fbuf: [256]u8 = undefined;
    var a = Args{ .out = &out };
    var task: sa.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &fbuf, worker, @ptrCast(*const void, &a));
    task.ctx = ctx; task.arg = @ptrCast(*void, &a); task.result = @ptrCast(*void, &a);
    task.cancel_requested = false; task.waiting_on = &task; task.has_waiting_on = false;
    var pt: [1]*sa.Task = undefined; pt[0] = &task;
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &task);
    sa.waitAll(&s) catch {};
    std.io.printInt(out.a); std.io.writeByte('\n');
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (out.a != 8) {
        @panic("async_frame_isparam_single_xmod: single-task accumulator not preserved");
    }
}
