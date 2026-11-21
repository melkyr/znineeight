// async_frame_lifetime_xmod — S10: a coroutine's ROOT frame must live in
// PERMANENT storage, never in an arena that is reset between ticks.
//
// Shape: a root frame is initialized in a PERMANENT, 8-aligned buffer
// (`perm`). The coroutine keeps a monotonic counter in a local that is live
// across each `@asyncSuspend` and publishes it to `out.last`. Between ticks
// the driver zeroes a SEPARATE scratch buffer (mirroring
// `sand_reset(&temp_arena)`); because the live frame is in `perm`, the
// counter survives all 8 ticks and `out.last` reaches 8.
//
// If the frame had been allocated from the reset scratch instead, the zeroing
// would clobber the frame's saved counter (and the `out` param pointer), so
// `out.last` would not reach 8 and the final assertion would fire. The
// fixture therefore FAILS when the root frame is in the reset arena and
// PASSES when it is permanent.
//
// The eight increments are unrolled (rather than a `while` loop) so the
// counter is a straight-line local live across each suspend; the driver's
// resume loop is what supplies the N-tick repetition.
//
// Context header layout (compiler-core, 32-bit): used@0, capacity@4, oom@8,
// 4 bytes padding; the pool base is `ctx + 16` (Rule A, cross-track ABI —
// must match std.async's HEADER_SIZE).
//
// GREEN: exact stdout "8\n" (RUNRC=0).

const std = @import("std");

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

const Out = struct { last: i32, ticks: i32 };
const CArgs = struct { out: *Out };

fn counter(out: *Out) void {
    var n: i32 = 0;
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
    n += 1; out.last = n; @asyncSuspend(null);
}

pub fn main() void {
    var out: Out = Out{ .last = 0, .ticks = 0 };
    // PERMANENT root-frame backing; `[K]u64` guarantees 8-alignment.
    var perm: [64]u64 = undefined;
    // Per-turn scratch the driver resets between ticks; the live root frame
    // must NOT live here.
    var scratch: [64]u64 = undefined;
    // Context pool (8-aligned) for child frames; `counter` has no await site,
    // so the pool is unused but the 16-byte header is still required.
    var pool: [16]u64 = undefined;
    var ctxp: *void = @ptrCast(*void, &pool);
    var ctxv: *Ctx = @ptrCast(*Ctx, &pool);
    ctxv.capacity = 128 - 16;
    var ca: CArgs = CArgs{ .out = &out };
    var args: *const void = @ptrCast(*const void, &ca);
    var frame: *void = @asyncInit(ctxp, @ptrCast([*]u8, &perm), counter, args);

    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        // Mirror `sand_reset(&temp_arena)`: zero the separate scratch buffer
        // before the tick. This must not touch the live root frame.
        var s: usize = 0;
        while (s < 64) : (s += 1) {
            scratch[s] = 0;
        }
        _ = @asyncResume(frame, null);
        out.ticks += 1;
    }

    if (out.ticks != 8) {
        @panic("async_frame_lifetime_xmod: tick count mismatch");
    }
    if (out.last != 8) {
        @panic("async_frame_lifetime_xmod: root frame counter clobbered between ticks");
    }
    std.io.printInt(out.last);
    std.io.writeByte('\n');
}
