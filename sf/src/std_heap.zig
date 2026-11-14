// std_heap.zig — Z98 std lib L4: binary min-heap over (i64 key, *void value).
//
// Contract (blueprint §3 L4): alloc arena at init | errors OutOfMemory |
// coroutine no. Imports only L1 (`std_arena`) — never a sibling (`std_map`/
// `std_sort`/`std_rle`) and never a higher layer (R3). `sf/src/std.zig` is NOT
// modified (Ruling F1: L4 modules are imported by path, not re-exported).
//
//   HeapItem                   { key: i64, value: *void }
//   heapInit(arena, capacity)  allocate a `capacity`-entry table from the arena
//   heapPush(h, item)          append + sift up; grows the table when full
//   heapPop(h) ?HeapItem       remove + return the minimum, or null when empty
//   heapPeek(h) ?HeapItem      the minimum without removal, or null when empty
//   heapLen(h) usize           number of live items
//
// Min-heap on `key`. Ties broken by insertion order (stable): each push stamps
// the item with a monotonically increasing sequence number and the heap orders
// by (key, seq), so among equal keys the earliest-inserted item pops first.
//
// Determinism (R6): the sift sequence is a pure function of the pushed items
// and their order — no address, clock, or PID input. Growth allocates a new,
// larger table from the arena and copies the live entries; the arena never
// frees, so a failed growth leaves the heap and the arena untouched and reports
// error.OutOfMemory. `heapPop`/`heapPeek`/`heapLen` never allocate.

const arena_mod = @import("std_arena.zig");

pub const HeapItem = struct {
    key: i64,
    value: *void,
};

// Internal entry: the public item plus the stability sequence number.
const HeapEntry = struct {
    key: i64,
    value: *void,
    seq: u64,
};

pub const Heap = struct {
    arena: *arena_mod.Arena,
    items: [*]HeapEntry,
    capacity: usize,
    len: usize,
    seq: u64,
};

// Total order: key first, then insertion order. The strict sequence makes the
// order total, so the heap is a correct min-heap with stable tie-breaking.
fn less(a: HeapEntry, b: HeapEntry) bool {
    if (a.key != b.key) return a.key < b.key;
    return a.seq < b.seq;
}

fn swap(h: *Heap, i: usize, j: usize) void {
    var t: HeapEntry = h.items[i];
    h.items[i] = h.items[j];
    h.items[j] = t;
}

fn siftUp(h: *Heap, start: usize) void {
    var idx: usize = start;
    while (idx > 0) {
        var parent: usize = (idx - 1) / 2;
        if (!less(h.items[idx], h.items[parent])) break;
        swap(h, idx, parent);
        idx = parent;
    }
}

fn siftDown(h: *Heap, start: usize) void {
    var idx: usize = start;
    while (true) {
        var left: usize = idx * 2 + 1;
        if (left >= h.len) break;
        var small: usize = left;
        var right: usize = left + 1;
        if (right < h.len and less(h.items[right], h.items[left])) {
            small = right;
        }
        if (!less(h.items[small], h.items[idx])) break;
        swap(h, idx, small);
        idx = small;
    }
}

// Grow the backing table from the arena. The new table is fully allocated and
// populated BEFORE `h` is mutated, so a failed allocation leaves the heap
// exactly as it was (and consumes no arena bytes).
fn grow(h: *Heap) arena_mod.ArenaError!void {
    var new_cap: usize = h.capacity * 2;
    if (new_cap == 0) new_cap = 1;
    var bytes: usize = new_cap * @sizeOf(HeapEntry);
    var raw = try arena_mod.alloc(h.arena, bytes);
    var p: [*]HeapEntry = @ptrCast([*]HeapEntry, raw);
    var i: usize = 0;
    while (i < h.len) : (i += 1) {
        p[i] = h.items[i];
    }
    h.items = p;
    h.capacity = new_cap;
}

pub fn heapInit(arena: *arena_mod.Arena, capacity: usize) !Heap {
    var bytes: usize = capacity * @sizeOf(HeapEntry);
    var raw = try arena_mod.alloc(arena, bytes);
    var p: [*]HeapEntry = @ptrCast([*]HeapEntry, raw);
    return Heap{ .arena = arena, .items = p, .capacity = capacity, .len = 0, .seq = 0 };
}

pub fn heapPush(h: *Heap, item: HeapItem) !void {
    if (h.len == h.capacity) {
        try grow(h);
    }
    var idx: usize = h.len;
    h.items[idx] = HeapEntry{ .key = item.key, .value = item.value, .seq = h.seq };
    h.seq += 1;
    h.len += 1;
    siftUp(h, idx);
}

pub fn heapPop(h: *Heap) ?HeapItem {
    if (h.len == 0) return null;
    var top: HeapEntry = h.items[0];
    h.len -= 1;
    if (h.len > 0) {
        h.items[0] = h.items[h.len];
        siftDown(h, 0);
    }
    return HeapItem{ .key = top.key, .value = top.value };
}

pub fn heapPeek(h: *const Heap) ?HeapItem {
    if (h.len == 0) return null;
    return HeapItem{ .key = h.items[0].key, .value = h.items[0].value };
}

pub fn heapLen(h: *const Heap) usize {
    return h.len;
}
