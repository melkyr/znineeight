// async_state_width_xmod — F2 (ASYNCTRACK2): the coroutine `state` counter must
// be u8/u16/u32 chosen by the suspension-point count (spec §3.2 item 3).
//
// `worker` has 300 explicit `@asyncSuspend` points, so the state width is u16.
// Pre-fix the state field, its stores, the switch, and the `-fsafe` range check
// were all hard-coded u8: state 256 truncated to 0 (restarting the body forever)
// and the range-check limit `total_states == 300` truncated to 44 (trapping
// early). RED is either the resume loop never terminating or an early trap.
// GREEN: all 300 suspends run, `out.*` is set, and the driver loop ends.
//
// std-free.

const CArgs = struct { out: *i32 };

fn worker(out: *i32) void {
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null); @asyncSuspend(null);
    out.* = 300;
}

pub fn main() void {
    var result: i32 = 0;
    var pool: [256]u8 = undefined;
    var fbuf: [16384]u8 = undefined;
    var ca: CArgs = CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &pool);
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, &fbuf, worker, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 300) {
        @panic("state width mismatch");
    }
}
