// stdlib_buf_growth_xmod — STDLIB std_buf (L2) doubling-growth GREEN fixture.
//
// Contract (blueprint §3 L2): growable byte buffer over an arena; growth is
// doubling; `slice()` is valid until the next append that grows; `clear`
// retains capacity; no `deinit`. This fixture imports std_buf directly by
// module basename AND smoke-checks the `std.buf` re-export.
//
// Capacity trace pinned here (init starts at 0):
//   append 'A' -> 0->1     append 'B' -> 1->2   (doubling 1)
//   append 'C' -> 2->4     (doubling 2)
//   append 'D' -> 4        (no growth: len 3 + 1 == 4)
//   append 'E' -> 4->8     (doubling 3)
//   reserve(200) at len 5  -> 8->256 (data preserved)
//
// GREEN (contract): deterministic byte-exact stdout `buf growth ok\n` (RUNRC=0).
const std = @import("std");
const buf = @import("std_buf.zig");

var g_backing: [512]u8 = undefined;
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
    ck(std.buf.capacity(&b) == 0, "init capacity 0");
    ck(std.buf.slice(&b).len == 0, "init slice empty");

    std.buf.appendByte(&b, 'A') catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 1, "cap 1 after first byte");
    ck(eq(std.buf.slice(&b), "A"), "A content");

    std.buf.appendByte(&b, 'B') catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 2, "cap 2 (doubling 1)");
    ck(eq(std.buf.slice(&b), "AB"), "AB content");

    std.buf.appendByte(&b, 'C') catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 4, "cap 4 (doubling 2)");
    ck(eq(std.buf.slice(&b), "ABC"), "ABC content");

    std.buf.appendByte(&b, 'D') catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 4, "cap 4 no growth at len 3->4");
    ck(eq(std.buf.slice(&b), "ABCD"), "ABCD content");

    std.buf.appendByte(&b, 'E') catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 8, "cap 8 (doubling 3)");
    ck(eq(std.buf.slice(&b), "ABCDE"), "ABCDE content");

    // reserve past the three doublings: 8 -> 16 -> 32 -> 64 -> 128 -> 256.
    std.buf.reserve(&b, 200) catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 256, "reserve cap 256");
    ck(eq(std.buf.slice(&b), "ABCDE"), "reserve preserves data");

    // append([]const u8) fits in the reserved capacity (no growth).
    var tail: []const u8 = "fghij";
    std.buf.append(&b, tail) catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b) == 256, "append slice no growth");
    ck(eq(std.buf.slice(&b), "ABCDEfghij"), "append slice content");

    // initCapacity gives an exact non-growing capacity.
    var b2 = std.buf.initCapacity(&g_arena, 32) catch {
        g_fail += 1;
        return;
    };
    ck(std.buf.capacity(&b2) == 32, "initCapacity 32");
    ck(std.buf.slice(&b2).len == 0, "initCapacity len 0");

    // std.buf re-export smoke check.
    var cap: usize = std.buf.capacity(&b);
    ck(cap == 256, "std.buf re-export");

    if (g_fail == 0) {
        std.io.write("buf growth ok\n");
    } else {
        std.io.write("buf growth FAIL\n");
    }
}
