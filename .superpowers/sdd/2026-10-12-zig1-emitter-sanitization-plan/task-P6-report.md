# Task P6 report — Lowerer carries decisions (semantic-only LIR)

Branch `zig1_improvements`, BASE `acda68be`. Requirements: `task-P6-brief.md` (binding, incl. Amendment 4 touch set). Shape: Investigate → Implement → Runtime battery. **Run stopped in Investigate (STOP-present, below). No source edits, no compiler-moving commit, no battery.**

## Status

**STOP-present** (brief Global Constraints format):

> I found the intention is P6's LIR records for field ordinal/name and the saturation semantic op (and the matching emitter consumption in exactly `lower.zig` + `lir.zig` + `c89_emit.zig`), but this is impossible given `async_state_machine.zig:remapInst` (`.binary` :331, `.call` :333, `.load_field` :334, `.store_field` :335, `.addr_of_field` :337, `.func_ref` :347) reconstructs those LirInst payloads **field-by-field**, so any new record field is silently dropped for every instruction of a remapped (async user-body) instruction stream — and battery item 4's own anchor `repro/mi_matrix/async_frame_structret_xmod` exercises exactly that shape (suspending `suspA`/`suspB` at `main.zig:23-24`: `p.a = p.a + 1` — pointer-base `load_field`/`store_field` in a remapped body), so the mandated 8-item battery cannot pass with the records in place, while the binding touch set ("Touch set = `lower.zig` + `lir.zig` + `c89_emit.zig` … Nothing else") forbids the copier edits that would make the records survive. The same class of gap was already a review-found real bug once in this plan (P6-pre: `remapInst` dropped `int_const` `width_bits`/`is_signed` → fix `82ff0743`, which is precisely an `async_state_machine.zig` edit).

Decision the operator must make before P6 can proceed (I do not rule — Authority: STOP-present overrides "rulings, not stalls"):

1. **Extend P6's touch set** with `async_state_machine.zig` copier-only edits (remapInst copies of the new fields + fresh-literal defaults), mirroring the P6-pre copier-fix precedent (`82ff0743`/`71979423`); or
2. **Re-scope P6** to the async-safe record subset only (callee fn type id via side tables + temp result types via `TempDecl`), deferring field-name and saturation records; or
3. Some third shape the operator has in mind (e.g. a record channel that survives `remapInst` without edits — none found, see I.3).

## Investigate (read-only; written before any source edit — no source edits happened)

Line cites re-derived by NAME at `acda68be` (plan P5-era cites stale, per brief).

### I.1 Named re-derivations in `sf/src/c89_emit.zig` — what each decides today

**`resolveFieldAccess` (c89_emit.zig:432-536).** Given `base_ty` + `field_id` + `mode` bits it decides: (a) the designator class (`.name` / `._N` / `.ptr` / `.len` / `.tag` / `.payload.<variant>._<sub>` / `->name` / `->_N`) from the base type kind + call-site mode bits; (b) the field's `name_id` + `type_id` by re-looking-up `fe_items[fields_start + field_id]` — the re-resolution of a decision lowering already made (`lowerFindFieldOrdinal` lower.zig:2222 consumes `astStoreNodePayload`'s field name → ordinal at ~30 sites); (c) existence/bounds under mode 16 (`field_id < fields_count`). Call sites (4):

| site | mode | outputs consumed |
|---|---|---|
| `emitFieldAssign` :289 | 45 (1\|4\|8\|32) | `efa_name` → `nameManglerMintField/MintMember`; `efa_tid` → pointer-field cast name + array-field copy detect |
| `.load_field` arm :6603 | 255 | designator bytes only (`lf_rname`/`lf_rtid` unused after) |
| `.store_field` arm :6642 | 495 | designator bytes; `sf_rtid` → cast name + array-copy detect |
| `.addr_of_field` arm :6790 | 736 (512\|32\|64\|128) | designator bytes only (`af_rname`/`af_rtid` unused after) |

`emitVariantFieldPayload` (shared by the payload arms, :392-427) additionally re-scans `hoisted_temps` for `src_temp`'s type to pick the variant sub-field — same re-derivation class.

