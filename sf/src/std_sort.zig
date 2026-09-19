// std_sort.zig — Z98 std lib L4: in-place sorting and binary search.
//
// Contract (blueprint §3 L4): alloc none | errors none | coroutine no.
// Imports only L0-L2 (`std_str`); never a sibling (`std_map`/`std_heap`/
// `std_rle`) and never a higher layer (R3). `sf/src/std.zig` is NOT modified
// (Ruling F1: L4 modules are imported by path, not re-exported).
//
//   Sortable          a caller-supplied vtable over `*void` data
//   sort(s)           introsort through the vtable
//   sortI32(items)    concrete wrapper
//   sortU32(items)    concrete wrapper
//   sortStr(items)    concrete wrapper (lexicographic, unsigned bytes)
//   binarySearchU32(items, key) ?usize   (requires sorted input)
//
// Algorithm: introsort — quicksort with median-of-three pivot selection, a
// recursion-depth limit of 2*floor(log2(n)), and a heapsort fallback once the
// limit is exhausted; ranges at or below INSERTION_THRESHOLD finish with an
// insertion sort. Worst case O(n log n); in place, no allocation.
//
// Stability (R6): NOT stable. Equal elements may be reordered. `sortI32`/
// `sortU32`/`sortStr` are likewise not stable. Callers needing stability must
// sort by a total order (e.g. a composite key).
//
// Determinism (R6): the comparison/swap sequence is a pure function of the
// input values and their initial order — no address, clock, or PID input — so
// the same input yields the same output on every run. The vtable's own
// callbacks are the caller's responsibility.
//
// `binarySearchU32` assumes `items` is sorted in non-decreasing order (e.g. by
// `sortU32`); on unsorted input the result is unspecified. It returns the index
// of an element equal to `key` (any one of several duplicates) or null.

const str_mod = @import("std_str.zig");

// Ranges of at most this many elements are finished with insertion sort.
const INSERTION_THRESHOLD: usize = 16;

pub const Sortable = struct {
    lenFn: fn(*void) usize,
    lessFn: fn(*void, usize, usize) bool,
    swapFn: fn(*void, usize, usize) void,
    data: *void,
};

// ---- vtable helpers -------------------------------------------------------

fn vlen(s: *Sortable) usize {
    return s.lenFn(s.data);
}

fn vless(s: *Sortable, i: usize, j: usize) bool {
    return s.lessFn(s.data, i, j);
}

fn vswap(s: *Sortable, i: usize, j: usize) void {
    s.swapFn(s.data, i, j);
}

// ---- insertion sort (finishes small ranges) -------------------------------

fn insertionSort(s: *Sortable, lo: usize, hi: usize) void {
    var i: usize = lo + 1;
    while (i < hi) : (i += 1) {
        var j: usize = i;
        while (j > lo) {
            if (!vless(s, j, j - 1)) break;
            vswap(s, j, j - 1);
            j -= 1;
        }
    }
}

// ---- heapsort (introsort fallback; bounds the worst case) -----------------

fn siftDown(s: *Sortable, lo: usize, n: usize, start: usize) void {
    var root: usize = start;
    while (root * 2 + 1 < n) {
        var child: usize = root * 2 + 1;
        if (child + 1 < n and vless(s, lo + child, lo + child + 1)) {
            child += 1;
        }
        if (vless(s, lo + root, lo + child)) {
            vswap(s, lo + root, lo + child);
            root = child;
        } else {
            return;
        }
    }
}

fn heapSortRange(s: *Sortable, lo: usize, hi: usize) void {
    var n: usize = hi - lo;
    if (n < 2) return;
    var start: usize = n / 2;
    while (start > 0) {
        start -= 1;
        siftDown(s, lo, n, start);
    }
    var end: usize = n;
    while (end > 1) {
        end -= 1;
        vswap(s, lo, lo + end);
        siftDown(s, lo, end, 0);
    }
}

// ---- quicksort partition (median-of-three pivot, Lomuto scheme) -----------

fn medianOfThree(s: *Sortable, a: usize, b: usize, c: usize) usize {
    if (vless(s, a, b)) {
        if (vless(s, b, c)) return b;
        if (vless(s, a, c)) return c;
        return a;
    } else {
        if (vless(s, a, c)) return a;
        if (vless(s, b, c)) return c;
        return b;
    }
}

fn partition(s: *Sortable, lo: usize, hi: usize) usize {
    var mid: usize = lo + (hi - lo) / 2;
    var pi: usize = medianOfThree(s, lo, mid, hi - 1);
    vswap(s, pi, hi - 1);
    var pivot: usize = hi - 1;
    var store: usize = lo;
    var i: usize = lo;
    while (i < pivot) : (i += 1) {
        if (vless(s, i, pivot)) {
            vswap(s, i, store);
            store += 1;
        }
    }
    vswap(s, store, pivot);
    return store;
}

