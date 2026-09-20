# Bits & Math — `std.bits` + `std.math`

| | |
|---|---|
| **Modules** | `std.bits`, `std.math` |
| **Layers** | `L0` — foundation layer: no library imports; pure bit and integer computation with no allocation and no error sets |
| **Import (re-export)** | `const std = @import("std");` → `std.bits`, `std.math` |
| **Import (by path)** | `const std_bits = @import("std_bits");`, `const std_math = @import("std_math");` |

## Module overview

`std.bits` and `std.math` are the pure-computation corner of the library. Both
are L0: they import nothing, allocate nothing, and declare no error sets. Every
function is a plain value-in/value-out computation over concrete integer types —
`u32`/`u64` for bits, `i32`/`u32` for math. Z98 has no generics, so each
operation is written for its exact type.

`std.bits` covers population count, leading/trailing zero counts, rotations, bit
reversal, masks, and bitfield `extract`/`insert`, plus `isPow2`/`nextPow2`. Z98
has no bit builtins beyond `@bitCast`, so these are hand-written loops and
arithmetic. Every function is total **except** `extract` and `insert`, which trap
on out-of-range offsets. The exact bounds are `off < 32`, `len <= 32`, and
`off + len <= 32`; a violation executes `unreachable`, which is a real trap in
both `-fsafe` and `-ffast`. The other functions never trap: `clz*`/`ctz*` of `0`
return the bit width, `nextPow2(0)` returns `1`, and `mask(bits)` is defined for
`bits` in `[0, 32]`.

`std.math` provides scalar `i32`/`u32` `min`/`max`, `abs`, `clamp`, a power-of-two
predicate, and power-of-two `alignUp`/`alignDown`. It has no floating-point
surface and no `f64`/`f32` helpers.

## Quick start

```zig
const std = @import("std");

pub fn main() void {
    var hdr: u32 = 0;
    hdr = std.bits.insert(hdr, @intCast(u32, 0xA), 0, 4);
    hdr = std.bits.insert(hdr, @intCast(u32, 0x3), 4, 4);

    const op = std.bits.extract(hdr, 0, 4);
    const n = std.bits.extract(hdr, 4, 4);
    const level = std.math.clamp(@intCast(i32, op), 0, 5);

    if (n == 3 and level == 5) {
        std.io.write("ok\n");
    }
}
```

## API

### `std.bits`

#### `popcount32`

**Purpose** — counts the set bits in a `u32`.

**When to use** — weight/parity-style work. For a 64-bit value use `popcount64`.

**Signature** — `pub fn popcount32(x: u32) u32`

**Parameters**
- `x` — the value to inspect.

**Returns** — the number of bits set in `x`, from `0` to `32`.

**Errors** — none.

**Example**
```zig
const n = std.bits.popcount32(0xF0F0); // 8
```

**Gotchas** — total for all inputs; the count is returned as `u32`.

#### `popcount64`

**Purpose** — counts the set bits in a `u64`.

**When to use** — population count of a 64-bit value. For a 32-bit value use
`popcount32`.

**Signature** — `pub fn popcount64(x: u64) u32`

**Parameters**
- `x` — the value to inspect.

**Returns** — the number of bits set in `x`, from `0` to `64`, as `u32`.

**Errors** — none.

**Example**
```zig
const n = std.bits.popcount64(0xFF00000000000000); // 8
```

**Gotchas** — the result is `u32`; it can represent the maximum of `64`.

#### `clz32`

**Purpose** — counts the leading zero bits of a `u32`.

**When to use** — finding the highest set bit or normalizing a value.

**Signature** — `pub fn clz32(x: u32) u32`

**Parameters**
- `x` — the value to inspect.

**Returns** — the number of zero bits before the most significant set bit, from
`0` to `32`. `clz32(0)` returns `32`.

**Errors** — none.

**Example**
```zig
const n = std.bits.clz32(1); // 31
```

**Gotchas** — zero is total, returning the width `32` rather than trapping.

#### `clz64`

**Purpose** — counts the leading zero bits of a `u64`.

**When to use** — finding the highest set bit of a 64-bit value.

**Signature** — `pub fn clz64(x: u64) u32`

**Parameters**
- `x` — the value to inspect.

**Returns** — the number of zero bits before the most significant set bit, from
`0` to `64`. `clz64(0)` returns `64`.

**Errors** — none.

**Example**
```zig
const n = std.bits.clz64(1); // 63
```

**Gotchas** — zero is total, returning the width `64`.

#### `ctz32`

