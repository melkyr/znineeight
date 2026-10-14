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
