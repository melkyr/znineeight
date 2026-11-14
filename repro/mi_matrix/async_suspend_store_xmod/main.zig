const WArgs = struct { out: *i32 };

fn worker(out: *i32) void {
    var acc: i32 = 1;
    @asyncSuspend(null);
    acc = acc + 2;
    out.* = acc;
}

pub fn main() void {
    // Verified: @asyncFrameSize(worker) == 80. The root frame buffer `fbuf`
    // below must be at least that large (the driver zero-fills the whole
    // frame); it was [64] before the `-fsafe` @asyncInit bounds check exposed
    // the overrun.
    if (@asyncFrameSize(worker) != 80) {
        @panic("async_suspend_store_xmod: worker frame size changed");
    }
    var result: i32 = 0;
    var cbuf: [64]u8 = undefined;
    var fbuf: [80]u8 = undefined;
    var wa: WArgs = WArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var args: *const void = @ptrCast(*const void, &wa);
    var frame: *void = @asyncInit(ctxp, &fbuf, worker, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 3) {
        @panic("async result mismatch");
    }
}
