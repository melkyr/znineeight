// async_frame_structret_xmod — D4 undeclared frame-save temp
// (a by-value struct-return temporary assigned to a module global in a
// suspending function). See NOTES.md.
//
// A suspending function assigns a by-value struct-return result
// (`g_val = mkBig(1)`) to a module global and then, inside a loop, passes
// `&g_val` to suspending calls at two sites (an if/else). The async
// frame-layout pass hoists the `.load_global` alias of `&g_val` as a live
// field; the emitter's DCE suppresses that temp's declaration and the frame
// save is emitted before `temp_global_map` is populated, so the emitted C
// references an undeclared `zT_N`. gcc rejects it pre-fix; after the fix the
// program compiles, links, and prints `5`.
const std = @import("std");

const Big = struct { a: u32, b: u32, c: u32, d: u32 };

var g_val: Big = undefined;

fn mkBig(x: u32) Big {
    return Big{ .a = x, .b = x, .c = x, .d = x };
}

fn suspA(p: *Big) void { @asyncSuspend(null); p.a = p.a + 1; }
fn suspB(p: *Big) void { @asyncSuspend(null); p.b = p.b + 1; }

const CArgs = struct { out: *u32 };

fn caller(out: *u32) void {
    g_val = mkBig(1);
    var i: u32 = 0;
    while (i < 3) : (i = i + 1) {
        if ((i & 1) == 0) {
            suspA(&g_val);
        } else {
            suspB(&g_val);
        }
    }
    out.* = g_val.a + g_val.b;
}

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

pub fn main() void {
    var result: u32 = 0;
    var cbuf: [1024]u8 = undefined;
    var fbuf: [1024]u8 = undefined;
    var ca: CArgs = CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 1024;
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, &fbuf, caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) { more = @asyncResume(frame, null); }
    if (result != 5) {
        @panic("async_frame_structret_xmod: expected 5");
    }
    std.io.printInt(@intCast(i32, result));
    std.io.write("\n");
}
