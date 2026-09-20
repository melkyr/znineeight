# Collections — `std_map` + `std_sort` + `std_heap` + `std_rle`

| | |
|---|---|
| **Modules** | `std_map`, `std_sort`, `std_heap`, `std_rle` |
| **Layers** | `L4` — collections layer: concrete hash maps, in-place sort and binary search, a stable binary min-heap, and run-length encoding; the allocating members draw from a caller `std.arena` (R1) |
| **Import (by path)** | `const std_map = @import("std_map");`, `const std_sort = @import("std_sort");`, `const std_heap = @import("std_heap");`, `const std_rle = @import("std_rle");` |

## Module overview

Z98 has **no generics**, so these modules are concrete: each collection is
declared over fixed key/value types rather than parameterized. All four are L4
and imported by path (not re-exported through `std`).

**`std_map` — three fixed-capacity hash maps.** `Map32x32` maps `u32 -> u32`,
`Map32Ptr` maps `u32 -> *void`, and `MapStrPtr` maps `[]const u8 -> *void`. Each
is open-addressed with linear probing over a table allocated once from the
caller's arena at `init`; `put` on an existing key replaces the value in place,
and a new key on a full table is `error.OutOfMemory`. `remove` marks the slot a
tombstone so probe chains stay intact, and a later `put` reuses it. `MapStrPtr`
copies each key byte-for-byte into the arena at `put`, so a stored key never
aliases the caller's buffer; lookups compare by byte content (`std_str.eql`).
The maps never free — arena reset reclaims everything. Iteration over the
backing table is deterministic (slot index ascending), because the slot a key
occupies is a pure function of the key, the capacity, and the insertion/removal
sequence (R6).

**`std_sort` — introsort and a `u32` binary search.** `sort` drives a
caller-supplied vtable (`Sortable`) through quicksort with a median-of-three
pivot, a recursion-depth limit of `2*floor(log2(n))`, a heapsort fallback once
the limit is exhausted, and an insertion sort for ranges of at most 16.
`sortI32`/`sortU32`/`sortStr` are concrete wrappers. Sorting is in place and
allocation-free, and it is **not stable**: equal elements may be reordered.
`binarySearchU32` assumes non-decreasing input and returns the index of any
matching element, or `null`.

**`std_heap` — a stable binary min-heap.** `Heap` orders `(i64 key, *void
value)` items by key, with ties broken by a monotonically increasing insertion
sequence, so among equal keys the earliest-inserted item pops first. The table is
allocated from the arena at `heapInit` and grows by doubling on `heapPush` when
full. Growth allocates and populates the new table **before** mutating the heap,
so a failed growth leaves the heap and the arena untouched and reports
`error.OutOfMemory`.

**`std_rle` — byte-oriented run-length encoding.** The wire format is a 4-byte
little-endian `u32` decoded-length prefix followed by tokens: a literal byte with
the high bit clear (`b < 0x80`), or a run control byte `0x80 | (n - 1)` plus a
value byte, emitting `v` `n` times (`1 <= n <= 128`). A maximal run of `n` equal
bytes is a single literal when `n == 1` and `v < 0x80`, and otherwise one or more
run tokens of at most 128 bytes each (a 129-run is `0xFF v` + `0x80 v`).
`encodedLen`/`decodedLen` allocate nothing; `encode`/`decode` allocate only their
output.

## Quick start

Build a small map, drain it in key order, sort the values, and search.

```zig
const std = @import("std");
const std_map = @import("std_map");
const std_sort = @import("std_sort");

var backing: [16384]u8 = undefined;
var arena = std.arena.init(backing[0..]);

pub fn main() void {
    var m = std_map.map32x32Init(&arena, 32) catch @panic("map init");
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        std_map.map32x32Put(&m, i, (i * 7) % 5) catch @panic("put");
    }
    _ = std_map.map32x32Remove(&m, 3);

    var vals: [7]u32 = undefined;
    var n: usize = 0;
    i = 0;
    while (i < 8) : (i += 1) {
        if (i == 3) continue;
        if (std_map.map32x32Get(&m, i)) |v| {
            vals[n] = v;
            n += 1;
        }
    }

    std_sort.sortU32(vals[0..n]);
    if (std_sort.binarySearchU32(vals[0..n], 2)) |ix| {
        std.io.printInt(@intCast(i32, ix));
        std.io.writeByte('\n');
    }
    std.arena.reset(&arena);
}
```

