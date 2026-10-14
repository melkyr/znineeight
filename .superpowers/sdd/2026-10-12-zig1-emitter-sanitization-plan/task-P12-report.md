# P12 report — Typedef ordering planned at the pre-emit boundary

Task: P12 (operator ruling 2026-10-12) — compute the typedef emission order ONCE at the
backend-neutral `phase_EmissionClassification`/`c89_plan` boundary and carry it; the emitter
walks the carried order and never sorts. Branch `zig1_improvements`, repo root.
Fixed point at start: `39bcb30b45df93631f9fc745f95dc1aa` (= P6-pre closeout value).

## Investigate

### I.1 Census — today's typedef-order machinery (all sites, current line numbers)

**The sort** — `tstTopologicalSort(reg, alloc) [*]u32`, `sf/src/c89_emit.zig:876-936` (comment
block `:868-875`): Kahn's algorithm over the P2 single type-reference relation
(`type_registry.typeRefs` for indegree, `typeRefsContains` for decrements) + the P2 fix-round-1
`popped` bitmap + ascending-tid cycle-residue append (every `types_len` tid appears in `result`
exactly once; no garbage tail). It `sandAlloc`s five buffers from the caller's arena in this
fixed order: `indegree` (4·tl) | `edge_buf` (4·tl) | `result` (4·tl) | `queue` (4·tl) |
`popped` (1·tl). `sandAlloc` (`sf/src/allocator.zig:43`) is an align-N bump: `result` is
immediately followed by `queue`, so a read `result[tl + k]` lands on `queue[k]` in ANY arena.
Returns `result`. Pure function of (registry contents, `types_len`); deterministic.

**The two call sites** (both at EMIT time; mutually exclusive per compilation):

| # | site | path | alloc | consumers |
|---|---|---|---|---|
| A | `c89_emit.zig:2295` (in `emitModule`) | single-file (`--dump-c89`, no `--output-dir`) | `emitter.alloc` = `ctx.alloc.scratch` | `emitSpecialTypes` only (`:2297`) |
| B | `main.zig:1429` (in `phase_C89Emission`) | multi-file (`--output-dir`/`-o` branch) | `&ctx.alloc.emission` | `emitSharedHeader` (`main.zig:1449`) + per-module `emitModuleHeaderFile` (`main.zig:1565`) |

Path exclusivity: `phase_C89Emission`'s `if (ctx.cli.output_dir_set) { … }` block ends in
`return` (`main.zig:~1597`) before the single-file tail (`emitIncludes` +
`cincludeUnionAll` + `emitModule`), so a compilation executes exactly ONE of A/B. The plan's
"double sort" = two duplicated decision sites in the code, never two executions.

**Order-array consumers** (all read `sorted[tsi]` with `tsi` bounded on LIVE `types_len`):
- `emitTypePasses` (`c89_emit.zig:1125`): three loops `:1144` (pass-1 forward typedefs),
  `:1168` (2a pointer-only), `:1181` (2b value-embedding) — `while (tsi < reg.types_len)`.
- `emitModuleHeaderFile` typedef walk (`c89_emit.zig:2199-2204`) — `while (tsi < emitter.registry.types_len)`.
Not a consumer: `emitGlobalExternDecls`'s `ts_ref_set` loop (`:2119`) walks tids DIRECTLY
(`tsgi` IS the tid, live-bounded) — unchanged by P12.

`tstEdgesWalk`/`tstSeenInRange`/`tstEdgesCount`/`tstEdgesFill`/`tstIsDep`/`c89NeedsEmitEdge`:
already DELETED at P2 (0 remaining callers). `tstTopologicalSort` is the only sort left.

### I.2 Two-call-site registry-state analysis (the STOP-gate question)

Pipeline order (`main.zig:395-431`): … `phase_LIRLowering` (`:815`) → `phase_EmissionClassification`
(`:1222`, called `:430`) → `phase_C89Emission` (`:1247`, called `:431`).

Full census of every registry-mutating call in `sf/src` (`typeRegistryGetOrCreate*` /
`RegisterNamedType` / `RegisterPrimitives` / `SetPacked` / `ComputePacked*Layout` /
`MarkFnPtrUsed` / `CNameIdSet`), by file:

