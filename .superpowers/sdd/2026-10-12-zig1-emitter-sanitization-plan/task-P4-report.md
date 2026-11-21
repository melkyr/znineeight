# P4 report — Single classification pass (execution order 5/10 per Task 0)

**Status:** DONE (battery all green; pins 0/8; corpus 0 movers). Round 1 STOPPED at Investigate (equivalence-map gaps filed below, kept verbatim as the record); operator RULING 2026-10-13 chose **option (a) — Extend + re-time**, and the resumed round implemented it (§ "Operator ruling" onward). One in-flight defect found and fixed during implementation (registration-timing gap — see I.5).
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

## Operator ruling (2026-10-13) — option (a) Extend + re-time (BINDING)

The controller relayed the operator's ruling: the STOP was correct and is recorded; P4 resumes under this amendment:

1. Grow `classifyTypeEmissionGroups` to carry ALL 11 decisions of the I.2 map — pointer-only + shared-set seeds (synthetic/carrier64/named-fn/typeRefs-closure) + skip decisions (void/bool/…/unnamed-non-special). The spec §4 "Type classification" row is amended accordingly (**recorded in `sf/docs/tech_docs/03_type_resolution.md` + `08_c89_emission.md` header notes and here**; closeout will note it).
2. B1 needed-tuple seed: re-time `collectNeededTuples` earlier, OR defer to a second step of the SAME resolver-owned mechanism (a resolver function the emitter calls at the point the data exists) — implementer picks the smaller-risk variant and documents why.
3. `computeSharedSet` + `shouldSkipTypeEmission` DELETED (no dead copies); the emitter CONSUMES the resolver mechanism; `main.zig` authorized in-touch-set for classification plumbing ONLY.
4. Everything else in the brief stands. Commits: (a) `refactor(type_resolver): P4 — single classification pass` (sf/src/** + sf/docs/tech_docs/**), (b) `docs(sdd): P4 report`.

### B1 variant chosen: SECOND STEP (amendment variant 2), not re-timing

Variant 1 (re-time `collectNeededTuples` earlier) is **infeasible without a semantic change**: the set is derived from LIR hoisted temps + global decls (`collectNeededTuples` walks `ts_fn.hoisted_temps` / `ctx.global_decls`), which only exist after `phase_LIRLowering` — six phases after `phase_TypeResolution` where the classification runs. Moving the collection earlier would have to approximate the set from pre-LIR state (e.g. all tuple types), which changes which tuples get typedefs (the comment at `collectNeededTuples` pins the exact membership: "registry-only print-args tuples must not produce C"). Variant 2 (second step of the same mechanism, called where the data exists) preserves the exact input. **Cost if wrong:** none identified — variant 2 is what the amendment describes verbatim.

### I.5 Registration-timing discovery (in-flight defect found + fixed during implementation)

The first option-(a) build (strict snapshot whitelists for `needs_def`/`shared`) compiled and self-hosted but emitted **broken C**: a minimal repro (`fn use() void { var parts: [3][]u8 = undefined; ... }`) lost both typedefs (`Arr_…Sli` / `Slice_…_u`), and hop1's self-emission dropped 423/465 `ZIG_ARRAY_*` guard blocks. Root cause (evidence chain kept in the session; key commands below):

- **Types are registered AFTER `phase_TypeResolution`.** `front_resolution`/sema/lowering call `typeRegistryGetOrCreate*` (`sf/src/lower.zig:2159/:2218/:2324/:2506/:4247/:6166` … — `typeRegistryGetOrCreatePtr`/`Array`/`Optional` during LIR lowering). Any type born after the classification snapshot was missing from the strict `needs_def`/`shared` whitelists → skipped by both pass filters → never emitted (while still used in bodies → gcc `unknown type name`).
- **Why the pre-P4 code never showed this:** `shouldSkipTypeEmission` and `computeSharedSet` evaluated their rules **LIVE at emission**, and `pointer_only_map` has always been a *snapshot* whose ABSENCE means value-embedding/shared (`is_clsv = pointer_only_map miss`) — the historical fallthrough covered post-snapshot types automatically.
- **Minimal repro evidence** (seed compiler = pre-P4 semantics vs the first P4 build vs the fixed build):
  - pre-P4 (`_unpack/zig1-seed/zig1 -ffast --dump-c89 main.zig`): `typedef … zT_8F083A69_Slice_zT_0B42B2F8_u;` + `typedef … zT_4C214FEE_Arr_zT_8F083A69_Sli[3];` present.
  - first P4 build: both absent (only the i64/u64/f64 carriers emitted).
  - fixed P4 build: `diff out_old.c out_fix.c` → **IDENTICAL**.

**Fix (still amendment-shaped):** step 2 became `classifyTypeEmissionFinalize(reg, shared, po, nd, needed)` — the SAME resolver-owned mechanism's second step, called by the emitter from `emitTypePasses` (the point where `needed_tuple_set` is complete AND the registry is final): it re-applies the same rule helpers (idempotent) over the current registry — `classificationNeedsDef` → `needs_def`; the shared seeds with **`is_clsv = po MAP MEMBERSHIP`** (preserving the snapshot fallthrough exactly) + the E4 needed-tuple seed; then `classificationSharedClosure`. One copy of each rule; step 1 computes the groups for the snapshot (the amendment's "carry ALL 11"), step 2 completes them where the data exists. `pointer_only` deliberately stays the step-1 snapshot (a type registered later must remain value-embedding for byte-identical 2a/2b placement — the old `pointer_only_map` had exactly this semantics).

## Implement (one compiler-moving commit)

Source edits via `edit`/`fastedit` only (X.7; `fastedit` crashed once on the `return ClassificationResult{…}` line — `undefined is not an object (evaluating 'code.matchAll')` — chunked `edit` used per P3 precedent; one anchor-line typo `*[*]u32` → `[*][*]u32` on `growWpEdges` was introduced and immediately fixed before any build).

**`sf/src/type_resolver.zig`** (the classification, now the single mechanism):
- `ClassificationResult` (`:171`): `ids/len` → three maps `pointer_only` / `needs_def` / `shared` (`hash_mod.U32ToU32Map`).
- `classifyTypeEmissionGroups` (`:640`): PO algorithm + CLS markers **verbatim**; the old ids-collection loop is replaced by the group-map build (E1 po map + count `plen`; E8/E9/E11 via `classificationNeedsDef`; E2/E3'/E5/E6 shared seeds) + `classificationSharedClosure`; returns the three maps.
- New helpers (single copy of each rule): `classificationIsSyntheticEmittable` (the 8-kind list that lived twice in the deleted emitter functions), `classificationNeedsDef` (positive complement of `shouldSkipTypeEmission`'s E8/E9/E11; E10 `skip_arb` intentionally absent — unreachable-equivalent, O1), `classificationSharedClosure` (verbatim map-based port of `computeSharedSet`'s E7 closure, probes `typeRefsContains`), `pub classifyTypeEmissionFinalize` (step 2 — see I.5).
- `hash_mod` import: the file already had one (`:23`) — no new import (a duplicate I added was removed).

**`sf/src/c89_emit.zig`** (pure consumption):
- **DELETED:** `computeSharedSet` (was `:1106-1172`), `shouldSkipTypeEmission` (was `:1179-1205`), the D6-1 comment, the `skip_arb` local (0 remaining references — grep-verified).
- `C89Emitter` gains `needs_def_map: U32ToU32Map` (`:584`); `c89EmitterInit` takes `pointer_only_map, needs_def_map, shared_map` by value (the `pointer_only_len` hint param is gone; the maps are allocated by the classification).
- `emitTypePasses` (`:1122`): opens with `type_resolver.classifyTypeEmissionFinalize(reg, &emitter.shared_set, &emitter.pointer_only_map, &emitter.needs_def_map, &emitter.needed_tuple_set)`; the two `shouldSkipTypeEmission` call sites become `if (u32ToU32MapGet(&emitter.needs_def_map, tid) == null) continue;` at the **same filter positions** (2a after the po/shared checks, 2b after the d2 block).
- `emitSharedHeader`: the `computeSharedSet` call is gone (finalize lives in `emitTypePasses`, which both pass paths run).
- `emitModule`: signature drops `ptr_only_ids/ptr_only_len`; the id→map fill loop is deleted (maps arrive pre-loaded).

**`sf/src/main.zig`** (classification plumbing ONLY, per amendment 3):
- `CompilerContext.pointer_only_ids/pointer_only_len` → `cls: type_resolver.ClassificationResult` (placeholder local `cls_init` — Z98: struct fields cannot init to `undefined`; the first build failed `incompatible types … from type 'int'` at that line and the Init-pattern local fixed it).
- `phase_TypeResolution` stores `ctx.cls = ptr_grp`; `phase_C89Emission` passes `ctx.cls.pointer_only/needs_def/shared` to `c89EmitterInit`; both old fill loops deleted; `emitModule` call updated; `mangler_hint` reads `ctx.cls.pointer_only.count`.

**`sf/src/type_registry.zig`** (comment-only): the P2 relation doc-comment's `computeSharedSet` mention now names the P4 classification closure.

**`sf/docs/tech_docs/`**: `03_type_resolution.md`, `08_c89_emission.md`, `09_pipeline_orchestration.md`, `INDEX.md` updated (signatures, data flow, fn tables, `[updated: 2026-10-12 — P4 …]` notes) — including the **spec §4 "Type classification" row amendment** record (row's `pointer-only / value-embeds / needs-definition` → the three emission groups `pointer_only` / `needs_def` / `shared`, value-embeds = pointer-only complement; closeout will note it).

## Runtime battery (FULL; every claim = command + observed output)

Final binary `/tmp/opencode_p4/s4/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/opencode_p4/s4` (repo root).

### 1. Seed rebuild + two-hop closure

```
[seed] hop1 binary md5: fd6c32cb3039cbf26f76a6372a3e3c32
[seed] hop2 binary md5: fd6c32cb3039cbf26f76a6372a3e3c32
[seed] two-hop closure OK: hop1 == hop2 == fd6c32cb3039cbf26f76a6372a3e3c32
=== [seed] Done: /tmp/opencode_p4/s4 ===
```
Fixed point `25f246289f655f1692657da5cdf124a7` → **`fd6c32cb3039cbf26f76a6372a3e3c32`** (moved — expected: `sf/src` changed; hop1==hop2 proven). Seed NOT rotated (closeout-only).

### 2. Corpus classify (vs frozen Appendix A)

```
$ bash scripts/corpus/classify /tmp/opencode_p4/s4/zig1_5_clean /tmp/opencode_p4/corpus_p4.txt
wrote /tmp/opencode_p4/corpus_p4.txt: 1124 dirs
$ md5sum /tmp/opencode_p4/corpus_p4.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/opencode_p4/corpus_p4.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff /tmp/task0_work/corpus_baseline.txt /tmp/opencode_p4/corpus_p4.txt → rc=0, 0 lines
$ awk '{print $2}' … | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
```
**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical to frozen Appendix A. 0 class movers.**

### 3. Runtime goldens (5 md5s, byte-identical)

Build (Task 0 §1.3 recipe): `zig1_5_clean --dump-c89 <ENTRY> > gold/<n>.c` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include gold/<n>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o gold/<n>` — all 4: dump rc=0, gcc rc=0, 0 `error:` (gol 13924-line dump / lisp 19277 / json 15596 / mud 14789 — line counts match the P3 record).

| golden | command | observed md5 | frozen | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | YES |
| json | `cd examples/z98/json_parser && timeout 60 gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh gold/mud srv.out cli.out` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0ab…` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f…` | YES |

**5/5 byte-identical.**

### 4. mi_matrix runtime anchors (25 + oob)

Anchor set re-enumerated by the frozen definition (non-`stdlib_*` ∧ non-empty `expected.txt` ∧ `expected.rc=0`): `for d in repro/mi_matrix/*/; … | wc -l` → **25**. Harness: `bash scripts/stdlib/run_fixtures.sh /tmp/opencode_p4/s4/zig1_5_clean <the 25 dirs>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`** (incl. `slice_index_field_store_xmod`).

Trap fixture (`-fsafe`): `slice_index_field_store_oob_xmod` — dump rc=0, build rc=0, **run rc=133** (Trace/breakpoint trap), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` md5; `expected.rc` = `133`. **MATCH.**

### 5. `examples/z98/*/` matrix (26 build + 26 run)

Build per dir (`zig1_5_clean -ffast -o matrix/<n> <entry>` + `sh build_target.sh linux matrix/<n>/prog`, entry = `main.zig` → `<n>.zig` → first `*.zig`; output dir pre-created): **26/26 dump=0 / build=0**; per-dir `.c` counts identical to Task 0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38).

