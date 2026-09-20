# Memory — `std.arena` + `std.mem`

| | |
|---|---|
| **Modules** | `std.arena`, `std.mem` |
| **Layers** | `L0` — foundation layer: no library imports; the arena that backs every allocating module, plus raw memory primitives |
| **Import (re-export)** | `const std = @import("std");` → `std.arena`, `std.mem` |
| **Import (by path)** | `const std_arena = @import("std_arena");`, `const std_mem = @import("std_mem");` |

## Module overview

`std.arena` is the Z98 library's single allocation mechanism. An `Arena` does
**not** own memory: it wraps a caller-owned backing buffer (`[]u8`) and
bump-allocates from it. `init` records the buffer pointer and length and sets the
cursor (`used`) to zero; `alloc` hands back `size` uninitialized bytes and
advances the cursor; `reset` sets the cursor back to zero, reclaiming everything
at once. There is no `free`, no per-allocation reuse, and no zeroing.

This is rule **R1**: every allocating function in the library takes
`arena: *std.arena.Arena` as its first parameter and returns `error.OutOfMemory`
(alone or inside a module error set) on exhaustion. Functions never own memory
across calls; the caller owns the backing buffer and must keep it alive and
suitably aligned for as long as any pointer from the arena is used.

`std.mem` is the raw, concrete memory surface that pairs with the arena: bulk
copy, zero, and equality over many-item pointers plus an explicit element count.
Z98 has no generics, so the copy family is spelled per element type
(`copyU8`/`copyU32`/`copyU64`); there is no generic `copy`. `std.mem` never
allocates and never fails.

## Quick start

```zig
const std = @import("std");

var backing: [256]u8 = undefined;
var src: [4]u8 = .{ 1, 2, 3, 4 };

pub fn main() !void {
    var arena = std.arena.init(backing[0..]);
    const p = try std.arena.alloc(&arena, 4);
    std.mem.copyU8(p, @ptrCast([*]const u8, &src), 4);
    if (std.mem.eqlU8(p, @ptrCast([*]const u8, &src), 4)) {
        std.io.write("copied\n");
    }
    std.arena.reset(&arena);
}
```

## API

### `Arena`

**Purpose** — the bump-allocator state: a pointer to caller-owned storage, its
capacity, and the current cursor.

**When to use** — you hold an `Arena` value only to pass `&arena` to allocating
functions; create it with `init` rather than by writing the fields.

**Signature** — `pub const Arena = struct { data: [*]u8, capacity: usize, used: usize };`

**Parameters** (fields)
- `data` — start of the caller-owned backing buffer.
- `capacity` — usable bytes in that buffer (`data[0..capacity]`).
- `used` — bytes handed out so far; the next allocation starts at `data + used`.

**Returns** — a plain value type; `init` returns one by value.

**Errors** — none.

**Example**
```zig
var backing: [64]u8 = undefined;
var arena = std.arena.init(backing[0..]);
```

**Gotchas** — treat `data` and `capacity` as read-only once initialized; they
describe the buffer you passed to `init` and the arena never reallocates it.

### `init`

**Purpose** — wraps a caller-owned `[]u8` as an `Arena` with `used == 0`.

**When to use** — once per backing buffer, before any `alloc`. For a growable
byte buffer over the arena, use `std.buf` rather than managing bytes by hand.

**Signature** — `pub fn init(data: []u8) Arena`

**Parameters**
- `data` — the backing buffer. Its pointer and length are stored; the buffer is
  not copied and not owned.

**Returns** — an `Arena` whose `capacity` is `data.len` and `used` is `0`.

**Errors** — none.

**Example**
```zig
var backing: [4096]u8 = undefined;
var arena = std.arena.init(backing[0..]);
```

**Gotchas** — the arena aliases `data`, so the caller keeps it alive and aligned.
Two arenas over distinct buffers are fully independent.

### `ArenaError`

**Purpose** — the error set of `alloc`; its only member is `OutOfMemory`.

**When to use** — when naming the error in a `catch`, or when a function's own
error set includes it.

**Signature** — `pub const ArenaError = error{OutOfMemory};`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors** — `error.OutOfMemory`.

**Example**
```zig
const p = std.arena.alloc(&arena, 8) catch |e| switch (e) {
    error.OutOfMemory => @panic("arena exhausted"),
};
p[0] = 0xFF;
```

**Gotchas** — `ArenaError` contains exactly one member; there is no other failure
mode.

### `alloc`

**Purpose** — reserves `size` bytes from the arena and returns a many-item
pointer to the start of the new region.

**When to use** — for scratch or owned storage whose lifetime ends at the next
`reset`. For a growable byte buffer use `std.buf`; for fixed raw copies use
`std.mem`; to free individual allocations use neither — the arena reclaims only
in bulk.

**Signature** — `pub fn alloc(self: *Arena, size: usize) ArenaError![*]u8`

**Parameters**
- `self` — pointer to the `Arena`; on success `used` advances by `size`.
- `size` — bytes to reserve. No alignment adjustment is applied: the result is
  `data + used`.

**Returns** — `[*]u8` to `size` uninitialized bytes inside the backing buffer,
valid until `reset` (or until the caller releases the backing buffer). The bytes
are not zeroed.

**Errors** — `error.OutOfMemory` when `used + size > capacity`.

