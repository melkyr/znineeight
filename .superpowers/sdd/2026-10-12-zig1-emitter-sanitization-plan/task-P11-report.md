# Task P11 report — Promotion spelling from carried result types

Branch `zig1_improvements`, BASE `e121569c` (confirmed `git rev-parse HEAD` = `e121569cf41ff9a0dadd9d8e1f5083166fe0fa33`). Requirements: `task-P11-brief.md` (binding, incl. controller pre-check facts). Shape: Investigate (written before source edits) → Implement (one commit (a)) → full 8-item runtime battery → this report (commit (b)).

**Status: COMPLETE** — shape (i) implemented in one compiler-moving commit (a) `91b58dba`; full 8-item battery green; pins 0/8 (decision-identity). No STOP: one sanctioned shape worked.

Commits: (a) `91b58dba` `refactor(c89_plan): P11 — UAC cast direction planned at the boundary; coercion.zig loses the C rule`; (b) this report `docs(sdd): P11 report`.

## Investigate (written before source edits — 2026-10-15)

### 1. Census (re-derived by NAME at HEAD `e121569c`; brief line-drift note applied)

- `coercionUsualArithPromote`: sole definition `sf/src/coercion.zig:238` (the P5 verbatim-relocation block, contract comment `:214-236`). Sole call site `sf/src/c89_emit.zig:3555` — `emitBinRvalueText`'s `if (op >= 10)` promote block; `prom_side` `0` → `lhs_cast = getCTypeName(r_tyid)`, `1` → `rhs_cast = getCTypeName(l_tyid)`, `2` → no cast. Matches controller pre-check (brief line 13; the task-text `:3622` cite is pre-P6 drift — current `:3555`).
- `emitBinRvalueText` callers: exactly 2 — `nestEmitBinExpr` (`c89_emit.zig:3531`, nested rvalue path via `nestEmitDefRvalue` `:3410`) and the `.binary` def arm (`:6808`, inside `emitInst` `:6111`). Both have their inst position in scope (`nestEmitDefRvalue` takes `def_bb`/`def_ii`; `emitInst` takes `inst_bb`/`inst_ii`) — the same ordinals `planConstCarrierAt` already consumes (`:3438`, `:6835`). Both consume the same planned spelling via those ordinals.
- Promote path fires ONLY for ops 10–15 (comparisons). `nestEmitBinExpr` early-returns for `op >= 16` (wrap spelling; sat never nests — `nestShapeOk` refuses `op >= 19`); the `.binary` def arm routes `op >= 16` to the wrap / `emitSatBinary` arm and only `op < 16` reaches `emitBinRvalueText`; the promote gate is `op >= 10`. Pre-check fact verified.
- P6 record shape verified: `binary.result_type` = `lowerBinSemType` (`sf/src/lower.zig:675-688`) = the RESULT temp's semantic type first (`lowerTempSemanticType(result)`), lhs/rhs fallback. Comparisons carry `TYPE_BOOL` — the plan's parenthetical gloss "cast to the carried semantic result type" is wrong on this path (would cast operands to bool). Pre-check fact verified at source.
- `getTempEffType` (`c89_emit.zig:4067`) census — 12 call sites: `:370` (assign_field int gate), `:3130` (written-type walk), `:3553-3554` (the promote site — UAC decision inputs), `:6230`/`:6233`, `:6428`/`:6431`, `:6614`, `:6649`/`:6656` (ptr/int-kind gates in store/field arms). The promote site is NOT its last consumer — nine non-UAC sites remain (pre-existing gate readers, out of P11 scope per "only the UAC-direction rule leaves `coercion.zig`"). What remains after P11: `getTempEffType` itself untouched (all other consumers keep it); on the promote path its two reads remain as the P5-named glue (§2).
- `coercion_mod` (`c89_emit.zig:32`) has exactly one use — the promote call. The import went with the call.

### 2. Shape verdict: (i) planner side-table (not a STOP — one sanctioned shape works)

The plan gloss ("cast to the carried semantic result type") is dead on the comparison path (`result_type` = bool — controller pre-check, verified). The plan sanctions (i) planner side-table or (ii) pure mechanical spelling from carried types.

