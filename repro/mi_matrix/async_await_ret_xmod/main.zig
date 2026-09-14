const CArgs = struct { out: *i32 };

fn worker() i32 {
    @asyncSuspend(null);
    return 7;
}

fn caller(out: *i32) void {
    out.* = worker();
}

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [256]u8 = undefined;
    var fbuf: [64]u8 = undefined;
    var ca: CArgs = CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var usedp: *u32 = @ptrCast(*u32, &cbuf);
    usedp.* = 0;
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, &fbuf, caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 7) {
        @panic("await ret mismatch");
    }
}
