# Text — `std.str` + `std.buf`

| | |
|---|---|
| **Modules** | `std.str`, `std.buf` |
| **Layers** | `L2` — data layer built on L0; string slices and growable buffers, importing only `std_arena` |
| **Import (re-export)** | `const std = @import("std");` → `std.str`, `std.buf` |
| **Import (by path)** | `const std_str = @import("std_str");`, `const std_buf = @import("std_buf");` |

## Module overview

`std.str` is a byte-slice library: it operates on `[]const u8` / `[]u8` and never
uses NUL termination. It has two kinds of function:

- **Non-allocating** operations that return a value or a **view** into the input
  slice — `len`, `eql`, `copy`, `copyZ`, `findChar`, `startsWith`, `endsWith`,
  `toUpper`, `toLower`, `trim`, `trimLeft`, `trimRight`, `indexOf`,
  `lastIndexOf`, `eqIgnoreCase`, `count`.
- **Allocating** operations that take `arena: *std.arena.Arena` first (rule R1)
  and return only `error.OutOfMemory` — `split`, `splitLines`, `join`, `replace`,
  `repeat`.

The central model is **views vs. copies**. `trim`, `trimLeft`, `trimRight`,
`split`, and `splitLines` return slices that alias the source; mutating the
source mutates those views, and the source must outlive them. `join`, `replace`,
and `repeat` allocate a fresh result in the arena and never mutate the input. In
particular `replace` only reads `s`, so `from` and `to` may alias `s`. The
`split`/`splitLines` outer array is the only thing they allocate; the segments
themselves are views into `s`.

`std.buf` is a growable byte buffer over an arena. A `Buf` stores the arena, a
`data` slice (the current allocation), and a logical `len`. Appends grow the
buffer by doubling, copying the live bytes into a new arena region and abandoning
the old one. Because the arena never frees, there is no `deinit`: `clear` resets
the logical length but keeps capacity, and `reset` on the owning arena reclaims
everything. The append family includes big- and little-endian encoders for
`u16`/`u32`/`u64`.

## Quick start

```zig
const std = @import("std");

var backing: [1024]u8 = undefined;

pub fn main() !void {
    var arena = std.arena.init(backing[0..]);

    var b = std.buf.init(&arena);
    try std.buf.append(&b, "id=");
    try std.buf.appendU32BE(&b, 7);
    std.io.write(std.buf.slice(&b));
    std.io.writeByte('\n');

    const parts = try std.str.split(&arena, "a,b,c", ',');
    const joined = try std.str.join(&arena, parts, ":");
    std.io.write(joined);
    std.io.writeByte('\n');

    std.arena.reset(&arena);
}
```

## API

### `std.str`

#### `len`

**Purpose** — returns the byte length of `s`.

**When to use** — when you want a named operation rather than `s.len`; the two are
identical.

**Signature** — `pub fn len(s: []const u8) usize`

**Parameters**
- `s` — the slice.

**Returns** — `s.len`, in bytes.

**Errors** — none.

**Example**
```zig
const n = std.str.len("hello"); // 5
```

**Gotchas** — counts bytes, not characters; a UTF-8 code point may span several
bytes.

#### `eql`

**Purpose** — reports whether two slices have the same length and identical
bytes.

**When to use** — byte-exact equality. For case-insensitive comparison use
`eqIgnoreCase`.

**Signature** — `pub fn eql(a: []const u8, b: []const u8) bool`

**Parameters**
- `a`, `b` — slices to compare.

**Returns** — `true` when lengths and all bytes match, else `false`.

**Errors** — none.

**Example**
```zig
if (std.str.eql(name, "root")) { std.io.write("ok\n"); }
```

**Gotchas** — case-sensitive; lengths are compared first, so a prefix never
matches.

#### `copy`

**Purpose** — copies the bytes of `src` into `dst`.

