// stdlib_sort_introsort_xmod — std_sort (L4) introsort-core coverage fixture.
//
// The other std_sort fixtures use inputs of at most 10 elements, which stay
// below INSERTION_THRESHOLD (16): they never enter `sortRange`'s quicksort
// loop, so `partition`, `medianOfThree`, `heapSortRange` and `siftDown` would
// be dead code under test. This fixture drives 200-element inputs through the
// real core, in both the concrete `sortU32` wrapper and the user `Sortable`
// vtable path.
//
// Patterns pinned (all length 200; each verified sorted + multiset-preserving):
//   - random (LCG, values < 1000);
//   - reverse-sorted (adversarial for a last-element pivot; exercises
//     median-of-three);
//   - all-equal (depth limit exhausts -> heapsort fallback);
//   - few-distinct / many-duplicates (LCG % 3; unbalanced partitions -> the
//     heapsort fallback runs on mixed values);
//   - organ pipe 0..99,99..0 (distinct values; the fallback runs and must
//     actually order them);
//   - a 200-element user `Pair` array sorted by key through `Sortable`.
//
// Multiset preservation is checked with a per-value count histogram (and the
// val-sum for the Pair case), so a "sort" that dropped or duplicated elements
// fails even if the result is non-decreasing.
//
// GREEN (contract): deterministic byte-exact stdout `introsort ok\n` (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

const N: usize = 200;
const HIST: usize = 1024;

const Pair = struct {
    key: u32,
    val: u32,
};

const PairBox = struct {
    items: []Pair,
};

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn histZero(h: []u32) void {
    var i: usize = 0;
    while (i < h.len) : (i += 1) h[i] = 0;
}

// Sorts `a` with sortU32 and checks sortedness + equal value histogram.
fn runU32(a: []u32, what: []const u8) void {
    var before: [HIST]u32 = undefined;
    var after: [HIST]u32 = undefined;
    histZero(before[0..]);
    var i: usize = 0;
    while (i < a.len) : (i += 1) before[a[i]] += 1;

    sort.sortU32(a);

    i = 1;
    while (i < a.len) : (i += 1) ck(a[i - 1] <= a[i], what);
    histZero(after[0..]);
    i = 0;
    while (i < a.len) : (i += 1) after[a[i]] += 1;
    i = 0;
    while (i < HIST) : (i += 1) ck(before[i] == after[i], what);
}

fn pairLen(data: *void) usize {
    var b: *PairBox = @ptrCast(*PairBox, data);
    return b.items.len;
}

fn pairLess(data: *void, i: usize, j: usize) bool {
    var b: *PairBox = @ptrCast(*PairBox, data);
    return b.items[i].key < b.items[j].key;
}

fn pairSwap(data: *void, i: usize, j: usize) void {
    var b: *PairBox = @ptrCast(*PairBox, data);
    var t: Pair = b.items[i];
    b.items[i] = b.items[j];
    b.items[j] = t;
}

// Sorts a user Pair array by key through the vtable and checks keys are
// non-decreasing, the key histogram is preserved, and the val-sum survives.
fn runPairs(items: []Pair, what: []const u8) void {
    var before: [HIST]u32 = undefined;
    histZero(before[0..]);
    var valsum: u32 = 0;
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        before[items[i].key] += 1;
        valsum += items[i].val;
    }

    var box = PairBox{ .items = items };
    var s = sort.Sortable{
        .lenFn = pairLen,
        .lessFn = pairLess,
        .swapFn = pairSwap,
        .data = @ptrCast(*void, &box),
    };
    sort.sort(s);

    i = 1;
    while (i < items.len) : (i += 1) ck(items[i - 1].key <= items[i].key, what);
    var after: [HIST]u32 = undefined;
    histZero(after[0..]);
    var v2: u32 = 0;
    i = 0;
    while (i < items.len) : (i += 1) {
        after[items[i].key] += 1;
        v2 += items[i].val;
    }
    i = 0;
    while (i < HIST) : (i += 1) ck(before[i] == after[i], what);
    ck(v2 == valsum, what);
}

pub fn main() void {
    var a: [N]u32 = undefined;
    var i: usize = 0;
    var st: u32 = 12345;

    // random
    i = 0;
    while (i < N) : (i += 1) {
        st = st *% 1664525 +% 1013904223;
        a[i] = st % 1000;
    }
    runU32(a[0..], "introsort random");

    // reverse sorted
    i = 0;
    while (i < N) : (i += 1) a[i] = @intCast(u32, N - i);
    runU32(a[0..], "introsort reverse");

    // all equal (depth exhaustion -> heapsort fallback)
    i = 0;
    while (i < N) : (i += 1) a[i] = 7;
    runU32(a[0..], "introsort equal");

    // few distinct / many duplicates (fallback on mixed values)
    st = 999;
    i = 0;
    while (i < N) : (i += 1) {
        st = st *% 1664525 +% 1013904223;
        a[i] = st % 3;
    }
    runU32(a[0..], "introsort dup");

    // organ pipe (distinct values; fallback must order them)
    i = 0;
    while (i < N / 2) : (i += 1) {
        a[i] = @intCast(u32, i);
        a[N - 1 - i] = @intCast(u32, i);
    }
    runU32(a[0..], "introsort organ");

    // large user-type vtable path
    var p: [N]Pair = undefined;
    st = 424242;
    i = 0;
    while (i < N) : (i += 1) {
        st = st *% 1664525 +% 1013904223;
        p[i].key = st % 1024;
        st = st *% 1664525 +% 1013904223;
        p[i].val = st % 100;
    }
    runPairs(p[0..], "introsort pairs");

    if (g_fail == 0) {
        std.io.write("introsort ok\n");
    } else {
        std.io.write("introsort FAIL\n");
    }
}
