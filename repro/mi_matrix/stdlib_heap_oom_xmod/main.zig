// stdlib_heap_oom_xmod — std_heap (L4) arena-exhaustion GREEN fixture (R1).
//
// Contract (blueprint §3 L4 + §1 R1): `heapInit` allocates its backing table
// from the caller's arena; `heapPush` grows that table from the arena when it
// is full. When the arena cannot satisfy the request the error is exactly
// `error.OutOfMemory`, the heap is left unchanged (len + contents), and no byte
// outside the arena is written.
//
// Layout: a 512-byte storage array; each case fills it 0xAB, hands a sub-slice
// to the arena, and after the forced failure asserts:
//   - the call reports exactly `error.OutOfMemory`;
//   - `arena.used` is unchanged from before the failing call;
//   - every byte OUTSIDE the arena region is still 0xAB (no out-of-arena write);
//   - every byte INSIDE the arena beyond `used` is still 0xAB (no over-write).
//
// Cases:
//   A. heapInit capacity 8 on an 16-byte arena -> OOM at init.
//   B. capacity 2 filled, arena exhausted, then a third push (growth) -> OOM;
//      the two entries stay intact and pop in order.
//   C. capacity 0 heap, arena exhausted, then the first push (growth) -> OOM;
//      len stays 0.
//
// GREEN (contract): deterministic byte-exact stdout `heap oom ok\n` (RUNRC=0).
const std = @import("std");
const heap_mod = @import("std_heap.zig");

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
fn initOom(ar: *std.arena.Arena, cap: usize) bool {
    var h = heap_mod.heapInit(ar, cap) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    _ = heap_mod.heapLen(&h);
    return false;
}

fn push(h: *heap_mod.Heap, key: i64, val: *void, what: []const u8) void {
    var it = heap_mod.HeapItem{ .key = key, .value = val };
    heap_mod.heapPush(h, it) catch {
        @panic(what);
    };
}

fn popIs(h: *heap_mod.Heap, want_key: i64, want_val: *void, what: []const u8) void {
    var got = heap_mod.heapPop(h);
    if (got) |it| {
        ck(it.key == want_key, what);
        ck(@ptrToInt(it.value) == @ptrToInt(want_val), what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    var v0: u32 = 10;
    var v1: u32 = 11;
    var v2: u32 = 12;
    var p0: *void = @ptrCast(*void, &v0);
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);

    // ---- A: init OOM (8-entry table > 16-byte arena) ----------------------
    fillAll();
    var arA = std.arena.init(g_storage[8..24]);
    ck(initOom(&arA, 8), "A init OutOfMemory");
    ck(arA.used == 0, "A used unchanged");
    checkOutside(8, 24, "A guard");
    checkTail(8, arA.used, arA.capacity, "A tail");

    // ---- B: growth OOM on a full capacity-2 heap --------------------------
    fillAll();
    var arB = std.arena.init(g_storage[8..200]);
    var hB = heap_mod.heapInit(&arB, 2) catch {
        @panic("B init");
    };
    push(&hB, 3, p0, "B push 3");
    push(&hB, 1, p1, "B push 1");
    ck(heap_mod.heapLen(&hB) == 2, "B filled");

    // Leave exactly one byte free: less than any growth request, so the next
    // push must fail in `grow` after allocating nothing.
    var remB = arB.capacity - arB.used;
    if (remB > 0) {
        _ = std.arena.alloc(&arB, remB - 1) catch {
            @panic("B exhaust");
        };
    }
    ck(arB.used == arB.capacity - 1, "B exhausted to one byte");
    var usedB = arB.used;
    var oomB = false;
    var itB = heap_mod.HeapItem{ .key = 2, .value = p2 };
    heap_mod.heapPush(&hB, itB) catch |e| {
        if (e == error.OutOfMemory) oomB = true;
    };
    ck(oomB, "B growth OutOfMemory");
    ck(arB.used == usedB, "B used unchanged");
    ck(heap_mod.heapLen(&hB) == 2, "B len unchanged");
    popIs(&hB, 1, p1, "B value 1 intact");
    popIs(&hB, 3, p0, "B value 3 intact");
    checkOutside(8, 200, "B guard");
    checkTail(8, usedB, arB.capacity, "B tail");

    // ---- C: first push on a capacity-0 heap with no arena left ------------
    fillAll();
    var arC = std.arena.init(g_storage[8..64]);
    var hC = heap_mod.heapInit(&arC, 0) catch {
        @panic("C init");
    };
    ck(heap_mod.heapLen(&hC) == 0, "C fresh len");
    var remC = arC.capacity - arC.used;
    if (remC > 0) {
        _ = std.arena.alloc(&arC, remC - 1) catch {
            @panic("C exhaust");
        };
    }
    var usedC = arC.used;
    var oomC = false;
    var itC = heap_mod.HeapItem{ .key = 1, .value = p0 };
    heap_mod.heapPush(&hC, itC) catch |e| {
        if (e == error.OutOfMemory) oomC = true;
    };
    ck(oomC, "C first-push OutOfMemory");
    ck(arC.used == usedC, "C used unchanged");
    ck(heap_mod.heapLen(&hC) == 0, "C len unchanged");
    ck(heap_mod.heapPop(&hC) == null, "C still empty");
    checkOutside(8, 64, "C guard");
    checkTail(8, usedC, arC.capacity, "C tail");

    if (g_fail == 0) {
        std.io.write("heap oom ok\n");
    } else {
        std.io.write("heap oom FAIL\n");
    }
}
