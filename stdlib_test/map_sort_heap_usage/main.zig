// stdlib_test/map_sort_heap_usage — Plan C Task 9 (R7b) usage program.
//
// Composes std_map (L4) + std_sort (L4) + std_heap (L4) into one intended
// workflow: a small record store keyed by id is built with std_map.Map32x32
// (put / replace / remove), its surviving values are drained in id order and
// sorted with std_sort.sortU32, the sorted array is binary-searched with
// std_sort.binarySearchU32, and the pre-sort value sequence is re-ordered by
// std_heap as a stable min-heap over (i64 key, *void value) with insertion
// tags proving tie stability.
//
// All inputs are fixed and all comparisons are internal asserts, so the stdout
// is a pure function of the source (no address/clock/PID input).
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   map_sort_heap_usage
//   map-len: 9
//   sorted: 0 0 1 1 2 2 3 4 9
//   search-9: 8
//   search-5: missing
//   heap: 0 0 1 1 2 2 3 4 9
//   stable: 1
//   map_sort_heap ok
// A mismatch calls @panic; the final line is `map_sort_heap ok` only on success.
const std = @import("std");
const map = @import("std_map.zig");
const sort = @import("std_sort.zig");
const heap = @import("std_heap.zig");

var g_storage: [16384]u8 = undefined;
var g_arena = std.arena.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn printU32List(tag: []const u8, items: []const u32) void {
    std.io.write(tag);
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        if (i != 0) std.io.write(" ");
        std.io.printInt(@intCast(i32, items[i]));
    }
    std.io.write("\n");
}

pub fn main() void {
    // --- std_map: build a 10-id record store, replace one, remove one -------
    var m = map.map32x32Init(&g_arena, 32) catch @panic("map init");
    ck(map.map32x32Len(&m) == 0, "fresh len");

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        map.map32x32Put(&m, i, (i * 7) % 5) catch @panic("map put");
    }
    map.map32x32Put(&m, 4, 9) catch @panic("map replace");
    ck(map.map32x32Remove(&m, 7), "map remove 7");
    ck(map.map32x32Remove(&m, 7) == false, "map remove twice");
    ck(map.map32x32Len(&m) == 9, "map len 9");

    // Drain the surviving values in id order (ids 0..9 except the removed 7).
    var vals: [9]u32 = undefined;
    var n: usize = 0;
    i = 0;
    while (i < 10) : (i += 1) {
        if (i != 7) {
            var got = map.map32x32Get(&m, i);
            if (got) |v| {
                vals[n] = v;
                n += 1;
            } else {
                ck(false, "map get");
            }
        }
    }
    ck(n == 9, "drained 9");

    // --- std_sort: ascending sort + binary search ---------------------------
    var sorted: [9]u32 = undefined;
    i = 0;
    while (i < 9) : (i += 1) {
        sorted[i] = vals[i];
    }
    sort.sortU32(sorted[0..]);
    i = 1;
    while (i < 9) : (i += 1) {
        ck(sorted[i - 1] <= sorted[i], "sort ascending");
    }

    var found9 = sort.binarySearchU32(sorted[0..], 9);
    var found5 = sort.binarySearchU32(sorted[0..], 5);
    ck(found9 != null, "binary search 9");
    ck(found5 == null, "binary search 5");

    // --- std_heap: stable min-heap over the pre-sort values -----------------
    // tags[i] is a distinct cell so each pushed item carries a verifiable
    // identity; among equal keys the earliest-inserted item must pop first.
    var tags: [9]u32 = undefined;
    i = 0;
    while (i < 9) : (i += 1) {
        tags[i] = i;
    }
    var h = heap.heapInit(&g_arena, 1) catch @panic("heap init");
    i = 0;
    while (i < 9) : (i += 1) {
        var it = heap.HeapItem{ .key = @intCast(i64, vals[i]), .value = @ptrCast(*void, &tags[i]) };
        heap.heapPush(&h, it) catch @panic("heap push");
    }
    var expect_tags = [_]u32{ 0, 5, 3, 7, 1, 6, 8, 2, 4 };
    var hkeys: [9]u32 = undefined;
    i = 0;
    while (i < 9) : (i += 1) {
        var got = heap.heapPop(&h);
        if (got) |it| {
            hkeys[i] = @intCast(u32, it.key);
            var idx: usize = (@ptrToInt(it.value) - @ptrToInt(&tags[0])) / @sizeOf(u32);
            ck(idx == @intCast(usize, expect_tags[i]), "heap stable tag");
        } else {
            ck(false, "heap pop");
        }
    }
    ck(heap.heapLen(&h) == 0, "heap empty");
    ck(heap.heapPop(&h) == null, "heap null after drain");

    // --- stdout contract ----------------------------------------------------
    std.io.write("map_sort_heap_usage\n");
    std.io.write("map-len: ");
    std.io.printInt(@intCast(i32, map.map32x32Len(&m)));
    std.io.write("\n");
    printU32List("sorted: ", sorted[0..]);
    std.io.write("search-9: ");
    if (found9) |ix| {
        std.io.printInt(@intCast(i32, ix));
    } else {
        std.io.write("missing");
    }
    std.io.write("\n");
    std.io.write("search-5: ");
    if (found5) |ix2| {
        std.io.printInt(@intCast(i32, ix2));
    } else {
        std.io.write("missing");
    }
    std.io.write("\n");
    printU32List("heap: ", hkeys[0..]);
    std.io.write("stable: 1\n");
    std.io.write("map_sort_heap ok\n");
}
