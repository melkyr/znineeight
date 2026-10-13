# P4 report — Single classification pass (execution order 5/10 per Task 0)

**Status:** BLOCKED at Investigate (plan-level divergence — equivalence-map evidence below). No source edit made; no compiler-moving commit; battery not run (tree unchanged at `b33ae234`, fixed point `25f246289f655f1692657da5cdf124a7` unaffected).
**Scope (plan text):** "P4: Single classification pass. Remove emitter `computeSharedSet:1702`/`shouldSkipTypeEmission:1775`; consume the resolver `classifyTypeEmissionGroups`. Gate: runtime battery."
**Tree at start:** `b33ae234` (P3 report), pins = P2-recorded values (P3 was 0/8 delta).
**Binding rule invoked (brief Investigate + controller resolution 6):** "if the resolver classification lacks a decision the emitter makes today (a real semantic gap, not a naming difference), that is a plan-level divergence — STOP/BLOCKED with the evidence — do not improvise a bridge."

---

## Investigate (read-only census + decision-by-decision equivalence map + precise edit plan — written before any source edit)

### I.0 Drift re-derivation (brief/plan cite → current `b33ae234`)

| item | brief said | current | note |
|---|---|---|---|
| `computeSharedSet` | `c89_emit.zig:1702` | **`c89_emit.zig:1106-1172`** | drift = P5/P1/P2/P3 deletions in this file; role re-derived in I.1 |
| `shouldSkipTypeEmission` | `c89_emit.zig:1775` | **`c89_emit.zig:1179-1205`** | same drift; call sites `emitTypePasses:1264` (sub-pass 2a) and `:1286` (sub-pass 2b) |
| `classifyTypeEmissionGroups` | `type_resolver.zig:662` | **`type_resolver.zig:636-856`** | drift = P2's graph rewrite above it; body otherwise unchanged since `f96e1206` |
| classification output ("pointer-only / value-embeds / needs-definition per the spec row") | spec §4 row | **`ClassificationResult{ids: [*]u32, len: u32}` (`type_resolver.zig:171-174`) = the pointer-only id list ONLY**; value-embeds exists only as its complement (CLS:v marker `:846`); **"needs-definition" output does not exist anywhere** (repo-wide `grep -rn "needs-definition" sf/src` → 0 hits; the string exists only in the spec row and the brief quoting it) | plan's assumed sufficiency already suspect at the output type |

### I.1 Census — every site of the three functions (grep evidence)

Command `grep -n "computeSharedSet\|shouldSkipTypeEmission\|classifyTypeEmissionGroups" sf/src/*.zig` (observed hits, abridged to the live set):

```
sf/src/c89_emit.zig:1106:pub fn computeSharedSet(reg: *TypeRegistry, emitter: *C89Emitter, alloc: *Sand) void {
sf/src/c89_emit.zig:1179:fn shouldSkipTypeEmission(ty: type_mod.Type, skip_arb: u8) u8 {
sf/src/c89_emit.zig:1264:        var sk = shouldSkipTypeEmission(ty, skip_arb);
sf/src/c89_emit.zig:1286:        var sk2 = shouldSkipTypeEmission(ty, skip_arb);
sf/src/c89_emit.zig:1295:    computeSharedSet(reg, emitter, emitter.alloc);
sf/src/main.zig:574:    var ptr_grp = type_resolver.classifyTypeEmissionGroups(&tr, &ctx.alloc.permanent);
sf/src/type_registry.zig:1243:// (`tstTopologicalSort` / `computeSharedSet`). It replaces the three divergent
sf/src/type_resolver.zig:636:pub fn classifyTypeEmissionGroups(self: *TypeResolver, perm_alloc: *Sand) ClassificationResult {
```

**`computeSharedSet` (c89_emit.zig:1106-1172)** — sole caller `emitSharedHeader:1295`. Builds `emitter.shared_set` (field `:585`, init `:660`) = "definition lives in `zig_special_types.h`". Seed rules, per type:
1. `:1108-1129` **synthetic**: `name_id==0` ∧ kind ∈ {slice, optional, error_union, error_set, tagged_union, union, array, fn_type} (`:1111-1118`), OR `name_id==0` ∧ tuple ∧ `emitter.needed_tuple_set` contains it (`:1123-1128`);
2. `:1131-1133` **is_clsv**: NOT in `emitter.pointer_only_map` (= classified value-embeds, CLS:v);
3. `:1134-1137` **carrier64**: kind ∈ {i64_type, u64_type, f64_type};
4. `:1138-1141` **fn_named**: fn_type ∧ `name_id != 0`.
Then `:1146-1171` **closure**: named aggregates {struct, tagged_union, union, packed_union, enum, error_set} that are pointer-only get promoted when some shared `sj` has `type_mod.typeRefsContains(reg, sj, ti2)` (`:1164`) — P2's type-reference ORDERING relation (post-P2 role: `computeSharedSet` is a consumer of `typeRefs`, not a competitor).

