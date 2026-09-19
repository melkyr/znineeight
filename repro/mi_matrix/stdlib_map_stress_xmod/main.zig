// stdlib_map_stress_xmod — STDLIB std_map (L4) hand-written stress table.
//
// No PRNG: every input is an explicit table or an explicit fixed loop (the key
// generator `fmtKey` is a literal formula over the loop index, written out).
// Stresses all three maps:
//   - Map32x32 capacity sweep 8..1024 at 50% load: put, get, replace, remove;
//   - heavy collisions: a capacity-16 table filled to 15/16 (linear probing),
//     then tombstones reused and the full-table OutOfMemory boundary;
//   - deterministic iteration order over a 400-key set: two maps built from the
//     identical sequence in separate arenas must have byte-identical
//     occupied-slot layout (state/key/val per slot);
//   - MapStrPtr copy-on-put key lifetime: a key put from a mutable source
//     buffer is still found after the source is mutated, and the mutated bytes
//     are not a key; 200 generated keys coexist; a second map is slot-identical.
//
// GREEN (contract): deterministic byte-exact stdout `map stress ok\n` (RUNRC=0).
const std = @import("std");
const map = @import("std_map.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

// fmtKey writes `prefix` then the decimal digits of `n` into buf and returns the
// slice. The map copies keys, so the caller may reuse buf immediately.
fn fmtKey(buf: []u8, prefix: u8, n: u32) []const u8 {
    var tmp: [12]u8 = undefined;
    var x: u32 = n;
    var i: usize = 12;
    if (x == 0) {
        i -= 1;
        tmp[i] = '0';
    } else {
        while (x > 0) {
            i -= 1;
            tmp[i] = @intCast(u8, @intCast(u32, '0') + (x % 10));
            x = x / 10;
        }
    }
    buf[0] = prefix;
    var j: usize = 0;
    while (i + j < 12) : (j += 1) {
        buf[1 + j] = tmp[i + j];
    }
    return buf[0 .. 1 + j];
}

// ---------------------------------------------------------------------------
// Map32x32 capacity sweep
// ---------------------------------------------------------------------------

fn sweep32x32(ar: *std.arena.Arena) void {
    var caps = [_]usize{ 8, 16, 32, 64, 128, 256, 512, 1024 };
    var ci: usize = 0;
    while (ci < caps.len) : (ci += 1) {
        var cap: usize = caps[ci];
        var m = map.map32x32Init(ar, cap) catch {
            @panic("sweep init");
        };
        var n: usize = cap / 2;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            var key: u32 = @intCast(u32, k) * 7 + 1;
            map.map32x32Put(&m, key, key * 3 + 1) catch {
                @panic("sweep put");
            };
        }
        ck(map.map32x32Len(&m) == n, "sweep len");

        k = 0;
        while (k < n) : (k += 1) {
            var key: u32 = @intCast(u32, k) * 7 + 1;
            var got = map.map32x32Get(&m, key);
            if (got) |v| {
                ck(v == key * 3 + 1, "sweep get");
            } else {
                ck(false, "sweep missing");
            }
        }

        // replace every even index; len is unchanged
        k = 0;
        while (k < n) : (k += 1) {
            if (k % 2 == 0) {
                var key: u32 = @intCast(u32, k) * 7 + 1;
                map.map32x32Put(&m, key, key * 5 + 2) catch {
                    @panic("sweep replace");
                };
            }
        }
        ck(map.map32x32Len(&m) == n, "sweep len after replace");
        k = 0;
        while (k < n) : (k += 1) {
            var key: u32 = @intCast(u32, k) * 7 + 1;
            var want: u32 = key * 3 + 1;
            if (k % 2 == 0) want = key * 5 + 2;
            var got = map.map32x32Get(&m, key);
            if (got) |v| {
                ck(v == want, "sweep replace get");
            } else {
                ck(false, "sweep replace missing");
            }
        }

        // remove every third; a removed key is gone, the rest survive
        k = 0;
        while (k < n) : (k += 1) {
            if (k % 3 == 0) {
                var key: u32 = @intCast(u32, k) * 7 + 1;
                ck(map.map32x32Remove(&m, key), "sweep remove");
            }
        }
        k = 0;
        while (k < n) : (k += 1) {
            var key: u32 = @intCast(u32, k) * 7 + 1;
            var got = map.map32x32Get(&m, key);
            if (k % 3 == 0) {
                ck(got == null, "sweep removed still present");
            } else {
                ck(got != null, "sweep survivor missing");
            }
        }
    }
}