Run per dir (CWD = example dir, `timeout 25` except mud_server 8; stdin `/dev/null` except rogue* `q\n`): **26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table** — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json_parser(+upgraded) `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`.

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/opencode_p4/s4/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

### 7. The 8 `--dump-c89` pins (old → new; record only)

| entry | mode | old (P2 fix round 1 = P3, `25f24628…`) | P4 (`fd6c32cb…`) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical**, as the amendment's "byte-identical for currently-working programs" required. Command per row: `zig1_5_clean <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

### 8. `--markers` telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 marker lines / 38,378 B** — **identical counts to the P3 record** (P2/P3: 3,436 / 38,378). Prefix histogram: `INT:new` 2005, `DC:k` 423, `FE:p` 240, `P` 195, `FWD:n=` 195, `RaD` 122, `MT` 86, `FE:` 69, `X:` 17, `IRP:p/n/m` 17 — matches the P3 histogram. The CLS block is emitted verbatim (no marker deltas from P4 by design).

---

## Observations (report-only; not fixed, per no-unrelated-fixes)

- **O1:** the `skip_arb` arm (`shouldSkipTypeEmission:1188-1190`) is unreachable-equivalent today: named arb_int/arb_uint types exist (`registerPrimitiveName` sets `name_id`, `type_registry.zig:1101-1108/:1152`) but no `computeSharedSet` seed covers the arb kinds and the closure promotes only aggregate kinds (`:1155-1159`) — so arb types are never in `shared_set` and the shared-header passes filter them at `:1262`/`:1275` before the skip call, while the single-file passes call with `skip_arb=0` (emit). The mode-dependent difference never fires; the shared-vs-single emission difference for arb comes from the `require_shared` filter, not the skip rule. Recorded as evidence for the map, not a defect fix.
- **O2:** P3 deferred residue (dead `TU_` composition `c89_emit.zig:~1603-1615`, `getUnsignedCTypeName` literal duplication) untouched, as directed.
- **O3:** `computeSharedSet`'s `is_clsv` (E2) is the only literal overlap between the emitter functions and the resolver classification — the overlap the spec's category-4 name suggests — but it is already a consumption of `pointer_only_map`, not a duplicate computation. The other named overlaps (skip list ↔ synthetic-kind list) are duplication **between the two emitter functions**, not with the resolver.
- **O4 (in-flight defect, FIXED — see I.5):** the first option-(a) shape (strict snapshot whitelists) silently dropped typedefs for types registered after `phase_TypeResolution`; caught by a minimal repro before any commit; fixed by `classifyTypeEmissionFinalize`. The pre-P4 po-map snapshot fallthrough (absent = value-embedding) is preserved deliberately.
- **O5 (in-flight compile failure, fixed — disclosed):** Z98 cannot initialize a struct-typed ctx field to `undefined` in the `CompilerContext` literal (emits `= 0` for a struct → gcc `incompatible types`); fixed with the codebase's `var x: T = undefined;` placeholder-local pattern (`cls_init`). First build log: `main_9472B9CB.c:1436:18: error: incompatible types when assigning to type 'zT_010C8DF0_ClassificationResul' from type 'int'`.
- **O6 (tooling, disclosed):** `fastedit` crashed once (`undefined is not an object (evaluating 'code.matchAll')`) — chunked `edit` used (P3 precedent); one anchor-line transcription typo (`*[*]u32` → `[*][*]u32` on `growWpEdges`) was caught in the diff preview and fixed immediately (no build ever ran on it).
- **O7 (pre-existing, report-only):** named tuple types get no typedef in the multi-file path (no shared seed covers `name_id != 0` tuples and `emitModuleHeaderFile` handles only {struct,tu,union,pu,enum,es}); they are emitted only in the single-file path (2a). Unchanged by P4 (membership-preserving), noted for the whole-branch review.
- **O8 (context):** the v97 committed seed's self-emission dump of the current `sf/src` differs from the P4 compiler's dump in typedef placement/ordering (e.g. named enums like `ErrorCode` land in the shared header vs module headers) — that is the ACCUMULATED P1–P4 emission evolution vs the pre-milestone seed, not a P4 delta; the P4 gate surfaces (8 example pins 0/8, corpus byte-identical, goldens 5/5, hop1==hop2) are clean.