**Purpose** — counts the trailing zero bits of a `u32`.

**When to use** — finding the lowest set bit or the alignment of a value.

**Signature** — `pub fn ctz32(x: u32) u32`

**Parameters**
- `x` — the value to inspect.

**Returns** — the number of zero bits after the least significant set bit, from
`0` to `32`. `ctz32(0)` returns `32`.

**Errors** — none.

**Example**
```zig
const n = std.bits.ctz32(0x10); // 4
```

**Gotchas** — zero is total, returning the width `32`.

#### `ctz64`

**Purpose** — counts the trailing zero bits of a `u64`.

**When to use** — finding the lowest set bit of a 64-bit value.

**Signature** — `pub fn ctz64(x: u64) u32`

**Parameters**
- `x` — the value to inspect.

**Returns** — the number of zero bits after the least significant set bit, from
`0` to `64`. `ctz64(0)` returns `64`.

**Errors** — none.

**Example**
```zig
const n = std.bits.ctz64(0x10); // 4
```

**Gotchas** — zero is total, returning the width `64`.

#### `rotl32`

**Purpose** — rotates a `u32` left by `n` bits.

**When to use** — circular shifts where bits leaving the top re-enter at the
bottom. For the opposite direction use `rotr32`.

**Signature** — `pub fn rotl32(x: u32, n: u32) u32`

**Parameters**
- `x` — the value to rotate.
- `n` — rotation amount; taken modulo `32`.

**Returns** — `x` rotated left by `n % 32` bits. A rotation of `0` returns `x`.

**Errors** — none.

**Example**
```zig
const r = std.bits.rotl32(0x80000001, 1); // 0x00000003
```

**Gotchas** — `n` wraps modulo `32`, so `rotl32(x, 32)` returns `x`. The
implementation masks the shifted half before shifting so the `-fsafe` left-shift
overflow (high-bit discard) check is never tripped.

#### `rotr32`

**Purpose** — rotates a `u32` right by `n` bits.

**When to use** — circular shifts in the opposite direction from `rotl32`.

**Signature** — `pub fn rotr32(x: u32, n: u32) u32`

**Parameters**
- `x` — the value to rotate.
- `n` — rotation amount; taken modulo `32`.

**Returns** — `x` rotated right by `n % 32` bits. A rotation of `0` returns `x`.

**Errors** — none.

**Example**
```zig
const r = std.bits.rotr32(0x00000003, 1); // 0x80000001
```

**Gotchas** — `n` wraps modulo `32`, so `rotr32(x, 32)` returns `x`.

#### `bitrev32`

**Purpose** — reverses the 32-bit order of a `u32`.

**When to use** — bit-order conversion for serialization or algorithms that index
from the opposite end.

**Signature** — `pub fn bitrev32(x: u32) u32`

**Parameters**
- `x` — the value to reverse.

**Returns** — `x` with bit `i` moved to bit `31 - i`.

**Errors** — none.

**Example**
```zig
const r = std.bits.bitrev32(1); // 0x80000000
```

**Gotchas** — a fixed 32-bit reversal; there is no 64-bit variant.

#### `mask`

**Purpose** — builds a `u32` with the low `bits` bits set.

**When to use** — constructing field masks for `extract`/`insert` or manual bit
work.

**Signature** — `pub fn mask(bits: u32) u32`

**Parameters**
- `bits` — number of low bits to set.

**Returns** — `0` when `bits == 0`; `0xFFFFFFFF` when `bits >= 32`; otherwise
`(1 << bits) - 1`.

**Errors** — none.

**Example**
```zig
const m = std.bits.mask(4); // 0x0000000F
```

**Gotchas** — values above `32` do not trap; they saturate to all 32 bits set.

#### `extract`

**Purpose** — extracts a bitfield of `len` bits starting at bit `off`.

**When to use** — pulling a packed field out of a header word. The inverse is
`insert`.

**Signature** — `pub fn extract(x: u32, off: u32, len: u32) u32`

**Parameters**
- `x` — the source word.
- `off` — starting bit offset.
- `len` — field width in bits.

**Returns** — `(x >> off) & mask(len)`, the field value right-aligned.

**Errors** — none (out-of-range offsets trap rather than returning an error).

**Example**
```zig
const a = std.bits.extract(0x000000AB, 0, 8); // 0xAB
```

**Gotchas** — **traps** via `unreachable` when `off >= 32`, `len > 32`, or
`off + len > 32`. The trap fires in both `-fsafe` and `-ffast`. `len == 0`
returns `0` and is in range.

