# P5 report — Predicates + promotion centralized (exec order 1/10)

Implementer: P5 implementer, 2026-10-12. Branch `zig1_improvements`, BASE `d743468b` (Task 0 fix-round-1 HEAD). Spec: `docs/superpowers/specs/2026-10-12-zig1-emitter-sanitization-design.md` §1/§3 cat 5/§4 row/§5 P5. Brief: `task-P5-brief.md`. Comparison anchors: `progress.md` `## Task 0` (frozen battery) + `task-0-report.md` §1 / Appendix A / §2.5.

## Investigate

### 0. Drift check vs plan cites (re-derived before editing)

`grep -n "fn <name>"` + content greps over `sf/src/c89_emit.zig` at HEAD `d743468b` — every brief cite EXACT, no drift (same verdict as Task 0 fix round 1 F4; file untouched since):

| brief cite | re-derived site | status |
|---|---|---|
| `:9473-9496` int-kind truth tables | `intKindIsSignedBase:9473`, `intKindIsUnsignedBase:9479`, `intKindWidthBytes:9487` (+ Task-2b3-D1-2 comment `:9470-9472`) | EXACT |
| `:4712-4929`, `:4895` signedness/width dispatchers + int-kind/scalar/pointer predicates | `classifyIntSignedness:4712`, `intTypeNeedsWidthWrap:4722`, `intTypeByteWidth:4895`, `typeIsIntKind:4903`, `retTypeIsScalarC:4912`, `typeIsPtrKind:4923` | EXACT |
| `emitBinRvalueText:4385` promotion | fn def `:4385`; mixed-sign promotion block `:4396-4418` | EXACT |
| owners | `type_registry.zig:919-1049` predicates family (`typeRegistryIntWidthBits:919`, `typeRegistryIntIsSigned:931`, `typeRegistryIsNumeric:997`, `typeRegistryIsInteger:1017`, `typeRegistryIsUnsigned:1035`, `typeRegistryIsPointer:1046`, `typeRegistryIsSlice:1051`); `coercion.zig` (`classifyCoercion:104` — promotion NOT yet exposed; only `CoercionKind.int_widen`/`int_literal_coerce` classification exists) | EXACT |

### 1. Census — every emitter-held instance of the three P5 responsibilities

Responsibilities in scope (spec §3 cat 5 / §4 row only): (a) int-kind/signedness/width predicates, (b) scalar/pointer classification predicates, (c) C usual-arithmetic conversions. Deliberately NOT in scope (other smell categories): C-name derivations (`getCTypeName`/`getUnsignedCTypeName` name tables = P1/P3), typedef emission classification (`computeSharedSet`/`shouldSkipTypeEmission`/`is_carrier64` = P4/P2), print-format routing (`printFnSourceName` float arms = naming/print), LIR re-decisions (`getTemp*` = P6), sat emission = P6/P9.

