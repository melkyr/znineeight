// stdlib_map_oom_xmod — std_map (L4) arena-exhaustion GREEN fixture (R1).
//
// Contract (blueprint §3 L4 + §1 R1): every map allocates its backing table
// from the caller's arena at init; a string key is copied into that arena at
// put. When the arena cannot satisfy the request the error is exactly
// `error.OutOfMemory`, the map is left unchanged (len + table contents), and no
// byte outside the arena is written.
//
// Layout: a 512-byte storage array; each case fills it 0xAB, hands a sub-slice
// to the arena, and after the forced failure asserts:
//   - the call reports exactly `error.OutOfMemory`;
//   - `arena.used` is unchanged from before the failing call;
//   - every byte OUTSIDE the arena region is still 0xAB (no out-of-arena write);
//   - every byte INSIDE the arena beyond `used` is still 0xAB (no over-write).
//
// Cases:
//   A. Map32x32 init on a 16-byte arena (table 8 slots) -> OOM at init.
//   B. Map32x32 capacity 4 filled, then a new key -> OOM; entries intact.
//   C. MapStrPtr capacity 2, arena then deliberately exhausted, then a new
//      string key -> OOM at the key copy; len stays 0.
//   D. Map32Ptr capacity 2 filled, then a new key -> OOM; entries intact.
//
// GREEN (contract): deterministic byte-exact stdout `map oom ok\n` (RUNRC=0).
const std = @import("std");
const map = @import("std_map.zig");

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

// Init helper that reports OutOfMemory without discarding the struct-returning
// call through `_ = ... catch` (the latter mis-emits in this compiler).
fn init32Oom(ar: *std.arena.Arena, cap: usize) bool {
    var m = map.map32x32Init(ar, cap) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = map.map32x32Len(&m);
    return false;
}

pub fn main() void {
    var v0: u32 = 0;
    var v1: u32 = 1;
    var v2: u32 = 2;
    var p0: *void = @ptrCast(*void, &v0);
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);

    // ---- A: init OOM (table 8 slots > 16-byte arena) ----------------------
    fillAll();
    var arA = std.arena.init(g_storage[8..24]);
    var a_oom = init32Oom(&arA, 8);
    ck(a_oom, "A init OutOfMemory");
    ck(arA.used == 0, "A used unchanged");
    checkOutside(8, 24, "A guard");
    checkTail(8, arA.used, arA.capacity, "A tail");

    // ---- B: full-table OOM (Map32x32) -------------------------------------
    fillAll();
    var arB = std.arena.init(g_storage[8..200]);
    var mB = map.map32x32Init(&arB, 4) catch {
        @panic("B init");
    };
    var kB: u32 = 0;
    while (kB < 4) : (kB += 1) {
        map.map32x32Put(&mB, kB, kB + 10) catch {
            @panic("B put");
        };
    }
    ck(map.map32x32Len(&mB) == 4, "B filled");
    var usedB = arB.used;
    var b_oom = false;
    map.map32x32Put(&mB, 77, 77) catch |e| {
        if (e == error.OutOfMemory) b_oom = true;
    };
    ck(b_oom, "B full OutOfMemory");
    ck(arB.used == usedB, "B used unchanged");
    ck(map.map32x32Len(&mB) == 4, "B len unchanged");
    kB = 0;
    while (kB < 4) : (kB += 1) {
        var g = map.map32x32Get(&mB, kB);
        if (g) |v| {
            ck(v == kB + 10, "B value intact");
        } else {
            ck(false, "B value present");
        }
    }
    checkOutside(8, 200, "B guard");
    checkTail(8, arB.used, arB.capacity, "B tail");

    // ---- C: string-key copy OOM (MapStrPtr) -------------------------------
    fillAll();
    var arC = std.arena.init(g_storage[8..200]);
    var mC = map.mapStrPtrInit(&arC, 2) catch {
        @panic("C init");
    };
    var rem = arC.capacity - arC.used;
    _ = std.arena.alloc(&arC, rem) catch {
        @panic("C exhaust");
    };
    ck(arC.used == arC.capacity, "C exhausted");
    var usedC = arC.used;
    var c_oom = false;
    map.mapStrPtrPut(&mC, "key", p0) catch |e| {
        if (e == error.OutOfMemory) c_oom = true;
    };
    ck(c_oom, "C key copy OutOfMemory");
    ck(arC.used == usedC, "C used unchanged");
    ck(map.mapStrPtrLen(&mC) == 0, "C len unchanged");
    checkOutside(8, 200, "C guard");

    // ---- D: full-table OOM (Map32Ptr) -------------------------------------
    fillAll();
    var arD = std.arena.init(g_storage[8..200]);
    var mD = map.map32PtrInit(&arD, 2) catch {
        @panic("D init");
    };
    map.map32PtrPut(&mD, 0, p0) catch {
        @panic("D put0");
    };
    map.map32PtrPut(&mD, 1, p1) catch {
        @panic("D put1");
    };
    ck(map.map32PtrLen(&mD) == 2, "D filled");
    var usedD = arD.used;
    var d_oom = false;
    map.map32PtrPut(&mD, 2, p2) catch |e| {
        if (e == error.OutOfMemory) d_oom = true;
    };
    ck(d_oom, "D full OutOfMemory");
    ck(arD.used == usedD, "D used unchanged");
    ck(map.map32PtrLen(&mD) == 2, "D len unchanged");
    var dg0 = map.map32PtrGet(&mD, 0);
    if (dg0) |v| {
        ck(@ptrToInt(v) == @ptrToInt(p0), "D value 0 intact");
    } else {
        ck(false, "D value 0 present");
    }
    checkOutside(8, 200, "D guard");
    checkTail(8, arD.used, arD.capacity, "D tail");

    if (g_fail == 0) {
        std.io.write("map oom ok\n");
    } else {
        std.io.write("map oom FAIL\n");
    }
}
