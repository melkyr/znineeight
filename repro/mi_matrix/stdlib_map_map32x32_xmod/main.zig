// stdlib_map_map32x32_xmod — std_map (L4) Map32x32 GREEN fixture.
//
// Contract (blueprint §3 L4): `map32x32Init(arena, capacity) !Map32x32`,
// `map32x32Get(m, key) ?u32`, `map32x32Put(m, key, val) !void`,
// `map32x32Remove(m, key) bool`, `map32x32Len(m) usize`. Open addressing,
// linear probing; `put` on an existing key replaces; a new key on a full table
// is `error.OutOfMemory`; `remove` leaves a tombstone so probe chains survive.
//
// Cases pinned:
//   - collision/load stress: capacity 64 filled with 64 distinct keys, every
//     Get returns its value (probe chains cross the whole table);
//   - key 0 and 0xFFFFFFFF are real keys (no sentinel collision);
//   - missing key -> null; full-table new key -> OutOfMemory, len unchanged;
//   - replace existing key changes the value but not len;
//   - remove existing -> true, again -> false, Get -> null, len decreases;
//   - re-put after remove reuses the tombstone and restores len;
//   - capacity 1: put, replace, remove, re-put, full-table OOM.
//
// GREEN (contract): deterministic byte-exact stdout `map32x32 ok\n` (RUNRC=0).
const std = @import("std");
const map = @import("std_map.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantU32(m: *map.Map32x32, key: u32, want: u32, what: []const u8) void {
    var got = map.map32x32Get(m, key);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    var backing: [8192]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var m = map.map32x32Init(&ar, 64) catch {
        @panic("init 64");
    };
    ck(map.map32x32Len(&m) == 0, "fresh len 0");

    // Fill the table completely: 64 distinct keys in 64 slots.
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        map.map32x32Put(&m, i, i * 7 + 1) catch {
            @panic("put fill");
        };
    }
    ck(map.map32x32Len(&m) == 64, "len 64");

    i = 0;
    while (i < 64) : (i += 1) {
        wantU32(&m, i, i * 7 + 1, "get filled");
    }

    // Sentinel-looking keys are ordinary keys.
    ck(map.map32x32Get(&m, 999) == null, "missing null");

    var oom = false;
    map.map32x32Put(&m, 1000, 5) catch |e| {
        if (e == error.OutOfMemory) oom = true;
    };
    ck(oom, "full table OutOfMemory");
    ck(map.map32x32Len(&m) == 64, "len after OOM");
    wantU32(&m, 0, 1, "key 0 intact after OOM");
    wantU32(&m, 63, 442, "key 63 intact after OOM");

    // Replace existing key.
    map.map32x32Put(&m, 5, 12345) catch {
        @panic("replace");
    };
    ck(map.map32x32Len(&m) == 64, "len after replace");
    wantU32(&m, 5, 12345, "replaced value");

    // Remove + tombstone reuse.
    ck(map.map32x32Remove(&m, 5), "remove true");
    ck(map.map32x32Remove(&m, 5) == false, "remove twice false");
    ck(map.map32x32Get(&m, 5) == null, "removed get null");
    ck(map.map32x32Len(&m) == 63, "len after remove");

    map.map32x32Put(&m, 5, 77) catch {
        @panic("re-put");
    };
    ck(map.map32x32Len(&m) == 64, "len after re-put");
    wantU32(&m, 5, 77, "re-put value");

    // Remove half; the rest must still resolve through the tombstones.
    i = 0;
    while (i < 32) : (i += 1) {
        ck(map.map32x32Remove(&m, i), "remove first half");
    }
    ck(map.map32x32Len(&m) == 32, "len after half remove");
    i = 32;
    while (i < 64) : (i += 1) {
        var want: u32 = i * 7 + 1;
        if (i == 5) want = 77;
        wantU32(&m, i, want, "remaining value");
    }

    // ---- capacity 1: every transition exercised at the smallest size ------
    var small_backing: [64]u8 = undefined;
    var sar = std.arena.init(small_backing[0..]);
    var sm = map.map32x32Init(&sar, 1) catch {
        @panic("init 1");
    };
    ck(map.map32x32Len(&sm) == 0, "small fresh len");
    map.map32x32Put(&sm, 0xFFFFFFFF, 0xDEADBEEF) catch {
        @panic("small put");
    };
    ck(map.map32x32Len(&sm) == 1, "small len 1");
    wantU32(&sm, 0xFFFFFFFF, 0xDEADBEEF, "small get");
    var soom = false;
    map.map32x32Put(&sm, 1, 2) catch |e| {
        if (e == error.OutOfMemory) soom = true;
    };
    ck(soom, "small full OOM");
    map.map32x32Put(&sm, 0xFFFFFFFF, 7) catch {
        @panic("small replace");
    };
    ck(map.map32x32Len(&sm) == 1, "small len after replace");
    wantU32(&sm, 0xFFFFFFFF, 7, "small replaced");
    ck(map.map32x32Remove(&sm, 0xFFFFFFFF), "small remove");
    ck(map.map32x32Len(&sm) == 0, "small len after remove");
    map.map32x32Put(&sm, 9, 9) catch {
        @panic("small re-put");
    };
    wantU32(&sm, 9, 9, "small re-put value");

    if (g_fail == 0) {
        std.io.write("map32x32 ok\n");
    } else {
        std.io.write("map32x32 FAIL\n");
    }
}
