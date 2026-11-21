# xmod_global_field_access — RED/GREEN  [Defensive repros — Plan 1, 2026-08-04]

## What it tests
Cross-module global field access (`lib.counter`). RED exercises the module field-access
path for a `SymbolKind.global` member; GREEN is the same-module control (module-local
global via F-7 `load_global`).

## Expected classification
RED likely FAIL (gcc) or `warning[3023]` + uninit read, because `lower.zig:1850-1871`
module field-access path handles `type_alias`/`function` but NOT `SymbolKind.global`.
GREEN should be OK (module-local global via F-7 `load_global`).

## Deferred item
Guards the cross-module global field-access gap (F-7 review I-1). FIX is a SEPARATE task
(Plan 1 Task P1-2) — this repro is created here, no fix.