## API

### `std_map`

#### `Map32x32`

**Purpose** — an open-addressed `u32 -> u32` map with a fixed capacity.

**When to use** — integer-keyed lookups where the key set is known up front.
For a `*void` value use `Map32Ptr`; for string keys use `MapStrPtr`.

**Signature** — `pub const Map32x32 = struct { entries: [*]Entry32x32, capacity: usize, len: usize };`

**Parameters** (fields)
- `entries` — pointer to the caller-arena table (`Entry32x32` is private).
- `capacity` — number of slots; fixed at `init`.
- `len` — live entries (excludes tombstones).

**Returns** — a plain value type; `map32x32Init` returns one by value.

**Errors** — none.

**Example**
```zig
var m = std_map.map32x32Init(&arena, 32) catch @panic("init");
```

**Gotchas** — the table is arena-owned and never freed; reclaim it with
`arena.reset`. Do not write the fields by hand.

#### `Map32Ptr`

**Purpose** — an open-addressed `u32 -> *void` map with a fixed capacity.

**When to use** — integer-keyed maps of opaque pointers. For integer values use
`Map32x32`; for string keys use `MapStrPtr`.

**Signature** — `pub const Map32Ptr = struct { entries: [*]Entry32Ptr, capacity: usize, len: usize };`

**Parameters** (fields)
- `entries` — pointer to the caller-arena table (`Entry32Ptr` is private).
- `capacity` — number of slots; fixed at `init`.
- `len` — live entries (excludes tombstones).

**Returns** — a plain value type; `map32PtrInit` returns one by value.

**Errors** — none.

**Example**
```zig
var m = std_map.map32PtrInit(&arena, 16) catch @panic("init");
```

**Gotchas** — the map stores the pointer, not what it points at; keep the
pointee alive.

#### `MapStrPtr`

**Purpose** — an open-addressed `[]const u8 -> *void` map whose string keys are
copied into the arena at `put`.

**When to use** — string-keyed maps of opaque pointers.

**Signature** — `pub const MapStrPtr = struct { arena: *arena_mod.Arena, entries: [*]EntryStrPtr, capacity: usize, len: usize };`

**Parameters** (fields)
- `arena` — the arena that owns the copied keys (used by `put`).
- `entries` — pointer to the caller-arena table (`EntryStrPtr` is private).
- `capacity` — number of slots; fixed at `init`.
- `len` — live entries (excludes tombstones).

**Returns** — a plain value type; `mapStrPtrInit` returns one by value.

**Errors** — none.

**Example**
```zig
var m = std_map.mapStrPtrInit(&arena, 16) catch @panic("init");
```

**Gotchas** — `put` copies the key, so a stored key never aliases the caller's
buffer; lookup is by byte content. The map never frees keys; `arena.reset`
reclaims them.

#### `map32x32Init`

**Purpose** — allocates a zeroed `capacity`-slot `Map32x32` table from the arena.

**When to use** — the entry point for an integer map.

**Signature** — `pub fn map32x32Init(arena: *arena_mod.Arena, capacity: usize) !Map32x32`

**Parameters**
- `arena` — the allocation source.
- `capacity` — number of slots. `0` is allowed and yields an always-full map.

**Returns** — a `Map32x32` with `len == 0`.

**Errors** — `error.OutOfMemory` when the arena cannot provide
`capacity * @sizeOf(Entry32x32)` bytes.

**Example**
```zig
var m = std_map.map32x32Init(&arena, 32) catch @panic("init");
```

**Gotchas** — the table is not resized; size `capacity` for the worst case. With
`capacity == 0`, every `put` returns `OutOfMemory`.

#### `map32x32Get`

**Purpose** — looks up `key` and returns its value.

**When to use** — the read path.

**Signature** — `pub fn map32x32Get(m: *Map32x32, key: u32) ?u32`

**Parameters**
- `m` — the map.
- `key` — the key to find.