| file | mutating calls | when they run |
|---|---|---|
| `symbol_registrator.zig` | 8 | `phase_SymbolRegistration` |
| `type_resolver.zig` | 17 | `phase_TypeResolution` (type-expr resolution / layout: `:1716` RegisterNamedType, `:1947/:2011/:2084-2087/:2104-2117` GetOrCreate*) |
| `semantic_analyzer.zig` | 28 | `phase_SemanticAnalysis` |
| `lower.zig` | 33 | `phase_LIRLowering` |
| `async_state_machine.zig` | 21 | `phase_LIRLowering` (step synthesis) |
| `async_analysis.zig` / `async_frame_layout.zig` | 1 / 1 | `phase_AsyncFrameSize` / lowering (`main.zig:398/:812/:924`) |
| `main.zig` | 1 | `typeRegistryRegisterPrimitives` `:217` (startup) |
| `c89_emit.zig` | **1** | `typeRegistryGetOrCreatePtr` `:2643` — inside `emitHoistedDecls`, i.e. during `emitFunctionSet` BODIES (the only emit-time append) |
| `cinclude.zig`, `emit_support.zig`, `name_mangler.zig`, `lir_stream.zig`, `hash.zig`, `lir_opt_pass.zig`, `c89_plan.zig` | 0 | — |

Window [end of `phase_EmissionClassification` → either sort call site] runs only:
`nameManglerInit`, `c89EmitterInit` (map inits reading `types_len` for capacity),
`errorCodeRegistryFinalize` (read walk), the `ts_ref_set`/reachability walk
(`lirStreamReadFunction` + `pruneTypeMarkByValue` — read-only recursion), and (path A only)
`emitIncludes` + `cincludeUnionAll`. **ZERO registry mutations in the window** (grep-verified
per-file; the only emit-time mutation `:2643` runs strictly later, inside body emission).
The one registry column that can still be written during emission is the `c_name_id` spelling
memo (P3 `typeCName` first-derivation memoization) — it is not an input to
`typeRefs`/`typeNeedsFullDef`/`typeRefsContains`, and no `typeCName` call precedes either sort.

**Conclusions:**
1. `types_len` and every typeRefs input are IDENTICAL at classification-end and at both sort
   call sites. `tstTopologicalSort` is a pure, deterministic function of that state → the
   order computed at the classification boundary is EXACTLY the order either call site
   computes today. A cannot differ from B (same pure function on the same state; and they
   never both run). Unifying at the boundary cannot change emission → the brief's STOP
   condition ("two sort call sites can produce DIFFERENT orders and unifying changes
   emission") is NOT triggered.
2. Decision-identity is therefore held by construction (not merely observed): the carried
   order == today's order. Gates expected: pins 0/8, probe-dump byte-identical.

### I.3 Post-snapshot appended types — handling decision (the KNOWN deferred minor)

The only emit-time type append is `c89_emit.zig:2643`
(`typeRegistryGetOrCreatePtr(emitter.registry, ap.elem, false)`, `emitHoistedDecls`'s `.binary`
array-decay arm) — runs in `emitFunctionSet` bodies. Today:

- **Single-file (path A):** every sorted walk runs in `emitSpecialTypes` BEFORE any body
  (`emitFunctionSet` is later in `emitModule`) → live `types_len` == sort snapshot → no
  over-read; the D2 measure markers (pass 2b, `use_emitted_set=1`) are safe.
- **Multi-file (path B):** `emitSharedHeader` runs before the module loop (live == snapshot).
  The per-module loop is `emitModuleHeaderFile` THEN `emitModuleFile`; module i's bodies can
  append types before module j>i's header walk, and THAT walk (live-bounded over the
  snapshot-length array) over-reads `sorted[tsi]` for `tsi ≥ snapshot`. The over-read lands in
  the sort's own `queue` buffer (I.1 adjacency) whose entries are Kahn-enqueued tids — valid
  tids < snapshot. Every tid occurs exactly once in `sorted[0..snapshot)` (P2 append
  invariant), so an over-read hit is a RE-VISIT of an already-walked tid. Re-visits are
  provable no-ops: the walk filters (`name_id`, `module_id`, kind, `pointer_only_map`,
  `shared_set`) are stable-map lookups and the `emitted_type_set`/`seen` dedup is monotone, so
  a second visit skips exactly where the first emitted-or-skipped. Appended tids themselves
  are never in `sorted` → never typedef-walked; their spelling flows through `getCTypeName`/
  `emitTypeDeps`/`emitPointeeDep` at the use site (unchanged). The direct-tid `ts_ref_set`
  loop skips them (`ts_ref_set` miss + `name_id == 0`). This is the P2 re-review's recorded
  "bounded harm — … over-read lands in own queue buffer" analysis, unchanged.

