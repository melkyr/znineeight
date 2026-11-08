// async_wrapper_eu_payload_ok_xmod — Phase 3.5 D14 repro.
//
// A suspending wrapper (`try wait(c); return 32;`) returning a non-void
// error-union payload must compile and propagate success and error. Pre-fix
// this shape hits `error[3043]` (async parent_result slot type mismatch) or
// emits a GCC-incompatible step ABI for the plain tail return.
//
// GREEN (post-fix) contract: stdout `32 0\n0 1\n`, rc 0, under both `-ffast`
// and `-fsafe`.
const std = @import("std");

const E = error{Boom};

fn wait(c: *u32) E!void {
    @asyncSuspend(null);
    if (c.* != 0) return E.Boom;
}

fn wrapper(c: *u32) E!u32 {
    try wait(c);
    return 32;
}

const Args = struct { out: *u32, c: *u32, failed: *u32 };

fn caller(out: *u32, c: *u32, failed: *u32) void {
    var r: u32 = wrapper(c) catch {
        failed.* = 1;
        return;
    };
    out.* = r;
}

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn drive(out: *u32, c: *u32, failed: *u32) void {
    var cbuf: [256]u8 = undefined;
    var fbuf: [256]u8 = undefined;
    var a = Args{ .out = out, .c = c, .failed = failed };
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
    var c: u32 = 0;
    var out: u32 = 0;
    var failed: u32 = 0;

    drive(&out, &c, &failed);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');

    c = 1;
    out = 0;
    failed = 0;
    drive(&out, &c, &failed);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');
}