**Returns** — `?u32`: the stored value, or `null` when the key is absent (or the
capacity is 0).

**Errors** — none; absence is the `null` optional.

**Example**
```zig
if (std_map.map32x32Get(&m, 7)) |v| {
    std.io.printInt(@intCast(i32, v));
}
```

**Gotchas** — a removed key reads as absent. The probe stops at the first empty
slot, which is why removal uses tombstones rather than clearing.

#### `map32x32Put`

**Purpose** — inserts or replaces the value for `key`.

**When to use** — the write path; replaces in place on an existing key.

**Signature** — `pub fn map32x32Put(m: *Map32x32, key: u32, val: u32) !void`

**Parameters**
- `m` — the map.
- `key` — the key to insert or replace.
- `val` — the value to store.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` when the table has no free slot (or the
capacity is 0). An existing key never fails.

**Example**
```zig
std_map.map32x32Put(&m, 7, 42) catch @panic("put");
```

**Gotchas** — a failed insert leaves the map unchanged. A tombstone is reused
before the probe gives up.

#### `map32x32Remove`

**Purpose** — removes `key`, marking its slot a tombstone.

**When to use** — to delete an entry while keeping probe chains valid.

**Signature** — `pub fn map32x32Remove(m: *Map32x32, key: u32) bool`

**Parameters**
- `m` — the map.
- `key` — the key to remove.

**Returns** — `true` when the key was present and is now removed, `false`
otherwise.

**Errors** — none; a missing key is `false`.

**Example**
```zig
if (std_map.map32x32Remove(&m, 7)) {
    std.io.write("removed\n");
}
```

**Gotchas** — removal does not shrink or compact the table, and the tombstone
still occupies a slot.

#### `map32x32Len`

**Purpose** — returns the number of live entries.

**When to use** — sizing loops or checking emptiness.

**Signature** — `pub fn map32x32Len(m: *const Map32x32) usize`

**Parameters**
- `m` — the map.

**Returns** — `len`: live entries, excluding tombstones.

**Errors** — none.

**Example**
```zig
const n = std_map.map32x32Len(&m);
```

**Gotchas** — `len` counts live keys, not occupied slots, so it can be smaller
than the number of non-empty slots.

#### `map32PtrInit`

**Purpose** — allocates a zeroed `capacity`-slot `Map32Ptr` table from the arena.

**When to use** — the entry point for an integer-to-pointer map.

**Signature** — `pub fn map32PtrInit(arena: *arena_mod.Arena, capacity: usize) !Map32Ptr`

**Parameters**
- `arena` — the allocation source.
- `capacity` — number of slots.

**Returns** — a `Map32Ptr` with `len == 0`.

**Errors** — `error.OutOfMemory` when the arena cannot provide
`capacity * @sizeOf(Entry32Ptr)` bytes.

**Example**
```zig
var m = std_map.map32PtrInit(&arena, 16) catch @panic("init");
```

**Gotchas** — fixed capacity; size it for the worst case. `capacity == 0` makes
every `put` fail.

#### `map32PtrGet`

**Purpose** — looks up `key` and returns its pointer value.

**When to use** — the read path.

**Signature** — `pub fn map32PtrGet(m: *Map32Ptr, key: u32) ?*void`

**Parameters**
- `m` — the map.
- `key` — the key to find.

**Returns** — `?*void`: the stored pointer, or `null` when absent.

**Errors** — none; absence is the `null` optional.

**Example**
```zig
if (std_map.map32PtrGet(&m, 7)) |p| {
    _ = p;
}
```

**Gotchas** — the value type is a non-optional `*void`, so `null` unambiguously
means "absent"; you cannot store a null pointer. The map does not own the
pointee.

#### `map32PtrPut`

**Purpose** — inserts or replaces the pointer value for `key`.

**When to use** — the write path.

**Signature** — `pub fn map32PtrPut(m: *Map32Ptr, key: u32, val: *void) !void`

**Parameters**
- `m` — the map.
- `key` — the key to insert or replace.
- `val` — the pointer to store.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` when the table has no free slot (or the
capacity is 0).

