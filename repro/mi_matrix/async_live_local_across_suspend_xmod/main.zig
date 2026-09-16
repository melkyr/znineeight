// async_live_local_across_suspend_xmod — loop-carried local live across @asyncSuspend.
//
// Two coroutines are interleaved. Each has a loop-carried accumulator (`n` / `m`)
// that is mutated and read across an explicit `@asyncSuspend` inside a `while`.
// The accumulator is read only on the NEXT iteration (via the loop back-edge),
// never after the suspend in LINEAR block order, so P3's `hasReadAfter`
// (`sf/src/async_frame_layout.zig:373-384`) — which scans blocks linearly from
// the suspend point forward and does NOT follow CFG back-edges — never marks it
// live. It is therefore absent from the P3 layout (`:481-519`) and
// `saveAllFields`/`reloadAllFields` (`sf/src/async_state_machine.zig:253-279`)
// never persist it. (The loop counter `i`/`j` IS persisted: its `i += 1`
// continue-expression is emitted after the suspend block in linear order.)
//
// RED today (fixed point 43d41bfb903d56c153ebf653131aef6d): dump rc=0, gcc clean,
// link rc=0, then run rc=133 (SIGTRAP) with stderr
//   panic: async_live_local_across_suspend_xmod: coA counter not preserved
// The resume path re-enters the step function with `n` an uninitialized C local;
// interleaving coB's step (same stack slot) makes the lost accumulator
// deterministic. NOTE: a SINGLE coroutine alone can pass by stack-slot reuse
// (the C local happens to retain its value), so the interleave is required to
// expose #9 reliably — see the Task 2b-I report Q1.
//
// Expected GREEN contract (Task 2b-F): P3's liveness is made loop-aware, the
// frame persists `n`/`m`, and the program exits rc=0 with out.a == 8 and
// out.b == 800 (no stdout). Fix locus: P3 `asyncLayoutFrame` LIVE analysis
// (`sf/src/async_frame_layout.zig:481-519`, `hasReadAfter`), NOT P2 sizing
// (P2's `scanFrameLocals` already over-reserves every node) and NOT the
// save/reload emission (which faithfully saves the fields it is given).
//
// GREEN (Task 2b-F, fixed point 0da3f1391075e3e77c54b626d5550e3b): dump rc=0,
// 4 `.c`, gcc clean, link rc=0, run rc=0, no stdout. `hasReadAfter` is now
// CFG-aware (follows branch/jump/switch successors and loop back-edges), so the
// loop-carried accumulator is marked LIVE and the frame persists it. Emitted
// evidence (`__Z98Step_coA`): base saved only `out`@12 and `i`@16; now `n` is
// saved at frame offset 16 (plus the intermediate temps), and reloaded on the
// resume path.
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
    if (out.a != 8) {
        @panic("async_live_local_across_suspend_xmod: coA counter not preserved");
    }
    if (out.b != 800) {
        @panic("async_live_local_across_suspend_xmod: coB counter not preserved");
    }
}
