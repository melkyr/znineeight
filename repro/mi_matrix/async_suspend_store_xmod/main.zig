const WArgs = struct { out: *i32 };

fn worker(out: *i32) void {
    var acc: i32 = 1;
    @asyncSuspend(null);
    acc = acc + 2;
    out.* = acc;
}

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [64]u8 = undefined;
    var fbuf: [64]u8 = undefined;
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
