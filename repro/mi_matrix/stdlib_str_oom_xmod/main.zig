// stdlib_str_oom_xmod — std_str (L2) arena-exhaustion GREEN fixture (R1 / blueprint §5).
//
// Contract (blueprint §3 L2 + Global Constraint R1): the five allocating
// functions — `split`, `splitLines`, `join`, `replace`, `repeat` — allocate from
// the caller's arena and return `error.OutOfMemory` when it cannot satisfy the
// request. On that path the function must NOT trap and must NOT write outside
// the arena (no partial output, no corruption).
//
// Layout: a 32-byte storage array whose middle 16 bytes [8..24) back the arena;
// the 8-byte guards on either side are filled 0xAB. Every OOM case is forced by
// asking for MORE than 16 bytes with a fresh arena, then asserting:
//   - the call reports exactly `error.OutOfMemory`;
//   - `arena.used` is unchanged (still 0);
//   - both 8-byte guards AND the whole arena region are still 0xAB (no write at
//     all, inside or outside the arena).
//
// Covered (all five allocating functions):
//   split       "a,b,c" (3 parts -> 24B)                        OOM
//   splitLines  "a\nb\nc" (3 lines -> 24B)                      OOM
//   join        ["aaaaaaaaaa","bbbbbbbbbb"] sep "" (20B)        OOM
//   replace     ("abc","a",16-byte to) growth (18B)             OOM
//   replace     ("aaaaaaaaaaaaaaaaaaaa","","x") empty-from (20B) OOM
//   repeat      ("abcdefgh",3) (24B)                            OOM
// plus a positive control: a fresh 16-byte arena satisfies split("a,b")'s exact
// 16-byte request (proving the arena works and the OOMs are size-driven).
//
// The join input parts are produced by `std.str.split` over a SEPARATE arena
// (never `[N][]const u8 = undefined`, whose -ffast zero-fill is a known
// compiler defect outside this task's scope).
//
// GREEN (contract): deterministic byte-exact stdout `str oom ok\n` (RUNRC=0).
const std = @import("std");

var g_storage: [32]u8 = undefined;
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn guardFill() void {
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        g_storage[i] = 0xAB;
    }
}

fn checkGuards(what: []const u8) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        ck(g_storage[i] == 0xAB, what);
    }
    i = 24;
    while (i < 32) : (i += 1) {
        ck(g_storage[i] == 0xAB, what);
    }
}

fn checkArenaUntouched(what: []const u8) void {
    var i: usize = 8;
    while (i < 24) : (i += 1) {
        ck(g_storage[i] == 0xAB, what);
    }
}

fn newArena() std.arena.Arena {
    return std.arena.init(g_storage[8..24]);
}

fn oomSplit(ar: *std.arena.Arena, s: []const u8, sep: u8) bool {
    _ = std.str.split(ar, s, sep) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    return false;
}

fn oomSplitLines(ar: *std.arena.Arena, s: []const u8) bool {
    _ = std.str.splitLines(ar, s) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    return false;
}

fn oomJoin(ar: *std.arena.Arena, parts: [][]const u8, sep: []const u8) bool {
    _ = std.str.join(ar, parts, sep) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    return false;
}

fn oomReplace(ar: *std.arena.Arena, s: []const u8, from: []const u8, to: []const u8) bool {
    _ = std.str.replace(ar, s, from, to) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    return false;
}

fn oomRepeat(ar: *std.arena.Arena, s: []const u8, n: usize) bool {
    _ = std.str.repeat(ar, s, n) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    return false;
}

pub fn main() void {
    // ---- split: 3 parts need 3*8 = 24B > 16B -------------------------------
    guardFill();
    var ar = newArena();
    var s1: []const u8 = "a,b,c";
    ck(oomSplit(&ar, s1, ','), "split OutOfMemory");
    ck(ar.used == 0, "split used unchanged");
    checkGuards("split guard");
    checkArenaUntouched("split arena untouched");

    // ---- splitLines: 3 lines need 24B > 16B -------------------------------
    guardFill();
    ar = newArena();
    var s2: []const u8 = "a\nb\nc";
    ck(oomSplitLines(&ar, s2), "splitLines OutOfMemory");
    ck(ar.used == 0, "splitLines used unchanged");
    checkGuards("splitLines guard");
    checkArenaUntouched("splitLines arena untouched");

    // ---- join: total 20B > 16B; parts built over a separate arena ---------
    var pstorage: [64]u8 = undefined;
    var par = std.arena.init(pstorage[0..]);
    var csv: []const u8 = "aaaaaaaaaa,bbbbbbbbbb";
    var parts = std.str.split(&par, csv, ',') catch {
        @panic("join parts setup");
    };
    ck(parts.len == 2, "join parts count");
    guardFill();
    ar = newArena();
    var empty: []const u8 = "";
    ck(oomJoin(&ar, parts, empty), "join OutOfMemory");
    ck(ar.used == 0, "join used unchanged");
    checkGuards("join guard");
    checkArenaUntouched("join arena untouched");

    // ---- replace growth: "abc" - "a" + 16-byte to => 18B > 16B ------------
    guardFill();
    ar = newArena();
    var s3: []const u8 = "abc";
    var from1: []const u8 = "a";
    var to1: []const u8 = "0123456789ABCDEF";
    ck(oomReplace(&ar, s3, from1, to1), "replace growth OutOfMemory");
    ck(ar.used == 0, "replace growth used unchanged");
    checkGuards("replace growth guard");
    checkArenaUntouched("replace growth arena untouched");

    // ---- replace empty-from path: copies s.len (20B) > 16B ----------------
    guardFill();
    ar = newArena();
    var s4: []const u8 = "aaaaaaaaaaaaaaaaaaaa";
    var nofrom: []const u8 = "";
    var to2: []const u8 = "x";
    ck(oomReplace(&ar, s4, nofrom, to2), "replace empty-from OutOfMemory");
    ck(ar.used == 0, "replace empty-from used unchanged");
    checkGuards("replace empty-from guard");
    checkArenaUntouched("replace empty-from arena untouched");

    // ---- repeat: 8 * 3 = 24B > 16B ----------------------------------------
    guardFill();
    ar = newArena();
    var s5: []const u8 = "abcdefgh";
    ck(oomRepeat(&ar, s5, 3), "repeat OutOfMemory");
    ck(ar.used == 0, "repeat used unchanged");
    checkGuards("repeat guard");
    checkArenaUntouched("repeat arena untouched");

    // ---- positive control: a fresh 16B arena satisfies split("a,b") exactly
    guardFill();
    ar = newArena();
    var s6: []const u8 = "a,b";
    var ok = std.str.split(&ar, s6, ',') catch {
        @panic("split positive control");
    };
    ck(ok.len == 2, "positive count");
    ck(std.str.eql(ok[0], "a") and std.str.eql(ok[1], "b"), "positive parts");
    ck(ar.used == 16, "positive used == capacity");

    if (g_fail == 0) {
        std.io.write("str oom ok\n");
    } else {
        std.io.write("str oom FAIL\n");
    }
}
