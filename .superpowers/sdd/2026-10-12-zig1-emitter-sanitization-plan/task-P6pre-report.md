# P6-pre report — C89 spelling planner (carrier derivation)

**Status:** DONE (battery all green; pins 0/8; emitted-C byte-identical; one residual documented under Concerns — the untyped materialization's semantic width/signedness is still recorded at lowering time via the planner's derivation entry, P6 makes it an explicit LIR field)

**Scope:** operator ruling 2026-10-12 (ii): carriers are C-spelling choices, never LIR fields. New module `sf/src/c89_plan.zig` at the `phase_EmissionClassification` boundary; carrier derivation (i32/u32/i64/u64) moves out of `lowerExactIntArg`/lowering into the planner (side-table state, read by the emitter at spell time). LIR gains NO carrier fields. Gate: runtime battery.

---

## Investigate (read-only census + derivation-equivalence argument + precise edit plan — written BEFORE any source edit)

### I.0 Drift re-derivation (brief/plan cite → tree `9ced323b892fa3e1bc4eb0b1598a416a`)

| brief cite | current location | verdict |
|---|---|---|
| `lowerExactIntArg`, `sf/src/lower.zig` | `lower.zig:1655` (rule application at `:1660`) | exact |
| `c89_emit.zig:4573`-era comment referencing `lowerExactIntArg` | `c89_emit.zig:4553-4571` (Task-2 comment; "materialised by lowering into its value-chosen carrier (i32/u32/i64/u64; `lowerExactIntArg`)") | era-cite; text found |
| `phase_EmissionClassification` boundary (`sf/src/main.zig:1212`) | `main.zig:1212` (call at `:420`, between `phase_LIRLowering` `:412` and `phase_C89Emission` `:421`) | exact |
| `EmissionClassification` state (`type_resolver.zig:168-182`) | `type_resolver.zig:177-182` (struct; doc comment `:171-176`) | exact |
| LIR const shape (`sf/src/lir.zig`) | `lir.zig:74` `int_const: struct { value: u64, result: u32 }`; temp record `TempDecl{temp_id, type_id}` `lir.zig:17-20` | exact |

### I.1 Census — every carrier decision site (i32/u32/i64/u64 choice)

The "carrier" is the C materialization type of an integer constant (the per-program carrier typedef family i32/u32/i64/u64). Every site that CHOOSES one, re-derived by grep over `sf/src` (`comptimeIntUntypedType|intConstTypeForValue` — the two decision functions):

| # | site | file:line | what it decides | class |
|---|---|---|---|---|
| C1 | `comptimeIntUntypedType` | `comptime_eval.zig:1382-1397` | exact `ComptimeInt` → narrowest fitting `TYPE_I32/U32/I64/U64` (negative → signed; `null` outside the 64-bit window) | **the value→carrier derivation rule** |
| C2 | `lowerExactIntArg` | `lower.zig:1655-1668` (applies C1 at `:1660`) | materialization temp type for an exact untyped (resolved `TYPE_INT_LIT`) print-arg / inferred-tuple-elem integer; values fitting i32 keep the legacy untyped temp (`TEMP_NONE`); >64-bit reports `error[3000]` | carrier materialization at lowering |
| C3 | `lowerFoldedIntConst` | `lower.zig:3613-3635` (applies C1 at `:3618`) | same materialization for a folded integer expression whose resolved type is `TYPE_INT_LIT`/`TYPE_UNDEFINED` | carrier materialization at lowering |
| C4 | `intConstTypeForValue` | `c89_emit.zig:3866-3873` | **emit-time** per-const C carrier: hoisted `integer_literal_type` → `I32/U32/U64` by value thresholds (`v <= 2^31-1` / `v <= 2^32-1` / else — note: no i64 arm); hoisted `TYPE_UNDEFINED` → `TYPE_USIZE`; otherwise identity (the hoisted type) | **emit-time deciding helper (forbidden shape)** |

C4's three consumption sites (all in `c89_emit.zig`):

| site | use |
|---|---|
| `:2597` (written-type inference walk inside `emitHoistedDecls`, `:2562` loop over `(bb_idx, ii)`) | the C declaration type of the const's hoisted temp |
| `:3495` (`nestEmitDefRvalue` `.int_const` arm; caller `emitValueExpr:3432-3461` has the def loc `(dfbb, dfii)`) | rvalue spelling of an inlined const |
| `:6922` (`emitInst` `.int_const` statement arm; caller `emitFunctionBody:8344-8373` walk has `(bb_idx, inst_idx)`) | rvalue spelling of a const statement |

**NOT carriers — semantic type inference (untouched; class evidence below):**

| # | site | what it decides |
|---|---|---|
| S1 | `semantic_analyzer.zig:5954`, `:6712` | the Z98 slot type of an unannotated container-level binding whose folded init needs it (`const c = 2000000000 + 1000000000` → `u32`) |
| S2 | `semantic_analyzer.zig:6530` | the Z98 element type of an untyped tuple element ("the element type sema picked for the tuple's C model") |
| S3 | `lower.zig:8304-8312` (`:8311`) | the same binding-slot rule for function-local decls (where lowering owns `decl_local`) |

Class evidence for S1–S3: these decide **which Z98 type a binding/element has** (spec §4 "Lowerer-carried decisions" row: `decl_local.type_id` / tuple element types are semantic LIR facts), and the identical rule lives in sema (S1/S2 — `semantic_analyzer.zig` is outside the P6-pre touch set). The P6-pre brief names `lowerExactIntArg`/lowering's **carrier** derivation; C2/C3 materialize an untyped const VALUE into a runtime slot (the C carrier), while S1–S3 type a NAMED binding. S3 stays on the semantic primitive (`ce_mod.comptimeIntUntypedType`) exactly like S1/S2.

**Spelling (kept — C syntax surface / typedef-name application; legitimate per plan Global Constraints):**
`intLitSuffixUns` `c89_emit.zig:3855` / `intLitSuffixNeg` `:3861` (value-keyed literal suffix), `writeIntConstRvalue` `:3692` (decimal/hex + suffix given a carrier), `getCTypeName`→`typeCName` (typedef-name application). The `c89_emit.zig:4553-4571` comment (I.0) is updated by the implement step.

### I.2 Derivation-equivalence argument (why the planner reproduces every carrier exactly)

**Inputs available on LIR/const types today** (per the brief: work from whatever semantic facts exist today; P6 will add explicit width/signedness fields): the const's **result temp semantic type** (`hoisted_temps[].type_id` — width/signedness for typed consts; `integer_literal_type`/`undefined_type` for untyped) + the const's **value** (`int_const.value: u64`). P6-pre gains no LIR fields.

**Decision-identity target:** the carriers **lowering chose** (C2/C3's `comptimeIntUntypedType` result — the const's semantic width/signedness, bijective with i32/u32/i64/u64) **and** the carriers **the emitter's C4 derived at spell time**. The planner must produce both, unchanged.

**Why the derivation cannot be re-run from value alone (evidence — the sign collision):** an untyped exact integer is materialized as `int_const.value = ciToU64(v)` (two's-complement u64). Two distinct exact values share one pattern: `0 - 3000000000` (ComptimeInt −3000000000 → `0xFFFFFFFF4D9F2FFF`) and the literal `18446744070697051616` (ComptimeInt +18446744070697051616 → the same u64). Zig/Z98 prints `-3000000000` for the first and `18446744070697051616` for the second (Finding-1's own test pair `18446744073709551615` / `0 - 3000000000` is the same phenomenon). C2/C3 distinguish them by deriving **signed** vs **unsigned** carriers from the sign of the `ComptimeInt` — recorded on LIR as the materialization temp's semantic type (i64 vs u64). No derivation from `(integer_literal_type, u64)` can recover that sign; therefore the full "temp keeps `TYPE_INT_LIT`, planner derives from value only" variant would change carriers (and printed output) for negative exact values and is **impossible before P6's explicit signedness fields** (out of P6-pre scope by the brief). The planner therefore derives **from the const's semantic type + value** — exactly the inputs the brief names ("the LIR const's type/width/signedness/value semantics").

