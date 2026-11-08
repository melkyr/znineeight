// async_wrapper_eu_payload_ok_xmod — Phase 3.5 D14 exact-shape repro.
//
// A suspending wrapper (`try wait(c); return id;`) returning a non-void
// error-union payload shaped exactly like `std_http2.Http2Error!u32` must
// compile and propagate success and error. The result is a runtime `id`
// parameter, not a literal.
//
// GREEN (post-fix) contract: stdout `42 0\n0 1\n`, rc 0, under both `-ffast`
// and `-fsafe`.
const std = @import("std");

// Same name count/shape as `std_http2.Http2Error` (15 members).
const Http2Error = error{
    NotHttp2,
    BadConfig,
    TooLarge,
    Protocol,
    Corrupt,
    Closed,
    Io,
    OutOfMemory,
    StreamClosed,
    StreamReset,
    GoAway,
    NoStream,
    Busy,
    BadCertificate,
    AuthenticationFailed,
};

fn wait(c: *u32) Http2Error!void {
    @asyncSuspend(null);
    if (c.* != 0) return Http2Error.Protocol;
}

fn wrapper(c: *u32, id: u32) Http2Error!u32 {
    try wait(c);
    return id;
}

const Args = struct { out: *u32, c: *u32, failed: *u32, id: u32 };

fn caller(out: *u32, c: *u32, failed: *u32, id: u32) void {
    var r: u32 = wrapper(c, id) catch {
        failed.* = 1;
        return;
    };
    out.* = r;
}

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn drive(out: *u32, c: *u32, failed: *u32, id: u32) void {
    var cbuf: [256]u8 = undefined;
    var fbuf: [256]u8 = undefined;
    var a = Args{ .out = out, .c = c, .failed = failed, .id = id };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 256;
    var args: *const void = @ptrCast(*const void, &a);
    var frame: *void = @asyncInit(ctxp, &fbuf, caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
}

pub fn main() void {
    var id: u32 = 42;
    var c: u32 = 0;
    var out: u32 = 0;
    var failed: u32 = 0;

    drive(&out, &c, &failed, id);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');

    c = 1;
    out = 0;
    failed = 0;
    drive(&out, &c, &failed, id);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');
}
