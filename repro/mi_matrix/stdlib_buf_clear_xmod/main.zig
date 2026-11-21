// stdlib_buf_clear_xmod — STDLIB std_buf (L2) clear-and-reuse GREEN fixture.
//
// Contract (blueprint §3 L2): `clear` retains capacity; the buffer is reusable
// afterwards without re-growing as long as the retained capacity suffices.
// `slice()` is valid until the next append that grows.
//
// GREEN (contract): deterministic byte-exact stdout `buf clear ok\n` (RUNRC=0).
const std = @import("std");
const buf = @import("std_buf.zig");

var g_backing: [64]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn main() void {
    var b = std.buf.init(&g_arena);
    var hello: []const u8 = "hello";
    std.buf.append(&b, hello) catch {
        g_fail += 1;
    };
    // init 0 -> 1 -> 2 -> 4 -> 8 for five bytes.
    ck(std.buf.capacity(&b) == 8, "capacity after hello");
    ck(eq(std.buf.slice(&b), "hello"), "hello content");

    std.buf.clear(&b);
    ck(std.buf.capacity(&b) == 8, "clear retains capacity");
    ck(std.buf.slice(&b).len == 0, "clear empties slice");

    // Reuse: 5 bytes fit in the retained capacity -> no growth, no new arena
    // allocation, and the reused bytes are exactly the new content.
    var world: []const u8 = "world";
    std.buf.append(&b, world) catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 8, "reuse does not grow");
    ck(eq(std.buf.slice(&b), "world"), "reuse content");

    // clear is safe on an already-empty buffer.
    std.buf.clear(&b);
    std.buf.clear(&b);
    ck(std.buf.slice(&b).len == 0, "double clear empty");

    std.buf.appendByte(&b, 'X') catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 8, "byte after clear does not grow");
    ck(eq(std.buf.slice(&b), "X"), "byte after clear content");

    if (g_fail == 0) {
        std.io.write("buf clear ok\n");
    } else {
        std.io.write("buf clear FAIL\n");
    }
}
