// stdlib_heap_stress_xmod — STDLIB std_heap (L4) hand-written stress table.
//
// No PRNG: the key sequence is an explicit fixed loop (`(i*37)%500`). Stresses:
//   - 2000 pushes into a capacity-1 heap (forces every doubling), then a full
//     drain: keys non-decreasing and, among equal keys, insertion order is
//     preserved (tie stability);
//   - 600 all-equal keys drain in exact push order;
//   - push/pop interleave across further growth;
//   - the empty-pop boundary (peek/pop null, len 0) including a capacity-0 init,
//     and pop-after-drain null.
//
// GREEN (contract): deterministic byte-exact stdout `heap stress ok\n` (RUNRC=0).
const std = @import("std");
const heap_mod = @import("std_heap.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

var g_vals: [2200]i64 = undefined;
var g_backing: [4194304]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);

fn valAt(i: usize) *void {
    return @ptrCast(*void, &g_vals[i]);
}

fn idxOf(p: *void) usize {
    var i: usize = 0;
    while (i < 2200) : (i += 1) {
        if (@ptrToInt(p) == @ptrToInt(&g_vals[i])) return i;
    }
    return 2200;
}

fn push(h: *heap_mod.Heap, key: i64, i: usize, what: []const u8) void {
    var it = heap_mod.HeapItem{ .key = key, .value = valAt(i) };
    heap_mod.heapPush(h, it) catch {
        @panic(what);
    };
}

// drainStable pops every item and checks non-decreasing keys with insertion
// order preserved among equal keys.
fn drainStable(h: *heap_mod.Heap, want_n: usize, what: []const u8) void {
    var n: usize = 0;
    var pk: i64 = 0;
    var pi: i64 = -1;
    var have: bool = false;
    while (true) {
        var got = heap_mod.heapPop(h);
        if (got) |it| {
            var idx = idxOf(it.value);
            ck(idx < 2200, what);
            if (have) {
                ck(it.key >= pk, what);
                if (it.key == pk) {
                    ck(@intCast(i64, idx) > pi, what);
                } else {
                    pi = -1;
                }
            }
            pi = @intCast(i64, idx);
            pk = it.key;
            have = true;
            n += 1;
        } else {
            break;
        }
    }
    ck(n == want_n, what);
    ck(heap_mod.heapLen(h) == 0, what);
}

pub fn main() void {
    var i: usize = 0;
    while (i < 2200) : (i += 1) {
        g_vals[i] = @intCast(i64, i);
    }
    var ha = heap_mod.heapInit(&g_arena, 1) catch {
        @panic("A init");
    };
    i = 0;
    while (i < 2000) : (i += 1) {
        push(&ha, @intCast(i64, (i * 37) % 500), i, "A push");
    }
    ck(heap_mod.heapLen(&ha) == 2000, "A len");
    drainStable(&ha, 2000, "A drain");

    // ---- B: 600 all-equal keys drain in exact push order -------------------
    var hb = heap_mod.heapInit(&g_arena, 2) catch {
        @panic("B init");
    };
    i = 0;
    while (i < 600) : (i += 1) {
        push(&hb, 7, i, "B push");
    }
    var n: usize = 0;
    while (true) {
        var got = heap_mod.heapPop(&hb);
        if (got) |it| {
            ck(it.key == 7, "B key");
            ck(idxOf(it.value) == n, "B exact push order");
            n += 1;
        } else {
            break;
        }
    }
    ck(n == 600, "B count");

    // ---- C: push/pop interleave across growth ------------------------------
    var hc = heap_mod.heapInit(&g_arena, 4) catch {
        @panic("C init");
    };
    i = 0;
    while (i < 100) : (i += 1) {
        push(&hc, @intCast(i64, (i * 13) % 97), i, "C push a");
    }
    i = 0;
    while (i < 30) : (i += 1) {
        var got = heap_mod.heapPop(&hc);
        ck(got != null, "C pop a");
    }
    ck(heap_mod.heapLen(&hc) == 70, "C len after pops");
    i = 100;
    while (i < 200) : (i += 1) {
        push(&hc, @intCast(i64, (i * 13) % 97), i, "C push b");
    }
    ck(heap_mod.heapLen(&hc) == 170, "C len after second push");
    drainStable(&hc, 170, "C drain");

    // ---- D: empty-pop boundary (capacity 0) --------------------------------
    var hd = heap_mod.heapInit(&g_arena, 0) catch {
        @panic("D init");
    };
    ck(heap_mod.heapLen(&hd) == 0, "D empty len");
    ck(heap_mod.heapPeek(&hd) == null, "D empty peek");
    ck(heap_mod.heapPop(&hd) == null, "D empty pop");
    push(&hd, 42, 0, "D push");
    ck(heap_mod.heapLen(&hd) == 1, "D len 1");
    var pk = heap_mod.heapPeek(&hd);
    if (pk) |it| {
        ck(it.key == 42, "D peek key");
    } else {
        ck(false, "D peek missing");
    }
    var gp = heap_mod.heapPop(&hd);
    if (gp) |it| {
        ck(it.key == 42, "D pop key");
    } else {
        ck(false, "D pop missing");
    }
    ck(heap_mod.heapPop(&hd) == null, "D pop after drain null");

    // ---- E: empty and single via a fresh heap ------------------------------
    var he = heap_mod.heapInit(&g_arena, 8) catch {
        @panic("E init");
    };
    ck(heap_mod.heapPeek(&he) == null, "E peek empty");
    push(&he, -5, 1, "E push");
    var ep = heap_mod.heapPeek(&he);
    if (ep) |it| {
        ck(it.key == -5, "E peek single");
    } else {
        ck(false, "E peek single missing");
    }
    var eq = heap_mod.heapPop(&he);
    if (eq) |it| {
        ck(it.key == -5, "E pop single");
    } else {
        ck(false, "E pop single missing");
    }
    ck(heap_mod.heapLen(&he) == 0, "E len after single");

    if (g_fail == 0) {
        std.io.write("heap stress ok\n");
    } else {
        std.io.write("heap stress FAIL\n");
    }
}
