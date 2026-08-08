# xmod_pub_const_global — FAIL (emission defect, undeclared zG_ global)  [I-task: rogue_mud build attempt, 2026-08-07]

## What it tests
A cross-module reference to a `pub const` integer global — `colors.COLOR_WHITE`
where `colors.zig` declares `pub const COLOR_WHITE: u8 = 7;`. The consumer
(`main.zig`) references it as a field value and in a struct literal. The
emitted C refers to `zG_97359566_COLOR_WHITE` — an undeclared storage
global that is never defined, never `extern`-declared, and never folded to
its comptime value.

## Origin (rogue_mud)
`examples/z98/rogue_mud/main.zig` references `ui_mod.COLOR_WHITE`,
`ui_mod.COLOR_BLACK`, `ui_mod.COLOR_GREEN`, `ui_mod.COLOR_RED`,
`ui_mod.COLOR_BLUE`, `ui_mod.COLOR_YELLOW`, `ui_mod.COLOR_BRIGHT` (declared
`pub const ...: u8 = N;` in `ui.zig:24-32`) inside `renderLocal`/
`broadcastDungeon`/`broadcastOneClient`. Every use emits
`zG_<hash>_COLOR_*` which is undeclared → gcc `error: 'zG_...' undeclared`.
Same-module uses fold fine (`ui.c` emits `zT_65 = 7;`).

## The compiler gap
The F8 ident_expr const-chain fold (comptime-folding named consts) does not
cover cross-module `pub const` integer globals: a `pub const x: T = <literal>`
referenced from another module lowers to a storage-global `zG_` read, but
the emitter never emits that global's definition or an `extern` decl for it
(a module-scope `pub const` is not a storage global in the emission model —
only `pub var` gets a `zG_` slot). Result: undeclared identifier in the
emitted C.

## Measured result (2026-08-07, /tmp/zrg/zig1)
- dump rc=0, 2 `.c` emitted.
- gcc per-file `-c` rc=1: 2 `error: 'zG_97359566_COLOR_WHITE' undeclared`,
  2 `error: 'zG_0FC2D9A4_COLOR_BLACK' undeclared`.
- Classification: **FAIL** (emission defect; not a green-guard; not an ICE).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/.../out.c repro` accepts cross-module `pub const`
refs (rc=0, emits C) — valid Z98, genuine compiler gap.

## Expected classification
FAIL until cross-module `pub const` integer globals are either comptime-folded
at the reference site (F8 already folds same-module ident chains) or emitted
with an `extern const` decl + definition.
