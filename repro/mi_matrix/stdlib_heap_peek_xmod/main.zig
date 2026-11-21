// stdlib_heap_peek_xmod — std_heap (L4) `heapPeek` GREEN fixture.
//
// Contract (blueprint §3 L4): `heapPeek(h) ?HeapItem` returns the minimum item
// without removing it, or null when empty. Peek does not allocate and does not
// change `heapLen`.
//
// Cases pinned: empty peek null; peek returns the smallest key and leaves len
// unchanged; repeated peek is identical; after a pop peek returns the next
// minimum; peek after growth; peek with negative keys.
//
// GREEN (contract): deterministic byte-exact stdout `heapPeek ok\n` (RUNRC=0).
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

fn peekIs(h: *const heap_mod.Heap, want_key: i64, want_val: *void, what: []const u8) void {
    var got = heap_mod.heapPeek(h);
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
    var p1: *void = @ptrCast(*void, &v1);
    var p2: *void = @ptrCast(*void, &v2);
    var p3: *void = @ptrCast(*void, &v3);
    var p4: *void = @ptrCast(*void, &v4);
    var p5: *void = @ptrCast(*void, &v5);
    var p6: *void = @ptrCast(*void, &v6);

    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var h = heap_mod.heapInit(&ar, 2) catch {
        @panic("init");
    };

    ck(heap_mod.heapPeek(&h) == null, "empty peek null");

    push(&h, 8, p1, "push 8");
    ck(heap_mod.heapLen(&h) == 1, "len after first");
    peekIs(&h, 8, p1, "peek single");
    peekIs(&h, 8, p1, "peek single again");
    ck(heap_mod.heapLen(&h) == 1, "len unchanged by peek");

    push(&h, 3, p2, "push 3");
    peekIs(&h, 3, p2, "peek new min");
    ck(heap_mod.heapLen(&h) == 2, "len after second");

    push(&h, 12, p3, "push 12");
    push(&h, 1, p4, "push 1");
    push(&h, 5, p5, "push 5");
    push(&h, 9, p6, "push 9");
    peekIs(&h, 1, p4, "peek min of six");
    ck(heap_mod.heapLen(&h) == 6, "len unchanged by peek six");
    peekIs(&h, 1, p4, "peek min repeated");

    // Pop the minimum; peek must advance to the next minimum.
    var popped = heap_mod.heapPop(&h);
    if (popped) |it| {
        ck(it.key == 1, "pop min");
        ck(@ptrToInt(it.value) == @ptrToInt(p4), "pop min val");
    } else {
        ck(false, "pop min present");
    }
    peekIs(&h, 3, p2, "peek next min");
    ck(heap_mod.heapLen(&h) == 5, "len after pop");

    // Negative keys are ordered correctly by peek.
    var hn = heap_mod.heapInit(&ar, 1) catch {
        @panic("init neg");
    };
    push(&hn, 0, p1, "neg push 0");
    push(&hn, -2, p2, "neg push -2");
    push(&hn, -7, p3, "neg push -7");
    peekIs(&hn, -7, p3, "neg peek min");
    ck(heap_mod.heapLen(&hn) == 3, "neg len unchanged");

    if (g_fail == 0) {
        std.io.write("heapPeek ok\n");
    } else {
        std.io.write("heapPeek FAIL\n");
    }
}
