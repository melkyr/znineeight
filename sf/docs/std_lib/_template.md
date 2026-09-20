# `_template.md` — Z98 std-lib domain doc template

> **This file is the template, not a published module doc.** It defines the
> uniform structure every domain doc under `sf/docs/std_lib/` follows. Do not
> link to it as a module doc and do not publish it in the `STD_README.MD` index.
> To write a domain doc: copy this file to `<domain>.md`, delete everything
> above the first `---`, replace the `<Domain>` title and every `<...>`
> placeholder, and keep the section order and the per-function entry order
> exactly.

---

# <Domain> — `<std_module_a>` + `<std_module_b>`

| | |
|---|---|
| **Modules** | `<std_module_a>`, `<std_module_b>` |
| **Layers** | `<L0>` — <one-line layer meaning>; `<L2>` — <one-line layer meaning> |
| **Import (re-export)** | `const std = @import("std");` → `std.<name>` |
| **Import (by path)** | `const <std_module> = @import("<std_module>");` |

<Delete the import row(s) that do not apply. The twelve `std` re-exports are
`io`, `arena`, `str`, `mem`, `math`, `debug`, `net`, `async`, `bits`, `os`,
`time`, `buf`; reach them as `std.arena`, `std.str`, and so on. Every other
module is imported directly by its bare name, e.g. `@import("std_file")` (the
search path appends `.zig`; the sibling form `@import("std_file.zig")` also
resolves).>

## Module overview

<What the module is for, in user terms, and its model — the one idea a reader
must hold in their head. State the ownership/lifetime rule (R1 arena), the error
rule (R2), and any layering note (R3) that applies. Keep it to a few paragraphs;
no signatures here.>

## Quick start

<A minimal, complete, working example: import, set up, call the module, show the
result. Real signatures, idiomatic Z98 (no generics; `try`/`catch`; `?T`
optionals; `[]u8` slices). This is illustrative, not compiled by a gate.>

```zig
const std = @import("std");

pub fn main() !void {
    // <set up>
    // <call the module>
    // <show the result>
}
```

## API

<One entry per public function, in the exact order below. Document public types
and error sets under the same headings. Every signature, parameter, return
type, and error member must match `sf/src/<module>.zig` — never invent an API.>

### Per-function entry skeleton

````markdown
### <function name>

**Purpose** — <what it does, in one or two sentences.>

**When to use** — <the job it serves, and its nearest alternatives.>

**Signature** — `<real signature from source>`

**Parameters**
- `<name>` — <meaning and constraints.>

**Returns** — <meaning of the return value, including `null`/`?T`/sentinels.>

**Errors** — <each error member and when it is produced; write "none" if it
cannot fail.>

**Example**
```zig
<illustrative Z98 snippet using the real signature>
```

**Gotchas** — <invariants, aliasing, lifetime, determinism, arena ownership.>
````

**Example entry (filled in):**

### std.arena.alloc

**Purpose** — Reserves `size` bytes from the arena and returns a pointer to the
start of the new region.

**When to use** — When you need scratch or owned storage whose lifetime ends
when the arena is reset. For a growable byte buffer use `std.buf`; for fixed
raw copies use `std.mem`; for one-off heap-free scratch that you free
individually, this is not the tool — the arena only frees by `reset`.

**Signature** — `pub fn alloc(self: *Arena, size: usize) ArenaError![*]u8`

**Parameters**
- `self` — pointer to the `Arena`; the call mutates it (`used` advances by
  `size`).
- `size` — number of bytes to reserve. No alignment adjustment is applied: the
  returned pointer is `arena.data + used`, so its alignment is that of the
  backing buffer plus the current offset.

**Returns** — `[*]u8`, a many-item pointer to `size` uninitialized bytes inside
the arena's caller-owned backing buffer. Valid until the next `reset` (or until
the backing buffer is released by the caller). The region is **not** zeroed.

**Errors** — `error.OutOfMemory` when `used + size > capacity`.

**Example**
```zig
const std = @import("std");

var backing: [1024]u8 = undefined;

pub fn main() !void {
    var arena = std.arena.init(backing[0..]);
    const p = try std.arena.alloc(&arena, 16);
    p[0] = 42;
    std.io.printInt(@intCast(i32, p[0]));
    std.arena.reset(&arena);
}
```

**Gotchas**
- The arena does **not** own `backing`; the caller keeps the buffer alive and
  aligned for as long as any pointer from the arena is used.
- `alloc` never frees and never reuses: memory is reclaimed only in bulk by
  `std.arena.reset`. There is no `free`.
- Overflow of `used + size` is checked before the write, so a failed `alloc`
  leaves the arena unchanged.
- `alloc(&arena, 0)` returns the current cursor; it is a valid pointer but not
  dereferenceable.

## See also

- `<std_module_a>`, `<std_module_b>` — the modules in this doc.
- `<other_domain>.md` — <why it is related>.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
