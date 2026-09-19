// stdlib_rle_oom_xmod — std_rle (L4) arena-exhaustion GREEN fixture (R1).
//
// Contract (blueprint §3 L4 + §1 R1): `encode`/`decode` allocate only their
// output from the caller's arena; when the arena cannot satisfy the request the
// error is exactly `error.OutOfMemory`, no byte outside the arena is written,
// and `arena.used` is unchanged.
//
// Layout: a 512-byte storage array; each case fills it 0xAB, hands a sub-slice
// to the arena, and after the forced failure asserts:
//   - the call reports exactly `error.OutOfMemory`;
//   - `arena.used` is unchanged from before the failing call;
//   - every byte OUTSIDE the arena region is still 0xAB (no out-of-arena write);
//   - every byte INSIDE the arena beyond `used` is still 0xAB (no over-write).
//
// Cases:
//   A. encode 4 bytes (needs 6) on a 5-byte arena -> OOM.
//   B. encode empty input (needs the 4-byte prefix) on a 3-byte arena -> OOM.
//   C. decode a 16-byte stream on a 15-byte arena -> OOM.
//   D. encode with exactly enough room succeeds and advances `used` by exactly
//      `encodedLen`.
//   E. decode with exactly enough room succeeds and advances `used` by exactly
//      `decodedLen`.
//
// GREEN (contract): deterministic byte-exact stdout `rle oom ok\n` (RUNRC=0).
const std = @import("std");
const rle = @import("std_rle.zig");

const GUARD: u8 = 0xAB;
const STORAGE: usize = 512;

var g_storage: [STORAGE]u8 = undefined;
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn fillAll() void {
    var i: usize = 0;
    while (i < STORAGE) : (i += 1) {
        g_storage[i] = GUARD;
    }
}

fn checkOutside(lo: usize, hi: usize, what: []const u8) void {
    var i: usize = 0;
    while (i < lo) : (i += 1) {
        ck(g_storage[i] == GUARD, what);
    }
    i = hi;
    while (i < STORAGE) : (i += 1) {
        ck(g_storage[i] == GUARD, what);
    }
}

fn checkTail(off: usize, used: usize, cap: usize, what: []const u8) void {
    var i: usize = off + used;
    while (i < off + cap) : (i += 1) {
        ck(g_storage[i] == GUARD, what);
    }
}

fn encOom(ar: *std.arena.Arena, src: []const u8) bool {
    var got = rle.encode(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

fn decOom(ar: *std.arena.Arena, src: []const u8) bool {
    var got = rle.decode(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

pub fn main() void {
    // ---- A: encode 4 bytes needs 6, arena has 5 ---------------------------
    fillAll();
    var arA = std.arena.init(g_storage[8..13]);
    var srcA = [_]u8{ 'A', 'A', 'A', 'A' };
    ck(rle.encodedLen(srcA[0..]) == 6, "A encodedLen");
    ck(encOom(&arA, srcA[0..]), "A encode OutOfMemory");
    ck(arA.used == 0, "A used unchanged");
    checkOutside(8, 13, "A guard");
    checkTail(8, arA.used, arA.capacity, "A tail");

    // ---- B: encode empty needs 4, arena has 3 -----------------------------
    fillAll();
    var arB = std.arena.init(g_storage[8..11]);
    var eB: [1]u8 = undefined;
    ck(encOom(&arB, eB[0..0]), "B encode OutOfMemory");
    ck(arB.used == 0, "B used unchanged");
    checkOutside(8, 11, "B guard");
    checkTail(8, arB.used, arB.capacity, "B tail");

    // ---- C: decode a 16-byte stream, arena has 15 -------------------------
    fillAll();
    var arC = std.arena.init(g_storage[8..23]);
    var srcC = [_]u8{ 16, 0, 0, 0, 0x8F, 0x41 };
    ck(rle.decodedLen(srcC[0..]) == 16, "C decodedLen");
    ck(decOom(&arC, srcC[0..]), "C decode OutOfMemory");
    ck(arC.used == 0, "C used unchanged");
    checkOutside(8, 23, "C guard");
    checkTail(8, arC.used, arC.capacity, "C tail");

    // ---- D: encode with exactly enough room -------------------------------
    fillAll();
    var arD = std.arena.init(g_storage[8..14]);
    var srcD = [_]u8{ 'A', 'A', 'A', 'A' };
    var gotD = rle.encode(&arD, srcD[0..]) catch {
        @panic("D encode");
    };
    ck(gotD.len == 6, "D len");
    ck(arD.used == 6, "D used exact");
    checkOutside(8, 14, "D guard");

    // ---- E: decode with exactly enough room -------------------------------
    fillAll();
    var arE = std.arena.init(g_storage[8..24]);
    var gotE = rle.decode(&arE, srcC[0..]) catch {
        @panic("E decode");
    };
    ck(gotE.len == 16, "E len");
    ck(arE.used == 16, "E used exact");
    checkOutside(8, 24, "E guard");
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        ck(gotE[i] == 0x41, "E value");
    }

    if (g_fail == 0) {
        std.io.write("rle oom ok\n");
    } else {
        std.io.write("rle oom FAIL\n");
    }
}