**Example**
```zig
std_map.map32PtrPut(&m, 7, @ptrCast(*void, &cell)) catch @panic("put");
```

**Gotchas** — a failed insert leaves the map unchanged. The map does not own the
pointee.

#### `map32PtrRemove`

**Purpose** — removes `key`, marking its slot a tombstone.

**When to use** — to delete an entry.

**Signature** — `pub fn map32PtrRemove(m: *Map32Ptr, key: u32) bool`

**Parameters**
- `m` — the map.
- `key` — the key to remove.

**Returns** — `true` when the key was present and is now removed, `false`
otherwise.

**Errors** — none; a missing key is `false`.

**Example**
```zig
_ = std_map.map32PtrRemove(&m, 7);
```

**Gotchas** — the tombstone remains; `len` drops but `capacity` does not.

#### `map32PtrLen`

**Purpose** — returns the number of live entries.

**When to use** — sizing loops or checking emptiness.

**Signature** — `pub fn map32PtrLen(m: *const Map32Ptr) usize`

**Parameters**
- `m` — the map.

**Returns** — `len`: live entries, excluding tombstones.

**Errors** — none.

**Example**
```zig
const n = std_map.map32PtrLen(&m);
```

**Gotchas** — counts live keys, not occupied slots.

#### `mapStrPtrInit`

**Purpose** — allocates a zeroed `capacity`-slot `MapStrPtr` table from the
arena and records the arena for key copies.

**When to use** — the entry point for a string-to-pointer map.

**Signature** — `pub fn mapStrPtrInit(arena: *arena_mod.Arena, capacity: usize) !MapStrPtr`

**Parameters**
- `arena` — the allocation source and the owner of copied keys.
- `capacity` — number of slots.

**Returns** — a `MapStrPtr` with `len == 0`.

**Errors** — `error.OutOfMemory` when the arena cannot provide
`capacity * @sizeOf(EntryStrPtr)` bytes.

**Example**
```zig
var m = std_map.mapStrPtrInit(&arena, 16) catch @panic("init");
```

**Gotchas** — fixed capacity. Keep the arena alive as long as the map is used.

#### `mapStrPtrGet`

**Purpose** — looks up a string key by byte content.

**When to use** — the read path for string-keyed maps.

**Signature** — `pub fn mapStrPtrGet(m: *MapStrPtr, key: []const u8) ?*void`

**Parameters**
- `m` — the map.
- `key` — the key bytes; compared with `std_str.eql`.

**Returns** — `?*void`: the stored pointer, or `null` when absent.

**Errors** — none; absence is the `null` optional.

**Example**
```zig
if (std_map.mapStrPtrGet(&m, "name")) |p| {
    _ = p;
}
```

**Gotchas** — comparison is exact byte equality, including length; the caller's
key need not be NUL-terminated or arena-owned.

#### `mapStrPtrPut`

**Purpose** — copies `key` into the arena and inserts or replaces its pointer
value.

**When to use** — the write path; safe even when `key` is a temporary slice.

**Signature** — `pub fn mapStrPtrPut(m: *MapStrPtr, key: []const u8, val: *void) !void`