// ---- introsort driver ------------------------------------------------------

fn sortRange(s: *Sortable, lo: usize, hi: usize, depth: usize) void {
    var l: usize = lo;
    var h: usize = hi;
    var d: usize = depth;
    while (h - l > INSERTION_THRESHOLD) {
        if (d == 0) {
            heapSortRange(s, l, h);
            return;
        }
        d -= 1;
        var p: usize = partition(s, l, h);
        var left_n: usize = p - l;
        var right_n: usize = h - (p + 1);
        // Recurse into the smaller side, loop on the larger: bounds the C stack.
        if (left_n < right_n) {
            sortRange(s, l, p, d);
            l = p + 1;
        } else {
            sortRange(s, p + 1, h, d);
            h = p;
        }
    }
    insertionSort(s, l, h);
}

pub fn sort(s: Sortable) void {
    var n: usize = s.lenFn(s.data);
    if (n < 2) return;
    var depth: usize = 0;
    var m: usize = n;
    while (m > 1) : (m = m / 2) {
        depth += 1;
    }
    depth = depth * 2;
    var ss: Sortable = s;
    sortRange(&ss, 0, n, depth);
}

// ---- concrete wrappers -----------------------------------------------------

const I32Box = struct { items: []i32 };

fn i32Len(data: *void) usize {
    var b: *I32Box = @ptrCast(*I32Box, data);
    return b.items.len;
}

fn i32Less(data: *void, i: usize, j: usize) bool {
    var b: *I32Box = @ptrCast(*I32Box, data);
    return b.items[i] < b.items[j];
}

fn i32Swap(data: *void, i: usize, j: usize) void {
    var b: *I32Box = @ptrCast(*I32Box, data);
    var t: i32 = b.items[i];
    b.items[i] = b.items[j];
    b.items[j] = t;
}

pub fn sortI32(items: []i32) void {
    var box = I32Box{ .items = items };
    var s = Sortable{
        .lenFn = i32Len,
        .lessFn = i32Less,
        .swapFn = i32Swap,
        .data = @ptrCast(*void, &box),
    };
    sort(s);
}

const U32Box = struct { items: []u32 };

fn u32Len(data: *void) usize {
    var b: *U32Box = @ptrCast(*U32Box, data);
    return b.items.len;
}

fn u32Less(data: *void, i: usize, j: usize) bool {
    var b: *U32Box = @ptrCast(*U32Box, data);
    return b.items[i] < b.items[j];
}

fn u32Swap(data: *void, i: usize, j: usize) void {
    var b: *U32Box = @ptrCast(*U32Box, data);
    var t: u32 = b.items[i];
    b.items[i] = b.items[j];
    b.items[j] = t;
}

pub fn sortU32(items: []u32) void {
    var box = U32Box{ .items = items };
    var s = Sortable{
        .lenFn = u32Len,
        .lessFn = u32Less,
        .swapFn = u32Swap,
        .data = @ptrCast(*void, &box),
    };
    sort(s);
}

const StrBox = struct { items: [][]const u8 };

fn strLen(data: *void) usize {
    var b: *StrBox = @ptrCast(*StrBox, data);
    return b.items.len;
}

// Lexicographic order over unsigned bytes; a proper prefix sorts first.
fn strLess(data: *void, i: usize, j: usize) bool {
    var b: *StrBox = @ptrCast(*StrBox, data);
    var a = b.items[i];
    var c = b.items[j];
    var an: usize = str_mod.len(a);
    var cn: usize = str_mod.len(c);
    var n: usize = an;
    if (cn < n) n = cn;
    var k: usize = 0;
    while (k < n) : (k += 1) {
        if (a[k] != c[k]) return a[k] < c[k];
    }
    return an < cn;
}

fn strSwap(data: *void, i: usize, j: usize) void {
    var b: *StrBox = @ptrCast(*StrBox, data);
    var t: []const u8 = b.items[i];
    b.items[i] = b.items[j];
    b.items[j] = t;
}

pub fn sortStr(items: [][]const u8) void {
    var box = StrBox{ .items = items };
    var s = Sortable{
        .lenFn = strLen,
        .lessFn = strLess,
        .swapFn = strSwap,
        .data = @ptrCast(*void, &box),
    };
    sort(s);
}

// ---- binary search ---------------------------------------------------------

pub fn binarySearchU32(items: []const u32, key: u32) ?usize {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        var mid: usize = lo + (hi - lo) / 2;
        var v: u32 = items[mid];
        if (v == key) return mid;
        if (v < key) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return null;
}