**`shouldSkipTypeEmission` (c89_emit.zig:1179-1205)** — callers only `emitTypePasses:1264/:1286` (both test `sk != 0` → `continue`; the 1/2/3 subcodes are unread). Decisions: skip void (`:1180`); skip {bool, noreturn, null, undefined, integer_literal, type, module} (`:1181-1187`); skip arb_uint/arb_int when `skip_arb != 0` (`:1188-1190`); skip `name_id==0` ∧ kind ∉ {slice, optional, error_union, error_set, tagged_union, union, array, fn_type} (`:1191-1203`); else emit. `skip_arb` is a per-pass parameter: 1 for the shared-header path, 0 for the single-file path (`emitTypePasses:1218-1224`).

**`classifyTypeEmissionGroups` (type_resolver.zig:636-856)** — sole caller `main.zig:574` (`phase_TypeResolution`), result stored `ctx.pointer_only_ids/len` (`main.zig:575-576`). Computes the per-type boolean `pointer_only` (kind dispatch over struct/tagged_union/union/packed_union/array/error_union/optional using predicates `kindIsAggregateCore:597` / `fieldEmbedsByValue:603` / `requiresFullDef:608`, plus a worklist propagation `:814-827`), returns **only the pointer-only id list** (`:855-856`), emits CLS:c/CLS:p/CLS:v markers (`:840-852`). It outputs **no** shared-placement information and **no** skip / needs-definition information.

**How the classification is consumed today (already wired):** `pointer_only_map` filled from `ctx.pointer_only_ids` at `main.zig:1372-1373` (output-dir path) and `c89_emit.zig:2383-2385` (`emitModule`); consumed at `computeSharedSet:1132/:1161`, `emitTypePasses:1259` (2a)/`:1275` (2b split), `emitModuleHeaderFile:2300-2301` (module-header defs = pointer-only ∧ ¬shared). `shared_set` consumed at `emitTypePasses:1261` (`require_shared` filter) and `emitModuleHeaderFile:2301`.

**`needed_tuple_set` timeline (load-bearing):** populated by `collectNeededTuples` (`c89_emit.zig:5753`) from `main.zig:1245` (LIR hoisted temps) and `main.zig:1341` (global decls) — both **inside `phase_C89Emission`**. Phase order (`runCompiler`, `main.zig:377-408`): `phase_TypeResolution` (classification runs here, `:574`) → Front → Comptime → Sema → Static → AsyncFrame → `phase_LIRLowering` → `phase_C89Emission` (needed_tuple_set built → `emitSharedHeader` → `computeSharedSet`). The classification runs **6 phases before** the needed-tuple set exists.

### I.2 Decision-by-decision equivalence map

For every classification decision the two emitter functions make today: which `classifyTypeEmissionGroups` output replaces it.