**When to use** — to move a slice into a caller-owned fixed buffer. For a
NUL-terminated target use `copyZ`; for raw many-pointer ranges use
`std.mem.copyU8`.

**Signature** — `pub fn copy(dst: []u8, src: []const u8) void`

**Parameters**
- `dst` — destination slice.
- `src` — source slice.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var buf: [16]u8 = undefined;
std.str.copy(buf[0..], "hi"); // buf[0..2] == "hi"
```

**Gotchas** — if `src.len > dst.len` the call is a silent no-op: nothing is
copied, not even a prefix. Bytes in `dst` beyond `src.len` are untouched.

#### `copyZ`

**Purpose** — copies `src` to a many-item pointer and appends a NUL byte.

**When to use** — to produce a C-style NUL-terminated string from a Z98 slice.

**Signature** — `pub fn copyZ(dst: [*]u8, src: []const u8) usize`

**Parameters**
- `dst` — destination many-item pointer; must have room for `src.len + 1` bytes.
- `src` — source slice.

**Returns** — `src.len`, the number of bytes written before the NUL.

**Errors** — none.

**Example**
```zig
var buf: [8]u8 = undefined;
const n = std.str.copyZ(@ptrCast([*]u8, &buf), "hi"); // n == 2, buf[2] == 0
```

**Gotchas** — there is no destination-length check; the caller guarantees room
for `src.len + 1`. The NUL is written at `dst[src.len]`.

#### `findChar`

**Purpose** — finds the first occurrence of a byte in `s`.

**When to use** — single-byte scan; for a multi-byte needle use `indexOf`.

**Signature** — `pub fn findChar(s: []const u8, c: u8) ?usize`

**Parameters**
- `s` — the slice to scan.
- `c` — the byte to find.

**Returns** — the index of the first `c`, or `null` when absent.

**Errors** — none.

**Example**
```zig
const i = std.str.findChar("a=b", '='); // ?usize, 1
```

**Gotchas** — scans forward only; use `lastIndexOf` (for slices) or a manual
reverse loop for the last match.

#### `startsWith`

**Purpose** — reports whether `s` begins with `prefix`.

**When to use** — prefix tests. For the suffix use `endsWith`.

**Signature** — `pub fn startsWith(s: []const u8, prefix: []const u8) bool`

**Parameters**
- `s` — the slice.
- `prefix` — the candidate prefix.

**Returns** — `true` when `s` starts with `prefix`, else `false`. An empty
`prefix` always matches.

**Errors** — none.

**Example**
```zig
if (std.str.startsWith(path, "/tmp/")) { std.io.write("tmp\n"); }
```

**Gotchas** — case-sensitive; a `prefix` longer than `s` returns `false`.

#### `endsWith`

**Purpose** — reports whether `s` ends with `suffix`.

**When to use** — suffix tests such as file extensions. For the prefix use
`startsWith`.

**Signature** — `pub fn endsWith(s: []const u8, suffix: []const u8) bool`

**Parameters**
- `s` — the slice.
- `suffix` — the candidate suffix.

**Returns** — `true` when `s` ends with `suffix`, else `false`. An empty `suffix`
always matches.

**Errors** — none.

**Example**
```zig
if (std.str.endsWith(name, ".txt")) { std.io.write("text\n"); }
```

**Gotchas** — case-sensitive; a `suffix` longer than `s` returns `false`.

#### `toUpper`

**Purpose** — converts ASCII lowercase letters in `s` to uppercase, in place.

**When to use** — ASCII-only uppercasing of an owned mutable buffer.

**Signature** — `pub fn toUpper(s: []u8) void`

**Parameters**
- `s` — mutable slice to modify.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var buf: [3]u8 = .{ 'a', 'b', 'c' };
std.str.toUpper(buf[0..]); // "ABC"
```

**Gotchas** — in place and ASCII-only; bytes outside `a`–`z` are unchanged.
Takes `[]u8`, so the source must be mutable.

#### `toLower`

