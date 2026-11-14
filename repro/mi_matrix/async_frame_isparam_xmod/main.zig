// async_frame_isparam_xmod — uninitialized `is_param` drops live locals from
// a coroutine frame (deterministic two-coroutine interleave).
//
// Two coroutines are registered as scheduler tasks and interleaved by
// `std.async.tick`. Each carries a loop accumulator (`n` / `m`) and a loop
// counter (`i` / `j`) live across an explicit `@asyncSuspend`. The frame
// layout's LIVE analysis (`sf/src/async_frame_layout.zig:562-567`) allocates
// its `is_param` predicate buffer with the NO-FILL primitive `allocU8Raw` and
// then sets only the parameter entries, so every non-parameter entry is stale
// heap memory. When those stale bytes are non-zero the live scan at `:584`
// skips the temp (`if (is_param[tu] != 0) continue;`) and the field emitter at
// `:609` never adds it to the frame. The affected coroutine's accumulator and
// counter are therefore NOT saved by `saveAllFields` / reloaded by
// `reloadAllFields` (`sf/src/async_state_machine.zig:253-279`); on resume the
// step reads uninitialized C locals.
//
// The two-coroutine interleave makes the corruption deterministic at runtime
// (a SINGLE coroutine alone can pass by C stack-slot reuse — see the
// `async_frame_isparam_single_xmod` control). With `coA` declared first its
// `is_param` lands on the dirty bytes, so `coA`'s `n`/`i` are dropped while
// `coB`'s `m`/`j` are persisted: stdout `701 800` (garbage `out.a`, correct
// `out.b`). The complementary declaration order (`coB` first) drops `coB`
// instead — see `async_frame_isparam_order_xmod`.
//
// RED today (fixed point 5c24305437629da54b4e4de1ed52e0e0): dump rc=0, 6 `.c`,
// gcc rc=0 but `warning: 'i' may be used uninitialized` in `__Z98Step_coA`,
// link rc=0, run rc=133 (SIGTRAP) with stdout
//   `701 800`
// and stderr
//   panic: async_frame_isparam_xmod: a live local was dropped from the frame
// The emitted `__Z98Step_coA` saves only the `out` param at frame offset 12;
// `n` and `i` are absent.
//
// GREEN contract (Task 4b-F: zero-init `is_param`): the live scan becomes
// deterministic, `coA` persists `n`/`i` (and `coB` `m`/`j`), and the program
// exits rc=0 with stdout `8 800`.
const std = @import("std");
const sa = @import("std_async.zig");

extern "c" fn fflush(f: *void) i32;

const Out = struct { a: i32, b: i32 };
const Args = struct { out: *Out };

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
    // [2]u64 == 16 bytes and guarantees the 8-alignment contextInit requires.
    var pool: [2]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &pool)[0..16]);
    var fa: [256]u8 = undefined;
    var fb: [256]u8 = undefined;
    var aa = Args{ .out = &out };
    var ab = Args{ .out = &out };
    var ta: sa.Task = undefined;
    var tb: sa.Task = undefined;
    ta.frame = @asyncInit(@ptrCast(*void, ctx), &fa, coA, @ptrCast(*const void, &aa));
    ta.ctx = ctx; ta.arg = @ptrCast(*void, &aa); ta.result = @ptrCast(*void, &aa);
    ta.cancel_requested = false; ta.waiting_on = &ta; ta.has_waiting_on = false;
    tb.frame = @asyncInit(@ptrCast(*void, ctx), &fb, coB, @ptrCast(*const void, &ab));
    tb.ctx = ctx; tb.arg = @ptrCast(*void, &ab); tb.result = @ptrCast(*void, &ab);
    tb.cancel_requested = false; tb.waiting_on = &tb; tb.has_waiting_on = false;
    var pt: [2]*sa.Task = undefined; pt[0] = &ta; pt[1] = &tb;
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &ta);
    _ = sa.addTask(&s, &tb);
    sa.waitAll(&s) catch {};
    std.io.printInt(out.a); std.io.writeByte(' ');
    std.io.printInt(out.b); std.io.writeByte('\n');
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (out.a != 8 or out.b != 800) {
        @panic("async_frame_isparam_xmod: a live local was dropped from the frame");
    }
}