**Example**
```zig
var backing: [64]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const p = try std.arena.alloc(&arena, 16);
p[0] = 0xFF;
```

**Gotchas**
- The bounds check runs before `used` advances, so a failed `alloc` leaves the
  arena unchanged.
- `alloc` never frees and never reuses; only `reset` reclaims.
- `alloc(&arena, 0)` returns the current cursor — a valid pointer that must not
  be dereferenced.
- The returned pointer's alignment is that of `data` plus the current offset;
  there is no alignment parameter.

### `reset`

**Purpose** — rewinds the arena cursor to zero, making every previously allocated
byte available again.

**When to use** — at a scope boundary once every pointer obtained since `init`
(or the previous `reset`) is no longer needed.

**Signature** — `pub fn reset(self: *Arena) void`

**Parameters**
- `self` — the arena to rewind.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.arena.reset(&arena);
const p = try std.arena.alloc(&arena, 16);
```

**Gotchas** — `reset` does not zero the backing bytes and does not change
ownership. Every pointer from the arena is invalid after the next `reset`;
reusing one is a use-after-reset.

### `copyU8`

**Purpose** — copies `n` bytes from `src` to `dst`.

**When to use** — for a raw byte-range copy between many-item pointers; for slice
copies that carry their own length use `std.str.copy`.

**Signature** — `pub fn copyU8(dst: [*]u8, src: [*]const u8, n: usize) void`

**Parameters**
- `dst` — destination many-item pointer; must have room for `n` bytes.
- `src` — source many-item pointer; must have at least `n` readable bytes.
- `n` — element count.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var dst: [4]u8 = undefined;
var src: [4]u8 = .{ 1, 2, 3, 4 };
std.mem.copyU8(@ptrCast([*]u8, &dst), @ptrCast([*]const u8, &src), 4);
```

**Gotchas** — no bounds checking and no overlap handling: the forward byte loop
corrupts overlapping ranges when `dst > src`. Use disjoint regions.

### `copyU32`

**Purpose** — copies `n` `u32` elements from `src` to `dst`.

**When to use** — when both sides are typed `u32` storage and you want element
counts rather than byte counts.

**Signature** — `pub fn copyU32(dst: [*]u32, src: [*]const u32, n: usize) void`

**Parameters**
- `dst` — destination `u32` pointer; room for `n` elements.
- `src` — source `u32` pointer; at least `n` readable elements.
- `n` — element count (not bytes).

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var dst: [2]u32 = undefined;
var src: [2]u32 = .{ 7, 9 };
std.mem.copyU32(@ptrCast([*]u32, &dst), @ptrCast([*]const u32, &src), 2);
```

**Gotchas** — no bounds checking and not overlap-safe; `n` counts elements.

### `copyU64`

**Purpose** — copies `n` `u64` elements from `src` to `dst`.

**When to use** — when both sides are typed `u64` storage and you want element
counts rather than byte counts.

**Signature** — `pub fn copyU64(dst: [*]u64, src: [*]const u64, n: usize) void`

**Parameters**
- `dst` — destination `u64` pointer; room for `n` elements.
- `src` — source `u64` pointer; at least `n` readable elements.
- `n` — element count (not bytes).

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var dst: [1]u64 = undefined;
var src: [1]u64 = .{ 0x0102030405060708 };
std.mem.copyU64(@ptrCast([*]u64, &dst), @ptrCast([*]const u64, &src), 1);
```

**Gotchas** — no bounds checking and not overlap-safe; `n` counts elements.

### `zeroU8`

**Purpose** — writes `n` zero bytes starting at `dst`.

**When to use** — to clear a freshly allocated region before use, or to wipe a
buffer between reuses.

**Signature** — `pub fn zeroU8(dst: [*]u8, n: usize) void`

**Parameters**
- `dst` — the region to zero; must have room for `n` bytes.
- `n` — byte count.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
const p = try std.arena.alloc(&arena, 16);
std.mem.zeroU8(p, 16);
```

**Gotchas** — no bounds checking; only the `u8` form exists, so multi-byte
elements must be zeroed as bytes.

### `eqlU8`

**Purpose** — reports whether `n` bytes at `a` and `b` are equal.

**When to use** — to compare two raw byte regions of known length; for slices use
`std.str.eql`, and for ASCII case-insensitive comparison use
`std.str.eqIgnoreCase`.

**Signature** — `pub fn eqlU8(a: [*]const u8, b: [*]const u8, n: usize) bool`

**Parameters**
- `a` — first region; at least `n` readable bytes.
- `b` — second region; at least `n` readable bytes.
- `n` — byte count.

**Returns** — `true` when all `n` bytes match, `false` at the first mismatch.

**Errors** — none.

**Example**
```zig
var x: [2]u8 = .{ 1, 2 };
var y: [2]u8 = .{ 1, 2 };
if (std.mem.eqlU8(@ptrCast([*]const u8, &x), @ptrCast([*]const u8, &y), 2)) {
    std.io.write("same\n");
}
```

**Gotchas** — `n == 0` returns `true` regardless of the pointers.

## See also

- `std.arena`, `std.mem` — the modules in this doc.
- [`text.md`](text.md) — `std.buf` and the allocating `std.str` functions are
  arena-backed and follow R1.
- [`collections.md`](collections.md) — the maps, heap, and RLE codec all allocate
  through `std.arena`.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
