// stdlib_heap_pop_xmod — std_heap (L4) `heapPop` GREEN fixture.
//
// Contract (blueprint §3 L4): `heapPop(h) ?HeapItem` removes and returns the
// minimum item (smallest key), or null when the heap is empty. Pop never
// allocates. After a pop the heap property is restored (sift-down).
//
// Cases pinned: empty pop null; single element; a 12-item scrambled heap fully
// drained in ascending key order; interleaved push/pop; pop-then-push reuse
// after draining to empty.
//
// GREEN (contract): deterministic byte-exact stdout `heapPop ok\n` (RUNRC=0).
const std = @import("std");
const heap_mod = @import("std_heap.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
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
    var v1: u32 = 1;
    var v2: u32 = 2;
    var v3: u32 = 3;
    var v4: u32 = 4;
    var v5: u32 = 5;
    var v6: u32 = 6;
    var v7: u32 = 7;
    var v8: u32 = 8;
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);
    var p3: *void = @ptrCast(*void, &v3);
    var p4: *void = @ptrCast(*void, &v4);
    var p5: *void = @ptrCast(*void, &v5);
    var p6: *void = @ptrCast(*void, &v6);
    var p7: *void = @ptrCast(*void, &v7);
    var p8: *void = @ptrCast(*void, &v8);

    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var h = heap_mod.heapInit(&ar, 4) catch {
        @panic("init");
    };

    // Empty heap.
    ck(heap_mod.heapPop(&h) == null, "empty pop null");
    ck(heap_mod.heapLen(&h) == 0, "empty len");

    // Single element.
    push(&h, 7, p1, "single push");
    popIs(&h, 7, p1, "single pop");
    ck(heap_mod.heapPop(&h) == null, "single then empty");

    // Twelve scrambled items, fully drained.
    push(&h, 50, p1, "push 50");
    push(&h, 20, p2, "push 20");
    push(&h, 80, p3, "push 80");
    push(&h, 10, p4, "push 10");
    push(&h, 60, p5, "push 60");
    push(&h, 30, p6, "push 30");
    push(&h, 90, p7, "push 90");
    push(&h, 40, p8, "push 40");
    push(&h, 70, p1, "push 70");
    push(&h, 15, p2, "push 15");
    push(&h, 55, p3, "push 55");
    push(&h, 25, p4, "push 25");
    ck(heap_mod.heapLen(&h) == 12, "twelve len");

    popIs(&h, 10, p4, "drain 10");
    ck(heap_mod.heapLen(&h) == 11, "len 11");
    popIs(&h, 15, p2, "drain 15");
    popIs(&h, 20, p2, "drain 20");
    popIs(&h, 25, p4, "drain 25");
    popIs(&h, 30, p6, "drain 30");
    popIs(&h, 40, p8, "drain 40");
    popIs(&h, 50, p1, "drain 50");
    popIs(&h, 55, p3, "drain 55");
    popIs(&h, 60, p5, "drain 60");
    popIs(&h, 70, p1, "drain 70");
    popIs(&h, 80, p3, "drain 80");
    popIs(&h, 90, p7, "drain 90");
    ck(heap_mod.heapLen(&h) == 0, "drained len 0");
    ck(heap_mod.heapPop(&h) == null, "drained pop null");

    // Reuse after draining to empty.
    push(&h, 3, p3, "reuse push 3");
    push(&h, 1, p1, "reuse push 1");
    push(&h, 2, p2, "reuse push 2");
    popIs(&h, 1, p1, "reuse pop 1");
    popIs(&h, 2, p2, "reuse pop 2");
    popIs(&h, 3, p3, "reuse pop 3");

    // Interleaved push/pop keeps the minimum on top.
    push(&h, 5, p5, "mix push 5");
    push(&h, 9, p7, "mix push 9");
    popIs(&h, 5, p5, "mix pop 5");
    push(&h, 4, p4, "mix push 4");
    popIs(&h, 4, p4, "mix pop 4");
    popIs(&h, 9, p7, "mix pop 9");

    if (g_fail == 0) {
        std.io.write("heapPop ok\n");
    } else {
        std.io.write("heapPop FAIL\n");
    }
}