---

## P4 fix round 2 — placement correction (Decision-vs-spelling)

**Status:** DONE (battery all green; pins 0/8; corpus 0 movers; markers byte-identical). Operator ruling 2026-10-12: the landed P4 shape (emitter-invoked `classifyTypeEmissionFinalize` at `c89_emit.zig:1140`, result maps on `C89Emitter`, `collectNeededTuples` in `c89_emit.zig`) is a **Decision-vs-spelling deviation** — "a helper invoked at emit time whose output selects between semantics is FORBIDDEN; its decision must be recorded at its owning phase." This round corrects PLACEMENT only; zero decision-logic change (every rule body verbatim; I.2 map E1–E11 outputs identical — proven by pins 0/8 + corpus byte-identical).

### Target shape (controller-approved; plan P4 fix round 2, `task-P4r2-brief.md`)

1. New backend-neutral phase `phase_EmissionClassification(ctx)` in `sf/src/main.zig`, between `phase_LIRLowering` and `phase_C89Emission` — classification completes here, BEFORE any backend runs.
2. `type_resolver.EmissionClassification{ shared_set, pointer_only_map, needs_def_map, needed_tuple_set }` (plain Z98; the brief's exact fields) on `CompilerContext`, maps on the permanent arena. `C89Emitter` holds `classif: *EmissionClassification` — READS only.
3. `classifyTypeEmissionFinalize` invocation moves OUT of `emitTypePasses` into the boundary step. `emitTypePasses` retains ZERO classification calls.
4. `collectNeededTuples` moves to `sf/src/type_resolver.zig` (verbatim); its two call loops (formerly `main.zig:1251/:1347`, mid-`phase_C89Emission`) run in the boundary step over the same sources (`LirFunction.hoisted_temps` via `ctx.lir_stream`/`ctx.lir_slots`, and `ctx.global_decls`) — no emitter data needed.
5. The late-type "snapshot whitelist" workaround (the P4 in-flight emit-time patch, I.5) is deleted: the finalize walks the FULL registry at the boundary where all types exist.
6. Placement change only — zero decision-logic change; pins 0/8 expected.

### Design decisions (Investigate, read-only before edits)

- **Placement-only reading (points 3+5+6).** `classifyTypeEmissionGroups` stays at `phase_TypeResolution` with its rules VERBATIM (the E1 po snapshot is the recorded decision: "a type absent from `po` counts as value-embedding"; recomputing po at the boundary would flip late types ve→po and move 2a/2b placement — NOT decision-identical, so po stays resolution-time per the amended plan's "`classifyTypeEmissionGroups` (resolution-time) plus `classifyTypeEmissionFinalize` completed at … boundary"). The finalize body is verbatim (same nd/sh/tuple/closure rules). What is DELETED is the emit-time invocation — the in-flight late-type patch — and its "re-application at emit time" framing; the boundary walk replaces it (the I.5 workaround narrative dies with the emit-time call).
- **B1/needed-tuple placement (unchanged decision):** `needed_tuple_set` is collected at the boundary from LIR/ctx — the same inputs and the same `collectNeededTuples` code as the former mid-emission loops. The finalize sees the complete set exactly as the old emit-time finalize did.
- **Why the boundary walk is decision-identical to the old emit-time walk:** the registry is frozen between the boundary and the old finalize point (`emitTypePasses` top) — `phase_C89Emission`'s preamble (`c89EmitterInit`, `errorCodeRegistryFinalize`, the reachability walk `pruneTypeMarkByValue` — pure walk, no registrations — and the globals loop) registers nothing; emission-time `typeRegistryGetOrCreatePtr` sites (`c89_emit.zig:2632`, the P6 getTemp re-derivation) fire after BOTH old and new finalize points and produce only unnamed ptr types (needs_def=false → never emitted). The nd/sh/closure rules are pure functions of registry state + po-map membership + needed_tuple_set → identical maps.
- **`is_clsv = po MAP MEMBERSHIP`** (absent = clsv) stays verbatim — it IS the E2 decision given E1's snapshot semantics (not a workaround).
- **No phase marker** on `phase_EmissionClassification` — keeps the `--markers` stream byte-identical (placement-only; documented in the fn comment).

### Implement (per file)

**`sf/src/type_resolver.zig`:**
- `ClassificationResult` → `EmissionClassification{ shared_set, pointer_only_map, needs_def_map, needed_tuple_set }` (the brief's exact shape; home = the classification owner).
- `classifyTypeEmissionGroups(self, classif: *EmissionClassification, perm_alloc) void` — body verbatim (PO algorithm + CLS markers + group maps + closure); the return becomes three field assignments into `classif`.
- `classifyTypeEmissionFinalize(reg, classif: *EmissionClassification) void` — body verbatim (local aliases `shared/po/nd/needed` over the struct maps); comment reframed (boundary completion; the emit-time patch deleted).
- `collectNeededTuples(reg, set, tid)` — verbatim move from `c89_emit.zig:5659` (P4's version).

**`sf/src/c89_emit.zig`:**
- `C89Emitter`: the four map fields (`pointer_only_map`/`needs_def_map`/`shared_set`/`needed_tuple_set`) → `classif: *type_resolver.EmissionClassification` (reads only).
- `c89EmitterInit`: the three map parameters + the internal `needed_tuple_set` init → the single `classif` pointer.
- All 11 map reads rewired `emitter.classif.*` (2a/2b filters `:1170-:1195`, `emitModuleHeaderFile:2207-2208`, `emitNeededTupleRec/Types/At`).
- **DELETED:** the `type_resolver.classifyTypeEmissionFinalize(...)` call at `emitTypePasses` (was `:1140`) + its comment — `emitTypePasses` now has ZERO classification calls.
- **DELETED:** `collectNeededTuples` (moved to `type_resolver.zig`).

**`sf/src/main.zig`:**
- `CompilerContext.cls: ClassificationResult` → `emission_classif: type_resolver.EmissionClassification` (4 maps init'd on `&compiler_alloc.permanent`).
- NEW `phase_EmissionClassification(ctx)` (between `phase_LIRLowering` and `phase_C89Emission`; `runCompiler` call inserted): `lirStreamBeginRead` → per-slot `lirStreamReadFunction(…, &ctx.alloc.lir_read)` → `collectNeededTuples` per hoisted temp → `lirStreamEndRead`; then `collectNeededTuples` per `ctx.global_decls` entry; then `classifyTypeEmissionFinalize(ctx.typereg, &ctx.emission_classif)`. (BeginRead/EndRead pair is safe in both spill backends: ram `spillClose` only clears `opened`, disk closes/reopens.)
- `phase_TypeResolution`: `classifyTypeEmissionGroups(&tr, &ctx.emission_classif, &ctx.alloc.permanent)` (the `ptr_grp` plumbing gone).
- `phase_C89Emission`: the two `collectNeededTuples` calls removed (their loops keep the reachability duties); `c89EmitterInit(…, &ctx.emission_classif, …)`; `mangler_hint` reads `ctx.emission_classif.pointer_only_map.count`.

**`sf/docs/tech_docs/`:** `03_type_resolution.md`, `08_c89_emission.md`, `09_pipeline_orchestration.md`, `INDEX.md` updated (`[updated: 2026-10-12 — P4 fix round 2 …]` notes; `EmissionClassification` rows; the 11-phase flow; `collectNeededTuples` → `type_resolver.zig` in INDEX Table B).

### Evidence (command + observed output per claim)

**1. The moved call — `emitTypePasses` retains ZERO classification calls:**
```
$ grep -rn "classifyTypeEmission\|collectNeededTuples" sf/src/c89_emit.zig
(no output)
$ grep -rn "classifyTypeEmissionFinalize" sf/src/*.zig
sf/src/main.zig:1227:    type_resolver.classifyTypeEmissionFinalize(ctx.typereg, &ctx.emission_classif);
sf/src/type_resolver.zig:1006:pub fn classifyTypeEmissionFinalize(...)
```
The only invocation is `phase_EmissionClassification` (main.zig:1227) — the emitter never calls it.

**2. The boundary phase** (`sf/src/main.zig:1198-1228`): `phase_EmissionClassification` — `collectNeededTuples` loops (LIR hoisted temps + `ctx.global_decls`) + `classifyTypeEmissionFinalize`; called from `runCompiler` between `phase_LIRLowering` and `phase_C89Emission` (`main.zig:410`).

**3. The snapshot-workaround deletion:** the emit-time finalize call + comment (P4's "Re-applies … at emission (step 2 …)" block) is deleted from `c89_emit.zig` (grep above: 0 hits in `c89_emit.zig`); the finalize body walks `0..reg.types_len` at the boundary (full registry) — `type_resolver.zig:1006`. `emitTypePasses` (`c89_emit.zig:1107+`) contains only the po/shared/needs_def map filters.

**4. Decision-equivalence spot-checks:** the I.2 rules are verbatim (`classificationNeedsDef`/`classificationIsSyntheticEmittable`/`classificationSharedClosure` untouched; `collectNeededTuples` body byte-move; the finalize body = local aliases + unchanged loop). The decisive checks are the gates: **pins 0/8** (below) — emitted C byte-identical for the 4 pin programs (8 dumps) — and the **corpus classify class file byte-identical** (the `corpus_p4.txt` per-dir FAIL/GREEN/OK strings, md5 `518eca1a…` = the frozen Appendix A baseline; the corpus gate compares the class file, NOT emitted C). (Fix round 1: this sentence previously claimed the corpus gate proved emitted-C byte-identity — it does not; C byte-identity is evidenced by the 8 pins + goldens only.)

**5. Emitter reads only:** `grep -c "emitter.classif\." sf/src/c89_emit.zig` → `11`; `grep -n "emitter\.pointer_only_map\|emitter\.shared_set\|emitter\.needs_def_map\|emitter\.needed_tuple_set" sf/src/c89_emit.zig` → 0 hits.

### Runtime battery (FULL; every claim = command + observed output)

Final binary `/tmp/opencode_p4/r2a/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/opencode_p4/r2a` (repo root).

**1. Seed rebuild + two-hop closure:**
```
[seed] hop1 binary md5: 9ced323b892fa3e1bc4eb0b1598a416a
[seed] hop2 binary md5: 9ced323b892fa3e1bc4eb0b1598a416a
[seed] two-hop closure OK: hop1 == hop2 == 9ced323b892fa3e1bc4eb0b1598a416a
=== [seed] Done: /tmp/opencode_p4/r2a ===
```
Fixed point `fd6c32cb3039cbf26f76a6372a3e3c32` → **`9ced323b892fa3e1bc4eb0b1598a416a`** (moved — `sf/src` changed; hop1==hop2 proven). Seed NOT rotated.

**2. Corpus classify (vs frozen Appendix A):**
```
$ bash scripts/corpus/classify /tmp/opencode_p4/r2a/zig1_5_clean /tmp/opencode_p4/corpus_r2.txt
wrote /tmp/opencode_p4/corpus_r2.txt: 1124 dirs
$ md5sum /tmp/opencode_p4/corpus_r2.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/opencode_p4/corpus_r2.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff → rc=0, 0 lines
```
**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical. 0 class movers.**

**3. Runtime goldens (5/5 byte-identical):** builds 13924/19277/15596/14789 lines, 0 gcc errors; gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `b3d9f8974da24ddbf9d389f3d7d97322`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud session rc=0 server `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7` — all match the frozen values.

**4. mi_matrix anchors (25 + oob):** `run_fixtures.sh /tmp/opencode_p4/r2a/zig1_5_clean <25 dirs>` → `run_fixtures: 25 PASS / 0 FAIL over 25 dirs`; oob trap `slice_index_field_store_oob_xmod` — dump/build rc=0, run **rc=133**, stdout 0 bytes md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` (`expected.rc`=133). **MATCH.**

**5. `examples/z98/*/` matrix:** build **26/26** (dump=0, build=0; `.c` counts identical to §1.4: 7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38); run **26/26** rc + stdout md5_16 identical to the §1.4 table (same 26 values as the P4 round).

**6. Stdlib gate:** `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK`.

**7. The 8 `--dump-c89` pins (old = P2-fix-round-1/P3/P4 values → new):**

| entry | mode | old | P4 fix round 2 | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8.** Command per row: `zig1_5_clean <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

**8. `--markers` telemetry:** `zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig` — stderr **3,436 marker lines / 38,378 B — byte-identical counts to the P4/P3 record** (no new phase marker by design); prefix histogram identical (`INT:new` 2005, `DC:k` 423, `FE:p` 240, `P` 195, `FWD:n=` 195, `RaD` 122, `MT` 86, `FE:` 69).

### Observations (report-only)

- **O9:** `phase_EmissionClassification` deliberately emits no phase marker (the `T\n`/`C\n` convention) — a marker would move the `--markers` stream (+1 line); placement-only wins. If telemetry visibility of the boundary is wanted later, add it as a telemetry-only change.
- **O10:** the two `collectNeededTuples` call loops now walk the LIR a second time (the boundary walk is separate from `phase_C89Emission`'s reachability walk) — `lirStreamReadFunction` resets its dst arena per call, so no growth concern; measured marker/telemetry and memory gates unchanged.
- O1–O8 above stand unchanged.

---

## Fix round 1 (review items) — docs/comment truth-up only

**Status:** DONE — 7/7 items fixed (1 Important + 6 Minors). Zero behavior change: the only source touch is ONE comment line in `sf/src/type_registry.zig` (per contract); everything else is `task-P4-report.md` + `sf/docs/tech_docs/*.md`. Deferred per contract (NOT addressed): step-1 nd/sh seed loop dead-work cleanup; `phase_EmissionClassification` running when emission is skipped.

### Important — report overclaims corpus evidence (fixed)

`task-P4-report.md` §P4-fix-round-2 evidence item 4 claimed "corpus byte-identical — the emitted C for every corpus dir and the 4 pin programs is bit-for-bit the P2/P3/P4-recorded output". FALSE for the corpus half: the corpus gate compares the classify CLASS FILE (per-dir FAIL/GREEN/OK strings), not emitted C. Corrected text now reads: "**pins 0/8** (below) — emitted C byte-identical for the 4 pin programs (8 dumps) — and the **corpus classify class file byte-identical** (the `corpus_p4.txt` per-dir FAIL/GREEN/OK strings, md5 `518eca1a…` = the frozen Appendix A baseline; the corpus gate compares the class file, NOT emitted C)". Verification:
```
$ grep -c "the emitted C for every corpus dir" .superpowers/sdd/.../task-P4-report.md
0
$ grep -n "corpus classify class file byte-identical" .superpowers/sdd/.../task-P4-report.md
297:…the **corpus classify class file byte-identical** (the `corpus_p4.txt` per-dir FAIL/GREEN/OK strings, md5 `518eca1a…` = the frozen Appendix A baseline; the corpus gate compares the class file, NOT emitted C)…
```
The decision-identity case itself stands (pins 0/8 = emitted-C byte-identity for the 8 dumps; goldens 5/5 = runtime byte-identity; corpus class file = no class movers).

### Minors (folded in)

1. **`sf/src/type_registry.zig:1244` comment named nonexistent `classifyTypeEmissionSharedTuples`** (that name was renamed away in the P4 landing; the real closure is `classificationSharedClosure`, `type_resolver.zig:941` — the review cited `:922`, pre-P4r2-edit line). Comment now reads "`classificationSharedClosure` in `type_resolver.zig`". Verification:
```
$ grep -n "classificationSharedClosure\|classifyTypeEmissionSharedTuples" sf/src/type_registry.zig
1244:// `classificationSharedClosure` in `type_resolver.zig`). It
```
(one hit — the dead name is gone).

2. **`08_c89_emission.md` §1.1 stale prose** — "`emitModule` receives a `ptr_only_ids` array from the caller (calculated in `phase_C89Emission` in `main.zig`)": the parameter is deleted (`emitModule(emitter, name, c_includes)`, `c89_emit.zig:2272`) and the group was always computed in `phase_TypeResolution`. Reworded to point at `classif.pointer_only_map` and note the parameter is long deleted. The same stale signature also sat in §1.10 (`emitModule(emitter, name, c_includes, ptr_only_ids, ptr_only_len)` — one line above its already-updated call block); corrected there too (same finding class). Verification:
```
$ grep -n "ptr_only_ids" sf/docs/tech_docs/08_c89_emission.md
1:…(the former `ptr_only_ids`/`pointer_only_len` args and both id→map fill loops are deleted)…   ← historical [updated:] entry
82:(**P4 fix round 2**; the `ptr_only_ids` parameter is long deleted))…
676:`emitModule(emitter, name, c_includes)` (P4 fix round 2: the `ptr_only_ids`/`ptr_only_len`
```
(only the historical changelog entry + the two "long deleted" clarifications remain; the live signature is the 3-arg form.)

3. **`08_c89_emission.md` §1.18 stale** — tuples "collected in `phase_C89Emission` by `collectNeededTuples`". Now: "collected at the pre-emit `phase_EmissionClassification` boundary by `type_resolver.collectNeededTuples` — P4 fix round 2 (was mid-`phase_C89Emission`)". Verification: `grep -n "collected in .phase_C89Emission" sf/docs/tech_docs/08_c89_emission.md` → 0 live hits (the phrase is gone).

4. **`09_pipeline_orchestration.md` `cls` leftovers** — the phase-outputs flow diagram (`phase_TypeResolution → … cls`), the producers/consumers table row, and the debug note ("skipping TypeResolution means `cls` stays undefined") all said the round-0 name. All three now say `emission_classif` (the flow row also credits the completion at `phase_EmissionClassification`; the debug note says "stays unfilled (empty maps)" — the maps are init'd at ctx construction and filled later). Verification:
```
$ grep -on "ctx\.cls\|\`cls\`\| cls \|cls (" sf/docs/tech_docs/09_pipeline_orchestration.md
1:ctx.cls
$ grep -c "emission_classif" sf/docs/tech_docs/09_pipeline_orchestration.md
6
```
The single remaining `ctx.cls` is inside the dated P4 `[updated:]` changelog entry on line 1 (period-accurate history, consistent with the chain's convention of naming things as they were — the same entry also names the since-replaced `ClassificationResult`); every live surface is consistent.

5. **`INDEX.md` missing helper rows** — added `classificationIsSyntheticEmittable` / `classificationNeedsDef` / `classificationSharedClosure` → `type_resolver.zig`, alphabetically before `classifyCoercion` (peers `growWpEdges:547`/`fieldEmbedsByValue:502` were already indexed). Verification:
```
$ grep -n "classificationIsSyntheticEmittable\|classificationNeedsDef\|classificationSharedClosure" sf/docs/tech_docs/INDEX.md
251:| `classificationIsSyntheticEmittable` | type_resolver.zig |
252:| `classificationNeedsDef` | type_resolver.zig |
253:| `classificationSharedClosure` | type_resolver.zig |
```

6. **`03_type_resolution.md` `EmissionClassification` row used short names** (`pointer_only`/`needs_def`/`shared`) vs the actual struct fields — now lists the real fields `shared_set`, `pointer_only_map`, `needs_def_map`, `needed_tuple_set`. Verification: `grep -n "actual fields" sf/docs/tech_docs/03_type_resolution.md` → `275: … — actual fields: `shared_set`, `pointer_only_map` …, `needs_def_map` …, `needed_tuple_set` (E4 seed). …`.

### Re-verification (docs-only delta)

- `git diff --stat` for this round: `task-P4-report.md`, `sf/docs/tech_docs/{03,08,09,INDEX}.md`, and a 2-line comment block in `sf/src/type_registry.zig` — no code statements touched (`git diff sf/src/type_registry.zig` = comment lines only).
- Runtime battery unchanged from the P4 fix round 2 run (no code change; the previous binary `/tmp/opencode_p4/r2a/zig1_5_clean` evidence stands: pins 0/8, corpus class file `518eca1a…`, goldens 5/5, mi 25+oob, examples 26/26+26/26, stdlib 285/0, hop1==hop2 `9ced323b…`). The seed build is not re-run for a comment/docs delta — zero statement changes (the one source edit is `//`-line content).
