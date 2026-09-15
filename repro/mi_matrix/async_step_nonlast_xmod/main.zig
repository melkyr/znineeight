// async_step_nonlast_xmod — EXPECTED-FAIL: multi-module step-emission gap.
//
// A coroutine in a NON-LAST module. `co.zig` (module 1) owns the suspending
// `caller`; `last.zig` (module 2) is imported after it, so `co` is NOT the
// last-emitted module. `@asyncInit` references `__Z98Step_caller`, but the
// compiler appends every synthesized step to the LIR stream AFTER the module
// loop and the C emitter consumes only contiguous per-module runs, so the step
// owned by a non-last module is never emitted.
//
// This is the deliberate expected-fail counterpart to `async_libctx_mix_xmod`
// (which places its coroutine in the LAST-imported module to dodge the gap).
// The emitter fix is Track 4; this fixture is written now so it lands with it.
//
// Documented failure mode: the emitted `main_*.c` takes the address of
// `__Z98Step_caller` (as a function-pointer initializer) but the step function
// is never emitted, so the gcc build/link fails with an undeclared
// identifier / undefined reference (see EXPECTED_FAIL.md).

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
