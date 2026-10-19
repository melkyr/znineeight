// stdlib_map_robinhood_xmod — std_map (L4) Robin Hood invariants fixture.
//
// Pins the observables that a probing map must preserve across the internals
// upgrade: every inserted key stays reachable under reverse-insertion order,
// deletion never hides a later key in the probe chain (delete/reinsert, delete
// half, churn), overwriting an existing key never changes len, and the caller
// capacity remains the OOM boundary.
//
// Cases:
//   - reverse-insertion: 1000 keys inserted descending, all lookups succeed;
//   - delete-reinsert: delete 500, reinsert, all lookups succeed;
//   - delete-half: remove every even key, odd keys resolve, evens null;
//   - overwrite: re-put an existing key replaces the value, len unchanged;
//   - fill: capacity N -> N puts succeed, a new key -> error.OutOfMemory;
//   - adversarial same-home cluster: 257 keys sharing one home slot, delete
//     the head, every survivor still resolves (a stored u8 distance wraps);
//   - ctrl encoding: every slot is 0x80 (empty) or a 7-bit hash fragment;
//     0xFE never appears, in steady state and after deletions;
//   - churn: 10k put/remove cycles over a bounded key space; every survivor
//     resolves (checked periodically and at the end; no infinite loop).
//
// GREEN (contract): deterministic byte-exact stdout `map robinhood ok\n`
// (RUNRC=0).
const std = @import("std");
const map = @import("std_map.zig");

var g_fail: u32 = 0;

// Fixture-side copy of std_map's mix32, used only to target one home slot.
fn mix32(x0: u32) u32 {
    var x: u32 = x0;
    x = x ^ (x >> 16);
    x = x *% 0x7feb352d;
    x = x ^ (x >> 15);
    x = x *% 0x846ca68b;
    x = x ^ (x >> 16);
    return x;
}

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

// Steady-state ctrl byte: 0x80 empty, or the record's own 7-bit hash fragment.
// 0xFE (reserved) and the old 0/1/2 codes as control values never appear.
fn checkCtrl(m: *map.Map32x32, what: []const u8) void {
    var s: usize = 0;
    while (s <= m.mask) : (s += 1) {
        var st: u8 = m.entries[s].state;
        ck(st != 0xFE, what);
        if (st != 0x80) {
            ck(st <= 0x7F, what);
            var frag: u8 = @intCast(u8, mix32(m.entries[s].key) & 0x7F);
            ck(st == frag, what);
        }
    }
}

fn put32(m: *map.Map32x32, key: u32, val: u32, what: []const u8) void {
    map.map32x32Put(m, key, val) catch {
        @panic(what);
    };
}

