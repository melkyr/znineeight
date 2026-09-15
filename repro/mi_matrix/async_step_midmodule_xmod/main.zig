// async_step_midmodule_xmod — PASS: coroutine in the MIDDLE module of three.
//
// `main.zig` imports `mid.zig` (module 1) then `last.zig` (module 2), so `mid`
// is neither first nor last. The suspending `caller` lives in `mid.zig`; its
// synthesized `__Z98Step_caller` must be emitted in `mid`'s own `.c`/`.h`,
// matched to its owning `LirFunction.module_id` (Track-4 S15), instead of being
// dropped because steps are appended after the per-module lowering pass.
//
// This complements `async_step_nonlast_xmod` (two modules, non-last owner) and
// `async_libctx_mix_xmod` (last-module owner) by pinning the middle of three.
// GREEN: no stdout, RUNRC=0.

const mid = @import("mid.zig");
const last = @import("last.zig");

// Task 7 Context header at the start of the pool region (ctx == &cbuf):
// used@0, capacity@4, oom@8, 4 bytes padding; pool base is ctx+16 (Rule A,
// cross-track ABI — must match std.async's HEADER_SIZE).
const Ctx = struct { used: u32, capacity: u32, oom: u8 };

pub fn main() void {
    // Verified: @asyncFrameSize(mid.caller) == 72 (Rule A pads to a multiple of
    // 8). The assertion pins it so a frame-size change can never silently
    // overrun the root buffer below.
    if (@asyncFrameSize(mid.caller) != 72) {
        @panic("async_step_midmodule_xmod: caller frame size changed");
    }
    var result: i32 = 0;
    var cbuf: [256]u8 = undefined;
    var fbuf: [72]u8 = undefined;
    var ca: mid.CArgs = mid.CArgs{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 256;
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, &fbuf, mid.caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 10) {
        @panic("await result mismatch");
    }
    _ = last.ping();
}