#### `insert`

**Purpose** — writes a `len`-bit field at bit `off`, clearing the field first.

**When to use** — packing fields into a header word. The inverse is `extract`.

**Signature** — `pub fn insert(x: u32, val: u32, off: u32, len: u32) u32`

**Parameters**
- `x` — the destination word.
- `val` — the value to insert; only its low `len` bits are used.
- `off` — starting bit offset.
- `len` — field width in bits.

**Returns** — `x` with bits `[off, off + len)` replaced by `val & mask(len)`. A
`len` of `0` returns `x` unchanged.

**Errors** — none (out-of-range offsets trap rather than returning an error).

**Example**
```zig
var hdr: u32 = 0;
hdr = std.bits.insert(hdr, @intCast(u32, 0xA), 0, 4); // low nibble = 0xA
```

**Gotchas** — **traps** via `unreachable` when `off >= 32`, `len > 32`, or
`off + len > 32`. The trap fires in both `-fsafe` and `-ffast`. `val` is masked
to `len` bits, so high bits are ignored.

#### `isPow2`

**Purpose** — reports whether `x` is a power of two.

**When to use** — validating an alignment or size argument before using it as
one.

**Signature** — `pub fn isPow2(x: u32) bool`

**Parameters**
- `x` — the value to test.

**Returns** — `true` when exactly one bit is set; `false` for `0` and for values
with two or more bits set.

**Errors** — none.

**Example**
```zig
if (std.bits.isPow2(16)) { std.io.write("pow2\n"); }
```

**Gotchas** — `0` is not a power of two.

#### `nextPow2`

**Purpose** — returns the smallest power of two greater than or equal to `x`.

**When to use** — rounding a size up to a power-of-two alignment or bucket.

**Signature** — `pub fn nextPow2(x: u32) u32`

**Parameters**
- `x` — the value to round up.

**Returns** — `1` for `x <= 1`; otherwise the next power of two `>= x`. Returns
`0` when `x > 0x80000000`, because the next power of two is not representable in
`u32`.

**Errors** — none.

**Example**
```zig
const n = std.bits.nextPow2(5); // 8
```

**Gotchas** — `nextPow2(0x80000000)` is `0x80000000`; any larger `x` returns `0`
rather than trapping, so a `0` result signals "unrepresentable".

### `std.math`

#### `min`

**Purpose** — returns the smaller of two signed `i32` values.

**When to use** — signed lower-bound selection. For unsigned values use `minU`;
to force a floor use `clamp`.

**Signature** — `pub fn min(a: i32, b: i32) i32`

**Parameters**
- `a`, `b` — the values to compare.

**Returns** — `a` when `a < b`, otherwise `b`.

**Errors** — none.

**Example**
```zig
const m = std.math.min(-3, 5); // -3
```

**Gotchas** — signed only; no `i64` variant.

#### `max`

**Purpose** — returns the larger of two signed `i32` values.

**When to use** — signed upper-bound selection. For unsigned values use `maxU`;
to force a ceiling use `clamp`.

**Signature** — `pub fn max(a: i32, b: i32) i32`

**Parameters**
- `a`, `b` — the values to compare.

**Returns** — `a` when `a > b`, otherwise `b`.

**Errors** — none.

**Example**
```zig
const m = std.math.max(-3, 5); // 5
```

**Gotchas** — signed only; no `i64` variant.

#### `minU`

**Purpose** — returns the smaller of two unsigned `u32` values.

**When to use** — unsigned lower-bound selection. For signed values use `min`.

**Signature** — `pub fn minU(a: u32, b: u32) u32`

**Parameters**
- `a`, `b` — the values to compare.

**Returns** — `a` when `a < b`, otherwise `b`.

**Errors** — none.

**Example**
```zig
const m = std.math.minU(7, 3); // 3
```

**Gotchas** — unsigned only; there is no `minU64`.

#### `maxU`

**Purpose** — returns the larger of two unsigned `u32` values.

**When to use** — unsigned upper-bound selection. For signed values use `max`.

**Signature** — `pub fn maxU(a: u32, b: u32) u32`

**Parameters**
- `a`, `b` — the values to compare.

**Returns** — `a` when `a > b`, otherwise `b`.

**Errors** — none.

**Example**
```zig
const m = std.math.maxU(7, 3); // 7
```

**Gotchas** — unsigned only; there is no `maxU64`.

#### `abs`

**Purpose** — returns the absolute value of an `i32`.

**When to use** — magnitude of a signed difference or offset. To bound a value
instead, use `clamp`.