**Purpose** — converts ASCII uppercase letters in `s` to lowercase, in place.

**When to use** — ASCII-only lowercasing of an owned mutable buffer.

**Signature** — `pub fn toLower(s: []u8) void`

**Parameters**
- `s` — mutable slice to modify.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var buf: [3]u8 = .{ 'A', 'B', 'C' };
std.str.toLower(buf[0..]); // "abc"
```

**Gotchas** — in place and ASCII-only; bytes outside `A`–`Z` are unchanged.
Takes `[]u8`, so the source must be mutable.

#### `split`

**Purpose** — splits `s` on a single separator byte, returning the segments as
views into `s`.

**When to use** — field/CSV-style splitting on one byte. For line splitting use
`splitLines`; to reassemble use `join`.

**Signature** — `pub fn split(arena: *std.arena.Arena, s: []const u8, sep: u8) ![][]const u8`

**Parameters**
- `arena` — arena that supplies the outer segment array (R1).
- `s` — the slice to split; not mutated.
- `sep` — the separator byte.

**Returns** — `[][]const u8`: a mutable outer slice whose elements are views into
`s`. Empty `s` yields exactly one empty segment; a trailing separator yields a
trailing empty segment. `s.len + 1` is the upper bound on the segment count.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the arena
cannot supply `n * @sizeOf([]const u8)` bytes for the outer array.

**Example**
```zig
var backing: [256]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const parts = try std.str.split(&arena, "a,b,c", ',');
// parts.len == 3; parts[0] == "a"
```

**Gotchas**
- Only the outer array is allocated; the segments alias `s`, so `s` must outlive
  the result and mutating `s` changes the segments.
- The arena is not freed or reused; `reset` reclaims the outer array.
- The arena cursor must be aligned for slice headers when the arena is shared.

#### `splitLines`

**Purpose** — splits `s` on `'\n'`, stripping a single trailing `'\r'` from each
segment (CRLF-aware).

**When to use** — line-oriented parsing of an in-memory block. For a live file or
socket use `std_stream`'s line readers.

**Signature** — `pub fn splitLines(arena: *std.arena.Arena, s: []const u8) ![][]const u8`

**Parameters**
- `arena` — arena that supplies the outer segment array (R1).
- `s` — the slice to split; not mutated.

**Returns** — `[][]const u8`: views into `s`, one per line. The final
unterminated line is included; an empty `s` yields one empty segment.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the outer
array cannot be allocated.

**Example**
```zig
var backing: [256]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const lines = try std.str.splitLines(&arena, "one\r\ntwo\n");
// lines[0] == "one"; lines[1] == "two"
```

**Gotchas**
- Segments are views into `s`; `s` must outlive the result.
- A single trailing `\r` is stripped per segment; other `\r` bytes remain.
- Only the outer array is allocated.

#### `join`

**Purpose** — concatenates `parts` with `sep` between consecutive parts.

**When to use** — reassembling data from `split`, or building a delimited string.
For repeated repetition of one slice use `repeat`.

**Signature** — `pub fn join(arena: *std.arena.Arena, parts: [][]const u8, sep: []const u8) ![]u8`

**Parameters**
- `arena` — arena for the result (R1).
- `parts` — the pieces to concatenate, in order.
- `sep` — inserted between pieces, never before the first or after the last.

**Returns** — a freshly allocated `[]u8` in the arena; `parts.len == 0` yields an
empty slice.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the
result cannot be allocated.

**Example**
```zig
var backing: [256]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const parts = try std.str.split(&arena, "a,b", ',');
const out = try std.str.join(&arena, parts, ":"); // "a:b"
```

**Gotchas** — allocates only the result; `parts` and `sep` are read, not mutated,
so they may alias each other or `s`.

#### `trim`

**Purpose** — strips ASCII whitespace from both ends of `s` and returns the
remaining view.

**When to use** — cleaning up a line or field. For a caller-chosen byte set use
`trimLeft`/`trimRight`.

**Signature** — `pub fn trim(s: []const u8) []const u8`

**Parameters**
- `s` — the slice to trim.

**Returns** — a view `s[start..end]` with leading and trailing whitespace
removed; an all-whitespace slice yields an empty view.

**Errors** — none.

**Example**
```zig
const t = std.str.trim("  hi  "); // "hi"
```

**Gotchas** — ASCII whitespace only: space, tab, LF, CR, VT (`0x0B`), and FF
(`0x0C`). Returns a view, not a copy.

#### `trimLeft`

**Purpose** — strips leading bytes that occur in the `chars` set and returns the
remaining view.

**When to use** — removing a caller-defined prefix character set (for example
`"/"` or `"0"`). For whitespace use `trim`.

**Signature** — `pub fn trimLeft(s: []const u8, chars: []const u8) []const u8`

**Parameters**
- `s` — the slice to trim.
- `chars` — the set of bytes to strip from the left.

**Returns** — a view into `s` starting at the first byte not in `chars`.

**Errors** — none.

**Example**
```zig
const t = std.str.trimLeft("//path", "/"); // "path"
```

**Gotchas** — `chars` is a set, not a prefix: any leading byte in it is removed.
Returns a view.

#### `trimRight`

**Purpose** — strips trailing bytes that occur in the `chars` set and returns the
remaining view.

**When to use** — removing a caller-defined suffix character set. For whitespace
use `trim`.

**Signature** — `pub fn trimRight(s: []const u8, chars: []const u8) []const u8`

**Parameters**
- `s` — the slice to trim.
- `chars` — the set of bytes to strip from the right.

**Returns** — a view into `s` ending at the last byte not in `chars`.

**Errors** — none.

**Example**
```zig
const t = std.str.trimRight("path///", "/"); // "path"
```

**Gotchas** — `chars` is a set, not a suffix: any trailing byte in it is removed.
Returns a view.

#### `indexOf`

**Purpose** — finds the first occurrence of the multi-byte `needle` in `s`.

**When to use** — substring search. For a single byte use `findChar`; for the
last occurrence use `lastIndexOf`.

**Signature** — `pub fn indexOf(s: []const u8, needle: []const u8) ?usize`

**Parameters**
- `s` — the slice to scan.
- `needle` — the substring to find.

**Returns** — the first starting index of `needle`, or `null` when absent. An
empty `needle` returns `0`.

**Errors** — none.

**Example**
```zig
const i = std.str.indexOf("a::b", "::"); // ?usize, 1
```

**Gotchas** — byte search, not word or Unicode-aware; an empty needle matches at
index `0`.

#### `lastIndexOf`

**Purpose** — finds the last occurrence of the multi-byte `needle` in `s`.

**When to use** — finding the final delimiter, for example the extension dot in a
path. For the first occurrence use `indexOf`.

**Signature** — `pub fn lastIndexOf(s: []const u8, needle: []const u8) ?usize`

**Parameters**
- `s` — the slice to scan.
- `needle` — the substring to find.

**Returns** — the last starting index of `needle`, or `null` when absent. An
empty `needle` returns `s.len`.

**Errors** — none.

**Example**
```zig
const i = std.str.lastIndexOf("a.b.c", "."); // ?usize, 3
```

**Gotchas** — scans backward; an empty needle returns `s.len`, not `0`.

#### `eqIgnoreCase`

**Purpose** — compares two slices for equality, ignoring ASCII case.

**When to use** — case-insensitive keyword or header matching. For exact bytes use
`eql`.

**Signature** — `pub fn eqIgnoreCase(a: []const u8, b: []const u8) bool`

**Parameters**
- `a`, `b` — slices to compare.

**Returns** — `true` when lengths match and every byte pair is equal after ASCII
lowercasing, else `false`.

**Errors** — none.

**Example**
```zig
if (std.str.eqIgnoreCase(cmd, "HELP")) { std.io.write("help\n"); }
```

**Gotchas** — ASCII-only; non-alphabetic bytes must match exactly, and lengths
must match.

#### `replace`

**Purpose** — replaces every non-overlapping occurrence of `from` in `s` with
`to`, allocating the result.

**When to use** — text substitution where the source must stay unchanged. The
source `s` is only read, so the arguments may alias it.

**Signature** — `pub fn replace(arena: *std.arena.Arena, s: []const u8, from: []const u8, to: []const u8) ![]u8`

**Parameters**
- `arena` — arena for the result (R1).
- `s` — the source slice; not mutated.
- `from` — the byte pattern to replace. Empty `from` means "no replacement".
- `to` — the replacement bytes.

**Returns** — a freshly allocated `[]u8`. With an empty `from` this is a plain
copy of `s`.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the
result cannot be allocated.

**Example**
```zig
var backing: [256]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const out = try std.str.replace(&arena, "a-b-c", "-", ":"); // "a:b:c"
```

**Gotchas**
- Replacements are non-overlapping and scan left to right.
- `from`/`to` may alias `s` because `s` is read without mutation; the result is a
  separate allocation.
- An empty `from` performs no substitution (a copy), avoiding an infinite match.

#### `count`

**Purpose** — counts occurrences of a byte in `s`.

**When to use** — frequency of a delimiter, for example counting `','` before a
split.

**Signature** — `pub fn count(s: []const u8, needle: u8) usize`

**Parameters**
- `s` — the slice to scan.
- `needle` — the byte to count.

**Returns** — the number of positions where `s[i] == needle`.

**Errors** — none.

**Example**
```zig
const n = std.str.count("a,b,c", ','); // 2
```

**Gotchas** — single byte only; there is no substring-count function.

#### `repeat`

**Purpose** — concatenates `s` with itself `n` times, allocating the result.

**When to use** — padding or simple repetition. For joining distinct parts use
`join`.

**Signature** — `pub fn repeat(arena: *std.arena.Arena, s: []const u8, n: usize) ![]u8`

**Parameters**
- `arena` — arena for the result (R1).
- `s` — the slice to repeat.
- `n` — repetition count; `0` yields an empty slice.

**Returns** — a freshly allocated `[]u8` of length `s.len * n`.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the
result cannot be allocated.

**Example**
```zig
var backing: [256]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const out = try std.str.repeat(&arena, "ab", 3); // "ababab"
```

**Gotchas** — allocates `s.len * n` bytes up front; under the default `-fsafe`
mode an overflowing product traps before allocation.

### `std.buf`

#### `Buf`

**Purpose** — the growable buffer state: the owning arena, the current `data`
allocation, and the logical `len`.

**When to use** — create one with `init` or `initCapacity` and pass `&b` to the
`append*`/`reserve` functions rather than editing the fields.

**Signature** — `pub const Buf = struct { arena: *arena_mod.Arena, data: []u8, len: usize };`

**Parameters** (fields)
- `arena` — the arena that owns all storage.
- `data` — the current backing allocation; `data.len` is the capacity.
- `len` — the number of valid bytes at the front of `data`.

**Returns** — a plain value type; `init`/`initCapacity` return one by value.

**Errors** — none.

**Example**
```zig
var b = std.buf.init(&arena);
```

**Gotchas** — `data` may be replaced by a growing append; do not cache it or
`slice()` across a grow. The arena owns `data`; there is no `deinit`.

#### `init`

**Purpose** — creates an empty `Buf` over an arena with zero capacity.

**When to use** — the default constructor when you do not know the eventual size;
the first append grows the buffer. Use `initCapacity` to pre-size.

**Signature** — `pub fn init(arena: *std.arena.Arena) Buf`

**Parameters**
- `arena` — the arena that will own the buffer's storage.

**Returns** — a `Buf` with `len == 0` and `capacity == 0`.

**Errors** — none.

**Example**
```zig
var b = std.buf.init(&arena);
```

**Gotchas** — no allocation happens until the first append or `reserve`, so
`init` itself cannot fail.

#### `initCapacity`

**Purpose** — creates an empty `Buf` with a pre-allocated capacity.

**When to use** — when the final size is roughly known, to avoid repeated
reallocations.

**Signature** — `pub fn initCapacity(arena: *std.arena.Arena, cap: usize) !Buf`

**Parameters**
- `arena` — the arena that owns the storage.
- `cap` — bytes to reserve up front.

**Returns** — a `Buf` with `len == 0` and `capacity == cap`.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the arena
cannot supply `cap` bytes.

**Example**
```zig
var b = try std.buf.initCapacity(&arena, 64);
```

**Gotchas** — allocates immediately; the requested `cap` bytes come out of the
arena for the lifetime of the arena.

#### `capacity`

**Purpose** — returns the number of bytes the buffer can hold before the next
growth.

**When to use** — to check remaining headroom or size a downstream copy.

**Signature** — `pub fn capacity(b: *Buf) usize`

**Parameters**
- `b` — the buffer.

**Returns** — `b.data.len`.

**Errors** — none.

**Example**
```zig
const cap = std.buf.capacity(&b);
```

**Gotchas** — capacity is not length; `len` may be much smaller. Capacity changes
only on a growing append/reserve.

#### `slice`

**Purpose** — returns the live bytes of the buffer as `data[0..len]`.

**When to use** — to read or pass the accumulated bytes. The result is mutable,
so it can also be written in place.

**Signature** — `pub fn slice(b: *Buf) []u8`

**Parameters**
- `b` — the buffer.

**Returns** — a `[]u8` view of the first `len` bytes.

**Errors** — none.

**Example**
```zig
std.io.write(std.buf.slice(&b));
```

**Gotchas** — the view aliases the buffer's storage and is invalidated by the
next append or `reserve` that grows the buffer. It stays valid across
non-growing appends and `clear`.

#### `clear`

**Purpose** — resets the logical length to zero while keeping the allocation and
capacity.

**When to use** — to reuse a buffer for a new payload without reallocating.

**Signature** — `pub fn clear(b: *Buf) void`

**Parameters**
- `b` — the buffer.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.buf.clear(&b); // len == 0, capacity unchanged
```

