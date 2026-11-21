# voiddecl_mimic_r6v2 — self-hosting-shape mimic  [R6, 2026-08-18]

## Purpose
Final ladder rung of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
R1 (2 modules), R2 (chain depth 40), R3 (sibling count 39), R4 (identifier
volume 10k), R5 (nested 6×4 tree) all GREEN. This rung reconstructs the
TRIGGER shape: ~39 modules arranged in sf/src's import order with
representative identifier volume — OR produces a definitive negative
(shape+scale alone cannot reconstruct the drop).

NOTE: directory `voiddecl_mimic_r6` had a filesystem lock (files kept
reappearing); operator authorized `voiddecl_mimic_r6v2`. Commit message
unchanged per plan.

## Reconstructed layout (39 files = main.zig + m01..m38)
Modules 1–4 are the base four (mirroring sf/src allocator / string_interner /
source_manager / diagnostics — the modules silently dropped in self-compile).
Each defines 4 structs + 4 bare-T struct-returning fns (16 fns total), and is
imported by EVERY later module (fan-in) and by main:

| module | sf/src role | structs | fns (return .v) |
|--------|-------------|---------|-----------------|
| m01 | allocator | Sand, Pool, SandPool, CompAlloc | makeSand=101, makePool=102, makeSandPool=103, makeCompAlloc=104 |
| m02 | string_interner | Intern, InternEntry, InternTable, StringInterner | makeIntern=201, makeEntry=202, makeTable=203, makeInterner=204 |
| m03 | source_manager | Source, SourceFile, LineMap, SourceManager | makeSource=301, makeFile=302, makeLineMap=303, makeSourceManager=304 |
| m04 | diagnostics | Diag, DiagMsg, MsgBuf, DiagCollector | makeDiag=401, makeMsg=402, makeBuf=403, makeCollector=404 |

Modules m05..m38 (34 modules) follow sf/src's main.zig import order
(name_mangler, token, lexer, pal, parser, ast, itoa, path, module_registry,
import_resolver, analyzer, symbol_table, type_registry, c89_emit, lower, lir,
resolved_type_table, hash, coercion, semantic_analyzer, type_resolver,
comptime_eval, symbol_registrator, const_alias_prepass, cinclude,
growable_array, state_map, config, semantic, dump_tokens, dump_ast, extern_c,
extern_c_z98, constraint_checker). Each defines 2 structs (S0, S1) + 2
struct-returning fns:
- `make()`  → S0{ .v = m01.makeSand().v + m02.makeIntern().v + i }  (302+i)
- `make2()` → S1{ .v = m03.makeSource().v + m04.makeDiag().v + i }  (702+i)

i.e. the critical first-K pattern: every later module CALLS modules 1–4's
struct-returning fns. Import graph is a strict DAG (each module imports only
lower module ids, including the base four) matching sf/src's order; ~5–10
import edges per module. Identifier volume: 300 `pub const cNNN: u32` per
module × 38 = **11,400 identifiers** (self-compile ≈ 9,331).

`main.zig` (module 0) imports all 38 modules, calls struct-returning fns from
modules 1–4 (m01.makeSand, m02.makeIntern, m03.makeSource, m04.makeDiag) and
from the chain end (m38.make, m38.make2), prints each `.v` with `writeByte(' ')`
separators, then the sum.

## Dialect adaptation (documented per brief)
None required. Bare-T struct returns + module field-access calls throughout —
the R1–R5 clean form. NO cross-module type refs in any fn signature (the R2
I-DROP lead, deliberately excluded from this rung). No anytype, no @Type.

## Measured results (2026-08-18, /tmp/fx_subfolder/zig1, run FROM fixture dir)
Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → gcc
(`-m32 -std=c89` with absolute sf include/runtime paths) → run.

| shape | dump rc | error[3000] | gcc rc | run output | run rc | verdict |
|-------|---------|-------------|--------|------------|--------|---------|
| 39 modules (m01..m38 + main), 11.4k identifiers, sf-order DAG | 0 | none | 0 | ` 101 201 301 401 340 740 2084` | 0 | GREEN |

- Expected: a=101, b=201, c=301, d=401, e=302+38=340, f=702+38=740,
  sum=101+201+301+401+340+740=2084. All matched — every struct return resolved
  to its real type; modules 1–4 NOT dropped to void.
- Closure verification: emitted C contains all 38 modules' fns — 16 base fns
  (m01–m04) each referenced 38–41 times (every module + main call them) and
  34×`make` + 34×`make2` (m05–m38) present under mangled names. No module
  silently missing.
- No first-error site applicable (GREEN, no RED).

## Marker-signature match assessment
Real self-compile marker signature: 213 × `error[3000] cannot declare variable
of type void`, concentrated on the FIRST modules' struct-returning fns
(modules 1–4 = allocator/interner/source/diag) resolving to void.

This mimic: GREEN. The exact shape+scale (39 modules in sf/src import order,
base-four fan-in called by later modules AND main, 11.4k interned identifiers)
with the clean bare-T / module-field-access form does NOT reproduce the drop —
no `error[3000]`, all first-module struct returns resolve correctly through
the full DAG. 

## Ruling
**GREEN — definitive negative for shape+scale. The self-hosting-shape mimic
alone does NOT reconstruct the silent drop.** All six R-ladder rungs are now
discharged: 2-module, chain-40, sibling-39, volume-10k, nested-6×4, and this
39-module sf-order reconstruction with base-module fan-in. Shape+scale alone
cannot explain the self-compile drop; the trigger requires the mechanism the
R-ladder ruled out dimensionally — consistent with the R2 finding that an
explicit cross-module type reference in a fn signature trips error[3000] at
N=3 regardless of shape/scale. Hand to I-DROP (markers + intrusive fprintf on
a /tmp copy) to pin the exact dropped condition in the real self-compile.
