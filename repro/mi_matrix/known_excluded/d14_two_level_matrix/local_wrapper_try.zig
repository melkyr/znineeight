// d14_two_level_matrix sibling: local TRY wrapper around the await.
//
// `const x = try valueWait(...); return x;` — the try-bound await in a third
// wrapper level. Runnable. Post-fix expected stdout `42 0\n0 1\n`.
const std = @import("std");

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

fn valueWait(c: *u32, id: u32) Http2Error!u32 {
    @asyncSuspend(null);
    if (c.* != 0) return Http2Error.Protocol;
    return id;
}

fn wrapper(c: *u32, id: u32) Http2Error!u32 {
    const x = try valueWait(c, id);
    return x;
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