fn want32(m: *map.Map32x32, key: u32, want: u32, what: []const u8) void {
    var got = map.map32x32Get(m, key);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn verifyChurn(m: *map.Map32x32, present: []const u8, expected: []const u32) void {
    var j: usize = 0;
    while (j < 64) : (j += 1) {
        var got = map.map32x32Get(m, @intCast(u32, j));
        if (present[j] == 1) {
            if (got) |v| {
                ck(v == expected[j], "churn survivor value");
            } else {
                ck(false, "churn survivor missing");
            }
        } else {
            ck(got == null, "churn removed key present");
        }
    }
}

pub fn main() void {
    // ---- reverse insertion + delete/reinsert + delete-half ----------------
    var back_main: [65536]u8 = undefined;
    var ar_main = std.arena.init(back_main[0..]);
    var m = map.map32x32Init(&ar_main, 1000) catch {
        @panic("init main");
    };

    var i: u32 = 1000;
    while (i > 0) : (i -= 1) {
        put32(&m, i, i * 3 + 1, "reverse put");
    }
    ck(map.map32x32Len(&m) == 1000, "reverse len 1000");
    i = 1;
    while (i <= 1000) : (i += 1) {
        want32(&m, i, i * 3 + 1, "reverse get");
    }
    checkCtrl(&m, "reverse ctrl");

    // delete 500, then reinsert them with new values
    i = 1;
    while (i <= 500) : (i += 1) {
        ck(map.map32x32Remove(&m, i), "delete-reinsert remove");
    }
    ck(map.map32x32Len(&m) == 500, "delete-reinsert len 500");
    i = 1;
    while (i <= 500) : (i += 1) {
        ck(map.map32x32Get(&m, i) == null, "deleted key absent");
    }
    i = 1;
    while (i <= 500) : (i += 1) {
        put32(&m, i, i * 5 + 2, "delete-reinsert put");
    }
    ck(map.map32x32Len(&m) == 1000, "delete-reinsert len 1000");
    i = 1;
    while (i <= 1000) : (i += 1) {
        if (i <= 500) {
            want32(&m, i, i * 5 + 2, "delete-reinsert get");
        } else {
            want32(&m, i, i * 3 + 1, "delete-reinsert old get");
        }
    }
    checkCtrl(&m, "delete-reinsert ctrl");

    // remove every even key; odds must still resolve through the shifted slots
    i = 2;
    while (i <= 1000) : (i += 2) {
        ck(map.map32x32Remove(&m, i), "delete-half remove");
    }
    ck(map.map32x32Len(&m) == 500, "delete-half len 500");
    i = 1;
    while (i <= 1000) : (i += 2) {
        if (i <= 500) {
            want32(&m, i, i * 5 + 2, "delete-half odd value");
        } else {
            want32(&m, i, i * 3 + 1, "delete-half odd old value");
        }
    }
    i = 2;
    while (i <= 1000) : (i += 2) {
        ck(map.map32x32Get(&m, i) == null, "delete-half even absent");
    }
    checkCtrl(&m, "delete-half ctrl");

    // overwrite: existing key replaces value, len unchanged
    var before: usize = map.map32x32Len(&m);
    put32(&m, 1, 0xABCD, "overwrite put");
    ck(map.map32x32Len(&m) == before, "overwrite len unchanged");
    want32(&m, 1, 0xABCD, "overwrite value");

    // ---- fill to caller capacity, then OOM --------------------------------
    var back_fill: [8192]u8 = undefined;
    var ar_fill = std.arena.init(back_fill[0..]);
    var fm = map.map32x32Init(&ar_fill, 100) catch {
        @panic("init fill");
    };
    var f: u32 = 0;
    while (f < 100) : (f += 1) {
        put32(&fm, f, f * 2 + 1, "fill put");
    }
    ck(map.map32x32Len(&fm) == 100, "fill len 100");
    var oom = false;
    map.map32x32Put(&fm, 100, 1) catch |e| {
        if (e == error.OutOfMemory) oom = true;
    };
    ck(oom, "fill OOM");
    ck(map.map32x32Len(&fm) == 100, "fill len after OOM");
    f = 0;
    while (f < 100) : (f += 1) {
        want32(&fm, f, f * 2 + 1, "fill value intact");
    }
    checkCtrl(&fm, "fill ctrl");

    // ---- adversarial same-home cluster (stored u8 distance would wrap) ----
    var back_adv: [8192]u8 = undefined;
    var ar_adv = std.arena.init(back_adv[0..]);
    var am = map.map32x32Init(&ar_adv, 300) catch {
        @panic("init adversarial");
    };
    var adv_keys: [257]u32 = undefined;
    var want_home: usize = @intCast(usize, mix32(0)) & am.mask;
    var found: usize = 0;
    var cand: u32 = 0;
    while (found < 257) : (cand += 1) {
        if ((@intCast(usize, mix32(cand)) & am.mask) == want_home) {
            adv_keys[found] = cand;
            found += 1;
        }
    }
    var a: usize = 0;
    while (a < 257) : (a += 1) {
        put32(&am, adv_keys[a], adv_keys[a] + 1, "adversarial put");
    }
    ck(map.map32x32Len(&am) == 257, "adversarial len 257");
    checkCtrl(&am, "adversarial ctrl after insert");
    a = 0;
    while (a < 257) : (a += 1) {
        want32(&am, adv_keys[a], adv_keys[a] + 1, "adversarial get");
    }
    ck(map.map32x32Remove(&am, adv_keys[0]), "adversarial remove head");
    ck(map.map32x32Get(&am, adv_keys[0]) == null, "adversarial head absent");
    ck(map.map32x32Len(&am) == 256, "adversarial len after delete");
    a = 1;
    while (a < 257) : (a += 1) {
        want32(&am, adv_keys[a], adv_keys[a] + 1, "adversarial survivor");
    }
    checkCtrl(&am, "adversarial ctrl after delete");

    // ---- churn: 10k put/remove cycles over a bounded key space ------------
    var back_churn: [16384]u8 = undefined;
    var ar_churn = std.arena.init(back_churn[0..]);
    var cm = map.map32x32Init(&ar_churn, 128) catch {
        @panic("init churn");
    };
    var present: [64]u8 = undefined;
    var expected: [64]u32 = undefined;
    var z: usize = 0;
    while (z < 64) : (z += 1) {
        present[z] = 0;
        expected[z] = 0;
    }

    var c: u32 = 0;
    while (c < 10000) : (c += 1) {
        var k: u32 = c % 64;
        var v: u32 = c * 2 + 1;
        put32(&cm, k, v, "churn put");
        present[k] = 1;
        expected[k] = v;
        var r: u32 = (c + 32) % 64;
        _ = map.map32x32Remove(&cm, r);
        present[r] = 0;
        expected[r] = 0;
        if (c % 500 == 0) {
            verifyChurn(&cm, present[0..64], expected[0..64]);
        }
    }
    verifyChurn(&cm, present[0..64], expected[0..64]);
    checkCtrl(&cm, "churn ctrl");

    if (g_fail == 0) {
        std.io.write("map robinhood ok\n");
    } else {
        std.io.write("map robinhood FAIL\n");
    }
}