**The derivation the planner owns (moved from C4):** `deriveConstCarrier(reg, semantic_tid, value)` — verbatim C4 rule text (case-split: `integer_literal_type` → value-rule `I32/U32/U64` at the historical thresholds `2^31`/`2^32`; `TYPE_UNDEFINED` → `TYPE_USIZE`; else identity). C4 is DELETED from `c89_emit.zig` (0 call sites remain).

**Side-table completeness under the emit-time LIR opt (why the table can be filled at the boundary without running `lirOptRun` there):** `lirOptRun` (`lir_opt_pass.zig:2057`) runs inside `emitFunctionSet` (`c89_emit.zig:2256`) on the faulted-in fn copy and mutates it **in place only** (all rewrites assign `bb.insts.items[ii]`; no inst insert/delete — grep evidence: every mutation is `items[ii] = ...` or field rewrites). Hence `(bb_idx, inst_idx)` positions are **stable** across the opt. Post-opt `int_const` insts arise from exactly two rewrites:

1. **Const fold** (`runConstFold` `lir_opt_pass.zig:1993-2050`): `binary`/`unary`/`int_cast` at `(bb,ii)` → `int_const{value, result}` with the SAME result temp. Gate `resDeclIntType`/`constOperandIntType` (`:1714-1744`) requires a **concrete** integer hoisted type — `intKindWidth` (`:200-206`) returns 0 for `integer_literal_type`/`undefined_type`/arb kinds, so folded consts never land on untyped temps, and for concrete types C4's rule is value-independent identity.
2. **Arg-slot / join copy coalescing** (`coalesceArgCopies:1533`, `coalesceJoinCopies:1630`): `retargetDefResult` (`:1473`) rewrites a pure producer's **result id** in place (same `(bb,ii)`). The gate requires `dt == st` (`:1581`, `:1667`-region) — the target's hoisted type is **identical** to the producer's — so `deriveConstCarrier(hoisted, value)` is retarget-invariant.

Therefore: fill the table at the boundary for every inst of kind `int_const`/`binary`/`unary`/`int_cast` (exactly the kinds that are/become consts) keyed by `(fn, flattened (bb,ii) ordinal)` with `deriveConstCarrier(hoisted(result), value-or-0)`. At emit time every post-opt const's `(bb,ii)` has a table entry equal to what C4 would have computed at that site. Value-stability: the opt never rewrites `int_const.value` (rewrites touch operands/result only). Per-CONST (not per-temp) keys are required: join coalescing can retarget **two** arm consts onto one join temp (one per arm block), and C4 is a per-const derivation (the temp declaration then takes the last writer's rule in the written-type walk) — a per-temp key cannot represent both spellings.

