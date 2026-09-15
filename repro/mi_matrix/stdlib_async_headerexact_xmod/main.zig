// stdlib_async_headerexact_xmod — Track 3 std.async header-exact pool fixture.
//
// A buffer sized exactly to the 16-byte Context header yields capacity == 0:
// the first contextAlloc(n>0) returns error.OutOfFrame and sets the sticky
// `oom` flag, with no trap (16 - 16 == 0 is not an underflow) and `used` stays
// 0. Validates the `capacity = buf.len - 16` boundary.
// GREEN: exact stdout 1 1 1 1 (RUNRC=0).
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
    // [2]u64 is exactly 16 bytes and guarantees 8-alignment.
    var storage: [2]u64 = undefined;
    var buf: []u8 = @ptrCast([*]u8, &storage)[0..16];
    var ctx = std.async.contextInit(buf);
    pb(ctx.capacity == 0);
    pb(tryAlloc(ctx, 1) == false);
    pb(ctx.used == 0);
    pb(ctx.oom);
}
