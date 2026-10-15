# Task P6 report — Lowerer carries decisions (semantic-only LIR)

Branch `zig1_improvements`, BASE `acda68be`. Requirements: `task-P6-brief.md` (binding, incl. Amendment 4 touch set). Shape: Investigate → Implement → Runtime battery. **Run stopped in Investigate (STOP-present, below). No source edits, no compiler-moving commit, no battery.**

## Status

**COMPLETE** — round 1 STOP-presented (statement kept verbatim below as the record); operator Amendment 5 (rulings 1a + 2) resolved it: touch set extended with `async_state_machine.zig` copier-only edits and the sat semantic op fixed to the A15-pattern. Implemented as one compiler-moving commit (a) `2ad2e2cb`; full 8-item battery green (corpus 0 movers, goldens 5/5, mi_matrix 25+oob, examples 26/26+26/26, stdlib 285/0, hop1==hop2, fixed point `1293d62d…` → `48564285501eff1029207fcfe9416a66`, pins 0/8, markers unchanged).

### Round 1 STOP-present (record)

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

## Implement (one compiler-moving commit (a) `2ad2e2cb`; rulings 1a/2 folded into the I.4 edit plan)

Touch set (Amendment 5): `sf/src/lower.zig` + `sf/src/lir.zig` (record) + `sf/src/c89_emit.zig` (named removals/consumption) + `sf/src/async_state_machine.zig` (copier-only) + `sf/docs/tech_docs/**`. Diffstat: 7 files, +270/−183. `lir_opt_pass.zig`/`coercion.zig` untouched (whole-struct copies already preserve the new fields; no P11 work). `progress.md` untouched. No push.

**1. `lir.zig` (record).** `binary` += `result_type: u32, width: u8, is_signed: u8` (Amendment 5 ruling 2, A15 pattern; 19 B payload — `@sizeOf(LirInst)` stays 32 B); `load_field`/`store_field`/`assign_field` += `field_name_id: u32, field_type_id: u32` (24 B each); `addr_of_field` += `field_name_id`/`field_type_id` (20 B); `CallDirectData`/`TailCallData` += `fn_type_id: u32`. Record semantics documented on each payload (`field_name_id` 0 = synthetic slice/TU/tuple designator; `width`/`is_signed` semantic, never C carriers; `fn_type_id` 0xFFFFFFFF = none).

**2. `lower.zig` (record).** `emitInst` is the construction funnel (`lowerRecordFacts`): every `binary` records `result_type`/`width`/`is_signed` via `lowerBinSemType` (the exact former emit-time decision relocated: `result→lhs→rhs` type chain + the sat-family void/int-lit re-check; `typeKindIsSignedIntBase` + `typeRegistryIntWidthBits` P5 predicates at lowering) and every field inst records `field_name_id`/`field_type_id` via `lowerFieldRecord` (the old `fe_items`-by-ordinal resolution at the owning phase, ptr→pointee unwrapped; 0/0 for synthetic/OOB). `lowerCalleeFnTypeId` = the old `findCalleeFnTypeId` scan relocated (verbatim semantics incl. the `call_conv == 0` early-out → 0xFFFFFFFF) — recorded at the 3 `lirSideAppendCallDirect` sites and the `CallInfo`/`lirSideAppendTailCall` path (indirect tail calls record 0xFFFFFFFF, matching the old guard).

