# voiddecl_count_r3 — sibling module count probe  [R3, 2026-08-18]

## Purpose
Third rung of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
R1 (2 modules, cross-module struct return) and R2 (chain depth to 40) were
GREEN. This rung isolates whether SIBLING module COUNT drops the FIRST K modules
(the "modules 1-4 silently dropped" pattern behind 213x error[3000] during
self-compile): N ∈ {4, 8, 16, 32, 39} sibling modules all imported by main.zig,
all with the bare-T struct-return form (clean form — no cross-module type refs,
which R2 showed trip error[3000] independently of count).

## Fixture (committed state = N=39, the largest GREEN N tested)
39 sibling modules `mK.zig`, each with the literal K baked in (module identity
testable via output):

```zig
pub const S = struct { v: u32 };
pub fn make() S { var f = S{ .v = K }; return f; }
```

`main.zig` imports all 39 and calls every `mK.make()`, printing each `v` with
`writeByte(' ')` separators then `printInt` for the sum:

```zig
const std = @import("std");
const m1 = @import("m1.zig");
/* ... const m39 = @import("m39.zig"); ... */
pub fn main() void {
    var s: u32 = 0;
    s += m1.make().v;
    std.io.printInt(m1.make().v);
    std.io.writeByte(@intCast(u8, ' '));
    /* ... x39 ... */
    std.io.printInt(s);
}
```

No cross-module type refs (`a_next.T` style) anywhere — bare-T only, per brief.

## Measured results (2026-08-18, /tmp/fx_subfolder/zig1, run FROM fixture dir)
Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → gcc → run.

| N | dump rc | error[3000] count | gcc rc | run output (v values … sum) | run rc | verdict |
|---|---------|-------------------|--------|------------------------------|--------|---------|
| 4  | 0 | 0 | 0 | 1 2 3 4 → 10 | 0 | GREEN |
| 8  | 0 | 0 | 0 | 1 … 8 → 36 | 0 | GREEN |
| 16 | 0 | 0 | 0 | 1 … 16 → 136 | 0 | GREEN |
| 32 | 0 | 0 | 0 | 1 … 32 → 528 | 0 | GREEN |
| 39 | 0 | 0 | 0 | 1 … 39 → 780 | 0 | GREEN |

- Every v is printed in order, every module resolved, sum always correct
  (39×40/2 = 780). No module silently dropped at any N.
- Largest N that stays GREEN: **39** (committed). No N tripped the drop.
- No first-error site applicable (no RED at any tested N).

## Ruling
**GREEN at all N up to 39. Sibling module COUNT alone does NOT trip the
silent-drop bug.** The count dimension is discharged: main importing 39 sibling
modules with clean bare-T struct-return resolves all of them. Combined with R2,
neither chain depth (to 40) nor sibling count (to 39) trips error[3000]. The
remaining candidate mechanism (flagged in R2) is the explicit cross-module
TYPE REFERENCE in function return types, which tripped at N=3 regardless of
depth — that moves to the I-DROP/volume probe (R4) rather than being a count
artifact. Proceed to R4.
