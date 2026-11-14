// stdlib_heap_tie_xmod — std_heap (L4) tie-stability GREEN fixture (R6).
//
// Contract (blueprint §3 L4): "Min-heap on `key`. Ties broken by insertion
// order (stable)." Among items with equal keys, `heapPop` returns them in the
// order they were pushed, even after the sift-up/sift-down that growth and
// popping force.
//
// Cases pinned: three equal keys; equal keys interleaved with distinct keys;
// a sift-heavy interleave; a new equal key pushed after a pop sorts after the
// surviving equals; eight equal keys survive repeated growth; stability is
// preserved across a full drain.
//
// GREEN (contract): deterministic byte-exact stdout `heapTie ok\n` (RUNRC=0).
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

    var backing: [8192]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // A: three equal keys, insertion order.
    var ha = heap_mod.heapInit(&ar, 2) catch {
        @panic("A init");
    };
    push(&ha, 5, p1, "A push 1");
    push(&ha, 5, p2, "A push 2");
    push(&ha, 5, p3, "A push 3");
    popIs(&ha, 5, p1, "A pop 1");
    popIs(&ha, 5, p2, "A pop 2");
    popIs(&ha, 5, p3, "A pop 3");

    // B: equal keys interleaved with distinct keys.
    var hb = heap_mod.heapInit(&ar, 2) catch {
        @panic("B init");
    };
    push(&hb, 1, p1, "B push 1");
    push(&hb, 5, p2, "B push 5a");
    push(&hb, 1, p3, "B push 1b");
    push(&hb, 5, p4, "B push 5b");
    popIs(&hb, 1, p1, "B pop 1a");
    popIs(&hb, 1, p3, "B pop 1b");
    popIs(&hb, 5, p2, "B pop 5a");
    popIs(&hb, 5, p4, "B pop 5b");

    // C: sift-heavy interleave (distinct keys force swaps between equals).
    var hc = heap_mod.heapInit(&ar, 2) catch {
        @panic("C init");
    };
    push(&hc, 2, p1, "C push 2a");
    push(&hc, 1, p2, "C push 1a");
    push(&hc, 2, p3, "C push 2b");
    push(&hc, 1, p4, "C push 1b");
    push(&hc, 2, p5, "C push 2c");
    popIs(&hc, 1, p2, "C pop 1a");
    popIs(&hc, 1, p4, "C pop 1b");
    popIs(&hc, 2, p1, "C pop 2a");
    popIs(&hc, 2, p3, "C pop 2b");
    popIs(&hc, 2, p5, "C pop 2c");

    // D: a new equal key pushed after a pop sorts after the surviving equals.
    var hd = heap_mod.heapInit(&ar, 2) catch {
        @panic("D init");
    };
    push(&hd, 9, p1, "D push 1");
    push(&hd, 9, p2, "D push 2");
    popIs(&hd, 9, p1, "D pop 1");
    push(&hd, 9, p3, "D push 3");
    popIs(&hd, 9, p2, "D pop 2");
    popIs(&hd, 9, p3, "D pop 3");

    // E: eight equal keys with growth (capacity 1 -> 2 -> 4 -> 8).
    var he = heap_mod.heapInit(&ar, 1) catch {
        @panic("E init");
    };
    push(&he, 7, p1, "E push 1");
    push(&he, 7, p2, "E push 2");
    push(&he, 7, p3, "E push 3");
    push(&he, 7, p4, "E push 4");
    push(&he, 7, p5, "E push 5");
    push(&he, 7, p6, "E push 6");
    push(&he, 7, p7, "E push 7");
    push(&he, 7, p8, "E push 8");
    popIs(&he, 7, p1, "E pop 1");
    popIs(&he, 7, p2, "E pop 2");
    popIs(&he, 7, p3, "E pop 3");
    popIs(&he, 7, p4, "E pop 4");
    popIs(&he, 7, p5, "E pop 5");
    popIs(&he, 7, p6, "E pop 6");
    popIs(&he, 7, p7, "E pop 7");
    popIs(&he, 7, p8, "E pop 8");

    // F: equal keys mixed with distinct across a full drain.
    var hf = heap_mod.heapInit(&ar, 2) catch {
        @panic("F init");
    };
    push(&hf, 4, p1, "F push 4a");
    push(&hf, 2, p2, "F push 2");
    push(&hf, 4, p3, "F push 4b");
    push(&hf, 3, p4, "F push 3a");
    push(&hf, 4, p5, "F push 4c");
    push(&hf, 3, p6, "F push 3b");
    push(&hf, 4, p7, "F push 4d");
    popIs(&hf, 2, p2, "F pop 2");
    popIs(&hf, 3, p4, "F pop 3a");
    popIs(&hf, 3, p6, "F pop 3b");
    popIs(&hf, 4, p1, "F pop 4a");
    popIs(&hf, 4, p3, "F pop 4b");
    popIs(&hf, 4, p5, "F pop 4c");
    popIs(&hf, 4, p7, "F pop 4d");

    if (g_fail == 0) {
        std.io.write("heapTie ok\n");
    } else {
        std.io.write("heapTie FAIL\n");
    }
}