**`findCalleeFnTypeId` (c89_emit.zig:1676-1691).** Linear registry scan over all `fn_type`s matching `(name_id, module_id, call_conv&FN_FLAG_STDCALL)` — recovers the callee fn type id the lowerer had in hand, so the use site can cast to the `FS_…` typedef. Call sites (2): `.call_direct` arm :7185, direct-`.tail_call` arm :7325. (`tempFnTypeId` :1695 — the `.func_ref` arm :7842 — is in the `getTemp*` consumer family instead.)

**`getTemp*` / `hoisted*` family.** What each decides:

| helper | decision it makes today |
|---|---|
| `getTempTypeByIndex` :719 | first `hoisted_temps` match by `temp_id` (record-shaped read; no fallback) |
| `hoistedTypeOfInFn` :733 / `hoistedTypeOf` :742 | first match **with non-UNDEFINED `type_id`** — multi-decl "which decl's type wins" selection |
| `hoistedTypeId` :748 | first match, no UNDEFINED filter (load/store-global lookups) |
| `getTempEffType` :4099 | hoisted match + **UNDEFINED → `d4_wtype` written-type scan fallback** (type inferred from writes at emit time) + signedness derivation |
| `getTempTypeInfoResolve` :4132 / `getTempTypeInfo` :4147 | `hoistedTypeOf` + **fallback chain across other temps (`fb1`/`fb2`)** — decides which operand's type describes the operation; ICEs when all fail |

35 emit-time call sites (full grep in the working notes): `emitFieldAssign` :250/:330/:371; `tempFnTypeId` :1696; `nestEmit` family :3173/:3219/:3226/:3246/:3480/:3507/:3528/:3560/:3565/:3595-3596/:3651; `emitterTempIsPackedStructPtr` :5952; assign/index/store arms :6281/:6303/:6306/:6351/:6438/:6478/:6501/:6504/:6527/:6532; field arms :6575/:6591/:6636/:6691/:6726/:6733/:6776; binary arm :6823/:6827/:6868/:6873/:6913/:6970; call arms :7131; `lb.result` :7918; `emitFieldAssign`-adjacent :7980/:8005; `lg_pre` :8221; `tempPayloadIsVoid` :8679.

**`emitSatBinary` (c89_emit.zig:4166+).** Saturation semantics it decides at emit time: `width_bits = typeRegistryIntWidthBits(tid)` (:4168); `is_signed` argument — decided at the call site (`.binary` arm :6823-6829) by the `getTempTypeInfo(result, lhs, rhs)` fallback chain + a second chain when the result type is void/int_lit; the `width_bits == 64` vs smaller expression-shape selection; the signed vs unsigned bound sets. Op codes: 19 `BIN_SADD`, 20 `BIN_SSUB`, 21 `BIN_SMUL`, 22 `BIN_SSHL` (lower.zig:61-64).

### I.2 LIR construction-site census (`sf/src/lower.zig`) — the five records