**Gotchas** — the bytes are not zeroed; only `len` is reset. `slice()` returns an
empty view until the next append.

#### `reserve`

**Purpose** — ensures at least `extra` more bytes fit after the current `len`,
growing the buffer if needed.

**When to use** — to make a run of appends allocation-free, or to size a buffer
before writing into `slice()` directly.

**Signature** — `pub fn reserve(b: *Buf, extra: usize) !void`

**Parameters**
- `b` — the buffer.
- `extra` — additional bytes required beyond `len`.

**Returns** — nothing when `len + extra <= capacity` (no change), otherwise after
growing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when the arena
cannot supply the new capacity.

**Example**
```zig
try std.buf.reserve(&b, 128);
```

**Gotchas**
- Growth starts at capacity 1 (when empty) and doubles until `len + extra` fits;
  the old region is abandoned in the arena, never freed.
- On exhaustion the buffer is left untouched (no partial write).
- A growing `reserve` invalidates any earlier `slice()`/`data` view.

#### `append`

**Purpose** — appends a byte slice to the buffer, growing if necessary.

**When to use** — the general write path; use `appendByte` or the `appendU*`
encoders for a single scalar.

**Signature** — `pub fn append(b: *Buf, bytes: []const u8) !void`

**Parameters**
- `b` — the buffer.
- `bytes` — the bytes to append.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails; on failure `b` is unchanged.