// ---------------------------------------------------------------------------
// heavy collisions + full-table boundary
// ---------------------------------------------------------------------------

fn collisions(ar: *std.arena.Arena) void {
    var m = map.map32x32Init(ar, 16) catch {
        @panic("coll init");
    };
    var k: u32 = 0;
    while (k < 15) : (k += 1) {
        map.map32x32Put(&m, k, k +% 100) catch {
            @panic("coll put");
        };
    }
    ck(map.map32x32Len(&m) == 15, "coll full-ish len");
    k = 0;
    while (k < 15) : (k += 1) {
        var got = map.map32x32Get(&m, k);
        if (got) |v| {
            ck(v == k +% 100, "coll get");
        } else {
            ck(false, "coll missing");
        }
    }

    // remove five, reuse the tombstones with five new keys
    k = 0;
    while (k < 5) : (k += 1) {
        ck(map.map32x32Remove(&m, k), "coll remove");
    }
    ck(map.map32x32Len(&m) == 10, "coll len after remove");
    k = 100;
    while (k < 105) : (k += 1) {
        map.map32x32Put(&m, k, k) catch {
            @panic("coll re-put");
        };
    }
    ck(map.map32x32Len(&m) == 15, "coll len after tomb reuse");
    k = 100;
    while (k < 105) : (k += 1) {
        var got = map.map32x32Get(&m, k);
        if (got) |v| {
            ck(v == k, "coll re-put get");
        } else {
            ck(false, "coll re-put missing");
        }
    }

    // a completely full table (no empty, no tombstone): a new key is OOM
    var full = map.map32x32Init(ar, 16) catch {
        @panic("full init");
    };
    k = 0;
    while (k < 16) : (k += 1) {
        map.map32x32Put(&full, k + 200, k) catch {
            @panic("full put");
        };
    }
    ck(map.map32x32Len(&full) == 16, "full len");
    var oom = false;
    map.map32x32Put(&full, 999, 1) catch {
        oom = true;
    };
    ck(oom, "full table OOM");
    ck(map.map32x32Len(&full) == 16, "full len after OOM");
}

// ---------------------------------------------------------------------------
// deterministic iteration order (Map32x32, 400 keys)
// ---------------------------------------------------------------------------

fn determinism32(a1: *std.arena.Arena, a2: *std.arena.Arena) void {
    var m1 = map.map32x32Init(a1, 512) catch {
        @panic("det32 init a");
    };
    var m2 = map.map32x32Init(a2, 512) catch {
        @panic("det32 init b");
    };
    var i: u32 = 0;
    while (i < 400) : (i += 1) {
        var key: u32 = i * 11 + 3;
        map.map32x32Put(&m1, key, key * 7 + 5) catch {
            @panic("det32 put a");
        };
        map.map32x32Put(&m2, key, key * 7 + 5) catch {
            @panic("det32 put b");
        };
    }
    i = 0;
    while (i < 400) : (i += 5) {
        _ = map.map32x32Remove(&m1, i * 11 + 3);
        _ = map.map32x32Remove(&m2, i * 11 + 3);
    }
    i = 0;
    while (i < 50) : (i += 1) {
        var key: u32 = i * 13 + 1000;
        map.map32x32Put(&m1, key, key +% 9) catch {
            @panic("det32 re-put a");
        };
        map.map32x32Put(&m2, key, key +% 9) catch {
            @panic("det32 re-put b");
        };
    }
    ck(map.map32x32Len(&m1) == map.map32x32Len(&m2), "det32 len equal");
    i = 0;
    while (i < 512) : (i += 1) {
        ck(m1.entries[i].state == m2.entries[i].state, "det32 state order");
        ck(m1.entries[i].key == m2.entries[i].key, "det32 key order");
        ck(m1.entries[i].val == m2.entries[i].val, "det32 val order");
    }
}

// ---------------------------------------------------------------------------
// MapStrPtr: 200 generated keys + copy-on-put lifetime
// ---------------------------------------------------------------------------

