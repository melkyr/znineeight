// arena_oom_green_xmod — std.arena.alloc returns a named error union
// `std.arena.ArenaError![*]u8` with member `error.OutOfMemory` (C89-AHEAD A8F).
// Exhausting a tiny arena is a GRACEFUL outcome: the error union is caught and
// the `error.OutOfMemory` case is distinguished from success (no trap, no null
// dereference). Deterministic stdout, RUNRC=0: 1 2 99
const std = @import("std");

var buf: [16]u8 = undefined;
var arena = std.arena.init(buf[0..]);

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    const a0 = std.arena.alloc(&arena, 8) catch |e| {
        _ = e;
        p(-1);
        return;
    };
    a0[0] = 0xA0;
    p(1);

    const a1 = std.arena.alloc(&arena, 8) catch |e| {
        _ = e;
        p(-2);
        return;
    };
    a1[0] = 0xA1;
    p(2);

    // Arena is exactly full (16/16): the next allocation must surface
    // error.OutOfMemory, which is handled here instead of trapping.
    const a2 = std.arena.alloc(&arena, 1) catch |e| {
        if (e == error.OutOfMemory) {
            p(99);
        } else {
            p(-3);
        }
        return;
    };
    a2[0] = 0xFF;
    p(3);
}