**Example**
```zig
try std.buf.append(&b, "payload");
```

**Gotchas** — a growing append invalidates earlier `slice()` views. Appending an
empty slice is a no-op that cannot grow.

#### `appendByte`

**Purpose** — appends a single byte.

**When to use** — writing one raw byte, for example a delimiter or a NUL.

**Signature** — `pub fn appendByte(b: *Buf, byte: u8) !void`

**Parameters**
- `b` — the buffer.
- `byte` — the byte to append.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendByte(&b, 0);
```

**Gotchas** — writes raw bytes; it does not NUL-terminate in the C sense (the
buffer is not a string).

#### `appendU16BE`

**Purpose** — appends a `u16` in big-endian byte order.

**When to use** — network/wire formats that specify big-endian `u16` fields. For
little-endian use `appendU16LE`.

**Signature** — `pub fn appendU16BE(b: *Buf, v: u16) !void`

**Parameters**
- `b` — the buffer.
- `v` — the value; its high byte is written first.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendU16BE(&b, 0x1234); // bytes 12 34
```

**Gotchas** — exactly two bytes are appended, high byte first.

#### `appendU16LE`

**Purpose** — appends a `u16` in little-endian byte order.

**When to use** — formats that specify little-endian `u16` fields. For big-endian
use `appendU16BE`.