**Const-id encoding:** `fn_key = LirSlot.disk_offset` (unique per fn across the `lir_slots` regrouping at `main.zig:1437-1485` — the permutation preserves slot contents; set on the emitter at `emitFunctionSet` fn entry where the slot is in scope) + `inst_ord = Σ blocks[0..bb].insts.len + ii` (flat, stable, no bit-packing limits). Per-fn `U32ToU32Map` (the brief's example shape) keyed by `inst_ord`.

**C2/C3 relocation (the i32/u32/i64/u64 choice out of `lowerExactIntArg`/lowering):** the derivation entry moves to `c89_plan.untypedIntCarrier` (the C-carrier derivation for untyped exact ints; delegates the width/signedness semantics to the shared `ce_mod` primitive that sema's S1/S2 use). `lower.zig` keeps zero carrier-rule code: C2/C3 consume the planner entry and record the result as the const's semantic width/signedness on the temp (spec §4 "Lowerer-carried decisions": `int-const semantic width/signedness` — the semantic fact P6 will make an explicit LIR field; the C typedef carrier is derived from it by `deriveConstCarrier` at the boundary and read by the emitter only from the side table). The >64-bit `error[3000]` diagnostic path stays in lowering (diagnostics are lowering-owned; unchanged).

**Decision-identity conclusion:** every carrier the emitter applies = table[fn, ord] = `deriveConstCarrier(semantic, value)` = C4's historical output at that site (byte-identical by construction — same rule text, same inputs); every carrier lowering chose for C2/C3 = `untypedIntCarrier` = the same `comptimeIntUntypedType` values (same rule, new home). Pins 0/8 expected; emitted-C byte-identity expected.

### I.3 Precise edit plan (touch set — anything outside STOP/BLOCKED)

1. **`sf/src/c89_plan.zig` (NEW)** — C-specific pre-emit spelling planner:
   - `pub const C89SpellPlan` — side-table state on the permanent/emission arena: per-fn `U32ToU32Map` (const `inst_ord` → carrier tid) + `fn_keys` (`disk_offset` per planned fn). P12 later adds the typedef order to this same struct; P11 the cast-direction state.
   - `pub fn deriveConstCarrier(reg, semantic_tid, value) u32` — the moved C4 rule.
   - `pub fn untypedIntCarrier(v: ce_mod.ComptimeInt) ?u32` — the C-carrier derivation entry for untyped exact ints (C1's rule; consumed by C2/C3).
   - `pub fn spellInstOrd(lir_fn, bb_idx, ii) u32` — const-id ordinal encoding.
   - `pub fn spellPlanInit` / `pub fn spellPlanPlanFn` — boundary fill (no markers; `--markers` stream stays byte-identical).
   - `pub fn spellPlanCarrier(plan, fn_key, inst_ord) ?u32` — emitter read.
2. **`sf/src/main.zig`** — `CompilerContext` gains `spell_plan: c89_plan.C89SpellPlan` (next to `emission_classif`, same boundary mechanism); `phase_EmissionClassification` (`:1212`) gains the planner step (fill during its LIR walk; still no markers); `phase_C89Emission` passes `&ctx.spell_plan` to `c89EmitterInit`.
3. **`sf/src/c89_emit.zig`** — `C89Emitter` gains `plan: *c89_plan.C89SpellPlan` + `plan_fn_key: u32` (set per fn in `emitFunctionSet` from the slot's `disk_offset`); DELETE `intConstTypeForValue` (`:3866-3873`) and its 3 call sites (`:2597`, `:3495`, `:6922`) → side-table reads (`spellPlanCarrier`); `nestEmitDefRvalue` carries the def loc from `emitValueExpr`; `emitInst` carries `(bb_idx, inst_idx)` from its single caller (`emitFunctionBody:8372`). Suffix/spelling helpers unchanged. Comment at `:4553-4571` updated.
4. **`sf/src/lower.zig`** — C2 (`:1660`) and C3 (`:3618`) call `c89_plan.untypedIntCarrier` (comptime-int primitive no longer referenced at carrier sites). S3 (`:8311`) stays on `ce_mod` (semantic binding typing, as S1/S2). `lir.zig` untouched (no carrier-flavored fields exist on `int_const` — `{value, result}` is semantic facts only; no reduction needed).
5. **`sf/docs/tech_docs/`** — `INDEX.md` Table A (Function → File Index) rows for the new module (`deriveConstCarrier`, `untypedIntCarrier`, `spellPlanCarrier`, `spellPlanPlanFn`, `spellPlanInit`, `spellInstOrd`, `C89SpellPlan`) + annotation of the deleted `intConstTypeForValue` rows; `07_lir_lowering.md` + `08_c89_emission.md`/`09_pipeline_orchestration.md` `[updated: 2026-10-12 — P6-pre …]` on changed sections.

Expected touch set matches the brief: `sf/src/c89_plan.zig` (new), `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`, `sf/docs/tech_docs/` (`INDEX.md` Table A + `[updated: 2026-10-12]`). `sf/src/lir.zig` not needed (see 4). Nothing outside.

---

## Implement (one compiler-moving commit)

Per the I.3 edit plan; `edit`/`fastedit` only (X.7); no scripted/bulk transforms (X.3).

### `sf/src/c89_plan.zig` (NEW — the C-specific pre-emit spelling planner)

- `pub const C89SpellPlan` — side-table state (permanent arena): `fn_keys` (per planned fn, its LIR spill slot offset) + `fn_maps` (per fn a `U32ToU32Map`: flattened inst ordinal → planned carrier tid) + `fn_count`/`fn_cap`. P12 adds typedef-order state to this same struct; P11 the cast-direction state (same boundary mechanism).
- `pub fn deriveConstCarrier(reg, semantic_tid, value) u32` — THE carrier derivation, the verbatim relocated `intConstTypeForValue` rule (`integer_literal_type` → `I32/U32/U64` at the historical `2^31`/`2^32` thresholds — no i64 arm; `TYPE_UNDEFINED` → `TYPE_USIZE`; else identity).
- `pub fn untypedIntCarrier(v: ce_mod.ComptimeInt) ?u32` — the i32/u32/i64/u64 carrier derivation entry for untyped exact ints (the rule moved OUT of `lowerExactIntArg`/lowering; delegates the width/signedness semantics to the shared `ce_mod.comptimeIntUntypedType` primitive sema's binding typing also uses).
- `pub fn spellInstOrd(lir_fn, bb_idx, ii) u32` — const-id ordinal (flattened inst position; stable across the emit-time `lirOptRun`).
- `pub fn spellPlanInit` / `pub fn spellPlanPlanFn` / `pub fn spellPlanCarrier` — boundary fill + spell-time read. Fill covers inst kinds `int_const`/`binary`/`unary`/`int_cast` (exactly the kinds that are — or after the emit-time const-fold / copy-coalescing rewrites become — `int_const`s; see I.2). No marker traffic.

### `sf/src/main.zig`

- `CompilerContext` gains `spell_plan: c89_plan.C89SpellPlan` (beside `emission_classif`; placeholder-local init per the struct-literal rule).
- `phase_EmissionClassification` (`:1212`) gains the planner step: `c89_plan.spellPlanInit(&ctx.spell_plan, &ctx.alloc.permanent, ctx.lir_slots.len)` + `c89_plan.spellPlanPlanFn(..., ctx.lir_slots.items[ec_fi].disk_offset, &ec_fn)` inside its existing LIR walk (still no markers — the `--markers` stream stays byte-identical).
- `phase_C89Emission` passes `&ctx.spell_plan` to `c89EmitterInit` (new parameter after `classif`).

### `sf/src/c89_emit.zig`

- `C89Emitter` gains `plan: *c89_plan.C89SpellPlan` + `plan_fn_key: u32` (the current fn's LIR spill slot offset; set at fn entry in `emitFunctionSet` from `fn_slots[fn_slots_start + i].disk_offset` — unique per fn, stable across the `lir_slots` regrouping at `main.zig:1437-1485`).
- `intConstTypeForValue` (`:3866-3873`) **DELETED** (the emit-time deciding helper; rule text now lives in `c89_plan.deriveConstCarrier`). New `planConstCarrierAt(emitter, bb_idx, ii, semantic_tid)` = the spell-time READ (`spellPlanCarrier` by (fn_key, ordinal)); miss fallback = the const's semantic type (a LIR fact; unreachable per I.2's population proof).
- The 3 consumption sites rewired: written-type inference (`:2597`→`:2610`, has `(bb_idx, ii)` in its walk), `nestEmitDefRvalue` `.int_const` (`:3495`→`:3508`; the def loc `(def_bb, def_ii)` is threaded from `emitValueExpr`'s `lirOptNestDefLoc`), `emitInst` `.int_const` (`:6922`→`:6943`; `emitInst` gains `inst_bb`/`inst_ii` from its single caller `emitFunctionBody:8385`).
- Kept spelling: `writeIntConstRvalue` (`:3705`), `intLitSuffixUns`/`intLitSuffixNeg` (value-keyed literal suffix = C syntax surface). The `:4579` comment (Finding-1/print routing) updated to name the planner.

### `sf/src/lower.zig`

- `lowerExactIntArg` (`:1664`) and `lowerFoldedIntConst` (`:3622`) now call `c89_plan.untypedIntCarrier` — lower.zig keeps zero carrier-rule code. The materialization temp records the semantic width/signedness (spec §4 "Lowerer-carried decisions"; P6 adds explicit fields). The `error[3000]` diagnostic paths unchanged.
- `:8315` (unannotated local binding slot type) stays on `ce_mod.comptimeIntUntypedType` — semantic binding typing (I.1 S3; same rule class as sema's S1/S2; not a const carrier).
- `sf/src/lir.zig` untouched — `int_const {value: u64, result: u32}` is semantic facts only (no carrier-flavored spelling recorded → no reduction needed; ruling (ii) satisfied: carriers are planner-side, never LIR fields).

### `sf/docs/tech_docs/`

- `INDEX.md` Table A rows added (alphabetical): `deriveConstCarrier` (c89_plan), `planConstCarrierAt` (c89_emit), `spellInstOrd`/`spellPlanCarrier`/`spellPlanInit`/`spellPlanPlanFn` (c89_plan), `untypedIntCarrier` (c89_plan); `lowerExactIntArg` row annotated (P6-pre relocation).
- `07_lir_lowering.md` / `08_c89_emission.md` / `09_pipeline_orchestration.md`: title-line `[updated: 2026-10-12 — P6-pre …]` (newest-first) + the rule/field/flow notes (`lowerFoldedIntConst`/FB2 carrier texts → `c89_plan.untypedIntCarrier`; emitter field-table rows `plan`/`plan_fn_key`; `CompilerContext` row `21b spell_plan`; phase-10 diagram line + the producer/consumer table row).

### Derivation-equivalence evidence (beyond the battery)

Carrier-sensitive probe (`/tmp/opencode_p6pre/probe/main.zig`: Finding-1 pairs `18446744073709551615` / `0 - 3000000000`, the `2^32..2^63` i64-vs-u64 divergence window `9223372036854775807` / `9223372036854775808` / `5000000000`, untyped folds `2000000000 + 1000000000`, unannotated/annotated decls, if-join arms), dumped with the P6-pre compiler vs the Task-0-era binary:

```
$ diff <(grep -o 'z[a-zA-Z0-9_]* t[0-9]* = [^;]*;' OLD.c) <(grep -o 'z[a-zA-Z0-9_]* t[0-9]* = [^;]*;' NEW.c)
→ empty (CONST SPELLINGS IDENTICAL)
$ diff <(sort OLD.c) <(sort NEW.c)
→ empty (LINES IDENTICAL UP TO ORDER)
```

The only textual delta vs the Task-0-era binary is 3 typedefs' positions (the recorded P2 ordering change — expected vs a pre-P2 binary). The spellings preserve every historical carrier exactly, e.g. `printU32((unsigned int)(3000000000u))` (u32), `printU64((zT_u64)(18446744073709551615ULL))` (u64), `printI64((zT_i64)((zT_i64)-3000000000LL))` (i64 negative), `printI64((zT_i64)(9223372036854775807ULL))` (i64 carrier + value-keyed `ULL` suffix — the historical mix), `zT_8 = 5000000000ULL` (plain-literal u64 value-rule) vs `zT_10 = 3000000000u` (folded untyped u32).

---

## Runtime battery (FULL; every claim = command + observed output)

Compiler: `/tmp/opencode_p6pre/s1/zig1_5_clean` from
`FIXED_POINT_MD5=9ced323b892fa3e1bc4eb0b1598a416a bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/opencode_p6pre/s1` (repo root).

### 1. Seed rebuild + two-hop closure

```
[seed] hop2 binary md5: a5e7c03341f014cba52936157f92fdfa
[seed] two-hop closure OK: hop1 == hop2 == a5e7c03341f014cba52936157f92fdfa
error: fixed-point mismatch: got 'a5e7c03341f014cba52936157f92fdfa', want '9ced323b892fa3e1bc4eb0b1598a416a'
```

Fixed point `9ced323b892fa3e1bc4eb0b1598a416a` → **`a5e7c03341f014cba52936157f92fdfa`** (moved — `sf/src` changed; **hop1==hop2 proven**). The `FIXED_POINT_MD5` gate mismatch is the recorded delta (compiler-moving change; seed not rotated — closeout-only).

### 2. Corpus classify (vs frozen Appendix A)

```
$ bash scripts/corpus/classify /tmp/opencode_p6pre/s1/zig1_5_clean /tmp/opencode_p6pre/corpus_p6pre.txt
wrote /tmp/opencode_p6pre/corpus_p6pre.txt: 1124 dirs
$ md5sum /tmp/opencode_p6pre/corpus_p6pre.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/opencode_p6pre/corpus_p6pre.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff /tmp/task0_work/corpus_baseline.txt /tmp/opencode_p6pre/corpus_p6pre.txt
→ empty (DIFF EMPTY (byte-identical))
$ awk '{print $2}' … | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
```

**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical to frozen Appendix A. 0 class movers.**

### 3. Runtime goldens (5 md5s, byte-identical)

Build (Task 0 §1.3 recipe): `zig1_5_clean --dump-c89 examples/z98/<e>/main.zig > gold/<n>.c` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include gold/<n>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o gold/<n>` — all 4: dump rc=0, gcc rc=0, 0 `error:` (line counts 13924/19277/15596/14789 — identical to the P3/P4 record).

| golden | command | observed md5 | frozen | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | YES |
| json | `cd examples/z98/json_parser && timeout 60 gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh gold/mud srv.out cli.out` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0ab…` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f…` | YES |

**5/5 byte-identical.**

### 4. mi_matrix runtime anchors (25 + oob)

Anchor set re-enumerated by the frozen definition (non-`stdlib_*` ∧ non-empty `expected.txt` ∧ `expected.rc=0`) → **25**. Harness: `bash scripts/stdlib/run_fixtures.sh /tmp/opencode_p6pre/s1/zig1_5_clean <the 25 dirs>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`**.

Trap fixture (`-fsafe`): `slice_index_field_store_oob_xmod` — dump rc=0, build rc=0, **run rc=133** (Trace/breakpoint trap), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` md5. **MATCH.**

### 5. `examples/z98/*/` matrix (26 build + 26 run)

Build per dir (`zig1_5_clean -ffast -o matrix/<n> <entry>` + `sh build_target.sh linux matrix/<n>/prog`; entry resolution `main.zig` → `<dirname>.zig` → first `*.zig`): **26/26 dump=0 / ≥1 `.c` / build=0**; per-dir `.c` counts identical to §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38).

Run per dir (CWD = example dir, `timeout 25` except mud_server 8; stdin `/dev/null` except rogue* `q\n`): **26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table** — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`.

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/opencode_p6pre/s1/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

### 7. The 8 `--dump-c89` pins (old → new; record only)

Command per row: `zig1_5_clean <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

| entry | mode | old (P2-recorded = P3/P4, `9ced323b…`) | P6-pre (`a5e7c033…`) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical** (the relocation is carrier-identical, as expected).

### 8. `--markers` telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 marker lines / 38,378 B** — **identical counts to the P2/P3/P4 record** (3,436 / 38,378). The boundary planner step emits no markers by design.

Observation (pre-existing, NOT a P6-pre delta): the C written to stdout under `--markers` differs from the no-marker dump (15,569 vs 13,924 lines) — reproduced identically on the Task-0-era binary (`52c5feb5…` plain vs `e02b4de4…` with markers), i.e. marker instrumentation alters name-minting side effects; the gate for this task is the marker stream + the no-marker pins, both unchanged.

---

## Observations (report-only; not fixed, per no-unrelated-fixes)

- **O1:** `writeIntConstRvalue`'s literal suffixes stay **value-keyed** (`intLitSuffixUns/Neg`), not carrier-keyed — deliberate (historical bytes; C syntax surface). A carrier-keyed suffix (`5u` vs `5`) would move bytes for zero correctness gain.
- **O2:** the historical per-site hoisted-type lookup semantics differ slightly (`hoistedTypeOf` skips UNDEFINED-typed entries; the written-type pass reads the raw entry; `emitInst` defaults the 0/absent result to USIZE). For UNDEFINED-hoisted consts the nest path historically spelled with type 0 while the other two used USIZE — `writeIntConstRvalue` produces identical bytes for both (unsigned nonneg path + value-keyed suffix). The plan records `deriveConstCarrier(raw hoisted)` (USIZE for UNDEFINED), byte-compatible with all three sites (see report body).
- **O3:** `lirOptRun` running inside `emitFunctionSet` (post-boundary) is what makes the boundary see pre-opt LIR; the I.2 population proof (in-place rewrites, fold gate `intKindWidth != 0`, retarget `dt == st`) is what makes the side table complete without moving the opt. If a future opt rewrite ever inserts/inst-moves instructions or relaxes those gates, the table must be re-evaluated (P12's move of related machinery should keep this invariant in mind).
- **O4:** the `--markers` stdout C divergence (see battery item 8) is pre-existing (Task-0 binary reproduces it).

## Concerns

1. **Residual application site at lowering (documented, by necessity):** `lowerExactIntArg`/`lowerFoldedIntConst` still *apply* `c89_plan.untypedIntCarrier` to type the materialization temp (the const's semantic width/signedness). The derivation RULE lives in the planner and lower.zig keeps zero carrier-rule code; but the *call* remains at lowering time because today's LIR records the untyped int as a two's-complement u64 whose sign is unrecoverable at the boundary (I.2 sign-collision evidence) — P6's explicit semantic width/signedness fields are what would allow the application site to move too. Pins 0/8 prove the relocation is carrier-identical.
2. **Per-const keys vs per-temp:** the side table is keyed by inst ordinal (not result temp) because join copy coalescing can retarget two arm consts onto one temp with per-const carriers; the chosen encoding relies on the I.2 rewrite-stability properties of `lirOptRun` (observation O3).
3. **Typedef-ordering residue (NOT ours):** the probe-vs-Task-0 ordering delta is the recorded P2 change; P12 (typedef ordering planning) is the designated owner of ordering state in `C89SpellPlan`.

---

## Fix round 1

**Status:** DONE_WITH_CONCERNS (battery all green — pins 0/8, emitted-C byte-identical, hop1==hop2; one plan-internal verification-grep tension documented under Observations O5 — no edit-site deviation). Tree anchor `d0e5f451`; `sf/src/lir.zig:74` (plan §1.1) was already applied pre-dispatch and verified at start. Touch set: `sf/src/{lir,lower,c89_plan,c89_emit}.zig` + `sf/docs/tech_docs/` only. Tool channel: healthy after system reset — every source/doc change was one `edit` call at one site (read-before-edit; the 50 sibling rewrites bottom-to-top); **no shell fallback used, no bulk transforms**.

### Applied-vs-plan (verbatim; deviations NONE at edit sites)

| plan site | applied |
|---|---|
| §1.1 `lir.zig:74` `int_const: {value, result, width_bits, is_signed}` | pre-applied, verified (`sed -n '60,90p'`) |
| §1.2 `lowerUntypedIntFacts` + §1.3 `emitIntConstFacts`/`emitIntConst` | inserted above `foldPrintArgIntExact` (insert = anchor line -> new + original) |
| §1.3 50 sibling sites -> `emitIntConst(self, X, Y);` | 50 one-line rewrites (lines 678…8690 as planned; text-identical lines disambiguated by context, one site per `edit`) |
| §1.3 Class B 2 sites (1670/3635) | fact recording `emitIntConstFacts(..., fw, fs)` (in the §3.1/§3.2 bodies) |
| §3.1 `lowerExactIntArg` body + comment | replaced verbatim (§3.1 body; FB2 comment -> fact-recording wording) |
| §3.2 `lowerFoldedIntConst` body + comment | replaced verbatim (§3.2 body; "Untyped slots record the exact value's semantic width/signedness on the int_const; the planner derives the C carrier at the boundary") |
| §3.3 `foldPrintArgIntExact` comment + `c89_plan` import deletion | comment -> fact-recording wording (no rule names); `const c89_plan = @import(...)` deleted |
| §2.1 `carrierFromFacts` + `deriveConstCarrier(..., width_bits, is_signed)` | verbatim (value-rule text `:45-47` preserved inside) |
| §2.1 delete `untypedIntCarrier` + `ce_mod` import | deleted (0 callers remain) |
| §2.2 fill call + `.int_const` arm reads `ic.width_bits`/`ic.is_signed`, other kinds 0/0 | verbatim |
| §4.1 `d4_fcar` (field/init/alloc 4*max_temp sentinel 0xFFFFFFFF) + written-type `.int_const` arm fill gate (`width_bits != 0` ∧ `TYPE_INT_LIT` hoisted) | verbatim |
| §4.2 `factCarrierOfTemp` + `nestScalarEffTid` fact-carrier read | verbatim (read AFTER the kind-whitelist attempt) |
| §4.3 `.print_val` `route_tid` + Task-2 comment | verbatim (comment names the fact-carrier read) |
| §6.1.5 tech docs | INDEX.md Table A: 5 rows updated (`deriveConstCarrier`, `lowerExactIntArg`, `lowerFoldedIntConst`, `spellPlanPlanFn`, `untypedIntCarrier` -> **deleted (P6-pre fix round 1)**) + 5 rows added alphabetically (`carrierFromFacts`, `emitIntConst`, `emitIntConstFacts`, `factCarrierOfTemp`, `lowerUntypedIntFacts`); `07_lir_lowering.md`/`08_c89_emission.md`/`09_pipeline_orchestration.md` title-line `[updated: 2026-10-12 — P6-pre fix round 1 …]` newest-first + fact-fields/derivation/route notes (08 carries the O3 sentence verbatim) |

### Semantic-facts design + sign-collision resolution

`int_const` = `{value: u64, result: u32, width_bits: u8, is_signed: u8}` (facts only; ruling (ii): no carrier fields). `width_bits == 0` = no untyped-materialization width chosen (typed const — its carried result type holds the semantics — or bare untyped literal whose carrier the planner's historical value rule picks); `width_bits != 0` = untyped exact-value materialization, the facts are the semantic width/signedness. Sign-collision disambiguation (report I.1/I.2 evidence, re-verified in the probe):

| expression | ComptimeInt | u64 pattern | facts | carrier |
|---|---|---|---|---|
| `0 - 3000000000` | −3000000000 | `0xFFFFFFFF4D9F2FFF` | (64, 1) | i64 |
| literal `18446744070697051616` | +18446744070697051616 | `0xFFFFFFFF4D9F2FFF` | (64, 0) | u64 |

Recorded at lowering by `lowerUntypedIntFacts` (fit-query order I32/U32/I64/U64 = exactly `comptimeIntUntypedType`'s classes, queried through `comptimeIntFitsType`); the planner turns facts -> carrier at the boundary; the emitter applies from the side table / `d4_fcar`. After this fix: ZERO carrier-rule application in any lowering materialization site.

### §2.3 Derivation-equivalence proof (every class -> exactly the previously chosen carrier)

| class | hoisted type at the boundary | facts | old carrier (P6-pre) | new carrier |
|---|---|---|---|---|
| Class B: untyped exact materialization, neg `|v| ≤ 2^31` / nonneg `v < 2^31` | TYPE_I32 (carrier-typed temp) → identity | (32, 1) | TYPE_I32 | TYPE_I32 (`carrierFromFacts`) |
| Class B: nonneg `2^31 ≤ v < 2^32` | TYPE_U32 → identity | (32, 0) | TYPE_U32 | TYPE_U32 |
| Class B: neg `2^31 < |v| ≤ 2^63` / nonneg `2^32 ≤ v < 2^63` | TYPE_I64 → identity | (64, 1) | TYPE_I64 | TYPE_I64 |
| Class B: nonneg `2^63 ≤ v < 2^64` | TYPE_U64 → identity | (64, 0) | TYPE_U64 | TYPE_U64 |
| Class B: outside 64-bit | (no const; error[3000] dummy) | — | — | unchanged diagnostic |
| Class A: bare untyped literal (`lower.zig:4228` path) / `@asyncFrameSize` | TYPE_INT_LIT | (0, 0) | value rule I32/U32/U64 | same value rule (text preserved) |
| typed consts (all siblings, async, fold-produced) | concrete | (w,s) or indeterminate | identity | identity (facts NOT read — hoisted-kind gate) |
| TYPE_UNDEFINED hoisted | TYPE_UNDEFINED | — | TYPE_USIZE | TYPE_USIZE (unchanged) |

(Post-fix hoisted type of a Class B materialization is `TYPE_INT_LIT`; the table's middle column is the P6-pre class the rule was derived from. The i32-legacy gate becomes `fw == 32 and fs == 1` — identical class set.)

### Verification greps (observed output)

§3.4 invariant (plan expects EMPTY; paste refreshed by fix round 2 minor 2 — the fix-round-1 paste predated the doc-sweep comment additions in `0dc52ea6`/`355c8827` and the `:8351` cite drifted to `:8356`):

```
$ grep -n "untypedIntCarrier\|comptimeIntUntypedType\|deriveConstCarrier\|intConstTypeForValue\|c89_plan" sf/src/lower.zig
1626:// exactly `ce_mod.comptimeIntUntypedType`'s (comptime_eval.zig:1382-1397),
1845:                        // carrier is derived by c89_plan.deriveConstCarrier at
6988:                    // derived by c89_plan.deriveConstCarrier at the
8356:                        if (ce_mod.comptimeIntUntypedType(iv.v)) |ut| { decl_type = ut; }
```

NOT empty — see observation O5. All four lines are non-application mentions: `:1626` is the plan's own §1.2 helper doc-comment text (inserted verbatim — it names the historical window function as documentation), `:1845`/`:6988` are the fix-round-1 O6 truth-up call-site comments (they name `c89_plan.deriveConstCarrier` as the boundary mechanism — documentation of the live path), `:8356` is S3 (semantic unannotated-binding slot typing; report I.1 explicitly blesses it on `ce_mod`, and the plan's edit lists never include it). Every carrier-rule APPLICATION is gone from lowering (`untypedIntCarrier`/`c89_plan`/`deriveConstCarrier`/`intConstTypeForValue` as code: 0 hits).

§6.1.6 width_bits grep (observed): `lir.zig:74` (payload); `lower.zig:1638-1639` (`emitIntConstFacts`); `c89_plan.zig:31/33/34/42/48/129` (`carrierFromFacts`/`deriveConstCarrier`/fill); `c89_emit.zig:2618` (d4_fcar fill gate) + `:3211` (factCarrierOfTemp doc) — plus pre-existing unrelated `width_bits` locals in `writeIntConstRvalue`/sat-bound helpers.

§5.2/§5.3 indeterminate-facts check (named; out-of-touch-set residue):

```
$ grep -c "int_const = \." sf/src/async_state_machine.zig sf/src/lir_opt_pass.zig
sf/src/async_state_machine.zig:24
sf/src/lir_opt_pass.zig:3
$ grep -n "int_const = \." sf/src/lir_opt_pass.zig
2021: ... LirInst{ .int_const = .{ .value = v, .result = b.result } };
2034: ... LirInst{ .int_const = .{ .value = v, .result = u.result } };
2042: ... LirInst{ .int_const = .{ .value = v, .result = ic.result } };
$ grep -c "TYPE_INT_LIT" sf/src/async_state_machine.zig
0
```

The 24 + 3 out-of-touch-set constructions leave `width_bits`/`is_signed` indeterminate (contract touch set excludes those files; §5.3). SAFE by the read gates: the planner reads facts only for `integer_literal_type`-hoisted consts with `width_bits != 0` (`c89_plan.zig:44/48` — fold gate `intKindWidth ≠ 0` keeps folded consts concrete-hoisted) and the emitter's `d4_fcar` fill requires `width_bits != 0` ∧ `TYPE_INT_LIT` (`c89_emit.zig:2618`); `async_state_machine.zig` has 0 `TYPE_INT_LIT` (all async result temps typed). Self-host safety: fields copied/serialized, never semantically consumed there → hop1==hop2 garbage-independent (proven by the battery). **CORRECTION (fix round 2, Important 1 — re-true'd):** this paragraph's airtightness claim was FALSE as stated — the `grep -c TYPE_INT_LIT` verification tested CONSTRUCTION sites only and missed the `remapInst` COPIER (`async_state_machine.zig:352`), which dropped the facts of remapped USER-body consts whose hoisted temps stay `TYPE_INT_LIT` — the gates then read indeterminate values (empirically harmful: the confirmer in `## Fix round 2`). The gate audit is extended to COPY sites and re-true'd in `## Fix round 2` (every producer AND copier enumerated). O3 (verbatim, kept for P12): "lirOptRun running inside emitFunctionSet (post-boundary) is what makes the boundary see pre-opt LIR; the I.2 population proof (in-place rewrites, fold gate intKindWidth != 0, retarget dt == st) is what makes the side table complete without moving the opt. If a future opt rewrite ever inserts/inst-moves instructions or relaxes those gates, the table must be re-evaluated (P12's move of related machinery should keep this invariant in mind)."

### §6.3 Decision-identity probe (OLD = `a5e7c033…` P6-pre binary, NEW = fix binary)

Probe = Finding-1 pairs `18446744073709551615` / `0 - 3000000000`; i64/u64 window `9223372036854775807` / `9223372036854775808` / `5000000000`; untyped fold `2000000000 + 1000000000`; unannotated/annotated decls; if-join arms (`/tmp/opencode_p6pre/probe/main.zig`).

```
$ /tmp/opencode_p6pre/s1/zig1_5_clean --dump-c89 probe/main.zig > probe/OLD.c   # rc=0
$ /tmp/p6fix1/s1/zig1_5_clean   --dump-c89 probe/main.zig > probe/NEW.c   # rc=0
$ diff <(grep -o 'z[a-zA-Z0-9_]* t[0-9]* = [^;]*;' OLD.c) <(grep -o 'z[a-zA-Z0-9_]* t[0-9]* = [^;]*;' NEW.c)
→ empty (CONST SPELLINGS IDENTICAL)
$ diff <(sort OLD.c) <(sort NEW.c)
→ empty (LINES IDENTICAL UP TO ORDER)
$ diff OLD.c NEW.c
→ empty (WHOLE FILE BYTE-IDENTICAL — stronger than the required pair)
```

Sign-collision evidence lines (NEW.c == OLD.c): `printU32((unsigned int)(3000000000u))`, `printU64((zT_u64)(18446744073709551615ULL))`, `printI64((zT_i64)((zT_i64)-3000000000LL))` (64,1), `printI64((zT_i64)(9223372036854775807ULL))`, `printU64((zT_u64)(9223372036854775808ULL))`, `zT_8 = 5000000000ULL;` (Class A statement shape preserved) vs `zT_10 = 3000000000u;` (folded untyped u32).

### Runtime battery (FULL; command + observed output per claim)

Compiler: `/tmp/p6fix1/s1/zig1_5_clean` from
`FIXED_POINT_MD5=a5e7c03341f014cba52936157f92fdfa bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p6fix1/s1` (repo root).

**1. Seed rebuild + two-hop closure** (frozen anchor `a5e7c03341f014cba52936157f92fdfa`):

```
[seed] hop2 binary md5: 0c2a83ebe85ff2e61216c966c2d537c5
[seed] two-hop closure OK: hop1 == hop2 == 0c2a83ebe85ff2e61216c966c2d537c5
error: fixed-point mismatch: got '0c2a83ebe85ff2e61216c966c2d537c5', want 'a5e7c03341f014cba52936157f92fdfa'
```

**hop1==hop2 proven**; fixed point `a5e7c033…` → **`0c2a83ebe85ff2e61216c966c2d537c5`** (new, recorded; compiler-moving — `FIXED_POINT_MD5` gate mismatch expected).

**2. Corpus classify** (vs frozen Appendix A baseline `/tmp/task0_work/corpus_baseline.txt`):

```
$ bash scripts/corpus/classify /tmp/p6fix1/s1/zig1_5_clean /tmp/p6fix1/corpus_fix1.txt
wrote /tmp/p6fix1/corpus_fix1.txt: 1124 dirs
$ md5sum /tmp/p6fix1/corpus_fix1.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p6fix1/corpus_fix1.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff … → empty (DIFF EMPTY (byte-identical))
$ awk '{print $2}' … | sort | uniq -c → 116 FAIL / 58 GREEN / 950 OK
```

**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical class file, 0 movers.**

**3. Runtime goldens (5 md5s):** dump+gcc per Task-0 §1.3 recipe (all dump rc=0, gcc rc=0, 0 `error:`; line counts 13924/19277/15596/14789 = record). gol `timeout 120 ./gol` rc=0 `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `printf '(+ 1 2)\n' | ./lisp` rc=0 `b3d9f8974da24ddbf9d389f3d7d97322`; json rc=0 `8bda3d5a1ec07d14a301bc343df32bf8`; mud `bash examples/z98/mud_server/demo/session.sh …` rc=0 srv `66c8f0abb926cca7baf9a0d1692ab318` / cli `93147d0f0bbd983a9d844fea8b7a6fa7`. **5/5 byte-identical.**

**4. mi_matrix anchors 25 + oob:** `bash scripts/stdlib/run_fixtures.sh /tmp/p6fix1/s1/zig1_5_clean <the frozen 25 dirs (/tmp/opencode_p6pre/mi25.list)>` → `run_fixtures: 25 PASS / 0 FAIL over 25 dirs`. Trap fixture (`-fsafe`) `slice_index_field_store_oob_xmod`: dump rc=0, build rc=0, **run rc=133** (Trace/breakpoint trap), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` md5. **MATCH.**

**5. examples/z98/*/ matrix:** build per dir (`-ffast -o`, `build_target.sh linux`) **26/26 dump=0 / ≥1 `.c` / build=0**, `.c` counts identical to §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38). Run per dir (CWD=example dir; `timeout 25`, mud 8; stdin `/dev/null`, rogue* `q\n`) **26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table** (days_in_month `8c0d394cbc6e7f36` … mud_server rc=124 `9545fe1d245293ef` … z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3` — full 26-row match).

**6. Stdlib gate:** `bash scripts/stdlib/verify_stdlib.sh /tmp/p6fix1/s1/zig1_5_clean` → `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` + `STDLIB GATE OK`.

**7. The 8 `--dump-c89` pins (old → new; P6-pre values):**

| entry | mode | old | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical.**

**8. `--markers` telemetry:** `zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 marker lines / 38,378 B** — identical to the P2-P6-pre record (planner step emits no markers).

### Observations (fix round 1; report-only)

- **O5 (plan-internal verification tension — NOT an edit-site deviation):** the §3.4 invariant greps `comptimeIntUntypedType` and expects EMPTY, but (a) the plan's own §1.2 helper doc-comment text names `ce_mod.comptimeIntUntypedType` (inserted verbatim per "execute VERBATIM"), and (b) S3 (`lower.zig:8356` after the O6 comment truth-ups; `:8351` in the fix-round-1 tree, unannotated-binding slot typing) uses it and is explicitly blessed by I.1 ("S3 stays on the semantic primitive") with no edit-site anywhere in the plan. The expected EMPTY is unreachable without out-of-plan edits (self-censoring the plan's comment, or rewriting S3 — a semantic change outside the fix's adjudicated gap). Real output pasted above; every carrier-rule application is gone.
- **O6 (stale call-site comments, left untouched by VERBATIM discipline):** `lower.zig:1814`/`:6946`-region call-site comments still say "value-chosen carrier (and a value-chosen int_const temp)" for `lowerExactIntArg`'s result; §3.3 enumerates exactly two comment-update sites (foldPrintArgIntExact + lowerFoldedIntConst) and these are not among them. Comment-only staleness; no grep-invariant token; flagged for a future doc sweep.
- **O7:** the §5.4 Class B knock-ons (`materializeShiftLhs` untyped-LHS path under `-fsafe`; `materializeInto`/`lowerArrayElemTupleCoerce` `int_literal_coerce` cast firing) produced 0 pin deltas, 0 corpus movers, 0 golden deltas — consistent with "expected 0 battery impact (narrow shape)".

## Concerns (fix round 1)

1. **O5 above** — plan-invariant tension documented; not blocking (edit sites verbatim; battery decision-identity holds: probe byte-identical, pins 0/8).
2. **Out-of-touch-set indeterminate facts** (§5.3 residue, by contract): a P6/follow-up sweep should fill `width_bits`/`is_signed` in `async_state_machine.zig`/`lir_opt_pass.zig` when those files are in scope (currently safe by the read gates; recorded in the §5.2/§5.3 grep check).

## Doc sweep (O6 + §3.4)

- **O6 truth-up (2/2):** the two stale `lowerExactIntArg` call-site comments (`sf/src/lower.zig` `:1841`/`:6983` regions — the O6 `:1814`/`:6946` regions, drifted by fix-round-1 comment insertions) now say the post-fix truth: the result records semantic int facts on its `int_const` temp; the carrier is derived by `c89_plan.deriveConstCarrier` at the `phase_EmissionClassification` boundary. Grep `value-chosen carrier` in `sf/src/lower.zig` → 0 hits (comment text only; zero behavior change).
- **§3.4 invariant line reworded:** plan `task-P6pre-fix1-plan.md` §3.4 expected grep outcome no longer claims EMPTY — it now states the accurate invariant (zero carrier-rule APPLICATIONS `untypedIntCarrier`/`deriveConstCarrier`/`intConstTypeForValue` in lowering, excluding doc-comment mentions and the blessed semantic site S3 `lower.zig:8351` unannotated-binding slot typing), closing O5's plan-internal tension.
- **No battery re-run:** comment/doc-text-only edits cannot change emission (no token reaches codegen); the fix-round-1 battery at fixed point `0c2a83ebe85ff2e61216c966c2d537c5` stands unchanged.

---

## Fix round 2

**Status:** DONE_WITH_CONCERNS (Important 1 fixed + both minors folded in; full battery green — corpus 0 movers, goldens 5/5, mi_matrix 25+oob, examples 26+26, stdlib 285/0, pins 0/8, markers identical; targeted confirmer proves the correct `printI64`/`printU64` routes; one concern = the deferred items + the pre-existing out-of-touch-set construction residue). Tool channel healthy — `edit` only, no fallback. Touch set honored exactly: `sf/src/async_state_machine.zig` (copier line only), `sf/docs/tech_docs/07_lir_lowering.md`, report/plan .md.

### Important 1 — fix (one copier line)

`remapInst`'s `.int_const` arm (`async_state_machine.zig:352`) copied only `value`/`result`; the facts of every remapped USER-body const became indeterminate while its hoisted temp kept `TYPE_INT_LIT` (`td.type_id` copy `:952-954`), so both read gates semantically consumed garbage. Fixed verbatim per the required fix:

```zig
.int_const => |x| return LirInst{ .int_const = .{ .value = x.value, .result = x.result + b.base, .width_bits = x.width_bits, .is_signed = x.is_signed } },
```

### Gate audit — every `.int_const` producer AND copier (re-true'd §5.3 airtightness)

Claim (TRUE after this fix): **no indeterminate fact is ever semantically consumed** — every `int_const` that a gate can read carries defined `width_bits`/`is_signed`, either set at construction or copied intact; residual indeterminate sites sit on temps the gates structurally cannot read. Gates (the only two fact consumers): `c89_plan.zig:44-48` (reads facts iff hoisted kind `integer_literal_type` ∧ `width_bits != 0`) and `c89_emit.zig:2618` (`d4_fcar` fill iff hoisted `TYPE_INT_LIT` ∧ `width_bits != 0`).

**Producers (constructions):**
1. `lower.zig:1639` `emitIntConstFacts` — the single lowering construction path (all 52 sites route through it or `emitIntConst`); **sets all four fields**. Gate-readable (Class B) — defined by construction.
2. `async_state_machine.zig` — 23 own-const constructions (`:221, :469, :473, :477, :492, :525, :545, :553, :566, :583, :665, :684, :686, :705, :708, :726, :853, :856, :859, :1125, :1171, :1191, :1244`); facts NOT written (indeterminate). Gate-unreadable by construction: every result temp is the async machinery's own typed temp (offsets/sizes/state counters on `TYPE_U32`/`TYPE_USIZE`-class types; the file references `TYPE_INT_LIT` zero times), so neither gate's hoisted-kind condition can hold. Residue documented (out of this fix's touch set — "the copier line only").
3. `lir_opt_pass.zig` — 3 fold constructions (`:2021` binary-fold, `:2034` unary-fold, `:2042` int_cast-fold); facts NOT written (indeterminate). Gate-unreadable: the fold gate `intKindWidth ≠ 0` requires a concrete integer hoisted type, so the result is never `TYPE_INT_LIT`/`integer_literal_type`. Residue documented (out of touch set since fix round 1).

**Copiers:**
1. `async_state_machine.zig:352` `remapInst` — **this fix** — now copies all four fields (user-body consts keep their facts through the state-machine rebuild).
2. `lir_opt_pass.zig:1476` `retargetDefResult` `.int_const` arm — whole-payload copy (`var ni = ic; ni.result = newr;`) — facts ride along (no change needed).
3. Serialization (`lir_stream.zig`/`spill_store.zig`) — byte-level `@sizeOf(LirInst)` copies — facts ride along (size-generic; fix round 1 §5.1).

The old verification (`grep -c TYPE_INT_LIT async_state_machine.zig` = 0) is retained as construction-site evidence but is NOT sufficient alone (it cannot see copy-site loss); the copy-site rows above close that hole. A future producer or copier of `.int_const` must set/copy all four fields or prove its temps are gate-unreadable.

### Targeted runtime confirmer (the reviewer's shape + the sign-collision probe)

Fixture family (`/tmp/p6fix1/confirmer/`): a suspending fn (`@asyncSuspend(null)`) whose body prints a Class B exact untyped value, driven by the `@asyncInit`/`@asyncResume` loop (async_await_xmod driver shape). PRE = fix-round-1 compiler `0c2a83ebe85ff2e61216c966c2d537c5` (remap drops facts); POST = fix-round-2 compiler `39bcb30b45df93631f9fc745f95dc1aa`.

**V1 — the reviewer's exact shape:** `std.io.print("{}", .{0 - 3000000000});` in the suspending fn (facts (64,1), sign-collision pair):

```
PRE  dump: zF_37DCE311_printI64((zT_C69B2266_i64)((zT_C69B2266_i64)-3000000000LL));   # route printI64 (garbage happened to be (64,1))
POST dump: zF_37DCE311_printI64((zT_C69B2266_i64)((zT_C69B2266_i64)-3000000000LL));   # route printI64 (facts (64,1))
PRE  run:  -3000000000    POST run: -3000000000                                       # both print the Zig value (PRE only by luck)
```

**V3 — the collision twin (deterministic PRE harm):** `std.io.print("{}", .{18446744070697051616});` (facts (64,0) — same u64 pattern as `0 - 3012500000`):

```
PRE  dump: zF_37DCE311_printI64((zT_C69B2266_i64)((zT_C69B2266_i64)-3012500000LL));   # WRONG: garbage (64,1) flipped the u64 class to i64
POST dump: zF_90B60295_printU64((zT_79FAE712_u64)(18446744070697051616ULL));          # CORRECT: facts (64,0) -> u64
PRE  run:  -3012500000                                                                # WRONG value printed (Zig prints 18446744070697051616)
POST run:  18446744070697051616                                                      # CORRECT
```

V2 (V1 + extra statements before the print) matched V1 on both compilers. The PRE mechanism (from the fix-round-1 self-emission, `gen/async_state_machine_A730A7D6.c:2565-2574`): the remap copier's emitted C assigns only `zT_444.value`/`zT_444.result` and copies the whole record — `width_bits`/`is_signed` are uninit C locals (this binary's stack shape stably reads (64,1), which is why V1 looked fine while V3 was deterministically wrong). POST is correct by construction for every class (the facts ride the copy).

### Fold-in minors

1. **Stale tech docs truth-up (`07_lir_lowering.md:345`/`:525`):** both `c89_plan.untypedIntCarrier` (deleted) mentions now name the post-fix mechanism (`lowerUntypedIntFacts` facts + `c89_plan.deriveConstCarrier`/`carrierFromFacts`; the `:525` "value-chosen carrier" phrase and its "same `comptimeIntUntypedType` value" tail reworded to facts/class-windows). Plus a fix-round-2 title-line entry (the copier fix + re-true'd audit).
2. **§3.4 paste/cites refreshed (see Fix round 1 §3.4):** the fix-round-1 paste (2 hits) predated the doc-sweep comment additions (`0dc52ea6`/`355c8827`); refreshed to the final tree's 4 hits (`:1626` helper doc-ref, `:1845`/`:6988` O6 comments naming `deriveConstCarrier`, `:8356` S3) and the S3 cite corrected `:8351` → `:8356` in the paste and O5.

### Runtime battery (FULL; command + observed output per claim)

Compiler: `/tmp/p6fix1/r2s1/zig1_5_clean` from
`FIXED_POINT_MD5=0c2a83ebe85ff2e61216c966c2d537c5 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p6fix1/r2s1` (repo root).

**1. Seed rebuild + two-hop closure** (frozen anchor `0c2a83ebe85ff2e61216c966c2d537c5`):

```
[seed] hop2 binary md5: 39bcb30b45df93631f9fc745f95dc1aa
[seed] two-hop closure OK: hop1 == hop2 == 39bcb30b45df93631f9fc745f95dc1aa
error: fixed-point mismatch: got '39bcb30b45df93631f9fc745f95dc1aa', want '0c2a83ebe85ff2e61216c966c2d537c5'
```

**hop1==hop2 proven**; fixed point `0c2a83eb…` → **`39bcb30b45df93631f9fc745f95dc1aa`** (new, recorded; compiler-moving — gate mismatch expected).

**2. Corpus classify** (vs frozen Appendix A baseline): `bash scripts/corpus/classify /tmp/p6fix1/r2s1/zig1_5_clean /tmp/p6fix1/corpus_fix2.txt` → `wrote …: 1124 dirs`; md5 `518eca1a9b5d3e1cc5a48abce214abd8` both files; `diff` empty (byte-identical); counts 116 FAIL / 58 GREEN / 950 OK. **1124 = 950/58/116/0/0 — byte-identical class file, 0 movers.**

**3. Runtime goldens (5 md5s):** dump+gcc all rc=0, 0 `error:`, line counts 13924/19277/15596/14789 (record). gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `(+ 1 2)` `b3d9f8974da24ddbf9d389f3d7d97322`; json `8bda3d5a1ec07d14a301bc343df32bf8`; mud session rc=0 srv `66c8f0abb926cca7baf9a0d1692ab318` / cli `93147d0f0bbd983a9d844fea8b7a6fa7`. **5/5 byte-identical.**

**4. mi_matrix anchors 25 + oob:** `bash scripts/stdlib/run_fixtures.sh /tmp/p6fix1/r2s1/zig1_5_clean <frozen 25 dirs>` → `run_fixtures: 25 PASS / 0 FAIL over 25 dirs`. Trap fixture `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc=0, build rc=0, **run rc=133** (Trace/breakpoint trap), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt`. **MATCH.**

**5. examples/z98/*/ matrix:** build 26/26 dump=0 / `.c` counts identical to §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run 26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table (mud_server rc=124 `9545fe1d245293ef`; z9play rc=1 `2016494de476fcb6`; z9torr rc=1 `f666af15cf2625b3`; full 26-row match).

**6. Stdlib gate:** `bash scripts/stdlib/verify_stdlib.sh /tmp/p6fix1/r2s1/zig1_5_clean` → `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` + `STDLIB GATE OK`.

**7. The 8 `--dump-c89` pins (old → new):** all eight rows DELTA=0 against the P6-pre recorded values (mud `-fsafe` `8b3c3d72ab59a9ae3c971c6a7759c7c0` / `-ffast` `fa346108ed00d03a037c2f9331d3bdf8`; gol `1b5d49b141ee9c664a82c270454bd75b` / `01a4e2265b33c97a8ca6ff3dfa551231`; lisp `8e5f2bc288d1dc75d7aee284cb35c291` / `e3970e33ac09c8dfaa316d2d69bf61ec`; json `2a12d0aac24d5bcdd694f05e04a4f029` / `24e0e812e7dffa5a43750135405ffe3f`). **Pin delta: 0/8.** Semantic argument: the fix only changes emission where a USER-body fact-carryed const is remapped into an async body (the only garbage-consumption path — proven by the confirmer); none of the four pin programs contains that shape (else the (64,0)-class would have shown PRE garbage (64,1) deltas), so 0/8 is expected and the confirmer before/after is the semantic proof for the changed class.

**8. `--markers` telemetry:** `zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig` — dump rc=0; stderr **3,436 lines / 38,378 B** — identical to the P2-P6-pre record.

### Concerns (fix round 2)

1. **Out-of-touch-set construction residue (unchanged, documented):** `async_state_machine.zig` 23 own-const constructions + `lir_opt_pass.zig` 3 fold constructions still leave the fact fields indeterminate — safe by the enumerated gate conditions (typed/concrete-hoisted temps), but a future sweep should fill them when those files are in scope (and any new `.int_const` producer/copier must satisfy the audit rule above).
2. **Deferred by operator (not addressed):** `spellPlanPlanFn`/`spellPlanCarrier` linear lookups (map before P12); `c89_emit.zig:566-568` re-indent churn; the plan-mandated §5.4 Class B disclosed item.
3. **PRE garbage was stably (64,1) for the fix-round-1 binary** — the V1 reviewer shape only *looked* correct pre-fix by stack-layout luck; other builds/classes (V3) are deterministically wrong. Anyone reading fix-round-1-era async dumps of Class B consts should treat their carrier spellings as untrustworthy.