fn strStress(ar: *std.arena.Arena) void {
    var vals: [256]u32 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        vals[i] = @intCast(u32, i) + 1;
    }

    var m = map.mapStrPtrInit(ar, 512) catch {
        @panic("str init");
    };
    var kb: [16]u8 = undefined;
    i = 0;
    while (i < 200) : (i += 1) {
        var key = fmtKey(kb[0..], 'k', @intCast(u32, i));
        var p: *void = @ptrCast(*void, &vals[i]);
        map.mapStrPtrPut(&m, key, p) catch {
            @panic("str put");
        };
    }
    ck(map.mapStrPtrLen(&m) == 200, "str len");
    i = 0;
    while (i < 200) : (i += 1) {
        var key = fmtKey(kb[0..], 'k', @intCast(u32, i));
        var got = map.mapStrPtrGet(&m, key);
        if (got) |v| {
            ck(@ptrToInt(v) == @ptrToInt(&vals[i]), "str get");
        } else {
            ck(false, "str missing");
        }
    }

    // replace every even key; len unchanged
    i = 0;
    while (i < 200) : (i += 1) {
        if (i % 2 == 0) {
            var key = fmtKey(kb[0..], 'k', @intCast(u32, i));
            var p: *void = @ptrCast(*void, &vals[i + 40]);
            map.mapStrPtrPut(&m, key, p) catch {
                @panic("str replace");
            };
        }
    }
    ck(map.mapStrPtrLen(&m) == 200, "str len after replace");

    // copy-on-put lifetime: mutate the source buffer after the put
    var src: [8]u8 = undefined;
    std.str.copy(src[0..], "lifetime");
    var pl: *void = @ptrCast(*void, &vals[250]);
    map.mapStrPtrPut(&m, src[0..8], pl) catch {
        @panic("lifetime put");
    };
    src[0] = 'X';
    src[1] = 'Y';
    var probe: [8]u8 = undefined;
    std.str.copy(probe[0..], "lifetime");
    var got = map.mapStrPtrGet(&m, probe[0..8]);
    if (got) |v| {
        ck(@ptrToInt(v) == @ptrToInt(pl), "lifetime stored key survives");
    } else {
        ck(false, "lifetime stored key lost");
    }
    ck(map.mapStrPtrGet(&m, src[0..8]) == null, "lifetime mutated bytes absent");

    // the empty string is an ordinary key
    var empty: []const u8 = "";
    var pe: *void = @ptrCast(*void, &vals[251]);
    map.mapStrPtrPut(&m, empty, pe) catch {
        @panic("empty put");
    };
    var ge = map.mapStrPtrGet(&m, empty);
    if (ge) |v| {
        ck(@ptrToInt(v) == @ptrToInt(pe), "empty key get");
    } else {
        ck(false, "empty key missing");
    }
}

fn strDeterminism(a1: *std.arena.Arena, a2: *std.arena.Arena) void {
    var vals: [64]u32 = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        vals[i] = @intCast(u32, i);
    }
    var m1 = map.mapStrPtrInit(a1, 256) catch {
        @panic("strdet init a");
    };
    var m2 = map.mapStrPtrInit(a2, 256) catch {
        @panic("strdet init b");
    };
    var kb: [16]u8 = undefined;
    i = 0;
    while (i < 60) : (i += 1) {
        var key = fmtKey(kb[0..], 's', @intCast(u32, i));
        var p: *void = @ptrCast(*void, &vals[i % 64]);
        map.mapStrPtrPut(&m1, key, p) catch {
            @panic("strdet put a");
        };
        map.mapStrPtrPut(&m2, key, p) catch {
            @panic("strdet put b");
        };
    }
    i = 0;
    while (i < 256) : (i += 1) {
        ck(m1.entries[i].state == m2.entries[i].state, "strdet state order");
        ck(std.str.eql(m1.entries[i].key, m2.entries[i].key), "strdet key order");
        ck(@ptrToInt(m1.entries[i].val) == @ptrToInt(m2.entries[i].val), "strdet val order");
    }
}

var g_back_a: [2097152]u8 = undefined;
var g_arena_a = std.arena.init(g_back_a[0..]);
var g_back_b: [1048576]u8 = undefined;
var g_arena_b = std.arena.init(g_back_b[0..]);

pub fn main() void {
    sweep32x32(&g_arena_a);
    collisions(&g_arena_a);
    determinism32(&g_arena_a, &g_arena_b);
    strStress(&g_arena_a);
    strDeterminism(&g_arena_a, &g_arena_b);

    if (g_fail == 0) {
        std.io.write("map stress ok\n");
    } else {
        std.io.write("map stress FAIL\n");
    }
}