**Decision (no new semantic decision required — the brief settles it: "must keep behaving
exactly as today"):** P12 keeps ALL walk code untouched (bounds stay on LIVE `types_len`; the
existing skip/fallthrough at the header walk is preserved verbatim) and moves
`tstTopologicalSort` VERBATIM (same five-allocation sequence → same `result`→`queue`
adjacency → the over-read reads the same queue contents). By I.2 the carried order has the
same length and the same entries as today's, so the over-read width (`live − snapshot`) and
values are identical. Post-snapshot appended types keep byte-identical behavior **by
construction** — no improvisation, no variant.

The P2 re-review follow-up ("bound the walk on the snapshot length") is NOT taken here: that
would change the walks — P12's mandate moves the ORDERING DECISION and keeps every walk
decision as-is ("the emitter walks the carried order and never sorts" = the same walk, fed
from carried state). The deferred minor stays deferred (its analysis updated: the over-read
remains the pre-existing bounded-harm path, now into the carried sort's `queue` buffer).
Boundary note: the over-read escapes the `queue` buffer only if
`live − snapshot > types_len` types were appended mid-emission — impossible in practice, and
the exposure is identical today vs after (same array sizes, same walk bounds).

### I.4 Precise edit plan (touch set: `sf/src/**` + `sf/docs/tech_docs/**` only)

**Algorithm home (stated per target shape 3): `c89_plan.zig` — the planner.** The ordering
DECISION belongs to the planner (spec §4 planner row "typedef emission order (P12)";
`C89SpellPlan`'s header reserves P12's state). `tstTopologicalSort` (body + P2 comment
verbatim; `tstEdgesWalk` already deleted at P2 — nothing else moves) becomes the planner's
private derivation over the P2 relation. `type_resolver.zig` is NOT touched (its own Kahn
machinery is the resolution-order sort — a different concern; the relation module
`type_registry.zig` is a pure read source for the derivation).

1. **`sf/src/c89_plan.zig`**
   - `C89SpellPlan` gains `typedef_order: [*]u32` (the carried order; the plan says "carry it
     (sorted)" — no separate length state, avoiding a write-only field of the P2
     `sorted_items` class; the covered length is the planning-time `types_len` by the sort's
     contract).
   - Move `tstTopologicalSort` verbatim from `c89_emit.zig` (keep the name for move
     auditability; make it non-`pub` — 0 external callers after the move; the emitter never
     sorts is then structurally true).
   - New boundary fill `spellPlanPlanTypeOrder(plan, alloc, reg)`:
     `plan.typedef_order = tstTopologicalSort(reg, alloc);` — the ONE computation, ONCE per
     compilation.
   - `spellPlanInit` inits the new field (`undefined`); header comment truth-up (P12 done).
2. **`sf/src/c89_emit.zig`**
   - DELETE `tstTopologicalSort` (`:868-936` incl. comment block) — moved to `c89_plan`.
   - `emitModule` `:2295`: `var sorted: [*]u32 = tstTopologicalSort(emitter.registry, emitter.alloc);`
     → `var sorted: [*]u32 = emitter.plan.typedef_order;` (the consumer region READS the
     carried order — approved target shape 2; `sorted` parameter threading of
     `emitSpecialTypes`/`emitSharedHeader`/`emitTypePasses`/`emitModuleHeaderFile` and every
     walk bound/body are UNTOUCHED — I.3).
   - Comment truth-ups (P12 notes at the `plan` field `:593-597` + `emitTypePasses` doc
     `:1121`).
3. **`sf/src/main.zig`**
   - `phase_EmissionClassification` (`:1222-1245`), after `classifyTypeEmissionFinalize`:
     `c89_plan.spellPlanPlanTypeOrder(&ctx.spell_plan, &ctx.alloc.permanent, ctx.typereg);`
     (planner-state arena `permanent` — the order must outlive all emission incl. multi-file's
     per-module header walks; the sort's internal bump adjacency is arena-independent).
   - Multi-file region `:1429`: `var sorted: [*]u32 = c89_mod.tstTopologicalSort(ctx.typereg, &ctx.alloc.emission);`
     → `var sorted: [*]u32 = ctx.spell_plan.typedef_order;` (region reads the carried order;
     the `emitSharedHeader`/`emitModuleHeaderFile` call sites keep threading `sorted`).
   - Comment truth-ups (`:124-125` spell_plan field note "P12 adds typedef order" → done;
     `:1223-1227` boundary comment "P12 later adds typedef-order state" → done; `:1425-1428`
     region comment).
4. **`sf/docs/tech_docs/`** (stamps `[updated: 2026-10-12]`)
   - `INDEX.md` Table A: `tstTopologicalSort` row → `c89_plan.zig`; P12 stamp.
   - `08_c89_emission.md`: "Type Topological Sort" section (planned-at-boundary wording),
     `emitModule` pseudocode step 1 (sort → carried-order read), `plan` field row
     (`:256`, "P12 adds typedef order" → done).
   - `03_type_resolution.md`: `typeRefs` row wording "the emitter's `tstTopologicalSort`" →
     "the planner's `tstTopologicalSort` (`c89_plan`)".
   - `09_pipeline_orchestration.md`: multi-module branch call list (`:573/:593`) + `spell_plan`
     rows (`:88/:820`) truth-ups; `phase_EmissionClassification` step note.

**Expected battery result (decision-identity gate):** pins 0/8, corpus class-file byte-identical
(0 movers), goldens 5/5, mi_matrix 25+oob MATCH, examples 26/26+26/26, stdlib 285/0,
hop1==hop2 with a NEW fixed point recorded (compiler-moving), markers 3,436/38,378 unchanged.
Plus a probe-dump equivalence (P6-pre §6.3 method): OLD vs NEW compilers dump a
typedef-ordering probe (aggregates by value, fn-ptr-with-EU-return D8 shape, enums, tagged/
packed unions, synthetic-element slices, optionals, tuples) single-file AND multi-file
(`zig_special_types.h` + per-module `.h`/`.c`) — `diff` empty.

## Implement

Executed exactly the I.4 edit plan (no deviations; source edits via `edit` only, regions read
before each edit, bottom-to-top per file).

**`sf/src/c89_plan.zig`**
- `C89SpellPlan` gains `typedef_order: [*]u32` (the carried order — "carry it (`sorted`)"; no
  length field, avoiding a write-only state of the P2 `sorted_items` class).
- `tstTopologicalSort` moved VERBATIM from `c89_emit.zig` (body incl. the P2
  popped/append residue machinery byte-identical; the P2 comment block travels with it and a
  P12 move note is added; visibility `pub fn` → `fn` — 0 external callers, so "the emitter
  never sorts" is now structural).
- New `pub fn spellPlanPlanTypeOrder(plan, alloc, reg)` — the ONE computation
  (`plan.typedef_order = tstTopologicalSort(reg, alloc)`), and `spellPlanInit` inits the new
  field (`undefined`).

**`sf/src/c89_emit.zig`**
- `tstTopologicalSort` DELETED from this file (moved; replaced by a 4-line P12 provenance
  note at the old site).
- `emitModule` (`:2295`-region): `var sorted: [*]u32 = tstTopologicalSort(emitter.registry, emitter.alloc);`
  → `var sorted: [*]u32 = emitter.plan.typedef_order;` — the consumer region reads the carried
  order (approved target shape 2). `emitSpecialTypes`/`emitSharedHeader`/`emitTypePasses`/
  `emitModuleHeaderFile` signatures, walk bounds and bodies: UNTOUCHED (I.3 — post-snapshot
  appended-type behavior preserved by construction).
- Comment truth-ups (P12 notes at the `plan` field + `emitTypePasses` doc).

**`sf/src/main.zig`**
- `phase_EmissionClassification`, last statement (after `classifyTypeEmissionFinalize`):
  `c89_plan.spellPlanPlanTypeOrder(&ctx.spell_plan, &ctx.alloc.permanent, ctx.typereg);` —
  ONCE per compilation at the backend-neutral boundary; permanent arena (the order outlives
  all emission incl. multi-file's per-module header walks; the sort's internal bump adjacency
  `result`→`queue` is arena-independent).
- Multi-file region (`:1429`-region): `var sorted: [*]u32 = c89_mod.tstTopologicalSort(ctx.typereg, &ctx.alloc.emission);`
  → `var sorted: [*]u32 = ctx.spell_plan.typedef_order;`; `emitSharedHeader`/`emitModuleHeaderFile`
  call sites keep threading `sorted`.
- Comment truth-ups (spell_plan field note, boundary comment, region comment).

**`sf/docs/tech_docs/`** (stamps `[updated: 2026-10-12]`)
- `INDEX.md`: Table A `tstTopologicalSort` row → `c89_plan.zig` (+ new `spellPlanPlanTypeOrder`
  row); Master-Index stamp.
- `08_c89_emission.md`: "Type Topological Sort" P12 paragraph (planned-at-boundary + the
  post-snapshot handling statement), `emitModule` pseudocode step 1 (sort → carried read),
  `plan` field row, H1 stamp.
- `03_type_resolution.md`: `typeRefs` + `typeResolverBuildDependencyGraph` rows ("the emitter's
  `tstTopologicalSort`" → "the planner's (`c89_plan`; P12 — was the emitter's)").
- `09_pipeline_orchestration.md`: multi-module branch description + call list (sort call gone),
  `spell_plan` data-flow + CompilerContext rows, phase-flow step 10 (+ `spellPlanPlanTypeOrder`),
  H1 stamp.

Grep gate after the edit: `tstTopologicalSort` remains only in `c89_plan.zig` (definition +
boundary fill) and doc/comment mentions; `grep -rn "tstTopologicalSort" sf/src/*.zig` shows 0
call sites in `c89_emit.zig`/`main.zig` — zero sort calls in the emitter or mid-emission.

## Runtime battery

Compiler under test: `/tmp/p12_work/s1/zig1_5_clean` from
`FIXED_POINT_MD5=39bcb30b45df93631f9fc745f95dc1aa bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p12_work/s1`
(repo root). OLD comparison binary: `/tmp/p6fix1/r2s1/zig1_5_clean` md5 `39bcb30b45df93631f9fc745f95dc1aa`
(= the pre-P12 recorded fixed point).

### Probe-dump equivalence (P6-pre §6.3 method) — decision-identity

Probe `/tmp/p12_work/probe/main.zig` (by-value aggregate chain `Inner/Middle/Outer`, `Color`
enum + `Tag` tagged-union + `Packed` packed struct, `Err` error set + `EU = Err!i32` + `Cb =
fn (Color) EU` D8 fn-ptr shape, `Holder` with `?Color` + `[]u8` + `[2]Middle`):

```
$ /tmp/p6fix1/r2s1/zig1_5_clean --dump-c89 probe/main.zig > probe/OLD.c   # rc=0, 12957 lines
$ /tmp/p12_work/s1/zig1_5_clean --dump-c89 probe/main.zig > probe/NEW.c   # rc=0
$ diff probe/OLD.c probe/NEW.c
→ empty (SINGLE-FILE WHOLE FILE BYTE-IDENTICAL)
```

Multi-file (both compilers run from the SAME exe dir `/tmp/p12_work/cmp/` — module stem tokens
are path-derived; `lib/` sets `diff -rq`-identical):

```
$ /tmp/p12_work/cmp/zig1_5_clean --dump-c89 --output-dir probe/old_dir probe/main.zig   # OLD binary, rc=0
$ /tmp/p12_work/cmp/zig1_5_clean --dump-c89 --output-dir probe/new_dir probe/main.zig   # NEW binary, rc=0
$ for f in old_dir/*.c old_dir/*.h old_dir/*.sh; do b=$(basename $f); diff -q old_dir/$b new_dir/$b || echo "DIFFERS: $b"; done
→ empty (EVERY .c/.h/.sh IDENTICAL)
$ cmp probe/old_dir/zig_special_types.h probe/new_dir/zig_special_types.h
→ IDENTICAL (the typedef order is spelled here — carried order == today's order)
```

### 1. Seed rebuild + two-hop closure (fixed point `39bcb30b…` → new)

```
[seed] hop2 binary md5: e93ca5eeb647f7465f5cd096b9208ca5
[seed] two-hop closure OK: hop1 == hop2 == e93ca5eeb647f7465f5cd096b9208ca5
error: fixed-point mismatch: got 'e93ca5eeb647f7465f5cd096b9208ca5', want '39bcb30b45df93631f9fc745f95dc1aa'
```

**hop1==hop2 proven**; fixed point `39bcb30b45df93631f9fc745f95dc1aa` →
**`e93ca5eeb647f7465f5cd096b9208ca5`** (new, recorded; compiler-moving — the `FIXED_POINT_MD5`
gate mismatch is the recorded delta, seed not rotated — closeout-only).

### 2. Corpus classify (vs frozen Appendix A baseline `/tmp/task0_work/corpus_baseline.txt`)

```
$ bash scripts/corpus/classify /tmp/p12_work/s1/zig1_5_clean /tmp/p12_work/corpus_p12.txt
wrote /tmp/p12_work/corpus_p12.txt: 1124 dirs
$ md5sum /tmp/p12_work/corpus_p12.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p12_work/corpus_p12.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff … → empty
$ awk '{print $2}' … | sort | uniq -c → 116 FAIL / 58 GREEN / 950 OK
```

**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical class file, 0 movers.**

### 3. Runtime goldens (5 md5s)

Dump+gcc per Task-0 §1.3 recipe (default `-fsafe`): all 4 dump rc=0 / gcc rc=0 / 0 `error:`;
line counts **13924/19277/15596/14789** (record):

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 gold/gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| gold/lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| json | `cd examples/z98/json_parser && gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| mud srv | `bash examples/z98/mud_server/demo/session.sh gold/mud mud_srv.out mud_cli.out` (session rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| mud cli | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

**5/5 byte-identical.**

### 4. mi_matrix anchors 25 + oob

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/p12_work/s1/zig1_5_clean $(cat /tmp/opencode_p6pre/mi25.list)
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```

Trap fixture (`-fsafe`) `slice_index_field_store_oob_xmod`: dump rc=0, build rc=0, **run rc=133**
(Trace/breakpoint trap), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt`
md5. **MATCH.**

### 5. examples/z98/*/ matrix (26/26 build + 26/26 run)

Build per dir (`-ffast -o`, `build_target.sh linux`; entry resolution `main.zig` →
`<dirname>.zig`): **26/26 dump=0 / ≥1 `.c` / build=0**; `.c` counts identical to Task-0 §1.4
(7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38). Run per dir (CWD = example dir;
`timeout 25`, mud 8; stdin `/dev/null`, rogue* `q\n`) — **26/26 rc + stdout md5_16 IDENTICAL to
the §1.4 table** (days_in_month `8c0d394cbc6e7f36` … mud_server rc=124 `9545fe1d245293ef` …
z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`; full 26-row match).

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/p12_work/s1/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

### 7. The 8 `--dump-c89` pins (old → new)

Command per row: `/tmp/p12_work/s1/zig1_5_clean <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

| entry | mode | old (P6-pre record) | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical.** Semantic argument: P12 only relocates WHERE the
order is computed (I.2 — the window is registry-mutation-free, so the carried order is the
same array today's sorts produce); the probe-dump + pins confirm emission identity directly.

### 8. `--markers` telemetry

```
$ /tmp/p12_work/s1/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin
dump rc=0; stderr 3,436 marker lines / 38,378 B
```

Identical to the P2–P6-pre record (3,436 / 38,378) — the boundary planner step emits no markers.

## Concerns

1. **Deferred minor kept deferred (by design):** the P2 re-review item (`emitModuleHeaderFile`
   live-`types_len` walk vs sort-time snapshot; follow-up "bound on snapshot length") is NOT
   taken here — P12 moves the ordering decision and keeps every walk decision as-is ("must keep
   behaving exactly as today", I.3). The over-read's queue-buffer landing is preserved by the
   verbatim move (five consecutive `sandAlloc`s). Cost if wrong: the latent bounded-harm
   over-read rides until the recorded follow-up; exposure identical to today.
2. **`sf/src/type_registry.zig:1243` comment staleness (disclosed, untouched):** the P2 relation
   comment still says "the emitter's typedef ordering (`tstTopologicalSort`, …)" — after P12 the
   sort is the planner's (`c89_plan`). Comment-only; the file is outside the touch set (its
   conditional allowance is "only if the sort algorithm home requires it" — the home is
   `c89_plan`, no `type_registry` edit required). Tech docs 03/08/09 carry the correct
   attribution. Future doc sweep can truth-up the one line.
3. **`c89_plan.spellPlanPlanFn`/`spellPlanCarrier` linear lookups** (P6-pre deferred minor "map
   before P12 grows the table") — P12 does NOT grow the per-fn table (it adds one module-level
   order), so the linear scan is unchanged; the deferred minor stands as-is.
4. **Module-stem path dependence in dump comparisons** (pre-existing, not a P12 delta): multi-file
   output names embed the path-derived FNV stem, so OLD/NEW multi-file comparisons must run from
   one exe dir (done — §probe). Unrelated to emission content (the `.c`/`.h` bodies and
   `zig_special_types.h` are what the decision-identity gate reads, and they are byte-identical).
