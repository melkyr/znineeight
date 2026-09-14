fn callee(out: *i32) void {
    @asyncSuspend(null);
    out.* = 10;
}

fn caller(out: *i32) void {
    var tmp: i32 = 0;
    callee(&tmp);
    out.* = tmp;
}

const CArgs = struct { out: *i32 };

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [256]u8 = undefined;
    var fbuf: [64]u8 = undefined;
    var ca: CArgs = CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, &fbuf, caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 10) {
        @panic("await result mismatch");
    }
}
