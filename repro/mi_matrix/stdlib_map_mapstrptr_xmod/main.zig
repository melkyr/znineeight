// stdlib_map_mapstrptr_xmod — std_map (L4) MapStrPtr GREEN fixture.
//
// Contract (blueprint §3 L4): `mapStrPtrInit(arena, capacity) !MapStrPtr`,
// `mapStrPtrGet(m, key) ?*void`, `mapStrPtrPut(m, key, val) !void`,
// `mapStrPtrRemove(m, key) bool`, `mapStrPtrLen(m) usize`. String keys are
// COPIED into the arena at put, so a stored key's lifetime is independent of
// the caller's source buffer; lookup is by byte content, not by slice identity.
//
// Cases pinned:
//   - put "hello" from a mutable source buffer, then MUTATE the buffer: the
//     stored key is still found by an equal-content slice from other memory
//     and NOT found under the mutated bytes (copy-on-put);
//   - replace an existing key keeps len and changes the value;
//   - remove by equal-content slice from different memory -> true, Get -> null,
//     len decreases, remove again -> false;
//   - the empty string is an ordinary key;
//   - several distinct keys coexist and resolve correctly.
//
// GREEN (contract): deterministic byte-exact stdout `mapstrptr ok\n` (RUNRC=0).
const std = @import("std");
const map = @import("std_map.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantPtr(m: *map.MapStrPtr, key: []const u8, want: *void, what: []const u8) void {
    var got = map.mapStrPtrGet(m, key);
    if (got) |v| {
        ck(@ptrToInt(v) == @ptrToInt(want), what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    var v1: u32 = 1;
    var v2: u32 = 2;
    var v3: u32 = 3;
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);
    var p3: *void = @ptrCast(*void, &v3);

    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var m = map.mapStrPtrInit(&ar, 16) catch {
        @panic("init");
    };
    ck(map.mapStrPtrLen(&m) == 0, "fresh len 0");

    // ---- copy-on-put: mutate the source after put -------------------------
    var kbuf: [5]u8 = undefined;
    std.str.copy(kbuf[0..], "hello");
    var key: []const u8 = kbuf[0..5];
    map.mapStrPtrPut(&m, key, p1) catch {
        @panic("put hello");
    };
    ck(map.mapStrPtrLen(&m) == 1, "len after put");
    kbuf[0] = 'j';

    var probe: [5]u8 = undefined;
    std.str.copy(probe[0..], "hello");
    wantPtr(&m, probe[0..5], p1, "stored key survives mutation");

    var mutated: [5]u8 = undefined;
    std.str.copy(mutated[0..], "jello");
    ck(map.mapStrPtrGet(&m, mutated[0..5]) == null, "mutated bytes not a key");

    // ---- replace existing key ---------------------------------------------
    map.mapStrPtrPut(&m, probe[0..5], p2) catch {
        @panic("replace hello");
    };
    ck(map.mapStrPtrLen(&m) == 1, "len after replace");
    wantPtr(&m, probe[0..5], p2, "replaced value");

    // ---- remove by equal content from a different buffer ------------------
    var other: [5]u8 = undefined;
    std.str.copy(other[0..], "hello");
    ck(map.mapStrPtrRemove(&m, other[0..5]), "remove by content");
    ck(map.mapStrPtrRemove(&m, other[0..5]) == false, "remove twice false");
    ck(map.mapStrPtrGet(&m, other[0..5]) == null, "removed get null");
    ck(map.mapStrPtrLen(&m) == 0, "len after remove");

    // ---- empty string is an ordinary key ----------------------------------
    var empty: []const u8 = "";
    map.mapStrPtrPut(&m, empty, p3) catch {
        @panic("put empty");
    };
    ck(map.mapStrPtrLen(&m) == 1, "len after empty put");
    wantPtr(&m, empty, p3, "empty key get");
    ck(map.mapStrPtrRemove(&m, empty), "remove empty");
    ck(map.mapStrPtrLen(&m) == 0, "len after empty remove");

    // ---- several distinct keys coexist ------------------------------------
    map.mapStrPtrPut(&m, "alpha", p1) catch {
        @panic("put alpha");
    };
    map.mapStrPtrPut(&m, "beta", p2) catch {
        @panic("put beta");
    };
    map.mapStrPtrPut(&m, "gamma", p3) catch {
        @panic("put gamma");
    };
    map.mapStrPtrPut(&m, "alpha", p3) catch {
        @panic("replace alpha");
    };
    ck(map.mapStrPtrLen(&m) == 3, "len after three");
    wantPtr(&m, "alpha", p3, "alpha replaced");
    wantPtr(&m, "beta", p2, "beta value");
    wantPtr(&m, "gamma", p3, "gamma value");
    ck(map.mapStrPtrGet(&m, "delta") == null, "delta missing");
    ck(map.mapStrPtrRemove(&m, "beta"), "remove beta");
    ck(map.mapStrPtrGet(&m, "beta") == null, "beta gone");
    ck(map.mapStrPtrLen(&m) == 2, "len after beta remove");

    if (g_fail == 0) {
        std.io.write("mapstrptr ok\n");
    } else {
        std.io.write("mapstrptr FAIL\n");
    }
}
