# voiddecl_volume_r4 — interned identifier volume probe  [R4, 2026-08-18]

## Purpose
Fourth rung of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
R1 (2 modules) GREEN, R2 (chain depth 40) GREEN, R3 (sibling count 39) GREEN.
Self-compile has 9,331 unique interned identifiers — this rung isolates whether
identifier VOLUME trips the silent-drop bug (modules silently skipped →
`error[3000] cannot declare variable of type void`). Bare-T struct-return form
(no cross-module type refs) to keep this a pure volume probe.

## Fixture
`mod.zig`: `N` identifiers `pub const vNNNN: u32 = NNNN;` (4-digit zero-padded,
v0000..v{N-1}) plus:
```zig
pub const Foo = struct { v: u32 };
pub fn make() Foo { var f = Foo{ .v = 7 }; return f; }
```

`main.zig` references every-100th identifier (v0000, v0100, … v0900 — all
present at every tested volume), prints their sum, then the struct-return value:
```zig
const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var s: u32 = 0;
    s += mod.v0000; s += mod.v0100; s += mod.v0200;
    s += mod.v0300; s += mod.v0400; s += mod.v0500;
    s += mod.v0600; s += mod.v0700; s += mod.v0800;
    s += mod.v0900;
    std.io.printInt(s);
    var x = mod.make();
    std.io.printInt(x.v);
}
```
Expected output: `4500` (0+100+…+900) then `7`.

## Measured results (2026-08-18, /tmp/fx_subfolder/zig1, run FROM fixture dir)
Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → gcc
(`-m32 -std=c89` with absolute sf include/runtime paths) → run.

| volume | identifiers | dump rc | error[3000] | gcc rc | run output | run rc | verdict |
|--------|-------------|---------|-------------|--------|------------|--------|---------|
| 1k  | 1,000 | 0 | none | 0 | `45007` | 0 | GREEN |
| 5k  | 5,000 | 0 | none | 0 | `45007` | 0 | GREEN |
| 10k | 10,000 | 0 | none | 0 | `45007` | 0 | GREEN |

- Sum always 4500 and struct-return always 7 — every referenced identifier
  resolved, `mod.make()` never resolved to void.
- Largest-GREEN volume: **10k** (committed mod.zig = 10,000 identifiers,
  ~289KB — larger than the brief's ~40–50KB estimate, but acceptable per the
  brief). Threshold: **not tripped** at any tested volume; no RED rung.

## Ruling
**GREEN at all volumes up to 10,000 identifiers. Interned-identifier volume
ALONE does NOT trip the silent-drop bug.** The volume dimension is discharged:
10k identifiers (beyond self-compile's 9,331) compile and run cleanly, struct
return resolves correctly, no `error[3000]`. Combined with R1–R3, neither 2- or
39-module sibling sets, chain depth to 40, nor identifier volume to 10k trips
the drop. The remaining candidate mechanisms: nested import-tree shape (R5) and
the self-hosting-shape mimic (R6). Proceed to R5.
