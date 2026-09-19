// stdlib_heap_push_xmod — std_heap (L4) `heapPush` GREEN fixture.
//
// Contract (blueprint §3 L4 + §1 R1): `heapPush(h, item) !void` appends the item
// and sifts it up; when the backing table is full it grows from the caller's
// arena (the error set includes `error.OutOfMemory`). Push does not reorder
// items with distinct keys: a min-heap always exposes the smallest key.
//
// Cases pinned: capacity 2 filled to 7 items (growth 2 -> 4 -> 8), then fully
// drained in ascending key order; capacity 0 (first push grows from nothing);
// negative keys sort below zero; a large random-order push is drained sorted.
//
// GREEN (contract): deterministic byte-exact stdout `heapPush ok\n` (RUNRC=0).
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
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);
    var p3: *void = @ptrCast(*void, &v3);
    var p4: *void = @ptrCast(*void, &v4);
    var p5: *void = @ptrCast(*void, &v5);
    var p6: *void = @ptrCast(*void, &v6);
    var p7: *void = @ptrCast(*void, &v7);

    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // capacity 2 -> growth to 4 -> 8 while pushing 7 items.
    var h = heap_mod.heapInit(&ar, 2) catch {
        @panic("init 2");
    };
    push(&h, 5, p1, "push 5");
    ck(heap_mod.heapLen(&h) == 1, "len 1");
    push(&h, 3, p2, "push 3");
    push(&h, 9, p3, "push 9");
    push(&h, 1, p4, "push 1");
    push(&h, 7, p5, "push 7");
    push(&h, 2, p6, "push 2");
    push(&h, 8, p7, "push 8");
    ck(heap_mod.heapLen(&h) == 7, "len 7");

    popIs(&h, 1, p4, "drain 1");
    popIs(&h, 2, p6, "drain 2");
    popIs(&h, 3, p2, "drain 3");
    popIs(&h, 5, p1, "drain 5");
    popIs(&h, 7, p5, "drain 7");
    popIs(&h, 8, p7, "drain 8");
    popIs(&h, 9, p3, "drain 9");
    ck(heap_mod.heapLen(&h) == 0, "len 0 after drain");
    ck(heap_mod.heapPop(&h) == null, "empty after drain");

    // capacity 0: the first push grows from nothing.
    var h0 = heap_mod.heapInit(&ar, 0) catch {
        @panic("init 0");
    };
    push(&h0, 42, p1, "push cap0");
    ck(heap_mod.heapLen(&h0) == 1, "cap0 len");
    popIs(&h0, 42, p1, "pop cap0");

    // negative keys sort below zero.
    var hn = heap_mod.heapInit(&ar, 1) catch {
        @panic("init neg");
    };
    push(&hn, 0, p1, "push 0");
    push(&hn, -5, p2, "push -5");
    push(&hn, -9, p3, "push -9");
    ck(heap_mod.heapLen(&hn) == 3, "neg len");
    popIs(&hn, -9, p3, "pop -9");
    popIs(&hn, -5, p2, "pop -5");
    popIs(&hn, 0, p1, "pop 0");

    // A larger scrambled sequence must drain in non-decreasing key order.
    var hb = heap_mod.heapInit(&ar, 4) catch {
        @panic("init big");
    };
    push(&hb, 17, p1, "big 17");
    push(&hb, 4, p2, "big 4");
    push(&hb, 23, p3, "big 23");
    push(&hb, 9, p4, "big 9");
    push(&hb, 1, p5, "big 1");
    push(&hb, 31, p6, "big 31");
    push(&hb, 12, p7, "big 12");
    push(&hb, 2, p1, "big 2");
    push(&hb, 25, p2, "big 25");
    ck(heap_mod.heapLen(&hb) == 9, "big len");
    popIs(&hb, 1, p5, "big drain 1");
    popIs(&hb, 2, p1, "big drain 2");
    popIs(&hb, 4, p2, "big drain 4");
    popIs(&hb, 9, p4, "big drain 9");
    popIs(&hb, 12, p7, "big drain 12");
    popIs(&hb, 17, p1, "big drain 17");
    popIs(&hb, 23, p3, "big drain 23");
    popIs(&hb, 25, p2, "big drain 25");
    popIs(&hb, 31, p6, "big drain 31");
    ck(heap_mod.heapLen(&hb) == 0, "big len 0");

    if (g_fail == 0) {
        std.io.write("heapPush ok\n");
    } else {
        std.io.write("heapPush FAIL\n");
    }
}
