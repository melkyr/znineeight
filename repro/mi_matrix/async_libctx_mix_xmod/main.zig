// async_libctx_mix_xmod — cross-track ABI Rule A regression (Track 2 + Track 3).
//
// The library path (`std.async.contextInit` / `contextAlloc`) and the compiler
// path (`@asyncInit` + the await-site child-frame allocation) share ONE
// `Context`. The library's pool base is `ctx + 16`; before Rule A the compiler
// used `ctx + 12`, so a library frame at `ctx+16` and a compiler child frame
// allocated from the same bump pointer could overlap.
//
// `main` imports `std_async.zig` directly (the library path) and drives the
// coroutine in `co.zig`. `co.zig` is imported after the std module so it is the
// last-emitted module: the compiler's synthesized `__Z98Step_*` functions are
// appended to the LIR stream after the module loop, and the C emitter walks
// functions in contiguous per-module runs, so only a step owned by the final
// module is emitted. (Single-module @asyncInit also works; a step in a non-last
// module is dropped — a separate, pre-existing multi-module emission gap.)
//
// Sequence: `contextInit` sizes the pool; `@asyncInit` resets `used`/`oom`;
// `contextAlloc(8)` hands out the library frame at `ctx+16` and advances `used`
// to 8; a sentinel is written at that frame's +4; the coroutine is driven and
// its await site allocates a child frame at `POOL_OFF + used`.
//   - Rule A (POOL_OFF = 16): child at ctx+24, strictly after the library frame
//     [ctx+16, ctx+24) -> sentinel intact -> PASS.
//   - Pre-fix (POOL_OFF = 12): child at ctx+20 = library frame +4 -> the child's
//     step word clobbers the sentinel -> panic -> FAIL.
//
// GREEN: no stdout, RUNRC=0.

const sa = @import("std_async.zig");
const co = @import("co.zig");

fn libAlloc(ctx: *sa.Context, n: usize, out: *[*]u8) bool {
    var p = sa.contextAlloc(ctx, n) catch return false;
    out.* = p;
    return true;
}

pub fn main() void {
    // 8-aligned backing for the shared Context + pool (32 * 8 = 256 bytes).
    var storage: [32]u64 = undefined;
    var buf: []u8 = @ptrCast([*]u8, &storage)[0..256];
    var ctx: *sa.Context = sa.contextInit(buf);

    var outv: u32 = 0;
    var root: [128]u8 = undefined;
    var ca: co.CArgs = co.CArgs{ .out = &outv };
    var args: *const void = @ptrCast(*const void, &ca);
    var ctxp: *void = @ptrCast(*void, ctx);
    var frame: *void = @asyncInit(ctxp, &root, co.caller, args);

    // Library path over the SAME Context: one 8-byte frame at ctx+16.
    var p: [*]u8 = undefined;
    if (!libAlloc(ctx, 8, &p)) {
        @panic("lib alloc failed");
    }
    var sentinel: *u32 = @ptrCast(*u32, p + 4);
    sentinel.* = 0x11223344;

    // Compiler path: drive the coroutine; its await site allocates a child.
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }

    if (sentinel.* != 0x11223344) {
        @panic("library frame corrupted by compiler child frame");
    }
    if (outv != 41) {
        @panic("await result mismatch");
    }
}
