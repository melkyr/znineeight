// stdlib_async_pool_xmod — Track 3 std.async Context pool fixture.
//
// Validates the std.async re-export reachable from a bare @import("std"):
//   contextInit / contextAlloc / contextMark / contextRelease
//   - 8+8 alloc -> used 16; mark at 16; alloc 8 -> used 24; release -> 16
//   - alloc 40 -> used 56; alloc 8 -> used 64; alloc 8 -> OutOfFrame (sticky
//     oom), used stays 64
//   - buf is 80 B (8-aligned); capacity = 80 - 16 = 64 usable bytes after the
//     16-byte header
// GREEN: exact stdout 1 1 1 1 1 0 1 1 (RUNRC=0).
const std = @import("std");

fn tryAlloc(ctx: *std.async.Context, n: usize) bool {
    var p = std.async.contextAlloc(ctx, n) catch return false;
    _ = p;
    return true;
}

fn pb(cond: bool) void {
    if (cond) {
        std.io.printInt(1);
    } else {
        std.io.printInt(0);
    }
    std.io.writeByte('\n');
}

pub fn main() void {
    // [10]u64 is exactly 80 bytes and guarantees 8-alignment; contextInit
    // requires an 8-aligned buffer.
    var storage: [10]u64 = undefined;
    var buf: []u8 = @ptrCast([*]u8, &storage)[0..80];
    var ctx = std.async.contextInit(buf);
    pb(tryAlloc(ctx, 8));
    pb(tryAlloc(ctx, 8));
    var mark = std.async.contextMark(ctx);
    pb(tryAlloc(ctx, 8));
    std.async.contextRelease(ctx, mark);
    pb(tryAlloc(ctx, 40));
    pb(tryAlloc(ctx, 8));
    pb(tryAlloc(ctx, 8));
    pb(ctx.used == 64);
    pb(ctx.oom);
}
