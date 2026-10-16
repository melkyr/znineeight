# z98 compiler — D1/D2 parity: canonical synthetic composites, comptime-if, conditional `@import` — Design

**Status:** Approved (operator, 2026-10-16 — rulings: Zig rule on the untaken arm; whole synthetic-composite family; conditional `@import` included; z9play `Key.none` workaround kept; pins may move).
**Binding for:** `docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md`.
**Oracle:** Zig 0.15.2 semantics (the project's parity target).

## §1 Scope

Fix two open compiler defects at root cause and add one missing Zig-idiom feature, so z9play M6 (Win9x) can proceed on the clean two-module `@isWindows()` shape:

- **D1** — a function pointer whose return type is an optional/error-union **of an aggregate** cannot be emitted (recorded in `examples/torrent_example_defects.md`).
- **D2** — a module referenced only from a comptime-dead `@isWindows()` arm is still emitted; its platform `@cInclude` breaks the other toolchain (recorded likewise).
- **Conditional `@import`** — `const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");` must resolve to the live module (the Zig idiom; currently yields `void`).
- **Static analyzers** (`sf/src/analyzer.zig`) adapt to the new surface and get a drift truth-up ("they are pretty outdated" — operator).

Out of scope: unrelated fixes; reverting z9play's `Key.none` contract (kept); general comptime module values.

## §2 D1 — canonical synthetic composites

**Bug 1 (identity).** `sf/src/type_registry.zig` — `typeRegistryGetOrCreateOptional:814`, `typeRegistryGetOrCreateErrorUnion:839`, `typeRegistryGetOrCreateArray:869` cache the composite **only when the payload is already laid out** (`if (pay_type.state == 2) … MapPut`). A composite created before its payload resolves is appended but never cached, so the next call creates a **second, distinct type id**. There are no state-mutation writes in the registry (every `.state =` is a creation site); layout resolution lives in `sf/src/type_resolver.zig` (`layoutEnsure:433`, `typeResolverResolve` — which resolves every type and sets `state=2`). Contrast: `typeRegistryGetOrCreatePtr:739` caches unconditionally — that is the model.

Consequence: a struct field's `?Key` and a function's `?Key` are different ids and `typeRegistryIsAssignable:1813` (which compares `fn_type.return_type` ids directly) rejects with `error[3000]`. The **same bug class** covers `E!Aggregate` and `[N]Aggregate` — the fix covers the whole synthetic-composite family (optional, error_union, array; tuple/slice audited).

**Fix 1:** cache by key **unconditionally** in the three (or more) GetOrCreate sites; ensure `layoutEnsure`/`typeResolverResolve` resolves late-created composites (on-demand `layoutEnsure` if a composite is created after the topological pass). Belt-and-braces: make `typeRegistryIsAssignable`'s `fn_type` comparison structural (return + params).

**Bug 2 (emit).** With one `?T` id (alias workaround), the frontend passes but the fn-pointer typedef is emitted before (or without) the composite typedef: `zig_special_types.h:663` `expected declaration specifiers or '...' before '*' token`, then `unknown type name 'zT_…_FP_zT_…_Opt_'`. The P2 relation already carries the fn-return name-position edge (`typeRefsWalk` fn_type → `return_type` name_pos=1) and `typeNeedsFullDef(optional)=true`, so the failure is one of: `typeHasForwardDecl` suppressing the edge (`typeRefEdgeTarget:1337` name_pos=1 path), or the per-kind emit dispatch (`sf/src/c89_emit.zig:1440-1453` — no optional/error_union/slice case visible) omitting the composite typedef.

**Fix 2 (repro-driven):** run the D1 reproducer; inspect the emitted `zig_special_types.h` (ordering vs missing typedef); fix so every composite typedef is emitted and ordered before every spelling reference (keep the fn-return edge honest vs `typeHasForwardDecl`; add the missing kinds to the emit dispatch if that is the gap).

## §3 Comptime-if folding (D2 root) — the Zig rule (operator-approved)

**Rule:** when an `if`/`else` condition is **comptime-known**, the untaken arm is **not semantically analyzed and not lowered** (Zig semantics: the untaken branch is eliminated before analysis). The `if`'s value/type is the live arm's. **Runtime conditions are untouched** — no branch folding, no simplification.

**Trigger set (narrow, fixture-pinned):** `@isWindows()` (already a compile-time-folded predicate, `comptime_eval.zig:1579`), literal `true`/`false`, and comptime `const` bool/int conditions the existing evaluator already folds (`comptimeEvalEvaluate`). Nothing else triggers.

**Consequence (D2 fixed at root):** dead-arm instructions never reach the LIR, so the module-reference edges in `sf/src/main.zig:1300-1440` (`func_ref`/`call_direct`/`load_global`/`store_global` + `pruneTypeMarkByValue` type edges) no longer exist for dead arms; the reachable-module closure no longer marks the wrong-platform module → its `@cInclude` is never emitted. (Examples cannot guard `@cInclude`: `c89_emit.zig:1941-1958` emits includes unconditionally.)

**Diagnostics:** errors inside a comptime-dead arm vanish (Zig behavior). T0 must scan the corpus for fixtures whose only error sits in a dead arm (class-mover risk) and STOP-present if any exist.

## §4 Conditional `@import`

`const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");` (and the `switch` form) must resolve to the live module. Requires `import_expr` in expression position (`semantic_analyzer.zig:1822/3389/5203`, `type_resolver.zig:2277/2323/2346`, `lower.zig:4390/4621` handle it only at decl/member positions today) plus the §3 sema fold. Out of scope: general comptime module values, conditional imports at runtime.

## §5 Static analyzers

`sf/src/analyzer.zig` (SignatureAnalyzer / LifetimeAnalyzer / NullPointerAnalyzer / DoubleFreeAnalyzer; tests `sf/src/tests/test_analyzer_bin.zig`, `tests/analyzers/`):

- **SignatureAnalyzer** accepts fn-pointer returns of `?Aggregate`/`E!Aggregate` post-fix (its C89-compatibility rules currently predate this shape and arbitrary-width ints / `.tag` / packed-union members).
- **Lifetime/NullPointer/DoubleFree** cover the current language surface incl. captures (open drift: `docs/tech_debt/static_analyzers.md` §2.1 "provenance not tracked through optional or error union captures").
- Truth-up `docs/design/static_analyzers.md`, `docs/sf/STATIC_ANALYZERS_p2.md`, `docs/tech_debt/static_analyzers.md`.

## §6 Gates

Battery per convention: corpus class-file byte-identical (frozen `518eca1a9b5d3e1cc5a48abce214abd8`, `1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`, 0 movers) + goldens 5/5 + mi_matrix 25+oob + examples 26/26 build + 26/26 run + stdlib 285/0 + seed two-hop `hop1==hop2`. **Pins (`--dump-c89`) recorded old→new and MAY move** (dead code disappears where a comptime-if existed — operator: "acceptable"). Markers telemetry recorded. New fixtures green.
