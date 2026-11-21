// async_step_nonlast_xmod — PASS: multi-module step emission (non-last module).
//
// A coroutine in a NON-LAST module. `co.zig` (module 1) owns the suspending
// `caller`; `last.zig` (module 2) is imported after it, so `co` is NOT the
// last-emitted module. `@asyncInit` references `__Z98Step_caller`, and the
// compiler emits that synthesized step in `co`'s own `.c`/`.h` because it is
// matched to its owning `LirFunction.module_id` (Track-4 S15). Before the fix,
// every synthesized step was appended to the LIR stream AFTER the module loop
// and the C emitter consumed only contiguous per-module runs, so the step owned
// by a non-last module was never emitted and the gcc build failed with
// `'...___Z98Step_caller' undeclared`.
//
// This is the non-last counterpart to `async_libctx_mix_xmod` (LAST-module
// coroutine, imported last on purpose) and `async_step_midmodule_xmod` (MIDDLE
// module of three). GREEN: no stdout, RUNRC=0.

const co = @import("co.zig");
const last = @import("last.zig");

// Task 7 Context header at the start of the pool region (ctx == &cbuf):
// used@0, capacity@4, oom@8, 4 bytes padding; pool base is ctx+16 (Rule A,
// cross-track ABI — must match std.async's HEADER_SIZE).
const Ctx = struct { used: u32, capacity: u32, oom: u8 };

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [256]u8 = undefined;
    // @asyncFrameSize(co.caller) == 72; the buffer must be at least that large.
    var fbuf: [72]u8 = undefined;
    var ca: co.CArgs = co.CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 256;
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, &fbuf, co.caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 10) {
        @panic("await result mismatch");
    }
    _ = last.ping();
}