**3. `c89_emit.zig` (named removals/consumption only).** (a) `resolveFieldAccess` consumes the recorded identity (`fe_items` lookups deleted; `name_out`/`fld_tid_out` outputs deleted; `emitFieldAssign`/`dceFieldIsArray` read the recorded field type — `dceFieldIsArray`'s own `fe_items` re-resolution went with it); base-kind/mode-bit designator spelling + bounds-visibility policy unchanged. (b) `findCalleeFnTypeId` DELETED (zero callers); `.call_direct`/`.tail_call` arms read `c.fn_type_id`/`tc.fn_type_id`. (c) `getTempEffType`'s `d4_wtype` write-scan fallback DELETED and `getTempTypeInfo`/`getTempTypeInfoResolve` (the cross-temp chain + ICE) DELETED — all temp-type reads are pure `TempDecl.type_id` record reads (`getTempTypeByIndex`/`hoistedTypeOf*` kept as readers). (d) The `.binary` `op >= 16` arm reads `b.result_type`/`b.is_signed` (ruling 2); `emitSatBinary(op, …, result_type, width, is_signed)` spells ONLY from the carried fields (its `typeRegistryIntWidthBits` derivation deleted); `nestEmitBinExpr` takes the carried `result_type`/`is_signed` from the inst (`nestEmitDefRvalue` passes `b.*`); `emitUnaryRvalue`'s wrap-neg reads the recorded result temp type (pure read — ruling 2 covers the binary family; the old `res→operand` chain is gone).

**4. `async_state_machine.zig` (copier-only, ruling 1a).** `remapInst` copies every new record field 4-field-style exactly like the `int_const` facts copier (`82ff0743`): `.binary` += `result_type`/`width`/`is_signed`; `.load_field`/`.store_field`/`.assign_field`/`.addr_of_field` += `field_name_id`/`field_type_id`. No other changes in the file (its own constructions never emit sat ops or field insts — frame fields go through `ptr_to_int`/`load`/`store`; `copyCallDirect`/`copyTailCall` are whole-struct copies (`var cd = …call_direct`) and already preserve `fn_type_id` — verified, no edit needed).

**5. Tech docs.** `[updated: 2026-10-12 — P6 …]` stamps in `07_lir_lowering.md` (the record funnel + side-table fact) and `08_c89_emission.md` (the four named removals), plus `INDEX.md` truth-up (`findCalleeFnTypeId` deleted, `emitSatBinary`/`getTempTypeByIndex` rows updated, `lowerCalleeFnTypeId`/`lowerFieldRecord`/`lowerRecordFacts`/`lowerBinSemType` indexed).

Pre-commit smoke (evidence before commit): gol golden built+run = `fcbf7e7cead5082f0a8caadd5a8f0ff9` (frozen); sat probe (`+|` on i32/u32, `*|` i32, `+%` u32) emits the correct carried-bounds C (`2147483647` / `(-2147483647 - 1)` signed bounds, `0xFFFFFFFFu` unsigned bound, the width-64 mul shape) and runs `2147483647 / -2147483648 / 2147483647 / 1 / 94` — saturate + wrap semantics exact.

## Runtime battery (all 8 items; compiler `/tmp/p6_build/zig1_5_clean`, built from the committed source)

### 1. Seed two-hop

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p6_build` → `[seed] hop2 binary md5: 48564285501eff1029207fcfe9416a66` / `[seed] two-hop closure OK: hop1 == hop2 == 48564285501eff1029207fcfe9416a66`. **hop1==hop2**; fixed point `1293d62d71dceeb734dee837a7e10e8e` → **`48564285501eff1029207fcfe9416a66`** (moved as expected; recorded; seed NOT rotated — Task C).

### 2. Corpus classify (class FILE vs frozen Appendix A)

`bash scripts/corpus/classify /tmp/p6_build/zig1_5_clean /tmp/p6_battery/corpus.txt` → `wrote …: 1124 dirs`; `md5sum` = `518eca1a9b5d3e1cc5a48abce214abd8` = frozen `518eca1a…` (**byte-identical, 0 movers**); tally `950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`.

### 3. Goldens 5/5

dump+gcc all rc=0 (0 `error:`). gol `timeout 120 ./gol` = `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `printf '(+ 1 2)\n' | timeout 60 ./lisp` = `b3d9f8974da24ddbf9d389f3d7d97322`; json (CWD `examples/z98/json_parser`) = `8bda3d5a1ec07d14a301bc343df32bf8`; mud session (`session.sh`) rc=0, server `66c8f0abb926cca7baf9a0d1692ab318`, client `93147d0f0bbd983a9d844fea8b7a6fa7`. **5/5 = frozen.**

### 4. mi_matrix 25 + oob

SET enumerated from the progress.md load-bearing definition (non-stdlib ∧ non-empty `expected.txt` ∧ `expected.rc==0`) → 25 dirs (list in the transcript; includes `slice_index_field_store_xmod`/`field_store_continue*`/`tagged_*`/`packed_*` families). `bash scripts/stdlib/run_fixtures.sh /tmp/p6_build/zig1_5_clean repro/mi_matrix/<25>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`**. Trap `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc=0, build rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt`). **MATCH.** Extra (non-anchor siblings, copier probe): `async_frame_structret_xmod` rc=0 `5` (suspending `p.a = p.a + 1` bodies through `remapInst` — the exact copier hazard of the Investigate STOP), `union_keyword_tag_xmod` rc=0 `P=.{ .int = 7 }`/`3`, `slice_of_slice_xmod` rc=0 `11` — all per NOTES.

