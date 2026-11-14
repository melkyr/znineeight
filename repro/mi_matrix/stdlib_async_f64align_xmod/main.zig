// stdlib_async_f64align_xmod — Track 3 std.async pool alignment fixture.
//
// The 16-byte header keeps `pool_base = ctx + 16` 8-aligned when the caller's
// buffer is 8-aligned. Allocating a frame-like struct that holds an `f64` from
// the pool must therefore return an 8-aligned pointer, and the `f64` field must
// round-trip through that pointer (no misaligned load/store).
// GREEN: exact stdout 1 1 1 (RUNRC=0).
const std = @import("std");

const Frame = struct {
    tag: u64,
    val: f64,
};

fn pb(cond: bool) void {
    if (cond) {
        std.io.printInt(1);
    } else {
        std.io.printInt(0);
    }
    std.io.writeByte('\n');
}

pub fn main() void {
    // [8]u64 is exactly 64 bytes and guarantees 8-alignment.
    var storage: [8]u64 = undefined;
    var buf: []u8 = @ptrCast([*]u8, &storage)[0..64];
    var ctx = std.async.contextInit(buf);
    var raw: [*]u8 = std.async.contextAlloc(ctx, @sizeOf(Frame)) catch @ptrCast([*]u8, 0);
    pb((@ptrToInt(raw) & 7) == 0);
    var f: *Frame = @ptrCast(*Frame, raw);
    f.tag = 7;
    f.val = 3.5;
    pb(f.val == 3.5);
    pb(f.tag == 7);
}