| # | emitter decision | site | resolver-classification output that replaces it | status |
|---|---|---|---|---|
| E1 | pointer-only membership (2a/2b split; closure eligibility; module-header filter) | `emitTypePasses:1259/:1275`, `computeSharedSet:1161`, `emitModuleHeaderFile:2300` | `ClassificationResult.ids` | **covered — already consumed today via `pointer_only_map`** |
| E2 | value-embeds membership (`is_clsv` shared seed; 2b split) | `computeSharedSet:1131-1133`, `emitTypePasses:1275` | complement of `ClassificationResult.ids` (CLS:v) | **covered — already consumed today** |
| E3 | shared seed: unnamed synthetic kinds {slice, optional, error_union, error_set, tagged_union, union, array, fn_type} | `computeSharedSet:1111-1118` | — | **LACKS** |
| E4 | shared seed: unnamed tuple ∈ `needed_tuple_set` | `computeSharedSet:1123-1128` | — | **LACKS + unavailable at the classification's run site** (see B1) |
| E5 | shared seed: carrier64 {i64, u64, f64} | `computeSharedSet:1134-1137` | — | **LACKS** |
| E6 | shared seed: named fn_type | `computeSharedSet:1138-1141` | — | **LACKS** |
| E7 | closure promotion (pointer-only named aggregates referenced from shared members) | `computeSharedSet:1146-1171` | none (`typeRefsContains` is P2's **ordering** relation — the design bullet forbids scope creep into ordering; the promotion decision itself is not a classification output) | **LACKS** |
| E8 | skip: void | `shouldSkipTypeEmission:1180` | — (void is classified **pointer-only**, `is_po` falls through the kind dispatch) | **LACKS** |
| E9 | skip: bool / noreturn / null / undefined / integer_literal / type / module | `:1181-1187` | — (all classified **pointer-only**) | **LACKS** |
| E10 | skip: arb_uint / arb_int when `skip_arb != 0` | `:1188-1190` | — (per-pass parameterized decision, not a per-type group; see observation O1) | **LACKS** |
| E11 | skip: unnamed non-special kinds | `:1191-1203` | — (such types are still classified po/ve regardless) | **LACKS** |

Concrete divergence witnesses (same classification group, different emitter treatment):
- `void_type`, `bool_type`, `i64_type`, a named struct with only scalar fields, and an unnamed non-special aggregate all classify **pointer-only** (kind dispatch falls through or only sees non-embedding fields) — yet the emitter respectively: skips (E8), skips (E9), forces into the shared header (E5), emits in the module header (not shared), skips (E11). The single boolean cannot express these.
- **Exceeds check (brief bullet 3):** the resolver classification does **NOT** exceed the emitter's — it is a strict subset (po/ve only). No previously-dead decisions to activate. Nothing beyond the map above.

### I.3 The two hard gaps (why "consume" cannot close the map)

- **B1 (timing):** E4's input `emitter.needed_tuple_set` is emission-time, LIR-derived state (`collectNeededTuples`, `main.zig:1245/:1341`, `phase_C89Emission`) and does not exist when `classifyTypeEmissionGroups` runs (`main.zig:574`, `phase_TypeResolution`). A single resolution-time classification cannot answer E4. Closing it requires re-timing the pass, splitting it into static + emission-time refinement, or keeping a second decision site — all design improvisations the plan never specifies.
- **B2 (absence):** the spec row's third group **"needs-definition" does not exist** in `ClassificationResult`, and the shared-placement outputs (E3/E5/E6/E7) have no classification counterpart at all. E8-E11 ("needs-definition" = emit-vs-skip) and E3-E7 (shared placement) are two genuinely different decision dimensions (an unnamed aggregate can be in `shared_set` via `is_clsv` yet skipped by `shouldSkipTypeEmission`; named arb types are emitted single-file yet never in `shared_set`) — the row's three names cannot cover them without inventing the output model.

**Conclusion:** the plan text ("remove `computeSharedSet`/`shouldSkipTypeEmission`; consume the resolver `classifyTypeEmissionGroups`") assumes the classification is sufficient to replace both functions. It is not: 9 of 11 decision classes (E3-E11) have no replacement output, two of them for structural reasons (B1 timing, B2 absence). Per the binding Investigate rule this is a plan-level divergence: STOP/BLOCKED; a gap needs operator eyes, not an improvisation.

### I.4 Precise edit plan

**NONE — stopped at the equivalence map.** No source file edited (I.0-I.3 are read-only evidence). Expected touch set per brief (`sf/src/type_resolver.zig`, `sf/src/c89_emit.zig`, `sf/docs/tech_docs/`) was **not** reached; note additionally that any rewiring would also touch `sf/src/main.zig` (the classification's consumer plumbing `:574-576/:1372-1373/:1551`) — outside the brief's stated touch set, a second sign the assumed shape is stale.

**Operator decision required (nothing chosen, nothing implemented):** e.g. (X) amend the plan to authorize extending/re-timing the classification (new outputs for needs-definition + shared placement, plus an emission-time refinement for needed tuples), or (Y) amend the plan text to a relocation shape that names those outputs. Either is a plan-text change; the implementer will not improvise it.

---

## Implement

Not reached — blocked at Investigate (I.3). No source edit, no tech-docs edit, no compiler-moving commit.

## Runtime battery

Not run — no source change; the tree at `b33ae234` and the Task-0 frozen anchors are untouched (`git status` at report time: only pre-existing dirty `progress.md` ledger + untracked `run.err` root stray, both not ours).

---

## Observations (report-only; not fixed, per no-unrelated-fixes)

- **O1:** the `skip_arb` arm (`shouldSkipTypeEmission:1188-1190`) is unreachable-equivalent today: named arb_int/arb_uint types exist (`registerPrimitiveName` sets `name_id`, `type_registry.zig:1101-1108/:1152`) but no `computeSharedSet` seed covers the arb kinds and the closure promotes only aggregate kinds (`:1155-1159`) — so arb types are never in `shared_set` and the shared-header passes filter them at `:1262`/`:1275` before the skip call, while the single-file passes call with `skip_arb=0` (emit). The mode-dependent difference never fires; the shared-vs-single emission difference for arb comes from the `require_shared` filter, not the skip rule. Recorded as evidence for the map, not a defect fix.
- **O2:** P3 deferred residue (dead `TU_` composition `c89_emit.zig:~1603-1615`, `getUnsignedCTypeName` literal duplication) untouched, as directed.
- **O3:** `computeSharedSet`'s `is_clsv` (E2) is the only literal overlap between the emitter functions and the resolver classification — the overlap the spec's category-4 name suggests — but it is already a consumption of `pointer_only_map`, not a duplicate computation. The other named overlaps (skip list ↔ synthetic-kind list) are duplication **between the two emitter functions**, not with the resolver.
