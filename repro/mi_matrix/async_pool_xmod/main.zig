// async_pool_xmod — Task 7 per-task LIFO child-frame pool + `error.OutOfFrame`.
//
// A deep chain of suspending calls (level1 -> level2 -> level3, all implicit
// awaits) is driven with a deliberately small Context pool: the first child
// frame (level2, 28 bytes) already exceeds `capacity = 20`, so the await site
// sets the sticky `oom` flag and takes the null/error terminal path instead of
// writing out of bounds. The fixture asserts `oom == 1` (no crash), i.e. pool
// exhaustion is reported rather than corrupting memory.
//
// Context header layout (compiler-core, 32-bit): the caller passes
// `ctx = &pool`; the header occupies the first bytes of `pool`:
//   used@0, capacity@4, oom@8, 4 bytes padding; the child-frame pool base is
//   `pool + 16` (Rule A, cross-track ABI — matches std.async's HEADER_SIZE).
// `@asyncInit` initializes `used = 0` and `oom = 0`; the test supplies
// `capacity`. `capacity` counts the usable pool bytes (after the header).

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn level3(out: *i32) void {
    @asyncSuspend(null);
    out.* = 3;
}

fn level2(out: *i32) void {
    var t: i32 = 0;
    level3(&t);
    out.* = t + 1;
}

fn level1(out: *i32) void {
    var t: i32 = 0;
    level2(&t);
    out.* = t + 1;
}

const L1Args = struct { out: *i32 };

pub fn main() void {
    // Verified: @asyncFrameSize(level1) == 80. The root frame buffer `cbuf`
    // below must be at least that large (the driver zero-fills the whole
    // frame); it was [64] before the `-fsafe` @asyncInit bounds check exposed
    // the overrun.
    if (@asyncFrameSize(level1) != 80) {
        @panic("async_pool_xmod: level1 frame size changed");
    }
    var result: i32 = 0;
    var pool: [64]u8 = undefined;
    var cbuf: [80]u8 = undefined;
    var fbuf: [64]u8 = undefined;
    var la: L1Args = L1Args{ .out = &result };
    var ctxp: *void = @ptrCast(*void, &pool);
    var ctxv: *Ctx = @ptrCast(*Ctx, &pool);
    // `used` and `oom` are initialized by `@asyncInit`; the test supplies only
    // the capacity (usable pool bytes after the header).
    ctxv.capacity = 20;
    var args: *const void = @ptrCast(*const void, &la);
    var frame: *void = @asyncInit(ctxp, &cbuf, level1, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (ctxv.oom != 1) {
        @panic("expected OutOfFrame");
    }
}
