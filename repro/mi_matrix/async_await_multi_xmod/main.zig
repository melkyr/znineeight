// Task 6D5 (Amendment 10 I1): per-await parent_result slots.
//
// `caller` has four value-returning implicit awaits of two different types
// (a(): i32, b(): i64) plus an interleaved void await (v()) that must NOT
// advance the kind-7 slot index. The first two awaits are straight-line; the
// last two sit in the then/else branches of an `if` (branch ordering, not just
// straight-line order). Each value-returning await must write/read its own
// slot so `b` (i64 = 5000000000) is not truncated through `a`'s i32 slot.
//
// The P4 per-slot type assertion in async_state_machine.zig fails closed with
// ERR_9001_ICE if P2/P3's slot order ever desyncs from P4's await order; this
// fixture is order-sensitive because adjacent slots have different types.
//
// Frame-size churn (Task 6D5 step 8): `caller` is the only function with >= 2
// value-returning awaits, so it is the only one that gains extra kind-7 slots;
// its authoritative P2 frame size is pinned here. `a`/`v`/`b` stay 16.

const CArgs = struct { o1: *i32, o2: *i64, ob1: *i32, ob2: *i64, cond: bool };

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn a() i32 {
    @asyncSuspend(null);
    return 42;
}

fn v() void {
    @asyncSuspend(null);
}

fn b() i64 {
    @asyncSuspend(null);
    return 5000000000;
}

fn caller(o1: *i32, o2: *i64, ob1: *i32, ob2: *i64, cond: bool) void {
    o1.* = a();
    v();
    o2.* = b();
    if (cond) {
        ob1.* = a();
    } else {
        ob2.* = b();
    }
}

pub fn main() void {
    var r1: i32 = 0;
    var r2: i64 = 0;
    var rb1: i32 = 0;
    var rb2: i64 = 0;
    var cbuf: [1024]u8 = undefined;
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.used = 0;
    ctxv.capacity = 1024;
    ctxv.oom = 0;

    if (@asyncFrameSize(caller) != 64) {
        @panic("caller frame size mismatch");
    }

    var ca1: CArgs = CArgs{ .o1 = &r1, .o2 = &r2, .ob1 = &rb1, .ob2 = &rb2, .cond = true };
    var fbuf1: [256]u8 = undefined;
    var ctxp1: *void = @ptrCast(*void, &cbuf);
    var args1: *const void = @ptrCast(*const void, &ca1);
    var frame1: *void = @asyncInit(ctxp1, &fbuf1, caller, args1);
    var more1: ?*void = @asyncResume(frame1, null);
    while (more1 != null) {
        more1 = @asyncResume(frame1, null);
    }
    if (r1 != 42) {
        @panic("straight a mismatch");
    }
    if (r2 != 5000000000) {
        @panic("straight b truncated");
    }
    if (rb1 != 42) {
        @panic("branch then mismatch");
    }

    var ca2: CArgs = CArgs{ .o1 = &r1, .o2 = &r2, .ob1 = &rb1, .ob2 = &rb2, .cond = false };
    var fbuf2: [256]u8 = undefined;
    ctxv.used = 0;
    var ctxp2: *void = @ptrCast(*void, &cbuf);
    var args2: *const void = @ptrCast(*const void, &ca2);
    var frame2: *void = @asyncInit(ctxp2, &fbuf2, caller, args2);
    var more2: ?*void = @asyncResume(frame2, null);
    while (more2 != null) {
        more2 = @asyncResume(frame2, null);
    }
    if (rb2 != 5000000000) {
        @panic("branch else truncated");
    }
}