| record | what already exists | what must be added |
|---|---|---|
| field ordinal/name | ordinal = `field_id` on `load_field`/`store_field`/`addr_of_field`/`assign_field` (all sites). **`name_id` is NOT the field name** — it is the base local's name (`nameMapGet(base_temp)`; the emitter uses it to spell the base, :6568/:6625) | the field's **`field_name_id`** (and `field_type_id` for the cast/array decisions in `emitFieldAssign`/`.store_field`) on all four field insts. The name is in hand at every site (`field_name_id = astStoreNodePayload(...)` / `lowerFindFieldOrdinal` region: :2619, :2964, :2319, :874 + ~30 emission sites :914, :2198, :2255, :2394, :2567, :3087-3127, :3875, :4022, :4868, :5244-5405, :6281-6283, :6881-6942, :6996, :7022, :7089, :7190-7192, :7613, :7635, :7917-7923, :8000, :8036, :8646, :8719) but is never recorded on the inst |
| callee fn type id | `CallDirectData.return_type`/`call_conv`, `TailCallData.return_type`/`call_conv` (side table); `.call`/`func_ref` resolve through the callee/result temp's type | **`fn_type_id`** on `CallDirectData` (sites :5549 `fp`, :5679 `fs`, :5750 `sm` — the fn payload/type is in hand) and `TailCallData` (:8217 via `CallInfo`; CallInfo is lower.zig-local, carries the id through). `.call`/`func_ref` carry it via the recorded callee/result temp type (mechanical ptr→fn projection) |
| temp result types | `TempDecl{temp_id, type_id}` (lir.zig:17-20) — copied intact by async (:965) | concretize: no `TYPE_UNDEFINED` holes at emit time (e.g. `lowerPreallocArgs` :3950-3953 allocates `TYPE_UNDEFINED` arg temps), so the `getTemp*`/`hoisted*` fallback chains (d4 write-scan, cross-temp fb chain) become dead and deletable; emitter keeps pure `TempDecl` reads |
| int-const width/signedness | **DONE** (`int_const{value,result,width_bits,is_signed}` lir.zig:74; all construction sites per combined fix H1 `71979423`) | nothing (Amendment 4: out of P6 scope; not touched) |
| saturation semantic op | `binary.op` ∈ {19,20,21,22} (kind of saturate) | the semantic domain — **`width`/`is_signed` (+ `result_type`)** of the operation's semantic types — recorded at lowering (sites: `lowerBinaryArm` :3937 via :4463 for `sat_add/sub/mul/shl`; `lowerCompoundAssign` :7339-7346 for `sat_*_assign`); A15/A18 precedent = exactly these fields on the inst ("lowering computes `result_type`/`width`/`is_signed` … so the emitter performs no type inspection") |

`LirInst` size budget: all planned fields fit the existing 32 B envelope (union slot 24 B; `load_field` 16→24 B, `store_field` 16→24 B, `assign_field` 16→24 B, `addr_of_field` 12→20 B, `binary` 13→19 B, `func_ref` 12→16 B). `lir_stream.zig` serializes `LirInst` by raw `@sizeOf` memcpy (:142/:246) — new fields ride automatically within one binary.

### I.3 The blocking finding — record transport through the async LIR copier

`async_state_machine.zig:317-411` `remapInst` rewrites every user-body instruction of a suspending function into the synthesized step function, reconstructing payloads **field-by-field** (e.g. `.binary => |x| … .{ .op = x.op, .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base }` :331; `.load_field` :334; `.store_field` :335; `.addr_of_field` :337; `.call` :333; `.func_ref` :347). A new payload field is therefore **zeroed/defaulted on every remapped inst** (with defaults) or the file **stops compiling** (without defaults). Fresh async-side constructions (`LirInst{.binary…}` :234, :482-558, :678-:730, `LirInst{.call…}` :414, `LirInst{.func_ref…}` :517/:730) have the same exposure. Channels that DO survive: side-table entries (copyCallDirect :297-304 / copyTailCall :306-313 — `var cd = …` whole-struct copies → `fn_type_id` is safe), `TempDecl.type_id` (:965 copies both fields → concretization is safe), `binary.op`/`field_id` (already copied). Per-fn maps (`temp_variant_sub_field`) are freshly `u32ToU32MapInit`ed (:769/:948) — not a transport. `lir_opt_pass.zig` is safe: all its reconstructions are whole-struct copies (`var nb = b;` :1113-1176, :1474-1507) and its folds replace insts with `int_const` (facts already filled).

**Empirical load-bearing (not "gate-unreadable"):** `repro/mi_matrix/async_frame_structret_xmod/main.zig:23-24` — `fn suspA(p: *Big) void { @asyncSuspend(null); p.a = p.a + 1; }` (same for `suspB`/`p.b`) — pointer-base `load_field`/`store_field` **inside remapped suspending bodies**. This fixture is one of the 25 mi_matrix runtime anchors (battery item 4). With the field-name record added and `remapInst` unfixed, the step fn's designators lose the record (spelling falls to the unknown-field `.f_<id>` shape or an ICE) → battery red. Precedent that this class bites: P6-pre's `int_const` facts were dropped by this same copier and became review-found real bug `82ff0743 fix(async_state_machine): remapInst copies int_const semantic facts`.

### I.4 Exact edit plan (as it would run once the touch-set question is settled)