**A. Truth tables + dispatchers (the plan's delete cites) — 9 functions, all private to `c89_emit.zig`:**

| # | site | membership (verbatim) | callers |
|---|---|---|---|
| 1 | `intKindIsSignedBase:9473-9477` | kind ∈ {i8,i16,i32,i64,isize,arb_int} | 3984, 4715, 4906, 4915, 4983, 5001, 5423 |
| 2 | `intKindIsUnsignedBase:9479-9483` | kind ∈ {u8,u16,u32,u64,usize,arb_uint} | 3984, 4718, 4906, 4915, 5424 |
| 3 | `intKindWidthBytes:9485-9496` | i8/u8/c_char→1; i16/u16→2; bool→1; i32/u32/isize/usize/integer_literal/null/undefined→4; i64/u64→8; else 0 | 4704, 4898 |
| 4 | `classifyIntSignedness:4712-4720` | TYPE_VOID→-1; (signed-base ∪ c_char ∪ integer_literal ∪ undefined ∪ null)→1; (unsigned-base ∪ bool)→0; else -1 | 4404, 4407 |
| 5 | `intTypeNeedsWidthWrap:4722-4730` | TYPE_VOID→0; only arb_int/arb_uint; `typeRegistryIntWidthBits < size*8` and ≥1 → 1 | 4025, 4032, 4037 |
| 6 | `intTypeByteWidth:4895-4901` | TYPE_VOID→0; `intKindWidthBytes(k)` if ≠0 else `ty.size` | 4410, 4414 |
| 7 | `typeIsIntKind:4903-4910` | TYPE_VOID→0; signed-base ∪ unsigned-base ∪ {c_char, bool, integer_literal, undefined, null} | 399, 7218, 7416, 7603, 7645 |
| 8 | `retTypeIsScalarC:4912-4921` | TYPE_VOID/TYPE_UNDEFINED/0→0; signed-base ∪ unsigned-base ∪ {c_char, integer_literal, bool, null, f32, f64, enum, error_set, ptr, many_ptr, fn} | 3914, 7126 |
| 9 | `typeIsPtrKind:4923-4929` | TYPE_UNDEFINED/TYPE_VOID/0→0; kind ∈ {ptr, many_ptr} | 301, 327, 7215, 7413, 7563, 7642 |

**B. Usual-arithmetic conversions — 1 block:** `emitBinRvalueText:4396-4418` (mixed-sign promotion: classify both operands via #4; when exactly one side is unsigned and its `intTypeByteWidth` (#6) is ≥ the signed side's, cast the signed operand to the other operand's C type via `getCTypeName`). Reached from `nestEmitBinExpr:4329` and the `.binary` def arm. No other UAC site exists in the emitter (the `op >= 16` width-wrap cast paths at `:4334`/`:7735` are the INTWIDTH wrap mechanism, not mixed-sign promotion — out of scope).

**C. Sibling composition sites (same responsibility, table membership inlined or consumed) — rewired to canonical calls, each keeps its own extras verbatim:**

| site | current form | action |
|---|---|---|
| `nestScalarEffTid:3984-3987` | composes #1+#2 with extras {c_char,bool,f32,f64,ptr,many_ptr,enum,error_set} | base refs → canonical; extras stay |
| `writeIntConstRvalue:4499` | INLINE VERBATIM COPY of #1's row (`i8 or i16 or i32 or i64 or isize or arb_int`) | → canonical `typeKindIsSignedIntBase` call (copy deleted) |
| `getUnsignedCTypeName:4704` | consumes #3 | → canonical width call |
| `getTempEffType:4983` | composes #1 with extras {undefined, null} (feeds `out_signed`) | base ref → canonical; extras stay |
| `getTempTypeInfoResolve:5001` | composes #1 only (`out_signed`; consumed by `nestEmitBinExpr:4334`/`.binary:7735` width-wrap `wsg`) | base ref → canonical |
| `printKindIsIntegerLike:5423-5424` | composes #1+#2 with extras {c_char, enum, integer_literal} | base refs → canonical; extras stay |

Note: `getTempEffType`'s `out_signed` membership (signed-base ∪ {undefined,null}) and `getTempTypeInfoResolve`'s (signed-base only) DIVERGE from each other and from #4 — all preserved verbatim (Task 0 §2.9.5 mandate).

**D. Censused, NOT rewired (observation-only; see Observations):** ~15 scattered inline `kind == ptr_type or kind == many_ptr_type` pair checks (`:179, :503, :1011, :1038, :1613, :1663, :3852, :3864, :5523, :6004, :6436, :6472, :6867, :7506, :7640, :7692, :8049, :8149`) plus local 1-2 kind tests in naming/print/typedef-emission contexts. These are NOT truth tables and are outside the plan's delete cites; they already coexist with canonical `typeRegistryIsPointer` today; rewiring them crosses P1/P3/P4 territory (naming/typedef classification). Membership equivalence of the pair check to `typeRegistryIsPointer` is exact for reachable tids (guards of #9 are redundant: tid 0/1/18 hold `none_sentinel`/`void`/`undefined` kinds).

**E. Canonical-owner findings (mapping):**

- Pointer: canonical `typeRegistryIsPointer` ALREADY exists (`:1046-1049`, membership `ptr|many_ptr`). #9's membership is IDENTICAL for all reachable tids (verified: `typeRegistryInit` registers `none_sentinel` at tid 0, `TYPE_VOID=1`, `TYPE_UNDEFINED=18`; none can be ptr kinds; #9's guards are therefore redundant). → DELETE #9; its 6 call sites call `type_mod.typeRegistryIsPointer` (bool form). This is the true single mechanism (no second pointer predicate is added to `type_registry`).
- Int-kind/signedness/width and scalar: no membership-compatible canonical predicate exists (`typeRegistryIntIsSigned` excludes c_char? NO — includes c_char as signed, but excludes integer_literal/undefined/null and recurses enum-backing; `typeRegistryIsInteger` excludes c_char/bool/undefined/null). Merging with the existing canonical set WOULD be a semantic change → plan authorizes EXPOSING the emitter's predicates in `type_registry` as the canonical surface, bodies relocated VERBATIM (membership-identical by construction). Both families coexist in `type_registry` with their exact documented memberships (Task 0 §2.9.5: "keep per-caller membership verbatim").
- Promotion: `coercion.zig` has no usual-arithmetic function; the plan authorizes exposing one (`coercionUsualArithPromote`) — pure relocation of the `:4396-4418` decision, composed from the newly exposed `type_registry` predicates (`typeRegistryIntSignednessClass`, `typeRegistryIntByteWidth`), matching `classifyCoercion(reg, src, tgt)`'s call shape (registry + TypeIds → decision). Emitter keeps only its emitter-shaped glue: temp→type resolution (`getTempEffType`, P6's later kill) + C-name minting (`getCTypeName`, P1/P3's later kill).

### 2. Precise edit plan

**`sf/src/type_registry.zig`** — one INSERT after `typeRegistryGetPointeeType` (`:1055-1059`), immediately after the `:919-1059` predicates family; 8 new `pub fn` (bodies = verbatim moves; `type_mod.TYPE_*` refs become bare `TYPE_*`; in-module calls unqualified):

| new pub fn (canonical name) | moved from | body change |
|---|---|---|
| `typeKindIsSignedIntBase(k: TypeKind) u8` | `intKindIsSignedBase` | none (kind-level truth table) |
| `typeKindIsUnsignedIntBase(k: TypeKind) u8` | `intKindIsUnsignedBase` | none |
| `typeKindIntWidthBytes(k: TypeKind) u32` | `intKindWidthBytes` | none |
| `typeRegistryIntSignednessClass(self, tyid) i8` | `classifyIntSignedness` | compose `typeKindIsSignedIntBase`/`typeKindIsUnsignedIntBase`; `type_mod.TYPE_VOID`→`TYPE_VOID` |
| `typeRegistryIntNeedsWidthWrap(self, tyid) u8` | `intTypeNeedsWidthWrap` | `type_mod.typeRegistryIntWidthBits`→`typeRegistryIntWidthBits` |
| `typeRegistryIntByteWidth(self, tyid) u32` | `intTypeByteWidth` | compose `typeKindIntWidthBytes` |
| `typeRegistryIsIntKind(self, tid) u8` | `typeIsIntKind` | compose bases |
| `typeRegistryIsScalarC(self, tid) u8` | `retTypeIsScalarC` | compose bases; `type_mod.TYPE_*`→bare |

No change to existing `type_registry.zig` functions (`typeRegistryIntIsSigned`/`typeRegistryIsInteger`/etc. untouched).

**`sf/src/coercion.zig`** — one INSERT at end (after `classifyCoercion` `:225`):

- `pub fn coercionUsualArithPromote(reg: *type_mod.TypeRegistry, l_tyid: TypeId, r_tyid: TypeId) u8` — verbatim relocation of the `emitBinRvalueText:4396-4418` decision: classify both operands via `type_mod.typeRegistryIntSignednessClass` (unresolved operand = TypeId 0 → unclassified/`-1`, matching the emitter's `getTempEffType`-failed path — verified tid 0 is `none_sentinel`, which classifies `-1`); width compare via `type_mod.typeRegistryIntByteWidth`; returns `0` = cast LHS to RHS's type, `1` = cast RHS to LHS's type, `2` = no promotion. Condition order and `>=` comparisons byte-faithful to `:4409-4417`.

**`sf/src/c89_emit.zig`** — bottom-to-top:

1. `:9470-9496` DELETE (Task-2b3-D1-2 comment + 3 truth tables — moved).
2. `:5423-5424` `printKindIsIntegerLike` base refs → `type_mod.typeKindIsSignedIntBase`/`type_mod.typeKindIsUnsignedIntBase`.
3. `:5001` `getTempTypeInfoResolve` base ref → `type_mod.typeKindIsSignedIntBase`.
4. `:4983` `getTempEffType` base ref → `type_mod.typeKindIsSignedIntBase` (extras stay).
5. `:4895-4929` DELETE (`intTypeByteWidth`, `typeIsIntKind`, `retTypeIsScalarC`, `typeIsPtrKind` — moved/#9 dropped).
6. `:4712-4730` DELETE (`classifyIntSignedness`, `intTypeNeedsWidthWrap` — moved).
7. `:4704` `getUnsignedCTypeName` → `type_mod.typeKindIntWidthBytes(k)`.
8. `:4499` `writeIntConstRvalue` inline signed-base copy → `if (type_mod.typeKindIsSignedIntBase(ict_bty.kind) != @intCast(u8, 0)) { is_signed = @intCast(u8, 1); }`.
9. `:4396-4418` promotion block → `_ = getTempEffType(...)`×2 + `coercion_mod.coercionUsualArithPromote(emitter.registry, l_tyid, r_tyid)` + side→`getCTypeName` glue (order of `getTempEffType`/`getCTypeName` preserved; `getCTypeName` emits `D6:` markers — called at most once, same branch as before).
10. `:4025/:4032/:4037` `nestShapeOk` → `type_mod.typeRegistryIntNeedsWidthWrap`.
11. `:3984-3985` `nestScalarEffTid` base refs → `type_mod.typeKindIsSignedIntBase`/`typeMod.typeKindIsUnsignedIntBase` (extras stay).
12. `:3914` → `type_mod.typeRegistryIsScalarC`.
13. `:327`, `:301` → `type_mod.typeRegistryIsPointer(registry, …)` (bool form).
14. `:399` → `type_mod.typeRegistryIsIntKind(registry, fa_src_ty) != 0`.
15. `:7215/:7413/:7563/:7642` → `type_mod.typeRegistryIsPointer` (bool form); `:7218/:7416/:7603/:7645` → `type_mod.typeRegistryIsIntKind != 0`; `:7126` → `type_mod.typeRegistryIsScalarC`.
16. imports `:30` area: add `const coercion_mod = @import("coercion.zig");` (acyclic: `coercion` imports only allocator/type_registry/hash/pal/itoa).

**`sf/docs/tech_docs/`** (AGENTS.md 1.1.1; INDEX.md Table A: `type_registry.zig`→`03_type_resolution.md`, `coercion.zig`→`05_semantic_analysis.md`, `c89_emit.zig`→`08_c89_emission.md`):
- `03_type_resolution.md`: `[updated: 2026-10-12 — P5 …]` + rows for the 8 exposed predicates in the fn table.
- `05_semantic_analysis.md`: `[updated: 2026-10-12 — P5 …]` + `coercionUsualArithPromote` row/contract.
- `08_c89_emission.md`: `[updated: 2026-10-12 — P5 …]` + deleted-table note + `emitBinRvalueText` now delegates promotion to `coercion`.
- `INDEX.md`: function-index rows for the new pub fns (moved/rehomed rows updated).

Touch set confirmation: `sf/src/type_registry.zig`, `sf/src/coercion.zig`, `sf/src/c89_emit.zig`, `sf/docs/tech_docs/{03_type_resolution,05_semantic_analysis,08_c89_emission,INDEX}.md` — all inside the expected set. Nothing outside → no STOP.

### 3. Semantic-preservation argument (membership verbatim)

- Every moved body is character-identical modulo the mechanical `type_mod.` qualifier drop and base-call rename; no set is widened/narrowed (Task 0 §2.5 row 2 + §2.9.5).
- #9→`typeRegistryIsPointer` substitution is membership-identical for all reachable tids (§1.E).
- Promotion: unresolved operands were never classified (flag-guarded); the relocated rule classifies TypeId 0 as `-1` (same); width compare reached only when both classified; `getCTypeName` side selection identical; `op >= 10` gate unchanged.
- No marker-emitting function changes call count/order (`getTempEffType`/predicates/widths are marker-free; `getCTypeName` at most once per op in the same branch). Expect `--markers` telemetry UNCHANGED (gol 3,241 lines / 36,038 B) — recorded either way in the battery.
- Emitted-C for user programs expected byte-identical (pins 8/8 unchanged); self-emission fixed point MUST move (compiler source changed) — recorded old→new with `hop1==hop2`, per Global Constraints.

### 4. Observations (report-only, NOT fixed)

- O1: ~18 inline `ptr_type or many_ptr_type` pair checks and assorted local kind tests remain in `c89_emit.zig` (census §1.D) — same membership as canonical `typeRegistryIsPointer` but local to naming/print/typedef-emission paths (other increments' categories). Possible later cleanup; out of P5's cited delete set.
- O2: `getTempEffType` vs `getTempTypeInfoResolve` `out_signed` memberships diverge (extras {undefined,null} vs none) — pre-existing, preserved verbatim; a later increment may want one policy.
- O3: `typeRegistryIntSignednessClass` (tri-state C-codegen class) and `typeRegistryIntIsSigned` (bool semantic signedness) intentionally coexist with different memberships (integer_literal/undefined/null/enum). Documented in tech docs; merging would be a semantic change (P5 forbids).
- O4: `getUnsignedCTypeName` remains a C-name derivation in the emitter (its width-table call is now canonical); P3's `typeCName` is its owner per Task 0 §2.9.2.

## Implement

### What was changed (diff vs the §2 edit plan)

One compiler-moving edit pass over the planned touch set ONLY: `sf/src/type_registry.zig`, `sf/src/coercion.zig`, `sf/src/c89_emit.zig` + `sf/docs/tech_docs/{03_type_resolution,05_semantic_analysis,08_c89_emission,INDEX}.md`. All source/doc edits via `edit`/`fastedit` (X.7: region re-read before every edit; bottom-to-top). Edit-plan conformance confirmed item-by-item against `git diff sf/src/` — nothing missing, nothing extra beyond the D1–D3 notes below:

| edit-plan item | observed in `git diff sf/src/` | verdict |
|---|---|---|
| `type_registry.zig`: 8 new `pub fn` after `typeRegistryGetPointeeType`, bodies verbatim (mod `type_mod.` drop; in-module calls unqualified) | `typeKindIsSignedIntBase`, `typeKindIsUnsignedIntBase`, `typeKindIntWidthBytes`, `typeRegistryIntSignednessClass`, `typeRegistryIntNeedsWidthWrap`, `typeRegistryIntByteWidth`, `typeRegistryIsIntKind`, `typeRegistryIsScalarC` — insert block after `:1058`, memberships/condition order byte-faithful to the deleted originals | EXACT |
| `coercion.zig`: `coercionUsualArithPromote` at end (after `classifyCoercion`), registry+TypeIds call shape, `>=` compares byte-faithful to old `:4409-4417` | present (`:225`+; +32 lines incl. contract comment); returns 0/1/2 per contract | EXACT |
| c89_emit 1. `:9470-9496` DELETE (Task-2b3-D1-2 comment + 3 truth tables) | deleted | EXACT |
| c89_emit 2. `:5423-5424` `printKindIsIntegerLike` base refs → canonical | rewired (`type_mod.typeKindIsSignedIntBase`/`typeKindIsUnsignedIntBase`) | EXACT |
| c89_emit 3. `:5001` `getTempTypeInfoResolve` base ref → canonical | rewired | EXACT |
| c89_emit 4. `:4983` `getTempEffType` base ref → canonical (extras stay) | rewired (`{undefined,null}` extras kept) | EXACT |
| c89_emit 5. `:4895-4929` DELETE (`intTypeByteWidth`, `typeIsIntKind`, `retTypeIsScalarC`, `typeIsPtrKind`) | deleted | EXACT |
| c89_emit 6. `:4712-4730` DELETE (`classifyIntSignedness`, `intTypeNeedsWidthWrap`) | deleted | EXACT |
| c89_emit 7. `:4704` `getUnsignedCTypeName` → `type_mod.typeKindIntWidthBytes(k)` | rewired | EXACT |
| c89_emit 8. `:4499` `writeIntConstRvalue` inline signed-base copy → `typeKindIsSignedIntBase` call | rewired (`if (type_mod.typeKindIsSignedIntBase(ict_bty.kind) != @intCast(u8, 0))`) | EXACT |
| c89_emit 9. `:4396-4418` promotion block → `_ = getTempEffType(...)`×2 + `coercion_mod.coercionUsualArithPromote` + side→`getCTypeName` glue | exactly that form; `getCTypeName` at most once, same mutually-exclusive branch | EXACT |
| c89_emit 10. `:4025/:4032/:4037` `nestShapeOk` → `typeRegistryIntNeedsWidthWrap` (3 sites) | rewired ×3 | EXACT |
| c89_emit 11. `:3984-3985` `nestScalarEffTid` base refs → canonical (extras stay) | rewired (extras `{c_char,bool,f32,f64,ptr,many_ptr,enum,error_set}` kept) | EXACT |
| c89_emit 12. `:3914` → `typeRegistryIsScalarC` | rewired (`emitHoistedDecls`) | EXACT |
| c89_emit 13. `:327`, `:301` → `type_mod.typeRegistryIsPointer` (bool form) | rewired ×2 (`emitFieldAssign`) | EXACT |
| c89_emit 14. `:399` → `typeRegistryIsIntKind(...) != 0` | rewired | EXACT |
| c89_emit 15. `:7215/:7413/:7563/:7642` → `typeRegistryIsPointer`; `:7218/:7416/:7603/:7645` → `typeRegistryIsIntKind`; `:7126` → `typeRegistryIsScalarC` | rewired (9 sites in `emitFlagOp`) | EXACT |
| c89_emit 16. imports: `const coercion_mod = @import("coercion.zig");` | added at imports block | EXACT |

Total: 9 emitter truth-table fns deleted (no dead copies), 24 call sites rewired + the promotion block delegated. Old-name grep over `c89_emit.zig` (defs + call sites of `intKindIsSignedBase`/`intKindIsUnsignedBase`/`intKindWidthBytes`/`classifyIntSignedness`/`intTypeNeedsWidthWrap`/`intTypeByteWidth`/`typeIsIntKind`/`retTypeIsScalarC`/`typeIsPtrKind`) → **zero hits**.

### Deviations from plan text (all immaterial; none semantic)

- **D1 (plan-text typo, not applied):** edit-plan item 11 spells `typeMod.typeKindIsUnsignedIntBase`; applied source uses `type_mod.` everywhere — `grep -n "typeMod\." sf/src/c89_emit.zig` → 0 hits (matches the controller requirement "no `typeMod.` typos").
- **D2 (tech-docs duty extras, same files/rows):** `08_c89_emission.md`'s bool paragraph referenced the now-deleted `intTypeByteWidth`/`classifyIntSignedness` names — re-pointed to `typeRegistryIntByteWidth`/`typeRegistryIntSignednessClass` (a direct consequence of the P5 rename, not an unrelated fix); `05_semantic_analysis.md`'s `## coercion.zig` header line-count annotation `211 lines` → `257 lines` (file grew by the new fn).
- **D3 (whitespace only):** the two deletion sites leave one extra blank line (before `writeSatNegDecimal` and before the Task-2b3 D3-3 comment) — no semantic content, no whitespace-only reformat elsewhere.
- **Note (not a deviation — the plan's exact prescribed form):** item 9's new code discards `getTempEffType`'s return and lets `coercionUsualArithPromote` see a `0` TypeId for unresolved operands; equivalence to the old flag-guarded classify is proven in check 2 below.

### Semantic-preservation checks (run during/after the edit pass)

1. **Membership verbatim:** every relocated body is character-identical to the deleted emitter body modulo the mechanical `type_mod.` qualifier drop + base-call rename (visible as delete/insert pairs in the diff); no membership set widened/narrowed (Task 0 §2.5/§2.9.5). `getTempEffType`'s and `getTempTypeInfoResolve`'s divergent `out_signed` extras preserved verbatim.
2. **`getTempEffType` failure-path equivalence (promotion relocation):** re-read `getTempEffType` (`c89_emit.zig:4901`) — `out_type.*` is written ONLY on the `return 1` path; both failure paths return 0 leaving the caller's `0` init intact. Old code classified only when `getTempEffType == 1` (else `l_sgn`/`r_sgn` stayed `-1`); new code passes TypeId 0 for unresolved operands and `coercionUsualArithPromote` classifies 0 as unclassified (`-1`) without consulting the registry. Edge case `eff == 0` on the success path: old `classifyIntSignedness(0)` read `none_sentinel`'s kind and returned `-1`; new code short-circuits 0 → `-1` — identical decision table in every reachable case. Width compare reached only when both sides classified 1/0 in both forms.
3. **Deleted-name audit:** grep of all 9 old names (defs + call sites) over `sf/src/c89_emit.zig` → 0 hits.
4. **Typo audit:** `grep -n "typeMod\." sf/src/c89_emit.zig` → 0 hits.
5. **Marker discipline:** `getCTypeName` (the only `D6:`-emitter on the promotion path) called at most once per binop, same mutually-exclusive branch as before; predicates/widths/`getTempEffType` are marker-free → `--markers` predicted UNCHANGED; battery item 8 confirms (3,241 lines / 36,038 B).
6. **Import acyclicity:** `coercion.zig` imports only allocator/type_registry/hash/pal/itoa — `coercion_mod` import in `c89_emit.zig` closes no cycle.
7. **Self-host + full battery:** build gate `hop1==hop2` with 0 errors, then the 8-item battery below (the actual gate) — all green.

### Tech docs (AGENTS.md 1.1.1 duty)

- `03_type_resolution.md`: title-line `[updated: 2026-10-12 — P5 …]` + 8 fn-table rows (after `typeRegistryGetPointeeType`, source order) with `[inference]` contracts.
- `05_semantic_analysis.md`: title-line `[updated: 2026-10-12 — P5 …]` + `### coercionUsualArithPromote` row/contract (signature, tri-state rules, 0/1/2 return contract, glue note) + header count fix (D2).
- `08_c89_emission.md`: title-line `[updated: 2026-10-12 — P5 …]` + §1.15 deleted-table note (all 9 deleted names listed, canonical homes named) + `emitBinRvalueText` now delegates promotion to `coercion` note + bool-paragraph stale names re-pointed (D2).
- `INDEX.md`: 9 function-index rows (8 × `type_registry.zig` + `coercionUsualArithPromote`), alphabetically placed. No moved/rehomed rows existed to update (old names were never indexed; grep 0).

## Runtime battery

Full battery per the brief's "Runtime battery + comparison anchors" (all 8 items). Zig1 under test: `/tmp/p5_work/seed/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p5_work/seed` (fresh out dir; `release/seed/` untouched). Comparison anchors: `progress.md` `## Task 0` + `task-0-report.md` §1 / Appendix A. Repo CWD `/workspace/znineeight` for all commands.

### 1. Seed rebuild + self-emission two-hop closure

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p5_work/seed
```
Observed (key lines):
```
[seed] hop1 binary md5: e81d9266955caaad6873fb728d7f494e
[seed] hop2 binary md5: e81d9266955caaad6873fb728d7f494e
[seed] two-hop closure OK: hop1 == hop2 == e81d9266955caaad6873fb728d7f494e
=== [seed] Done: /tmp/p5_work/seed ===
```
Extra: `md5sum /tmp/p5_work/seed/zig1_5_clean` → `e81d9266955caaad6873fb728d7f494e`; `ls /tmp/p5_work/seed/lib | wc -l` → `32`.
**Fixed point old→new: `bafbba9454cd2b134bdc3d50c65384e0` → `e81d9266955caaad6873fb728d7f494e` — MOVED (expected/allowed: the compiler source changed; recorded old→new per Global Constraints). hop1 == hop2 — MATCH.** No `FIXED_POINT_MD5` gate applied (the frozen point legitimately moved here).

### 2. Corpus classify — per-dir runtime class vs Appendix A

```bash
bash scripts/corpus/classify /tmp/p5_work/seed/zig1_5_clean /tmp/p5_work/corpus_p5.txt
# -> wrote /tmp/p5_work/corpus_p5.txt: 1124 dirs
awk '{print $2}' /tmp/p5_work/corpus_p5.txt | sort | uniq -c
# -> 116 FAIL / 58 GREEN / 950 OK   (no ICE/CRASH/NOENTRY)
awk '/^## Appendix A/{f=1} f&&/^```$/{c++; next} c==1{print} c>=2{exit}' \
  .superpowers/sdd/2026-10-12-zig1-emitter-sanitization-plan/task-0-report.md > /tmp/p5_work/appendix_a.txt
diff /tmp/p5_work/appendix_a.txt /tmp/p5_work/corpus_p5.txt && echo "diff: EMPTY"
md5sum /tmp/p5_work/appendix_a.txt /tmp/p5_work/corpus_p5.txt
# diff: EMPTY
# 518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p5_work/appendix_a.txt
# 518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p5_work/corpus_p5.txt
```
**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — tally matches the frozen baseline; per-dir list BYTE-IDENTICAL to Appendix A (diff EMPTY, md5 `518eca1a9b5d3e1cc5a48abce214abd8` both sides, 1124 lines). No class mover. UNCHANGED.**

### 3. Runtime goldens (4 programs / 5 md5s)

Build (per program; default `-fsafe`):
```bash
/tmp/p5_work/seed/zig1_5_clean --dump-c89 <ENTRY> > /tmp/p5_work/gold/<n>.c 2> <n>.dumperr   # rc=0 ×4
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/p5_work/gold/<n>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c \
    -o /tmp/p5_work/gold/<n>                                                                  # rc=0 ×4
```
Runs + observed:

| golden | command | run rc | observed md5 | frozen anchor | match |
|---|---|---|---|---|---|
| `game_of_life` | `timeout 120 /tmp/p5_work/gold/gol > gol.out` | 0 | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| `lisp_interpreter_curr` `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 /tmp/p5_work/gold/lisp > lisp.out` | 0 | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| `json_parser` | `cd examples/z98/json_parser && timeout 60 /tmp/p5_work/gold/json > json.out` | 0 | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| `mud_server` server | `bash examples/z98/mud_server/demo/session.sh /tmp/p5_work/gold/mud mud_srv.out mud_cli.out` (session rc=0) | 0 | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| `mud_server` client | (same session) | 0 | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

Bonus (baseline F6 shape): `cmp mud_srv.out examples/z98/mud_server/demo/canonical_expected.txt` → `IDENTICAL`; `cmp mud_cli.out …/canonical_client_expected.txt` → `IDENTICAL`.
**5/5 goldens byte-identical to the frozen md5s.**

### 4. `repro/mi_matrix` runtime anchor set (25 + oob)

Harness (golden-owner recipe `scripts/stdlib/run_fixtures.sh` — `zig1 -ffast -o` + `build_target.sh linux` + 3x run vs golden), the exact 25-dir set enumerated in Task 0 F1:

```bash
bash scripts/stdlib/run_fixtures.sh /tmp/p5_work/seed/zig1_5_clean \
  repro/mi_matrix/array_of_struct_literal_xmod … repro/mi_matrix/tagged_tag_sugar_xmod
```
Observed tail + all 25 lines `PASS repro/mi_matrix/<name>`:
```
----------------------------------------
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
In-bounds D5 confirmer inside the set: `slice_index_field_store_xmod` = `PASS` (the `9/11/22/ok` golden). D-fix trap subset (separate `-fsafe` recipe, Task 0 F3 shape):

```bash
/tmp/p5_work/seed/zig1_5_clean -fsafe -o /tmp/p5_work/anchor/oob repro/mi_matrix/slice_index_field_store_oob_xmod/main.zig   # dump rc=0
cd /tmp/p5_work/anchor/oob && sh build_target.sh linux ./prog                                                                # build rc=0
timeout 120 ./prog > run.out 2> run.err; echo "run rc=$?"   # -> run rc=133 (Trace/breakpoint trap)
wc -c < run.out                 # -> 0
md5sum < run.out                # -> d41d8cd98f00b204e9800998ecf8427e
md5sum < repro/mi_matrix/slice_index_field_store_oob_xmod/expected.txt   # -> d41d8cd98f00b204e9800998ecf8427e
```
**25/25 MATCH goldens (stdout md5 + rc each) + oob rc=133/empty MATCH. Set definition unchanged vs the frozen Task 0 anchor.**

### 5. `examples/z98/*/` matrix — build AND run

Build (per dir; entry resolution `main.zig` → `<dirname>.zig` → first `*.zig`):
```bash
/tmp/p5_work/seed/zig1_5_clean -ffast -o /tmp/p5_work/matrix/<name> <entry>          # dump rc=0 ×26
cd /tmp/p5_work/matrix/<name> && sh build_target.sh linux /tmp/p5_work/matrix/<name>/prog   # build rc=0 ×26
```
All 26 `.c` counts match the §1.4 baseline (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38). Run (`cd examples/z98/<name> && timeout 25 …`, mud 8s, rogue* fed `q\n`, else `/dev/null`):

| dir | rc | stdout md5 (16) | vs §1.4 baseline | verdict |
|---|---|---|---|---|
| days_in_month | 0 | `8c0d394cbc6e7f36` | same | correct |
| fibonacci | 0 | `b53b3a3d6ab90ce0` | same | correct |
| func_ptr_return | 0 | `f6a5477970a87a1c` | same | correct |
| game_of_life | 0 | `fcbf7e7cead5082f` | same | correct |
| heapsort | 0 | `8cf0a7844206319d` | same | correct |
| hello | 0 | `746308829575e17c` | same | correct |
| json_parser | 0 | `8bda3d5a1ec07d14` | same | correct |
| json_parser_upgraded | 0 | `8bda3d5a1ec07d14` | same | correct |
| json_parser_workaround | 0 | `dc22fa473650bd3d` | same | correct |
| lisp_interpreter | 0 | `1c1f0a417d5e9434` | same | correct |
| lisp_interpreter_adv | 0 | `1c1f0a417d5e9434` | same | correct |
| lisp_interpreter_curr | 0 | `1c1f0a417d5e9434` | same | correct |
| lisp_interpreter_upgraded | 0 | `1c1f0a417d5e9434` | same | correct |
| lzw | 0 | `c3c7765e6faf7b70` | same | correct |
| mandelbrot | 0 | `d596677501e36537` | same | correct |
| mud_server | 124 | `9545fe1d245293ef` | same | correct (documented timeout) |
| prime | 0 | `d095a94d20dcaf7a` | same | correct |
| quicksort | 0 | `45d2f0fb6fc40654` | same | correct |
| rogue_mud | 0 | `3fb6709e7bbd8964` | same | correct |
| rogue_mud_upgraded | 0 | `3fb6709e7bbd8964` | same | correct |
| sort_strings | 0 | `c6c047cbc13cdd4f` | same | correct |
| tco_defer | 0 | `264ea6b106a51dde` | same | correct |
| tco_factorial | 0 | `3d70c50b5a37d549` | same | correct |
| tco_return_try | 0 | `7421137aa2d104b4` | same | correct |
| z9play | 1 | `2016494de476fcb6` | same | correct (usage-on-no-args) |
| z9torr | 1 | `f666af15cf2625b3` | same | correct (usage-on-no-args) |

**26/26 build rc=0 + 26/26 run correct; every stdout md5 + rc identical to the frozen §1.4 table (z9play/z9torr rc=1, mud rc=124 = documented correct behaviors).**

### 6. Stdlib gate

```bash
bash scripts/stdlib/verify_stdlib.sh /tmp/p5_work/seed/zig1_5_clean
```
Observed (tail):
```
----------------------------------------
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```
**STDLIB GATE OK — 285 PASS / 0 FAIL; no lost PASS vs baseline 285.**

### 7. The 8 `--dump-c89` pin md5s — old→new

```bash
/tmp/p5_work/seed/zig1_5_clean <mode> --dump-c89 <ENTRY> 2>/dev/null | md5sum
```

| entry | mode | old (Task 0 frozen) | new (P5) | delta |
|---|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `-fsafe` | `498b90f191b544655a1b731ef480709d` | `498b90f191b544655a1b731ef480709d` | unchanged |
| `examples/z98/mud_server/main.zig` | `-ffast` | `50dbf5f02c1a5de920e158cab7f2f29b` | `50dbf5f02c1a5de920e158cab7f2f29b` | unchanged |
| `examples/z98/game_of_life/main.zig` | `-fsafe` | `52c5feb5f158e2af7b32a0509b43d4c6` | `52c5feb5f158e2af7b32a0509b43d4c6` | unchanged |
| `examples/z98/game_of_life/main.zig` | `-ffast` | `7271960fc6375ed1dee34b7abfb6325b` | `7271960fc6375ed1dee34b7abfb6325b` | unchanged |
| `examples/z98/lisp_interpreter_curr/main.zig` | `-fsafe` | `e6f96b81f00e678eeaaa1ea7ed7c2359` | `e6f96b81f00e678eeaaa1ea7ed7c2359` | unchanged |
| `examples/z98/lisp_interpreter_curr/main.zig` | `-ffast` | `ec82996028671a52a0a3d52ad307edf1` | `ec82996028671a52a0a3d52ad307edf1` | unchanged |
| `examples/z98/json_parser/main.zig` | `-fsafe` | `48eedfc0243431693f65518646ad280c` | `48eedfc0243431693f65518646ad280c` | unchanged |
| `examples/z98/json_parser/main.zig` | `-ffast` | `04124b2675e77020933cbfab20f883e1` | `04124b2675e77020933cbfab20f883e1` | unchanged |

**Pin delta count: 0/8 — emitted-C for user programs byte-identical (as predicted: the relocation is behavior-preserving; only the compiler's SELF-emission fixed point moved, item 1). Runtime proof = items 3–6.**

### 8. `--markers` telemetry

```bash
/tmp/p5_work/seed/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > /tmp/p5_work/mk_gol.c 2>/tmp/p5_work/mk_gol.bin
grep -ac '^' /tmp/p5_work/mk_gol.bin    # -> 3241
wc -c < /tmp/p5_work/mk_gol.bin         # -> 36038
```
Top prefixes (identical to the Task 0 §1.7 baseline): `1810 INT:new`, `423 DC:k`, `240 FE:p`, `195 P`, `195 FWD:n=`, `122 RaD`, `86 MT`, `69 FE:`.
**3,241 marker lines / 36,038 B — UNCHANGED vs frozen baseline.**

### Battery verdict summary

| gate | observed | vs frozen Task 0 anchor | verdict |
|---|---|---|---|
| seed two-hop closure | hop1 == hop2 == `e81d9266955caaad6873fb728d7f494e` | fixed point `bafbba94…` → `e81d9266…` (moved, allowed, recorded) | MATCH |
| corpus classify | 1124 = 950/58/116/0/0; per-dir list byte-identical (md5 `518eca1a…`) | Appendix A | UNCHANGED |
| runtime goldens | 5/5 md5s | frozen md5s | MATCH |
| mi_matrix anchors | 25/25 + oob rc=133/empty | §1.8 set (25+oob) | MATCH |
| examples matrix | 26/26 build + 26/26 run | §1.4 (incl. rc=1 ×2, rc=124) | MATCH |
| stdlib gate | 285 PASS / 0 FAIL, STDLIB GATE OK | 285/0 | MATCH |
| 8 dump pins | old→new recorded above | recorded-not-gated | delta 0/8 |
| markers | 3,241 lines / 36,038 B | 3,241 / 36,038 | UNCHANGED |

No gate failed; no observation diverges from the plan. Runtime behavior unchanged.
