// stdlib_heap_init_xmod — std_heap (L4) `heapInit` GREEN fixture.
//
// Contract (blueprint §3 L4 + §1 R1): `heapInit(arena, capacity) !Heap`
// allocates the backing table from the caller's arena at init; the error set is
// exactly `error.OutOfMemory`. A fresh heap has `heapLen == 0`, `heapPeek`
// null, `heapPop` null. `capacity` may be 0 (the first push grows the table).
//
// Cases pinned: capacities 1 / 8 / 64 on an adequate arena each start empty;
// capacity 0 starts empty; an inadequate arena makes init report exactly
// OutOfMemory and leaves the arena untouched (`used` unchanged).
//
// GREEN (contract): deterministic byte-exact stdout `heapInit ok\n` (RUNRC=0).
const std = @import("std");
const heap_mod = @import("std_heap.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

// Init helper that reports OutOfMemory without discarding the struct-returning
// call through `_ = ... catch` (the latter mis-emits in this compiler).
fn initOom(ar: *std.arena.Arena, cap: usize) bool {
    var h = heap_mod.heapInit(ar, cap) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = heap_mod.heapLen(&h);
    return false;
}

pub fn main() void {
    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var h1 = heap_mod.heapInit(&ar, 1) catch {
        @panic("init 1");
    };
    ck(heap_mod.heapLen(&h1) == 0, "cap1 fresh len");
    ck(heap_mod.heapPeek(&h1) == null, "cap1 fresh peek");
    ck(heap_mod.heapPop(&h1) == null, "cap1 fresh pop");

    var h8 = heap_mod.heapInit(&ar, 8) catch {
        @panic("init 8");
    };
    ck(heap_mod.heapLen(&h8) == 0, "cap8 fresh len");
    ck(heap_mod.heapPeek(&h8) == null, "cap8 fresh peek");
    ck(heap_mod.heapPop(&h8) == null, "cap8 fresh pop");

    var h64 = heap_mod.heapInit(&ar, 64) catch {
        @panic("init 64");
    };
    ck(heap_mod.heapLen(&h64) == 0, "cap64 fresh len");
    ck(heap_mod.heapPeek(&h64) == null, "cap64 fresh peek");

    var h0 = heap_mod.heapInit(&ar, 0) catch {
        @panic("init 0");
    };
    ck(heap_mod.heapLen(&h0) == 0, "cap0 fresh len");
    ck(heap_mod.heapPeek(&h0) == null, "cap0 fresh peek");
    ck(heap_mod.heapPop(&h0) == null, "cap0 fresh pop");

    // An 8-byte arena cannot hold a 64-entry table.
    var tiny: [8]u8 = undefined;
    var tar = std.arena.init(tiny[0..]);
    ck(initOom(&tar, 64), "init OutOfMemory");
    ck(tar.used == 0, "init OOM used unchanged");

    if (g_fail == 0) {
        std.io.write("heapInit ok\n");
    } else {
        std.io.write("heapInit FAIL\n");
    }
}
