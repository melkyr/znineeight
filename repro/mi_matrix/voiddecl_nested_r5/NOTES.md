# voiddecl_nested_r5 — nested import-tree shape probe  [R5, 2026-08-18]

## Purpose
Fifth rung of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
R1 (2 modules) GREEN, R2 (chain depth 40) GREEN, R3 (sibling count 39) GREEN,
R4 (identifier volume 10k) GREEN. This rung isolates whether a branching NESTED
import tree trips the silent-drop bug (modules silently skipped → `error[3000]
cannot declare variable of type void`). Self-compile's module graph is a real
tree, not a linear chain or flat sibling set — hence this shape.

## Fixture (shape: 6 children × 4 grandchildren + main = 31 files)
`main.zig` imports 6 roots (`root_a`…`root_f`). Each root imports and
re-exports 4 grandchildren (`sub_a1`…`sub_f4`, 24 total) via
`pub const gK = @import("sub_<r>K.zig");`. Each grandchild defines a struct and
a bare-T `make()`:

```zig
pub const S = struct { v: u32 };
pub fn make() S {
    var f = S{ .v = N };
    return f;
}
```

`main.zig` calls through the tree to every grandchild make() as a plain
module-level field-access call (`root_a.g1.make().v`, … `root_f.g4.make().v`),
prints each v with `std.io.writeByte(@intCast(u8, ' '))` separators, then
`std.io.printInt(sum)`.

## Dialect adaptation (documented per brief)
None required. The brief's "module field-access call through re-exports"
(`gK.make()` via the child) is the committed form verbatim — no forwarding fns,
no cross-module type references in any fn signature. (Per R2 notes, an explicit
cross-module type ref in a return type trips error[3000] at N=3 regardless of
depth — that is a separate I-DROP lead, deliberately excluded from this rung.)

## Measured results (2026-08-18, /tmp/fx_subfolder/zig1, run FROM fixture dir)
Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → gcc
(`-m32 -std=c89` with absolute sf include/runtime paths) → run.

| shape | dump rc | error[3000] | gcc rc | run output | run rc | verdict |
|-------|---------|-------------|--------|------------|--------|---------|
| 6 children × 4 grandchildren (24 leaf makes) | 0 | none | 0 | `1 2 … 24 300` | 0 | GREEN |

- Sum = 1+2+…+24 = 300 (verified). All 24 grandchild `make()` calls resolved
  through the two-level re-export tree — no module silently dropped, no make()
  resolved to void, values print in expected 1..24 order.
- No first-error site applicable (GREEN, no RED).

## Ruling
**GREEN. Nested branching import-tree shape (2-level, 6×4) does NOT trip the
silent-drop bug.** Proceed to R6. R1–R5 have now discharged: 2-module, chain
depth 40, sibling count 39, identifier volume 10k, and this nested-tree shape.
The remaining candidate is the self-hosting-shape mimic (R6).
