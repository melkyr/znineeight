// stdlib_async_pool_xmod — Track 3 std.async Context pool fixture.
//
// Validates the std.async re-export reachable from a bare @import("std"):
//   contextInit / contextAlloc / contextMark / contextRelease
//   - 8+8 alloc -> used 16; mark at 16; alloc 8 -> used 24; release -> 16
//   - alloc 40 -> used 56; alloc 40 -> OutOfFrame (sticky oom), used stays 56
//   - buf is 80 B; capacity = 80 - 12 = 68 usable bytes after the 12-byte header
// GREEN: exact stdout 1 1 1 1 0 1 1 (RUNRC=0).
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
    var buf: [80]u8 = undefined;
    var ctx = std.async.contextInit(buf[0..]);
    pb(tryAlloc(ctx, 8));
    pb(tryAlloc(ctx, 8));
    var mark = std.async.contextMark(ctx);
    pb(tryAlloc(ctx, 8));
    std.async.contextRelease(ctx, mark);
    pb(tryAlloc(ctx, 40));
    pb(tryAlloc(ctx, 40));
    pb(ctx.used == 56);
    pb(ctx.oom);
}