**Parameters**
- `m` — the map; its `arena` owns the copied key.
- `key` — the key bytes to copy and store.
- `val` — the pointer to store.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` when the table has no free slot or the arena
cannot copy the key. An existing key only replaces the value and does not
allocate.

**Example**
```zig
std_map.mapStrPtrPut(&m, "name", @ptrCast(*void, &cell)) catch @panic("put");
```

**Gotchas** — the copy is attempted only after the probe proves the key is new,
and before any table mutation, so an `OutOfMemory` leaves both the map and the
arena untouched. Replacing an existing key does **not** copy.

#### `mapStrPtrRemove`

**Purpose** — removes a string key, marking its slot a tombstone.

**When to use** — to delete an entry.

**Signature** — `pub fn mapStrPtrRemove(m: *MapStrPtr, key: []const u8) bool`

**Parameters**
- `m` — the map.
- `key` — the key bytes to remove.

**Returns** — `true` when the key was present and is now removed, `false`
otherwise.

**Errors** — none; a missing key is `false`.

**Example**
```zig
_ = std_map.mapStrPtrRemove(&m, "name");
```

**Gotchas** — the copied key is not freed (the arena reclaims only by `reset`);
only the slot becomes a tombstone.

#### `mapStrPtrLen`

**Purpose** — returns the number of live entries.

**When to use** — sizing loops or checking emptiness.

**Signature** — `pub fn mapStrPtrLen(m: *const MapStrPtr) usize`

**Parameters**
- `m` — the map.

**Returns** — `len`: live entries, excluding tombstones.

**Errors** — none.

**Example**
```zig
const n = std_map.mapStrPtrLen(&m);
```

**Gotchas** — counts live keys, not occupied slots.

### `std_sort`

#### `Sortable`

**Purpose** — a caller-supplied vtable over `*void` data: element count, less,
and swap.

**When to use** — to sort a type with no concrete wrapper (the wrappers cover
`i32`, `u32`, and `[]const u8`).

**Signature** — `pub const Sortable = struct { lenFn: fn(*void) usize, lessFn: fn(*void, usize, usize) bool, swapFn: fn(*void, usize, usize) void, data: *void };`

**Parameters** (fields)
- `lenFn` — returns the element count for `data`.
- `lessFn` — `true` when element `i` sorts before element `j`.
- `swapFn` — swaps elements `i` and `j` in place.
- `data` — the opaque payload passed to every callback.

**Returns** — a plain value type; `sort` takes it by value.

**Errors** — none.

**Example**
```zig
var box = MyBox{ .items = items };
var s = std_sort.Sortable{
    .lenFn = myLen,
    .lessFn = myLess,
    .swapFn = mySwap,
    .data = @ptrCast(*void, &box),
};
std_sort.sort(s);
```

**Gotchas** — `lessFn` must be a strict weak ordering; an inconsistent one gives
unspecified output. `data` must outlive the call and the callbacks must not
suspend.

#### `sort`

**Purpose** — sorts a `Sortable` in place with introsort.

**When to use** — when you need the generic vtable path. Prefer the concrete
wrappers for the covered element types.

**Signature** — `pub fn sort(s: Sortable) void`

**Parameters**
- `s` — the vtable and payload.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_sort.sort(s);
```

**Gotchas** — not stable. Allocation-free and in place. Worst case `O(n log n)`;
the comparison/swap sequence is deterministic for a given input order (R6), but
the vtable's own callbacks are the caller's responsibility.

#### `sortI32`

**Purpose** — sorts a `[]i32` ascending, in place.

**When to use** — the concrete path for signed 32-bit integers.

**Signature** — `pub fn sortI32(items: []i32) void`

**Parameters**
- `items` — the slice to sort in place.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var xs = [_]i32{ 3, -1, 2 };
std_sort.sortI32(xs[0..]);
```

**Gotchas** — not stable. `items.len < 2` is a no-op.

#### `sortU32`

**Purpose** — sorts a `[]u32` ascending, in place.

**When to use** — the concrete path for unsigned 32-bit integers; the natural
companion to `binarySearchU32`.

**Signature** — `pub fn sortU32(items: []u32) void`

**Parameters**
- `items` — the slice to sort in place.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var xs = [_]u32{ 3, 1, 2 };
std_sort.sortU32(xs[0..]);
```

**Gotchas** — not stable. `items.len < 2` is a no-op.

#### `sortStr`

**Purpose** — sorts a `[][]const u8` lexicographically by unsigned byte value,
in place.

**When to use** — the concrete path for byte-string slices.

**Signature** — `pub fn sortStr(items: [][]const u8) void`

