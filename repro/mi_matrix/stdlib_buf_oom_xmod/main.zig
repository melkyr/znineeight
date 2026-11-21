// stdlib_buf_oom_xmod — STDLIB std_buf (L2) arena-exhaustion GREEN fixture (R1).
//
// Contract (blueprint §3 L2 + Global Constraint R1): growth allocates from the
// caller's arena; when the arena cannot satisfy a growing append the error is
// `error.OutOfMemory`, the buffer is left unchanged (len + capacity), and no
// memory outside the arena is written.
//
// Layout: a 32-byte storage array whose middle 16 bytes [8..24) back the arena;
// the 8-byte guards on either side are filled with 0xAB. Filling the buffer to
// its exact 16-byte capacity then appending one more byte forces a doubling
// allocation (16 -> 32) that the arena must refuse.
//
// GREEN (contract): deterministic byte-exact stdout `buf oom ok\n` (RUNRC=0).
const std = @import("std");
const buf = @import("std_buf.zig");

var g_storage: [32]u8 = undefined;
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    // Guard the whole storage, then hand the middle 16 bytes to the arena.
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        g_storage[i] = 0xAB;
    }
    var arena = std.arena.init(g_storage[8..24]);

    var b = std.buf.initCapacity(&arena, 16) catch {
        g_fail += 1;
        return;
    };
    ck(std.buf.capacity(&b) == 16, "initCapacity 16");

    // Fill exactly to capacity: every append succeeds without growing.
    i = 0;
    while (i < 16) : (i += 1) {
        std.buf.appendByte(&b, @intCast(u8, i)) catch {
            g_fail += 1;
        };
    }
    ck(std.buf.slice(&b).len == 16, "filled to capacity");
    ck(std.buf.capacity(&b) == 16, "no growth at capacity");

    // The 17th byte needs a doubling allocation; the arena is exhausted.
    var oom_seen = false;
    std.buf.appendByte(&b, 0xFF) catch |e| {
        if (e == error.OutOfMemory) {
            oom_seen = true;
        } else {
            g_fail += 1;
        }
    };
    ck(oom_seen, "append returns OutOfMemory");
    ck(std.buf.slice(&b).len == 16, "len unchanged after OutOfMemory");
    ck(std.buf.capacity(&b) == 16, "capacity unchanged after OutOfMemory");

    // No write outside the arena: both guards are untouched.
    i = 0;
    while (i < 8) : (i += 1) {
        ck(g_storage[i] == 0xAB, "low guard untouched");
    }
    i = 24;
    while (i < 32) : (i += 1) {
        ck(g_storage[i] == 0xAB, "high guard untouched");
    }

    // The arena region holds exactly the appended bytes.
    i = 0;
    while (i < 16) : (i += 1) {
        ck(g_storage[8 + i] == @intCast(u8, i), "arena bytes intact");
    }

    if (g_fail == 0) {
        std.io.write("buf oom ok\n");
    } else {
        std.io.write("buf oom FAIL\n");
    }
}