### 5. examples 26/26 build + 26/26 run

Build (`-ffast -o` + `build_target.sh linux`): 26/26 dump=0 / `.c` counts identical to task-0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run (CWD = example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* `q\n`): 26/26 rc + stdout md5_16 IDENTICAL to §1.4 — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`. (First pass ran the matrix with the wrong CWD and showed 3 json mismatches — harness error, re-run with CWD=example-dir per the recipe; the table above is the authoritative run.)

### 6. stdlib

`bash scripts/stdlib/verify_stdlib.sh /tmp/p6_build/zig1_5_clean` → `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK`. (Includes the `stdlib_async_*` family — remapped bodies with the new records.)

### 7. The 8 `--dump-c89` pins (old → new)

| entry | mode | old (combined-fix record) | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — byte-identical C emission on the 4 gate programs** (the recorded facts are decision-identical to the removed re-derivations wherever the gates reach; pins recorded old→new as required).

### 8. Markers telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 lines / 38,378 B** — identical to the record (unchanged).

## Observations (report-only; no fixes)

- The battery is fully green AND byte-identical where the plan allows byte-identity (pins 0/8, markers unchanged) — the relocated decisions (`lowerBinSemType`/`lowerFieldRecord`/`lowerCalleeFnTypeId`) reproduce the removed emit-time derivations exactly, including the sat void/int-lit re-check and the `call_conv == 0` early-out. This is decision-identity evidence beyond the runtime gates.
- Deferred-minor class (not fixed, report-only): (a) `emitUnaryRvalue`'s wrap-neg now reads the recorded result temp type with no operand fallback (ruling 2 names the binary family; `wrap_negate` results are never UNDEFINED-registered, so the old chain's operand arm was unreachable — but the chain is gone rather than relocated for `unary`); (b) the old `getTempTypeInfo` all-fail ICE is now a graceful `wsg=0` spelling — unreachable on the whole battery (0 ICE corpus) and only reachable on LIR the old code ICEd; (c) `tempFnTypeId` (`func_ref`'s ptr→fn unwrap over the recorded type) and the `hoistedTypeOf*` UNDEFINED-skip readers remain as pure record readers; (d) `resolveFieldAccess`'s bounds-visibility policy (mode 16) is kept verbatim — it is a spelling-visibility guard over the recorded identity, not an identity re-resolution; (e) `lir.zig` `LirInst` envelope verified at 32 B (largest payload `load_field`/`store_field`/`assign_field` 24 B).
- Struct-literal note (mechanics): Z98 allows omitting struct-literal fields (no error; the omitted members are uninitialized payload bytes). All op>=16 `binary` and all field insts are filled at the `lower.zig` funnel, and `remapInst` copies every new field, so no record field is read from an unfilled construction; async's own `.binary` constructions (all `BIN_ADD`/`AND`/… < 16) never have their unused `result_type`/`width`/`is_signed` read.
- Harness note (echo of the combined-fix process note): run the pin loop and the `--markers` dump sequentially from one CWD — parallel runs race on the compiler's spill files (first-pass empty md5s were this race in the examples matrix too: the wrong-CWD run was my harness error, not a compiler delta).
- Commit budget: (a) `2ad2e2cb refactor(lower): P6 — lowerer records field identity/callee fn type/sat semantics; emitter spells only` (sf/src + tech docs); (b) this report. `progress.md` untouched (controller-owned). `run.err` left untracked and alone. No push.