**Parameters**
- `items` — the slice of string slices to sort in place.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var words = [_][]const u8{ "pear", "apple", "fig" };
std_sort.sortStr(words[0..]);
```

**Gotchas** — not stable; order is unsigned-byte lexicographic, and a proper
prefix sorts first. The slices are reordered, not their contents.

#### `binarySearchU32`

**Purpose** — binary-searches a sorted `[]const u32` for `key`.

**When to use** — after `sortU32`, for `O(log n)` membership and index lookup.

**Signature** — `pub fn binarySearchU32(items: []const u32, key: u32) ?usize`

**Parameters**
- `items` — a slice sorted in non-decreasing order.
- `key` — the value to find.

**Returns** — `?usize`: the index of an element equal to `key` (any one of
several duplicates), or `null` when absent.

**Errors** — none; absence is the `null` optional.

**Example**
```zig
if (std_sort.binarySearchU32(sorted[0..], 9)) |ix| {
    std.io.printInt(@intCast(i32, ix));
}
```

**Gotchas** — assumes sorted input; on unsorted input the result is
unspecified. With duplicates, which index is returned is unspecified.

### `std_heap`

#### `HeapItem`

**Purpose** — a public heap entry: an `i64` key and an opaque `*void` value.

**When to use** — as the unit pushed to and popped from a `Heap`.

**Signature** — `pub const HeapItem = struct { key: i64, value: *void };`

**Parameters** (fields)
- `key` — the ordering key; the minimum pops first.
- `value` — the opaque payload.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var it = std_heap.HeapItem{ .key = 5, .value = @ptrCast(*void, &cell) };
```

**Gotchas** — the heap orders by `key`, then by insertion order; it never
interprets `value`.

#### `Heap`

**Purpose** — a binary min-heap over `(i64, *void)` with arena-backed storage
and a monotonic insertion sequence.

**When to use** — as the value returned by `heapInit` and passed to the heap
functions.

**Signature** — `pub const Heap = struct { arena: *arena_mod.Arena, items: [*]HeapEntry, capacity: usize, len: usize, seq: u64 };`

**Parameters** (fields)
- `arena` — the allocation source for the table and its growth.
- `items` — pointer to the caller-arena table (`HeapEntry` is private).
- `capacity` — slots currently allocated.
- `len` — live items.
- `seq` — the next insertion sequence number (for stable ties).

**Returns** — a plain value type; `heapInit` returns one by value.

**Errors** — none.

**Example**
```zig
var h = std_heap.heapInit(&arena, 1) catch @panic("init");
```

**Gotchas** — the table is arena-owned and never freed; growth leaves the old
table allocated. Do not write the fields by hand.

#### `heapInit`

**Purpose** — allocates a `capacity`-entry heap table from the arena.

**When to use** — the entry point for a heap.

**Signature** — `pub fn heapInit(arena: *arena_mod.Arena, capacity: usize) !Heap`

**Parameters**
- `arena` — the allocation source.
- `capacity` — initial slots. `0` is allowed; the first `push` grows to 1.

**Returns** — a `Heap` with `len == 0` and `seq == 0`.

**Errors** — `error.OutOfMemory` when the arena cannot provide
`capacity * @sizeOf(HeapEntry)` bytes.

**Example**
```zig
var h = std_heap.heapInit(&arena, 1) catch @panic("init");
```

**Gotchas** — capacity is only the initial size; `heapPush` grows it.

#### `heapPush`

**Purpose** — appends an item and sifts it up to restore the min-heap order,
growing the table when full.

**When to use** — the insert path.

**Signature** — `pub fn heapPush(h: *Heap, item: HeapItem) !void`

