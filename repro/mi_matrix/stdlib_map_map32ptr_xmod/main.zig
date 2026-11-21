// stdlib_map_map32ptr_xmod — std_map (L4) Map32Ptr GREEN fixture.
//
// Contract (blueprint §3 L4): `map32PtrInit(arena, capacity) !Map32Ptr`,
// `map32PtrGet(m, key) ?*void`, `map32PtrPut(m, key, val) !void`,
// `map32PtrRemove(m, key) bool`, `map32PtrLen(m) usize`. Same open-addressing /
// linear-probing / tombstone semantics as Map32x32, with `*void` values.
//
// Cases pinned: fill a capacity-8 table (collision/load stress), every Get
// returns the exact pointer; missing -> null; full-table new key -> OOM;
// replace keeps len; remove -> tombstone + re-put reuse; remove-missing false.
//
// GREEN (contract): deterministic byte-exact stdout `map32ptr ok\n` (RUNRC=0).
const std = @import("std");
const map = @import("std_map.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantPtr(m: *map.Map32Ptr, key: u32, want: *void, what: []const u8) void {
    var got = map.map32PtrGet(m, key);
    if (got) |v| {
        ck(@ptrToInt(v) == @ptrToInt(want), what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    var a0: u32 = 10;
    var a1: u32 = 11;
    var a2: u32 = 12;
    var a3: u32 = 13;
    var a4: u32 = 14;
    var a5: u32 = 15;
    var a6: u32 = 16;
    var a7: u32 = 17;
    var a8: u32 = 18;

    var p0: *void = @ptrCast(*void, &a0);
    var p1: *void = @ptrCast(*void, &a1);
    var p2: *void = @ptrCast(*void, &a2);
    var p3: *void = @ptrCast(*void, &a3);
    var p4: *void = @ptrCast(*void, &a4);
    var p5: *void = @ptrCast(*void, &a5);
    var p6: *void = @ptrCast(*void, &a6);
    var p7: *void = @ptrCast(*void, &a7);
    var p8: *void = @ptrCast(*void, &a8);

    var backing: [1024]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var m = map.map32PtrInit(&ar, 8) catch {
        @panic("init 8");
    };
    ck(map.map32PtrLen(&m) == 0, "fresh len 0");

    map.map32PtrPut(&m, 0, p0) catch {
        @panic("put 0");
    };
    map.map32PtrPut(&m, 1, p1) catch {
        @panic("put 1");
    };
    map.map32PtrPut(&m, 2, p2) catch {
        @panic("put 2");
    };
    map.map32PtrPut(&m, 3, p3) catch {
        @panic("put 3");
    };
    map.map32PtrPut(&m, 4, p4) catch {
        @panic("put 4");
    };
    map.map32PtrPut(&m, 5, p5) catch {
        @panic("put 5");
    };
    map.map32PtrPut(&m, 6, p6) catch {
        @panic("put 6");
    };
    map.map32PtrPut(&m, 7, p7) catch {
        @panic("put 7");
    };
    ck(map.map32PtrLen(&m) == 8, "len 8");

    wantPtr(&m, 0, p0, "get 0");
    wantPtr(&m, 1, p1, "get 1");
    wantPtr(&m, 2, p2, "get 2");
    wantPtr(&m, 3, p3, "get 3");
    wantPtr(&m, 4, p4, "get 4");
    wantPtr(&m, 5, p5, "get 5");
    wantPtr(&m, 6, p6, "get 6");
    wantPtr(&m, 7, p7, "get 7");

    ck(map.map32PtrGet(&m, 123) == null, "missing null");

    var oom = false;
    map.map32PtrPut(&m, 99, p8) catch |e| {
        if (e == error.OutOfMemory) oom = true;
    };
    ck(oom, "full table OutOfMemory");
    ck(map.map32PtrLen(&m) == 8, "len after OOM");

    map.map32PtrPut(&m, 3, p8) catch {
        @panic("replace");
    };
    ck(map.map32PtrLen(&m) == 8, "len after replace");
    wantPtr(&m, 3, p8, "replaced value");

    ck(map.map32PtrRemove(&m, 3), "remove true");
    ck(map.map32PtrRemove(&m, 3) == false, "remove twice false");
    ck(map.map32PtrGet(&m, 3) == null, "removed get null");
    ck(map.map32PtrLen(&m) == 7, "len after remove");

    map.map32PtrPut(&m, 3, p3) catch {
        @panic("re-put");
    };
    ck(map.map32PtrLen(&m) == 8, "len after re-put");
    wantPtr(&m, 3, p3, "re-put value");

    if (g_fail == 0) {
        std.io.write("map32ptr ok\n");
    } else {
        std.io.write("map32ptr FAIL\n");
    }
}