- **Shape (ii) fails the Decision-vs-spelling rule.** The UAC direction is a three-way existence/type CHOICE (cast-LHS / cast-RHS / no cast) derived by comparing operand signedness classes + byte widths. Spelling it at emit time is exactly a "pure re-derivation of a decision" — forbidden (P6 precedent: `getTempTypeInfo` deleted despite being a pure function of temps). No choice-free mechanical spelling preserves the current bytes (e.g. casting both operands to a common type would move the pins). (ii) cannot preserve behavior + the rule on this path.
- **Shape (i) works.** The direction is computed ONCE at the `c89_plan` boundary (the same `phase_EmissionClassification` walk as the const-carrier plan) from CARRIED operand types (`hoisted_temps[].type_id` — the same recorded `TempDecl.type_id` facts `getTempEffType` reads), stored in `C89SpellPlan` side-table state; the emitter reads and spells. This is the Decision-vs-spelling-faithful reading the brief names (brief line 17).

Design (what moves, what stays) — decision-identity by construction:

- The UAC rule body moves verbatim `coercion.zig` → `c89_plan.zig` private `uacPromoteSide` (same `typeRegistryIntSignednessClass`/`typeRegistryIntByteWidth` calls — P5 predicates stay in `type_registry.zig`, they are not the C rule). `coercionUsualArithPromote` is deleted from `coercion.zig` entirely (the P5 relocation is undone; the rule is re-owned by the C-spelling planner per ruling (ii): "C-spelling decisions live in `c89_plan`").
- Side-table: `C89SpellPlan` gains `uac_maps: [*]hash_mod.U32ToU32Map` — per-fn, same `fn_keys`/`spellInstOrd` machinery. `fn_maps` cannot be reused as-is: a `.binary` inst already carries a const-carrier entry keyed by the same inst ordinal (`.binary` is in `spellPlanPlanFn`'s fold-capable set). Key = `spellInstOrd`; value = planned side `0`/`1`; only cast-needed entries stored (miss = `2` = no cast — decision-identical to the old `return 2` arm).
- Rule inputs at plan time mirror `getTempEffType` exactly (first `hoisted_temps` match; `0xFFFFFFFF`/`TYPE_VOID` → unresolved → `0`; the rule classifies `0` unclassified). `lirOptRun` runs post-boundary and rewrites insts in place only (P6-pre I.2 invariant: const-fold gate + copy-coalesce retarget `dt == st`); operand renames are type-preserving, so plan-time types == emit-time `getTempEffType` types — the direction and the cast type name are decision-identical to the removed emit-time computation.
- Emitter: the promote block replaces `coercion_mod.coercionUsualArithPromote(emitter.registry, l_tyid, r_tyid)` with a side-table read (`planUacSideAt`, mirroring `planConstCarrierAt`); the `getTempEffType` + `getCTypeName` glue stays verbatim — P5's own contract names it glue ("keeps only emitter glue — `getTempEffType` temp→type resolution plus `getCTypeName` cast-name minting"); P11's decision is the DIRECTION only. Ordinals threaded: `emitBinRvalueText`/`nestEmitBinExpr` gain `def_bb`/`def_ii` (already in both callers' scopes).
- No new LIR fields (P6 already carries what is needed — nothing seemed needed, no STOP); no `lower.zig`/`lir.zig`/`async_state_machine` edits; P5 predicates untouched.

### 3. Controller pre-check facts — verification record

| pre-check fact | verdict | cite |
|---|---|---|
| single call site `c89_emit.zig:3555` in `emitBinRvalueText`; sole def `coercion.zig:238` | verified | §1 |
| both callers (`nestEmitBinExpr` `:3531` + `.binary` arm `:6808`) must consume the same planned spelling | verified — both thread their own inst ordinals into the shared `emitBinRvalueText` | §1 |
| promote fires only ops 10–15 | verified | §1 |
| `binary.result_type` = result temp type = bool for comparisons; literal cast-to-result_type gloss does not fit | verified at `lower.zig:675-688` | §1 |
| plan sanctions (i) side-table OR (ii) mechanical; Decision-vs-spelling makes (i) the faithful reading | verified; (ii) additionally fails on behavior-identity | §2 |
| shape (i) state goes in `C89SpellPlan` side-table machinery | verified — `c89_plan.zig:11` already anticipates "P11 (UAC cast direction) later adds its state here too" | §2 |

## Implement

One commit (a) `91b58dba` (6 files: `c89_plan.zig` +117/-…, `c89_emit.zig`, `coercion.zig` -32, `05_semantic_analysis.md`, `08_c89_emission.md`, `INDEX.md`). Touch set exactly as sanctioned — no `lower.zig`/`lir.zig`/`async_state_machine`, no unrelated fixes, `run.err` left alone.

- `coercion.zig`: `coercionUsualArithPromote` + its P5 contract block DELETED (file 257 → 225 lines). `classifyCoercion`/`CoercionTable` (semantic-phase coercion) untouched; P5 predicates untouched in `type_registry.zig`.
- `c89_plan.zig`:
  - `C89SpellPlan` gains `uac_maps: [*]hash_mod.U32ToU32Map` (per-fn UAC-direction maps beside `fn_maps`; grow/init carry it).
  - `hoistedEffType` (private) — plan-time mirror of the emitter's `getTempEffType` resolution (first `hoisted_temps` match; `0xFFFFFFFF`/`TYPE_VOID` → `0`).
  - `uacPromoteSide` (private) — the rule body relocated VERBATIM from `coercion.zig` (same `typeRegistryIntSignednessClass`/`typeRegistryIntByteWidth` calls and `0`/`1`/`2` contract).
  - `spellPlanPlanFn` — for every `.binary` with `op ∈ [10,15]`: operand types via `hoistedEffType`, direction via `uacPromoteSide`, `u32ToU32MapPut(&plan.uac_maps[fi], ord, side)` when side < 2 (miss = no cast).
  - `spellPlanUac` (pub) — spell-time read by (fn_key, inst_ord), mirroring `spellPlanCarrier`.
- `c89_emit.zig`:
  - `planUacSideAt(emitter, bb_idx, ii)` — spell-time read; miss returns 2 (the old `return 2` arm).
  - `emitBinRvalueText` promote block: `coercion_mod.coercionUsualArithPromote(...)` → `planUacSideAt(emitter, def_bb, def_ii)`; the `getTempEffType`/`getCTypeName` glue verbatim unchanged. `coercion_mod` import deleted (its only use).
  - Ordinals threaded: `emitBinRvalueText`/`nestEmitBinExpr` gain trailing `def_bb`/`def_ii`; `nestEmitDefRvalue` passes its `def_bb`/`def_ii`; the `.binary` def arm passes `emitInst`'s `inst_bb`/`inst_ii`.
- Tech docs `[updated: 2026-10-12 — P11 …]`:
  - `05_semantic_analysis.md`: the `coercionUsualArithPromote` contract row is RE-OWNED (tombstone → `c89_plan.zig` `uacPromoteSide`, doc 08); `coercion.zig` header line-count truth-up (225).
  - `08_c89_emission.md`: new P11 head stamp + §1.15 P11 paragraph (SUPERSEDES the P5 promotion sentence) + `plan` field row gains the `uac_maps` contract.
  - `INDEX.md`: `coercionUsualArithPromote` row tombstoned; `uacPromoteSide`/`spellPlanUac`/`planUacSideAt` rows added (alphabetical); `spellPlanPlanFn` row gains the UAC fill.

Pre-commit smoke (evidence before commit; compiler `/tmp/p11_build/zig1_5_clean` = the two-hop build of the working tree that became commit (a), tree verified clean after commit): gol golden `fcbf7e7cead5082f0a8caadd5a8f0ff9` (frozen). Mixed-sign UAC probe (`cmpUL(a: u32, b: i32)` / `cmpLU(a: i32, b: u32)` / `cmpSame(u32, u32)`, dumped C):

```
if ((unsigned char)(a < (unsigned int)b))            /* u32 < i32: cast signed RHS to unsigned */
if ((unsigned char)((unsigned int)a <= b))           /* i32 <= u32: cast signed LHS to unsigned */
if ((unsigned char)(a < b))                          /* same class: no cast */
```

— the planned spelling matches the rule exactly in all three arms.

## Runtime battery (8 items; compiler `/tmp/p11_build/zig1_5_clean`, built from the committed source)

### 1. Seed two-hop

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p11_build` → `[seed] hop2 binary md5: 803e8dc1169dcb40e62d3e5de63cf545` / `[seed] two-hop closure OK: hop1 == hop2 == 803e8dc1169dcb40e62d3e5de63cf545`. **hop1==hop2**; fixed point `2bf36c59e9bde59b95ee05814afcac10` → **`803e8dc1169dcb40e62d3e5de63cf545`** (moved as expected — the compiler source moved; recorded; seed NOT rotated — Task C).

### 2. Corpus classify (class FILE vs frozen `518eca1a…`)

`bash scripts/corpus/classify /tmp/p11_build/zig1_5_clean /tmp/p11_battery/corpus.txt` → `wrote …: 1124 dirs`; `md5sum corpus.txt` = `518eca1a9b5d3e1cc5a48abce214abd8` = frozen `518eca1a…` (**byte-identical, 0 movers**); tally `950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`.

### 3. Goldens 5/5

dump+gcc all rc=0 (0 `error:`). gol `timeout 120 ./gol` = `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `printf '(+ 1 2)\n' | timeout 60 ./lisp` = `b3d9f8974da24ddbf9d389f3d7d97322`; json (CWD `examples/z98/json_parser`) = `8bda3d5a1ec07d14a301bc343df32bf8`; mud session (`examples/z98/mud_server/demo/session.sh`) rc=0, server `66c8f0abb926cca7baf9a0d1692ab318`, client `93147d0f0bbd983a9d844fea8b7a6fa7`. **5/5 = frozen.**

### 4. mi_matrix 25 + oob

SET DEFINITION (progress.md, load-bearing) enumerated → the 25 dirs (`array_of_struct_literal_xmod` `catch_discard_struct_xmod` `const_assign_ok_xmod` `empty_named_struct_field_xmod` `empty_named_struct_xmod` `enum_subbyte_backing_xmod` `f64_literal_precision_xmod` `field_store_continue_nested_xmod` `field_store_continue_xmod` `fn_ptr_signature_ok_xmod` `for_range_end_len_xmod` `len_array_field_xmod` `lexer_float_exponent_xmod` `lit64_decimal_xmod` `nested_loop_label_xmod` `optional_void_present_xmod` `packed_nested_whole_depth_ok_xmod` `packed_nested_wholeliteral_xmod` `packed_union_struct_wholemember_xmod` `shadow_ok_xmod` `sig_known_type_ok_xmod` `slice_index_field_store_xmod` `tagged_payload_whole_reassign_xmod` `tagged_tag_member_shadow_xmod` `tagged_tag_sugar_xmod`). `bash scripts/stdlib/run_fixtures.sh /tmp/p11_build/zig1_5_clean <25 dirs>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`**. Trap `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc=0, build rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt`). **MATCH.**

### 5. examples 26/26 build + 26/26 run

Build (`-ffast -o` + `build_target.sh linux`, output dirs pre-created): 26/26 dump=0 / `.c` counts identical to task-0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run (CWD = example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* fed `q\n`): 26/26 rc + stdout md5_16 IDENTICAL to §1.4 — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`.

### 6. stdlib

`bash scripts/stdlib/verify_stdlib.sh /tmp/p11_build/zig1_5_clean` → `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK`.

### 7. The 8 `--dump-c89` pins (old → new; sequential from repo root)

| entry | mode | old (P6 record) | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — byte-identical C emission** (decision-identity expected and observed: the planned direction reproduces the removed emit-time decision exactly wherever the gates reach).

### 8. Markers telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 lines / 38,378 B** — identical to the record (unchanged).

## Observations (report-only)

- Decision-identity holds end-to-end: pins 0/8, corpus class file byte-identical (0 movers), markers unchanged — the rule is a verbatim relocation applied to the same carried-type inputs, planned at the boundary (`spellPlanPlanFn`) instead of at spell time; `lirOptRun`'s type-preserving retargets (`dt == st` coalesce gate, in-place rewrites) keep plan-time and emit-time operand types equal, so the planned side equals the old computed side wherever the promote path is reached.
- The mixed-sign probe covers all three rule arms (side 0, side 1, side 2) empirically in addition to the 8 pins' whole-program byte-identity.
- `getTempEffType` remains with its 9 non-UAC consumers (pre-existing gate readers, out of P11 scope); the promote block's two reads survive as the P5-named glue (`getTempEffType` temp→type resolution + `getCTypeName` cast-name minting — spelling). The UAC decision (which side / whether any cast) no longer exists at emit time.
- Side-table completeness note (same posture as the carrier plan): the boundary plans pre-opt LIR; `lirOptRun` only rewrites in place (fold can turn a planned `binary` into a `int_const`, whose planned UAC entry is then simply unread — harmless). If a future opt ever inserts/moves insts or relaxes the type-preserving retarget gate, the UAC table must be re-evaluated (same O3 note the carrier plan carries).
- Deferred minors: none taken. No unrelated fixes made.

## Concerns

- C1: fixed point moved (expected): `2bf36c59e9bde59b95ee05814afcac10` → `803e8dc1169dcb40e62d3e5de63cf545`; seed NOT rotated (Task C closeout).
- C2: `uac_maps` miss conflates "planned side 2" with "not planned" — unreachable-by-construction for op 10–15 binaries (all planned); the defensive posture matches the carrier plan's miss fallback.
- C3: `spellPlanUac`/`planUacSideAt` keep the existing linear per-fn key scan (same as `spellPlanCarrier`); no performance/behavior change.
- C4: harness notes — `-o` requires a pre-created output dir (first oob attempt failed on that: harness error, not compiler); pins/markers run sequentially from one CWD (the documented spill-file race).