**Parameters**
- `h` — the heap.
- `item` — the item to insert; stamped with the next `seq` for stable ties.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` when the heap is full and the arena cannot grow
the table.

**Example**
```zig
std_heap.heapPush(&h, std_heap.HeapItem{ .key = 5, .value = @ptrCast(*void, &cell) }) catch @panic("push");
```

**Gotchas** — growth doubles the capacity; the new table is allocated and
populated before the heap is mutated, so a failed growth leaves both the heap and
the arena untouched.

#### `heapPop`

**Purpose** — removes and returns the minimum item.

**When to use** — the extract-min path.

**Signature** — `pub fn heapPop(h: *Heap) ?HeapItem`

**Parameters**
- `h` — the heap.

**Returns** — `?HeapItem`: the minimum, or `null` when empty. Ties are broken by
insertion order (earliest inserted first).

**Errors** — none; emptiness is the `null` optional. Never allocates.

**Example**
```zig
if (std_heap.heapPop(&h)) |it| {
    std.io.printInt(@intCast(i32, it.key));
}
```

**Gotchas** — the popped `value` pointer is returned as-is; the heap does not
own it. `len` drops by one.

#### `heapPeek`

**Purpose** — returns the minimum item without removing it.

**When to use** — to inspect the next item to pop.

**Signature** — `pub fn heapPeek(h: *const Heap) ?HeapItem`

**Parameters**
- `h` — the heap.

**Returns** — `?HeapItem`: the minimum, or `null` when empty.

**Errors** — none; never allocates.

**Example**
```zig
if (std_heap.heapPeek(&h)) |it| {
    _ = it;
}
```

**Gotchas** — read-only; the heap is unchanged.

#### `heapLen`

**Purpose** — returns the number of live items.

**When to use** — sizing loops or checking emptiness.

**Signature** — `pub fn heapLen(h: *const Heap) usize`

**Parameters**
- `h` — the heap.

**Returns** — `len`: live items.

**Errors** — none.

**Example**
```zig
const n = std_heap.heapLen(&h);
```

**Gotchas** — counts live items, not the allocated `capacity`.

### `std_rle`

#### `encodedLen`

**Purpose** — returns the exact encoded size (4-byte prefix plus tokens) for
`src`.

**When to use** — to size an output buffer before encoding; allocation-free.

**Signature** — `pub fn encodedLen(src: []const u8) usize`

**Parameters**
- `src` — the raw bytes.

**Returns** — the exact number of bytes `encode` will produce.

**Errors** — none.

**Example**
```zig
const need = std_rle.encodedLen(raw[0..]);
```

**Gotchas** — a maximal run is a literal only when it is a single byte with the
high bit clear; otherwise each 128-byte chunk costs two bytes.

#### `decodedLen`

**Purpose** — returns the decoded length recorded in an encoded stream's
4-byte prefix.

**When to use** — to size an output buffer before decoding, or to inspect the
declared length.

**Signature** — `pub fn decodedLen(src: []const u8) usize`

**Parameters**
- `src` — an encoded stream.

**Returns** — the little-endian `u32` prefix value as a `usize`; `0` when
`src.len < 4`.

**Errors** — none.

**Example**
```zig
const n = std_rle.decodedLen(enc[0..]);
```

**Gotchas** — trusts the prefix; it does not validate the token stream. A
truncated stream can declare more than it carries.

#### `encode`

**Purpose** — run-length encodes `src` into a freshly allocated arena buffer.

**When to use** — to compress a byte run.

**Signature** — `pub fn encode(arena: *arena_mod.Arena, src: []const u8) ![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — the raw bytes.

**Returns** — a `[]u8` holding the length prefix plus tokens; the encoding is a
pure function of `src` (R6).

**Errors** — `error.OutOfMemory` when the arena cannot provide
`encodedLen(src)` bytes.

**Example**
```zig
const enc = std_rle.encode(&arena, raw[0..]) catch @panic("encode");
```

**Gotchas** — allocates only the output; the result is valid until the next
arena `reset`. Worst case (all distinct bytes) grows by the 4-byte prefix.

#### `decode`

**Purpose** — decodes an RLE stream into a freshly allocated arena buffer.

**When to use** — to expand a stream produced by `encode`.

**Signature** — `pub fn decode(arena: *arena_mod.Arena, src: []const u8) ![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — an encoded stream.

**Returns** — a `[]u8` of `decodedLen(src)` bytes.

**Errors** — `error.OutOfMemory` when the arena cannot provide the declared
length.

**Example**
```zig
const back = std_rle.decode(&arena, enc[0..]) catch @panic("decode");
```

**Gotchas** — `decode` trusts a well-formed stream: a truncated stream yields a
zero-filled tail, and an overlong run is clamped to the declared length (it never
reads out of bounds). A `src.len < 4` input decodes to an empty slice.

## See also

- `std_map`, `std_sort`, `std_heap`, `std_rle` — the modules in this doc.
- [`memory.md`](memory.md) — the `std.arena` model every allocating function
  here follows (R1).
- [`text.md`](text.md) — `std.str.eql` is the string-key comparison `MapStrPtr`
  uses.
- [`codecs.md`](codecs.md) — the L5 encoders; `std_rle` is the L4 byte codec.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