1. `sf/src/lir.zig` (record): `load_field`/`store_field`/`assign_field` += `field_name_id: u32, field_type_id: u32`; `addr_of_field` += `field_name_id: u32, field_type_id: u32`; `binary` += `result_type: u32, width: u8, is_signed: u8` (sat semantic op = `op` + recorded domain; only meaningful for ops ≥ 16, zero-cost otherwise); `CallDirectData`/`TailCallData` += `fn_type_id: u32`; TempDecl invariant comment (type_id always concrete semantic type).
2. `sf/src/lower.zig` (record): populate the new fields at every construction site in I.2 (name from the `field_name_id` local already computed; type from the `fields[fi].type_id`/`var_fe.type_id` already looked up; sat `width`/`is_signed`/`result_type` from the result type via `type_registry` P5 predicates — consume, never duplicate); concretize `TempDecl.type_id` (fill `TYPE_UNDEFINED` holes at creation); `fn_type_id` at the three `lirSideAppendCallDirect` sites + the `CallInfo`/`lirSideAppendTailCall` path.
3. `sf/src/c89_emit.zig` (named removals/consumption only): `resolveFieldAccess` loses the `fe_items` re-lookup — spells `.`/`->`/`._N`/`.ptr`/`.len`/`.tag`/payload from the recorded `field_name_id`/`field_type_id` + recorded base/result types (designator form = C spelling); `findCalleeFnTypeId` DELETED (read `c.fn_type_id`/`tc.fn_type_id`); `getTemp*`/`hoisted*` fallback chains deleted — pure `TempDecl` record reads (the d4 write-scan fallback and the cross-temp fb chain are the re-derivations; `getTempEffType`/`getTempTypeInfo` reduce to readers); `emitSatBinary` reads recorded `width`/`is_signed`/`result_type` — no `typeRegistryIntWidthBits` derivation, no `getTempTypeInfo` at the `.binary` call site; no emit-time helper decides.
4. **REQUIRED, OUT OF TOUCH SET:** `async_state_machine.zig` `remapInst` — copy the new fields in the `.binary`/`.load_field`/`.store_field`/`.addr_of_field`/`.call`/`.func_ref` cases (and default-fill or extend the fresh async literals). Mirrors `82ff0743`.
5. Tech docs: `sf/docs/tech_docs/08_c89_emission.md` + INDEX stamps `[updated: 2026-10-12 — P6 …]` for the named-helper removals (duty only attaches to the compiler-moving commit, which does not exist here).

## Implement

Not started. Per the STOP-present rule ("STOP and present … No corner cuts") the run halts before any source edit; step 4 of the edit plan is impossible under the binding touch set.

## Runtime battery

Not run (no compiler-moving commit). The eight-item battery would be run after an operator-ruled implementation.

## Observations (report-only)

- The async-safe subset of P6 is real and small: `fn_type_id` on the two side-table structs (wholesale-copied) + `TempDecl.type_id` concretization + the emitter consumption of both. The field-name record and the sat domain record are the blocked parts — they are exactly two of the five deliverable items and two of the four named removals (`resolveFieldAccess` re-resolution cannot be removed without the recorded name; `emitSatBinary` semantics cannot be recorded without a payload the copier preserves).
- Reading (b) of "saturation semantic op" — "op + the recorded temp result types constitute the semantic record; P5 predicates at spell time are consumption, not decision" — would make the sat item async-safe. The brief's A15-precedent wording ("Lowering computes `result_type`/`width`/`is_signed` … so the emitter performs no type inspection" / "which saturate: signed/unsigned/width from the operation's semantic types") reads as reading (a) (explicit fields). I did not improvise a variant (spec §4.1: "never improvise a variant") — this is part of what the operator should confirm.
- `name_id` on `load_field`/`store_field`/`assign_field` is the base local's name, not the field's — the plan text's "field ordinal/name" is therefore NOT already recorded despite the superficially matching field name; any implementer should not repurpose `name_id` (it feeds `nameManglerMintLocal` base spelling, :6568/:6625).
- Commit budget: only the report commit exists (the brief's (a) `refactor(lower)` and (b) battery do not apply to a stopped run). `progress.md` untouched. No push. `run.err` left untracked and alone.