**Signature** — `pub fn appendU16LE(b: *Buf, v: u16) !void`

**Parameters**
- `b` — the buffer.
- `v` — the value; its low byte is written first.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendU16LE(&b, 0x1234); // bytes 34 12
```

**Gotchas** — exactly two bytes are appended, low byte first.

#### `appendU32BE`

**Purpose** — appends a `u32` in big-endian byte order.

**When to use** — wire/frame formats with big-endian `u32` lengths or headers.
For little-endian use `appendU32LE`.

**Signature** — `pub fn appendU32BE(b: *Buf, v: u32) !void`

**Parameters**
- `b` — the buffer.
- `v` — the value; most significant byte first.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendU32BE(&b, 7); // bytes 00 00 00 07
```

**Gotchas** — exactly four bytes are appended, most significant byte first.

#### `appendU32LE`

**Purpose** — appends a `u32` in little-endian byte order.

**When to use** — formats with little-endian `u32` fields. For big-endian use
`appendU32BE`.

**Signature** — `pub fn appendU32LE(b: *Buf, v: u32) !void`

**Parameters**
- `b` — the buffer.
- `v` — the value; least significant byte first.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendU32LE(&b, 7); // bytes 07 00 00 00
```

**Gotchas** — exactly four bytes are appended, least significant byte first.

#### `appendU64BE`

**Purpose** — appends a `u64` in big-endian byte order.

**When to use** — formats with big-endian 64-bit fields. For little-endian use
`appendU64LE`.

**Signature** — `pub fn appendU64BE(b: *Buf, v: u64) !void`

**Parameters**
- `b` — the buffer.
- `v` — the value; most significant byte first.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendU64BE(&b, 1); // 00 00 00 00 00 00 00 01
```

**Gotchas** — exactly eight bytes are appended, most significant byte first.

#### `appendU64LE`

**Purpose** — appends a `u64` in little-endian byte order.

**When to use** — formats with little-endian 64-bit fields. For big-endian use
`appendU64BE`.

**Signature** — `pub fn appendU64LE(b: *Buf, v: u64) !void`

**Parameters**
- `b` — the buffer.
- `v` — the value; least significant byte first.

**Returns** — nothing.

**Errors** — `error.OutOfMemory` (inferred `std.arena.ArenaError`) when growth
fails.

**Example**
```zig
try std.buf.appendU64LE(&b, 1); // 01 00 00 00 00 00 00 00
```

**Gotchas** — exactly eight bytes are appended, least significant byte first.

## See also

- `std.str`, `std.buf` — the modules in this doc.
- [`memory.md`](memory.md) — the arena model every allocating function here uses
  (R1), and the raw `std.mem` copies.
- [`codecs.md`](codecs.md) — base64/hex/UTF-8 transforms over the same byte
  slices and buffers.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
