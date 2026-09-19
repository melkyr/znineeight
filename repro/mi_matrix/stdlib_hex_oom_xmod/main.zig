// stdlib_hex_oom_xmod — STDLIB std_hex (L5) arena-exhaustion GREEN fixture.
//
// Contract (blueprint §3 L5 + §1 R1): encodeLower/encodeUpper/decode allocate
// only their output from the caller's arena; when the arena cannot satisfy the
// request the error is exactly error.OutOfMemory, no byte outside the arena is
// written, and arena.used is unchanged. An INVALID decode input needs no
// output, so it returns an empty slice and leaves arena.used unchanged.
//
// Layout: a 512-byte storage array; each case fills it 0xAB, hands a sub-slice
// to the arena, and asserts:
//   - the call reports exactly error.OutOfMemory (or, for invalid input, an
//     empty slice);
//   - arena.used is unchanged after a failing/rejecting call;
//   - every byte OUTSIDE the arena region and every unused byte INSIDE it is
//     still 0xAB (no out-of-arena or over-arena write).
//
// Cases:
//   A. encodeLower 4 bytes (needs 8) on a 7-byte arena -> OOM.
//   B. encodeUpper 1 byte (needs 2) on a 1-byte arena -> OOM.
//   C. decode "deadbeef" (needs 4) on a 3-byte arena -> OOM.
//   D. encodeLower with exactly enough room succeeds; used advances by 2*n.
//   E. encodeUpper with exactly enough room succeeds; used advances by 2*n.
//   F. decode with exactly enough room succeeds; used advances by n/2.
//   G. invalid decode returns length 0 and does not consume the arena.
//
// GREEN (contract): deterministic byte-exact stdout `hex oom ok\n` (RUNRC=0).
const std = @import("std");
const hex = @import("std_hex.zig");

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

fn encLOom(ar: *std.arena.Arena, src: []const u8) bool {
    var got = hex.encodeLower(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

fn encUOom(ar: *std.arena.Arena, src: []const u8) bool {
    var got = hex.encodeUpper(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

fn decOom(ar: *std.arena.Arena, src: []const u8) bool {
    var got = hex.decode(ar, src) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = got;
    return false;
}

pub fn main() void {
    var srcA = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var srcB = [_]u8{0x5A};
    var srcC: []const u8 = "deadbeef";

    // ---- A: encodeLower 4 bytes needs 8, arena has 7 ----------------------
    fillAll();
    var arA = std.arena.init(g_storage[8..15]);
    ck(encLOom(&arA, srcA[0..]), "A encodeLower OutOfMemory");
    ck(arA.used == 0, "A used unchanged");
    checkOutside(8, 15, "A guard");
    checkTail(8, arA.used, arA.capacity, "A tail");

    // ---- B: encodeUpper 1 byte needs 2, arena has 1 -----------------------
    fillAll();
    var arB = std.arena.init(g_storage[8..9]);
    ck(encUOom(&arB, srcB[0..]), "B encodeUpper OutOfMemory");
    ck(arB.used == 0, "B used unchanged");
    checkOutside(8, 9, "B guard");
    checkTail(8, arB.used, arB.capacity, "B tail");

    // ---- C: decode "deadbeef" needs 4, arena has 3 ------------------------
    fillAll();
    var arC = std.arena.init(g_storage[8..11]);
    ck(decOom(&arC, srcC), "C decode OutOfMemory");
    ck(arC.used == 0, "C used unchanged");
    checkOutside(8, 11, "C guard");
    checkTail(8, arC.used, arC.capacity, "C tail");

    // ---- D: encodeLower with exactly enough room --------------------------
    fillAll();
    var arD = std.arena.init(g_storage[8..16]);
    var gotD = hex.encodeLower(&arD, srcA[0..]) catch {
        @panic("D encodeLower");
    };
    ck(gotD.len == 8, "D len");
    ck(arD.used == 8, "D used exact");
    ckBytes(gotD, "deadbeef", "D value");
    checkOutside(8, 16, "D guard");

    // ---- E: encodeUpper with exactly enough room --------------------------
    fillAll();
    var arE = std.arena.init(g_storage[8..16]);
    var gotE = hex.encodeUpper(&arE, srcA[0..]) catch {
        @panic("E encodeUpper");
    };
    ck(gotE.len == 8, "E len");
    ck(arE.used == 8, "E used exact");
    ckBytes(gotE, "DEADBEEF", "E value");
    checkOutside(8, 16, "E guard");

    // ---- F: decode with exactly enough room -------------------------------
    fillAll();
    var arF = std.arena.init(g_storage[8..12]);
    var gotF = hex.decode(&arF, srcC) catch {
        @panic("F decode");
    };
    ck(gotF.len == 4, "F len");
    ck(arF.used == 4, "F used exact");
    ckBytes(gotF, srcA[0..], "F value");
    checkOutside(8, 12, "F guard");

    // ---- G: invalid decode allocates nothing ------------------------------
    fillAll();
    var arG = std.arena.init(g_storage[8..12]);
    var gotG = hex.decode(&arG, "deadbeef\n") catch {
        @panic("G decode");
    };
    ck(gotG.len == 0, "G empty");
    ck(arG.used == 0, "G used unchanged");
    checkOutside(8, 12, "G guard");

    if (g_fail == 0) {
        std.io.write("hex oom ok\n");
    } else {
        std.io.write("hex oom FAIL\n");
    }
}
