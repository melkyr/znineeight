# Fold — `std_fold`

| | |
|---|---|
| **Modules** | `std_fold` |
| **Layers** | `L0` — Foundation: no library imports; pure computation |
| **Import (re-export)** | `const std = @import("std");` → `std.fold` |
| **Import (by path)** | `const std_fold = @import("std_fold");` |

`std_fold` is one of the fourteen `std` re-exports; reach it as `std.fold`.
The bare by-path form resolves with the search path's `.zig` append.

## Module overview

`std_fold` provides a per-type **left fold** over a slice: walk the elements in
order and thread an accumulator through a caller-supplied combiner. There are
three concrete functions — `foldU32`, `foldI32`, and `foldUsize` — one per
element type. They are deliberately not generic: the combiner is a plain
function pointer (`fn (T, T) T`), passed through the compiler's normal indirect
call path.

The fold is exactly `acc = f(acc, x)` for each element from index 0 to
`xs.len - 1`, and the final accumulator is returned. An empty slice returns the
initial `acc` unchanged. The function performs no allocation, can fail with no
errors, and does not suspend (R1/R2/R4 do not apply). The combiner is the
caller's responsibility for determinism (R6); `std_fold` itself introduces no
address-, clock-, or PID-dependent behavior.

## Quick start

```zig
const std = @import("std");

fn addU32(a: u32, x: u32) u32 {
    return a + x;
}

pub fn main() void {
    var xs: [4]u32 = [4]u32{ 1, 2, 3, 4 };
    var total = std.fold.foldU32(xs[0..], 0, addU32);
    std.io.printInt(@intCast(i32, total));
}
```

Output: `10`.

## API

### foldU32

**Purpose** — Folds a `[]const u32` left to right with a `fn (u32, u32) u32`
combiner.

**When to use** — Sum, product, running maximum, or any order-sensitive
accumulation over `u32` elements. For another element type use `foldI32` /
`foldUsize`; for transforms that need per-element state beyond the accumulator,
write an explicit loop.

**Signature** — `pub fn foldU32(xs: []const u32, acc: u32, f: fn (u32, u32) u32) u32`

**Parameters**
- `xs` — the slice to walk; read-only and not retained after return.
- `acc` — the initial accumulator, returned unchanged for an empty slice.
- `f` — the combiner, called as `f(acc, x)` in slice order.

**Returns** — The final accumulator after the last element (or `acc` when
`xs.len == 0`).

**Errors** — none.

**Example**
```zig
fn addU32(a: u32, x: u32) u32 {
    return a + x;
}

var xs: [3]u32 = [3]u32{ 1, 2, 3 };
var total = std.fold.foldU32(xs[0..], 0, addU32);   // 6
```

**Gotchas** — The combiner must have exactly the `fn (u32, u32) u32`
signature; over/underflow behavior is the combiner's (`+` traps under
`-fsafe`, wraps under `-ffast`). The order is always left to right, so a
non-commutative combiner is observable.

### foldI32

**Purpose** — Folds a `[]const i32` left to right with a `fn (i32, i32) i32`
combiner.

**When to use** — Signed integer accumulation (sums, running differences,
signed maxima) where the accumulator must stay `i32`.

**Signature** — `pub fn foldI32(xs: []const i32, acc: i32, f: fn (i32, i32) i32) i32`

**Parameters**
- `xs` — the `i32` slice to walk.
- `acc` — the initial `i32` accumulator.
- `f` — the `fn (i32, i32) i32` combiner, called as `f(acc, x)` in order.

**Returns** — The final `i32` accumulator (`acc` for an empty slice).

**Errors** — none.

**Example**
```zig
fn subI32(a: i32, x: i32) i32 {
    return a - x;
}

var xs: [3]i32 = [3]i32{ 1, 2, 3 };
var r = std.fold.foldI32(xs[0..], 100, subI32);   // 94
```

**Gotchas** — Signed overflow is the combiner's behavior, not the fold's;
under `-fsafe` an overflowing `+`/`-` traps.

### foldUsize

**Purpose** — Folds a `[]const usize` left to right with a
`fn (usize, usize) usize` combiner.

**When to use** — Length/index/count accumulation over `usize` elements.
Converting to `i32` for printing requires an explicit `@intCast`.

**Signature** — `pub fn foldUsize(xs: []const usize, acc: usize, f: fn (usize, usize) usize) usize`

**Parameters**
- `xs` — the `usize` slice to walk.
- `acc` — the initial `usize` accumulator.
- `f` — the `fn (usize, usize) usize` combiner, called as `f(acc, x)` in order.

**Returns** — The final `usize` accumulator (`acc` for an empty slice).

**Errors** — none.

**Example**
```zig
fn addUsize(a: usize, x: usize) usize {
    return a + x;
}

var xs: [3]usize = [3]usize{ 10, 20, 30 };
var total = std.fold.foldUsize(xs[0..], 0, addUsize);   // 60
```

**Gotchas** — `usize` is a 32-bit unsigned type in the Z98 model; mixing it
with `i32` needs `@intCast`, and the combiner owns overflow behavior.

## See also

- `std_fold` — the module in this doc (re-exported as `std.fold`).
- [STD_README.MD](../../../STD_README.MD) — the curated std-lib index.
- [Language_Spec_Z98.md](../../../docs/reference/Language_Spec_Z98.md) — slices,
  function-pointer parameters, and the `for` capture rules.