**Signature** — `pub fn abs(n: i32) i32`

**Parameters**
- `n` — the value.

**Returns** — `n` when `n >= 0`, otherwise `0 - n`.

**Errors** — none.

**Example**
```zig
const a = std.math.abs(-9); // 9
```

**Gotchas** — the magnitude of `i32` minimum (`-2147483648`) is not representable
as a positive `i32`; `0 - n` overflows there and traps under the default `-fsafe`
mode.

#### `clamp`

**Purpose** — constrains a signed `i32` to the inclusive range `[lo, hi]`.

**When to use** — enforcing a signed floor and ceiling in one call. For unsigned
values use `clampU`.

**Signature** — `pub fn clamp(v: i32, lo: i32, hi: i32) i32`

**Parameters**
- `v` — the value to constrain.
- `lo` — lower bound, returned when `v < lo`.
- `hi` — upper bound, returned when `v > hi`.

**Returns** — `lo` when `v < lo`, `hi` when `v > hi`, otherwise `v`.

**Errors** — none.

**Example**
```zig
const c = std.math.clamp(42, 0, 10); // 10
```

**Gotchas** — assumes `lo <= hi`; with `lo > hi` the lower-bound test wins and the
result is `lo` for any `v < lo`.

#### `clampU`

**Purpose** — constrains an unsigned `u32` to the inclusive range `[lo, hi]`.

**When to use** — enforcing an unsigned floor and ceiling in one call. For signed
values use `clamp`.

**Signature** — `pub fn clampU(v: u32, lo: u32, hi: u32) u32`

**Parameters**
- `v` — the value to constrain.
- `lo` — lower bound, returned when `v < lo`.
- `hi` — upper bound, returned when `v > hi`.

**Returns** — `lo` when `v < lo`, `hi` when `v > hi`, otherwise `v`.

**Errors** — none.

**Example**
```zig
const c = std.math.clampU(200, 0, 100); // 100
```

**Gotchas** — assumes `lo <= hi`; with `lo > hi` the lower-bound test wins.

#### `isPowerOfTwoU32`

**Purpose** — reports whether a `u32` is a power of two.

**When to use** — validating an unsigned alignment or capacity argument.

**Signature** — `pub fn isPowerOfTwoU32(n: u32) bool`

**Parameters**
- `n` — the value to test.

**Returns** — `true` when exactly one bit is set; `false` for `0` and for values
with two or more bits set.

**Errors** — none.

**Example**
```zig
if (std.math.isPowerOfTwoU32(64)) { std.io.write("pow2\n"); }
```

**Gotchas** — `0` is not a power of two. This overlaps `std.bits.isPow2`; both
compute the same predicate.

#### `alignUp`

**Purpose** — rounds `n` up to the next multiple of `alignment`.

**When to use** — computing a padded size or an aligned offset. For the opposite
rounding use `alignDown`.

**Signature** — `pub fn alignUp(n: u32, alignment: u32) u32`

**Parameters**
- `n` — the value to round up.
- `alignment` — the alignment; must be a non-zero power of two.

**Returns** — the smallest multiple of `alignment` that is `>= n`.

**Errors** — none.

**Example**
```zig
const a = std.math.alignUp(5, 4); // 8
```

**Gotchas** — assumes `alignment` is a power of two; `alignment == 0` underflows
`alignment - 1` and traps under the default `-fsafe` mode, and a large `n` can
overflow `n + (alignment - 1)` (for example `n = 0xFFFFFFFF, alignment = 4`),
which also traps. A non-power-of-two alignment yields a meaningless result.

#### `alignDown`

**Purpose** — rounds `n` down to the previous multiple of `alignment`.

**When to use** — computing a base address or a block start. For the opposite
rounding use `alignUp`.

**Signature** — `pub fn alignDown(n: u32, alignment: u32) u32`

**Parameters**
- `n` — the value to round down.
- `alignment` — the alignment; must be a non-zero power of two.

**Returns** — the largest multiple of `alignment` that is `<= n`.

**Errors** — none.

**Example**
```zig
const a = std.math.alignDown(5, 4); // 4
```

**Gotchas** — assumes `alignment` is a power of two; `alignment == 0` underflows
`alignment - 1` and traps under the default `-fsafe` mode.

## See also

- `std.bits`, `std.math` — the modules in this doc.
- [`memory.md`](memory.md) — the arena's byte offsets pair with these alignment
  helpers.
- [`collections.md`](collections.md) — the maps and heap use power-of-two
  capacities and `std.math` bounds.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
