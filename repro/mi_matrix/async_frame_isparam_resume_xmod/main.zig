// async_frame_isparam_resume_xmod — GREEN control: the SAME two-coroutine
// shape driven by direct `@asyncResume` (no scheduler, no `std_async` import)
// persists its locals.
//
// This is the direct-resume sibling of `async_frame_isparam_xmod` /
// `async_frame_isparam_order_xmod`. The coroutine bodies are identical, but
// the driver calls `@asyncResume` directly instead of going through
// `std.async.tick`, and the program does not import `std_async.zig`. The
// resulting compile-time allocation layout places the frame-layout `is_param`
// buffer (`sf/src/async_frame_layout.zig:562`) on zeroed memory, so the LIVE
// scan is correct and both accumulators are saved/reloaded across the
// suspensions. This proves the corruption is not in the coroutine body, the
// state machine, or `@asyncResume`; it is the uninitialized `is_param` read in
// the frame layout, and it is layout/allocation dependent.
//
// (This is the same shape already pinned GREEN as
// `async_live_local_across_suspend_xmod` after Task 2b-F made `hasReadAfter`
// CFG-aware; this fixture restates it as the explicit control for the
// `is_param` pair.)
//
// GREEN today (fixed point 5c24305437629da54b4e4de1ed52e0e0): dump rc=0,
// 4 `.c`, gcc clean, link rc=0, run rc=0, stdout `8 800`.
const std = @import("std");

extern "c" fn fflush(f: *void) i32;

const Out = struct { a: i32, b: i32 };
const AArgs = struct { out: *Out };
const BArgs = struct { out: *Out };

fn coA(out: *Out) void {
    var n: i32 = 0;
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        n += 1;
        out.a = n;
        @asyncSuspend(null);
    }
}

fn coB(out: *Out) void {
    var m: i32 = 0;
    var j: i32 = 0;
    while (j < 8) : (j += 1) {
        m += 100;
        out.b = m;
        @asyncSuspend(null);
    }
}

pub fn main() void {
    var out: Out = Out{ .a = 0, .b = 0 };
    var acbuf: [64]u8 = undefined;
    var afbuf: [256]u8 = undefined;
    var bcbuf: [64]u8 = undefined;
    var bfbuf: [256]u8 = undefined;
    var aa: AArgs = AArgs{ .out = &out };
    var ba: BArgs = BArgs{ .out = &out };
    var actx: *void = @ptrCast(*void, &acbuf);
    var bctx: *void = @ptrCast(*void, &bcbuf);
    var aargs: *const void = @ptrCast(*const void, &aa);
    var bargs: *const void = @ptrCast(*const void, &ba);
    var af: *void = @asyncInit(actx, &afbuf, coA, aargs);
    var bf: *void = @asyncInit(bctx, &bfbuf, coB, bargs);
    var adone: bool = false;
    var bdone: bool = false;
    while (!adone or !bdone) {
        if (!adone) {
            var ra: ?*void = @asyncResume(af, null);
            if (ra == null) { adone = true; }
        }
        if (!bdone) {
            var rb: ?*void = @asyncResume(bf, null);
            if (rb == null) { bdone = true; }
        }
    }
    std.io.printInt(out.a); std.io.writeByte(' ');
    std.io.printInt(out.b); std.io.writeByte('\n');
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (out.a != 8 or out.b != 800) {
        @panic("async_frame_isparam_resume_xmod: direct @asyncResume dropped a live local");
    }
}
