// stdlib_map_determinism_xmod — std_map (L4) iteration-order determinism
// fixture (R6).
//
// Contract (blueprint §3 L4 + §1 R6): the map's storage layout is a pure
// function of the operation sequence — no addresses, no clock, no PID. Two maps
// built from identical sequences over separate arenas must have byte-identical
// occupied-slot layout (state/key/value per slot index), which is the map's
// iteration order (insertion-index order). This is checked directly against the
// backing `entries` array, not just through Get.
//
// Sequence per map: put 0..31 (fills a capacity-32 table), remove every even
// key (tombstones), re-put a removed key and one new key, then compare every
// slot of the two maps and every observable Get/Len result.
//
// GREEN (contract): deterministic byte-exact stdout `map determinism ok\n`.
const std = @import("std");
const map = @import("std_map.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    var b1: [16384]u8 = undefined;
    var b2: [16384]u8 = undefined;
    var ar1 = std.arena.init(b1[0..]);
    var ar2 = std.arena.init(b2[0..]);

    // ---- Map32x32 ---------------------------------------------------------
    var m1 = map.map32x32Init(&ar1, 32) catch {
        @panic("init 32x32 a");
    };
    var m2 = map.map32x32Init(&ar2, 32) catch {
        @panic("init 32x32 b");
    };
    var i: u32 = 0;
    while (i < 32) : (i += 1) {
        map.map32x32Put(&m1, i, i * 3 + 1) catch {
            @panic("32x32 put a");
        };
        map.map32x32Put(&m2, i, i * 3 + 1) catch {
            @panic("32x32 put b");
        };
    }
    i = 0;
    while (i < 32) : (i += 2) {
        _ = map.map32x32Remove(&m1, i);
        _ = map.map32x32Remove(&m2, i);
    }
    map.map32x32Put(&m1, 7, 700) catch {
        @panic("32x32 re-put a");
    };
    map.map32x32Put(&m2, 7, 700) catch {
        @panic("32x32 re-put b");
    };
    map.map32x32Put(&m1, 100, 1) catch {
        @panic("32x32 new a");
    };
    map.map32x32Put(&m2, 100, 1) catch {
        @panic("32x32 new b");
    };

    ck(map.map32x32Len(&m1) == map.map32x32Len(&m2), "32x32 len equal");
    i = 0;
    while (i < 32) : (i += 1) {
        ck(m1.entries[i].state == m2.entries[i].state, "32x32 state order");
        ck(m1.entries[i].key == m2.entries[i].key, "32x32 key order");
        ck(m1.entries[i].val == m2.entries[i].val, "32x32 val order");
    }
    i = 0;
    while (i < 33) : (i += 1) {
        var g1 = map.map32x32Get(&m1, i);
        var g2 = map.map32x32Get(&m2, i);
        if (g1) |v1| {
            if (g2) |v2| {
                ck(v1 == v2, "32x32 get equal");
            } else {
                ck(false, "32x32 get b missing");
            }
        } else {
            ck(g2 == null, "32x32 get null equal");
        }
    }

    // ---- Map32Ptr ---------------------------------------------------------
    var v0: u32 = 0;
    var v1: u32 = 1;
    var v2: u32 = 2;
    var v3: u32 = 3;
    var p0: *void = @ptrCast(*void, &v0);
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);
    var p3: *void = @ptrCast(*void, &v3);

    var q1 = map.map32PtrInit(&ar1, 16) catch {
        @panic("init 32ptr a");
    };
    var q2 = map.map32PtrInit(&ar2, 16) catch {
        @panic("init 32ptr b");
    };
    map.map32PtrPut(&q1, 0, p0) catch {
        @panic("32ptr put0 a");
    };
    map.map32PtrPut(&q2, 0, p0) catch {
        @panic("32ptr put0 b");
    };
    map.map32PtrPut(&q1, 1, p1) catch {
        @panic("32ptr put1 a");
    };
    map.map32PtrPut(&q2, 1, p1) catch {
        @panic("32ptr put1 b");
    };
    map.map32PtrPut(&q1, 2, p2) catch {
        @panic("32ptr put2 a");
    };
    map.map32PtrPut(&q2, 2, p2) catch {
        @panic("32ptr put2 b");
    };
    map.map32PtrPut(&q1, 3, p3) catch {
        @panic("32ptr put3 a");
    };
    map.map32PtrPut(&q2, 3, p3) catch {
        @panic("32ptr put3 b");
    };
    _ = map.map32PtrRemove(&q1, 2);
    _ = map.map32PtrRemove(&q2, 2);
    map.map32PtrPut(&q1, 2, p3) catch {
        @panic("32ptr re-put a");
    };
    map.map32PtrPut(&q2, 2, p3) catch {
        @panic("32ptr re-put b");
    };
    ck(map.map32PtrLen(&q1) == map.map32PtrLen(&q2), "32ptr len equal");
    i = 0;
    while (i < 16) : (i += 1) {
        ck(q1.entries[i].state == q2.entries[i].state, "32ptr state order");
        ck(q1.entries[i].key == q2.entries[i].key, "32ptr key order");
        ck(@ptrToInt(q1.entries[i].val) == @ptrToInt(q2.entries[i].val), "32ptr val order");
    }

    // ---- MapStrPtr --------------------------------------------------------
    var r1 = map.mapStrPtrInit(&ar1, 16) catch {
        @panic("init strptr a");
    };
    var r2 = map.mapStrPtrInit(&ar2, 16) catch {
        @panic("init strptr b");
    };
    map.mapStrPtrPut(&r1, "alpha", p0) catch {
        @panic("strptr alpha a");
    };
    map.mapStrPtrPut(&r2, "alpha", p0) catch {
        @panic("strptr alpha b");
    };
    map.mapStrPtrPut(&r1, "beta", p1) catch {
        @panic("strptr beta a");
    };
    map.mapStrPtrPut(&r2, "beta", p1) catch {
        @panic("strptr beta b");
    };
    map.mapStrPtrPut(&r1, "gamma", p2) catch {
        @panic("strptr gamma a");
    };
    map.mapStrPtrPut(&r2, "gamma", p2) catch {
        @panic("strptr gamma b");
    };
    map.mapStrPtrPut(&r1, "delta", p3) catch {
        @panic("strptr delta a");
    };
    map.mapStrPtrPut(&r2, "delta", p3) catch {
        @panic("strptr delta b");
    };
    _ = map.mapStrPtrRemove(&r1, "beta");
    _ = map.mapStrPtrRemove(&r2, "beta");
    map.mapStrPtrPut(&r1, "beta", p0) catch {
        @panic("strptr re-put a");
    };
    map.mapStrPtrPut(&r2, "beta", p0) catch {
        @panic("strptr re-put b");
    };
    ck(map.mapStrPtrLen(&r1) == map.mapStrPtrLen(&r2), "strptr len equal");
    i = 0;
    while (i < 16) : (i += 1) {
        ck(r1.entries[i].state == r2.entries[i].state, "strptr state order");
        ck(std.str.eql(r1.entries[i].key, r2.entries[i].key), "strptr key order");
        ck(@ptrToInt(r1.entries[i].val) == @ptrToInt(r2.entries[i].val), "strptr val order");
    }

    if (g_fail == 0) {
        std.io.write("map determinism ok\n");
    } else {
        std.io.write("map determinism FAIL\n");
    }
}
