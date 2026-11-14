// stdlib_base64_oom_xmod — STDLIB std_base64 (L5) arena-exhaustion GREEN fixture.
//
// Contract (blueprint §3 L5 + §1 R1): encode/decode allocate only their output
// from the caller's arena; when the arena cannot satisfy the request the error
// is exactly error.OutOfMemory, no byte outside the arena is written, and
// arena.used is unchanged. An INVALID decode input returns error.InvalidInput
// without allocating (arena.used unchanged); a VALID empty input returns a
// length-0 slice (no error) and also leaves arena.used unchanged.
//
// Layout: a 512-byte storage array; each case fills it 0xAB, hands a sub-slice
// to the arena, and asserts:
//   - the call reports exactly error.OutOfMemory (or, for invalid input,
//     error.InvalidInput);
//   - arena.used is unchanged after a failing/rejecting call;
//   - every byte OUTSIDE the arena region and every unused byte INSIDE it is
//     still 0xAB (no out-of-arena or over-arena write).
//
// Cases:
//   A. encode 4 bytes (needs 8) on a 7-byte arena -> OOM.
//   B. encode 1 byte (needs 4) on a 3-byte arena -> OOM.
//   C. decode "Zm9v" (needs 3) on a 2-byte arena -> OOM.
//   D. encode with exactly enough room succeeds; used advances by encodedLen.
//   E. decode with exactly enough room succeeds; used advances by the decoded
//      length (3), not by decodedLen's upper bound (also 3 here).
//   F. invalid decode returns error.InvalidInput and does not consume the arena.
//   G. valid empty decode returns a length-0 slice (no error), used unchanged.
//
// GREEN (contract): deterministic byte-exact stdout `base64 oom ok\n`
// (RUNRC=0).
const std = @import("std");
const b64 = @import("std_base64.zig");

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

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
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
    var got = b64.encode(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

fn decOom(ar: *std.arena.Arena, src: []const u8) bool {
    var got = b64.decode(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

fn decInvalid(ar: *std.arena.Arena, src: []const u8) bool {
    var got = b64.decode(ar, src) catch |e| {
        if (e == error.InvalidInput) return true;
        return false;
    };
    _ = got;
    return false;
}

pub fn main() void {
    var srcA = [_]u8{ 'A', 'A', 'A', 'A' };
    var srcB = [_]u8{'A'};
    var srcC: []const u8 = "Zm9v";

    // ---- A: encode 4 bytes needs 8, arena has 7 ---------------------------
    fillAll();
    var arA = std.arena.init(g_storage[8..15]);
    ck(b64.encodedLen(srcA.len) == 8, "A encodedLen");
    ck(encOom(&arA, srcA[0..]), "A encode OutOfMemory");
    ck(arA.used == 0, "A used unchanged");
    checkOutside(8, 15, "A guard");
    checkTail(8, arA.used, arA.capacity, "A tail");

    // ---- B: encode 1 byte needs 4, arena has 3 ----------------------------
    fillAll();
    var arB = std.arena.init(g_storage[8..11]);
    ck(encOom(&arB, srcB[0..]), "B encode OutOfMemory");
    ck(arB.used == 0, "B used unchanged");
    checkOutside(8, 11, "B guard");
    checkTail(8, arB.used, arB.capacity, "B tail");

    // ---- C: decode "Zm9v" needs 3, arena has 2 ----------------------------
    fillAll();
    var arC = std.arena.init(g_storage[8..10]);
    ck(decOom(&arC, srcC), "C decode OutOfMemory");
    ck(arC.used == 0, "C used unchanged");
    checkOutside(8, 10, "C guard");
    checkTail(8, arC.used, arC.capacity, "C tail");

    // ---- D: encode with exactly enough room -------------------------------
    fillAll();
    var arD = std.arena.init(g_storage[8..16]);
    var gotD = b64.encode(&arD, srcA[0..]) catch {
        @panic("D encode");
    };
    ck(gotD.len == 8, "D len");
    ck(arD.used == 8, "D used exact");
    ckBytes(gotD, "QUFBQQ==", "D value");
    checkOutside(8, 16, "D guard");

    // ---- E: decode with exactly enough room -------------------------------
    fillAll();
    var arE = std.arena.init(g_storage[8..11]);
    var gotE = b64.decode(&arE, srcC) catch {
        @panic("E decode");
    };
    ck(gotE.len == 3, "E len");
    ck(arE.used == 3, "E used exact");
    ckBytes(gotE, "foo", "E value");
    checkOutside(8, 11, "E guard");

    // ---- F: invalid decode errors and allocates nothing -------------------
    fillAll();
    var arF = std.arena.init(g_storage[8..12]);
    ck(decInvalid(&arF, "Zm9\n"), "F decode InvalidInput");
    ck(arF.used == 0, "F used unchanged");
    checkOutside(8, 12, "F guard");

    // ---- G: valid empty decode is a length-0 slice, no error --------------
    fillAll();
    var arG = std.arena.init(g_storage[8..12]);
    var eG: [1]u8 = undefined;
    var gotG = b64.decode(&arG, eG[0..0]) catch {
        @panic("G empty decode");
    };
    ck(gotG.len == 0, "G empty");
    ck(arG.used == 0, "G used unchanged");
    checkOutside(8, 12, "G guard");

    if (g_fail == 0) {
        std.io.write("base64 oom ok\n");
    } else {
        std.io.write("base64 oom FAIL\n");
    }
}
