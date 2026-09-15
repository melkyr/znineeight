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

// Task 7 Context header at the start of the pool region (ctx == &cbuf):
// used@0, capacity@4, oom@8, 4 bytes padding; pool base is ctx+16 (Rule A,
// cross-track ABI — must match std.async's HEADER_SIZE).
const Ctx = struct { used: u32, capacity: u32, oom: u8 };

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [256]u8 = undefined;
    // The root `caller` frame is 72 bytes (Rule A: padded to a multiple of 8);
    // the buffer must be at least that large, since @asyncInit zero-fills the
    // whole frame.
    var fbuf: [128]u8 = undefined;
    var ca: CArgs = CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 256;
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
