// stdlib_heap_len_xmod — std_heap (L4) `heapLen` GREEN fixture.
//
// Contract (blueprint §3 L4): `heapLen(h) usize` returns the number of live
// items. It does not allocate and is unaffected by growth.
//
// Cases pinned: fresh heap 0; each push +1; each pop -1; growth (2 -> 4 -> 8)
// does not change the count; drain to 0; push after drain restarts the count;
// peek does not change the count.
//
// GREEN (contract): deterministic byte-exact stdout `heapLen ok\n` (RUNRC=0).
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

pub fn main() void {
    var v1: u32 = 1;
    var v2: u32 = 2;
    var v3: u32 = 3;
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);
    var p3: *void = @ptrCast(*void, &v3);

    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var h = heap_mod.heapInit(&ar, 2) catch {
        @panic("init");
    };

    ck(heap_mod.heapLen(&h) == 0, "fresh 0");

    push(&h, 5, p1, "push 5");
    ck(heap_mod.heapLen(&h) == 1, "len 1");
    push(&h, 1, p2, "push 1");
    ck(heap_mod.heapLen(&h) == 2, "len 2");
    push(&h, 3, p3, "push 3");
    ck(heap_mod.heapLen(&h) == 3, "len 3 (grown 2->4)");
    push(&h, 2, p1, "push 2");
    ck(heap_mod.heapLen(&h) == 4, "len 4");
    push(&h, 4, p2, "push 4");
    ck(heap_mod.heapLen(&h) == 5, "len 5 (grown 4->8)");

    var pk = heap_mod.heapPeek(&h);
    ck(pk != null, "peek present");
    ck(heap_mod.heapLen(&h) == 5, "peek does not change len");

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var got = heap_mod.heapPop(&h);
        ck(got != null, "pop present");
        ck(heap_mod.heapLen(&h) == 5 - (i + 1), "len decrements on pop");
    }
    ck(heap_mod.heapLen(&h) == 0, "drained 0");
    var none = heap_mod.heapPop(&h);
    ck(none == null, "pop empty null");
    ck(heap_mod.heapLen(&h) == 0, "pop empty stays 0");

    push(&h, 11, p3, "reuse push");
    ck(heap_mod.heapLen(&h) == 1, "reuse len 1");
    var again = heap_mod.heapPop(&h);
    ck(again != null, "reuse pop present");
    ck(heap_mod.heapLen(&h) == 0, "reuse drained 0");

    if (g_fail == 0) {
        std.io.write("heapLen ok\n");
    } else {
        std.io.write("heapLen FAIL\n");
    }
}
