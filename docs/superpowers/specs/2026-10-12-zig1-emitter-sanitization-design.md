# zig1 Emitter Sanitization & Compiler-Debt — Design

**Status:** Approved (operator, 2026-10-12)
**Goal:** Move responsibilities that the C89 emitter (`sf/src/c89_emit.zig`) holds but that logically belong to earlier compiler stages into **single canonical mechanisms**, and re-fix the recurring compiler defects **D1–D8 at root cause** rather than per-reproducer sites — so the emitter becomes a pure "spell the already-decided semantics as C" stage.

**Driver:** the defect post-mortems for `examples/torrent_example_defects.md` (D1–D8) plus three read-only surveys of `c89_emit.zig` showing that every fix so far was a targeted site fix converging on an ad-hoc pattern, and that the emitter holds at least seven categories of responsibility that belong upstream (naming, type-dependency ordering, C-type-name derivation, type classification, semantic predicates/promotion, re-deciding lowerer/analyzer decisions, ICE-encoding of semantic invariants).

**Blueprint / prior art:** `docs/superpowers/plans/2026-10-09-zig1-codegen-defects-plan.md` (D1–D5, fixed at repro sites), `examples/torrent_example_defects.md` (D1–D8), the emitter surveys run 2026-10-12.

**Sequence:** after the z9play M0–M4 example work. Branch `zig1_improvements`, base seed **v97** (fixed point `bafbba9454cd2b134bdc3d50c65384e0`). Compiler work is authorized again for this milestone; the seed rotates at closeout (and each increment that moves emitted C may rotate earlier).

---

## §1 Core invariant and gate — runtime correctness, NOT byte-identity

**Binding gate: runtime behavior.** The emitter's output MAY change; what must not change is what programs *do*:

- `scripts/corpus/classify` — no increase in `FAIL`/`ICE`/`CRASH`; the runtime classification of every corpus dir is unchanged (only the emitted-C bytes may differ).
- Runtime goldens: `game_of_life` (`fcbf7e7c…`), `lisp_interpreter_curr` `(+ 1 2)` (`b3d9f897…`), `json_parser` (`8bda3d5a…`), `mud_server` server/client (`66c8f0ab…`/`93147d0f…`) — byte-identical stdout.
- The **examples matrix** (all `examples/z98/*/`) builds **and runs** correctly.
- The stdlib gate (`scripts/stdlib/verify_stdlib.sh`) stays green.
- The compiler self-emission two-hop closure holds (`hop1==hop2`).
- The `repro/mi_matrix` runtime confirmations (the dedicated runtime reproducers, e.g. `slice_index_field_store_xmod` prints `9/11/22/ok`) still pass.

**Explicitly NOT a gate: emitted-C byte-identity.** The 8 `--dump-c89` MD5 pins are **recorded** (old→new, with the runtime proof) and re-baselined when they move; a moved pin is expected and accepted for this milestone. Likewise any example's `--dump-c89` md5 may move.

**Every example must remain runtime-correct** — no functionality regresses; the strongest form of "equivalent" is runtime equivalence.

## §2 Scope and boundaries

**In scope:** the emitter-held responsibilities below, relocated to canonical single mechanisms; and root-cause fixes for D1–D8.

**Out of scope:** changing Z98 language semantics; new language features; the z9play example work (M5+) except where the emitter change forces a re-baseline; performance work not tied to a relocated responsibility; any change that alters a program's runtime behavior.

## §3 The seven smell categories (evidence summary)

1. **No single naming authority (roots D1, D2).** `NameMangler` is defined inside `c89_emit.zig:93`; `sf/src/name_mangler.zig` is a dead 7-line stub and `ctx.name_mangler` is written but never read. Keyword/collision handling is partial: `nameManglerMangle:657` does collision resolution, but **struct field names emit raw** (`:2091`, access `:468/:513/:524/:558`), union-member escape has no collision check (`:577/:594`), locals (`:2431`), temps (`:3195`), synthetic type names (`:897/:931/:940`), module symbols (`:2795`) and printer symbols (`:5530`) are each minted ad-hoc.
2. **Two divergent type-dependency graphs (roots D8).** Resolver graph `typeResolverBuildDependencyGraph` (`type_resolver.zig:629`) + `typeResolverGetSorted:889` are **dead**; the emitter's `c89NeedsEmitEdge:1324`, `tstEdgesWalk:1363`, `tstTopologicalSort:1484` drive emission. Predicates diverge (`c89NeedsEmitEdge` vs `layoutFieldNeedsEdge`/`fieldEmbedsByValue`/`requiresFullDef` vs the dead `type_registry.isValueDependency`); `fn_type` is missing in both; `packed_union` is missing in the emitter.
3. **`getCTypeName` re-derives the synthetic type model** (`:940`) and duplicates itself (`emitArrayType:2145`, `emitOptionalType:2373`); the emitter **writes** the `c_name_map` memo back into `TypeRegistry` (`:2428`).
4. **Classification overlap.** Resolver `classifyTypeEmissionGroups` (`type_resolver.zig:662`) vs emitter `computeSharedSet:1702` / `shouldSkipTypeEmission:1775`.
5. **Semantic predicate/promotion duplication.** Emitter re-implements int-kind signedness/width/scalar predicates (`:9473-9496`, `:4712-4929`, `:4895`) owned by `type_registry.zig:919-1049`, and C usual-arithmetic promotion (`emitBinRvalueText:4385`) owned by `coercion.zig`.
6. **Re-deciding lowerer/analyzer decisions.** `resolveFieldAccess:459` re-resolves fields already resolved by `semantic_analyzer.zig:1562`; `findCalleeFnTypeId:2458` linear-scans all types to recover the callee fn type; `getTemp*`/`hoisted*` (`:1172-1208`, `:4963-5028`) re-derive temp types; saturation semantics live in `emitSatBinary:5030-5400`.
7. **ICEs encoding semantic invariants + dead code** (`nest*`, dead `isValueDependency`, `typeResolverGetSorted`, the `name_mangler` stub).

## §4 Target architecture — the canonical components

| Component | Owns | Consumed by |
|---|---|---|
| **Identifier authority** (`sf/src/name_mangler.zig`, revived) | minting every emitted C identifier: C-keyword escape + collision resolution + stable per-kind names (fn/global/type/local/temp/union-member/**struct-field**/synthetic-type/module/printer) | emitter (all name sites), lowerer (if it coins names) |
| **Type-reference relation** (`sf/src/type_registry.zig`) | `typeRefs(tid)` → the type ids a type references; `typeNeedsFullDef(tid)` | resolver dependency graph **and** the emitter's typedef ordering (one source) |
| **C type-name** (`type_registry`/`type_resolver`) | `typeCName(tid)` → the canonical C type name (synthetic names minted here, once) | emitter (decl + use) |
| **Type classification** (`type_resolver`) | pointer-only / value-embeds / needs-definition — completed at the backend-neutral `phase_EmissionClassification` boundary (state: `EmissionClassification` on `CompilerContext`) | emitter (reads completed state only; never triggers classification) |

**§4.1 Decision-vs-spelling rule (binding; operator ruling 2026-10-12).** Every phase decides only what that phase owns; the emitter **spells** decided semantics as C89 and never **decides** anything Zig/program-level (existence, membership, ordering, types, which values). A helper invoked at emit time whose output selects between semantics is FORBIDDEN — its decision must be recorded at its owning phase. C89-specific *spelling* (syntax surface, carrier application via `sf/src/c89_plan.zig`, labels, typedef-name application) is legitimate in the C layers. If a task's intent cannot be satisfied under this rule, the implementer **STOP-presents** in this exact form: `I found the intention is X, but this is impossible given Y` — with Y as evidence; never improvise a variant.
| **Predicates + promotion** (`type_registry` + `coercion`) | int kind/signedness/width, scalar/pointer, usual arithmetic conversions | analyzer, lowerer, emitter |
| **Lowerer-carried decisions** (`lower.zig` + `lir.zig`) | field ordinal/name, callee fn type id, temp result type, int-const **semantic** width/signedness, saturation **semantic** op | emitter (reads; no re-resolution; spells only) |
| **C89 spelling planner** (`sf/src/c89_plan.zig`, NEW — P6-pre, ruling (ii)) | C-only choices: carrier derivation (moved out of lowering), typedef emission order (P12), C usual-arithmetic cast direction (P11), side-table state at the `phase_EmissionClassification` boundary | emitter (spell-time read) |
| **Front-end name resolution** (`semantic_analyzer`/`type_resolver`) | module-scope-first (lexical) type-name resolution | analyzer/lowerer (roots D7) |
| **Builtin descriptor table** (`semantic_analyzer`) | per-builtin expected arity (+ kind) | sema dispatch (roots D6) |
| **Frame-save rule** (`async_state_machine`/`lower.zig`; carried on frame layout/LIR) | WHAT to save/restore: only declared temps; no global by-value round-trip (roots D3/D4) — emitter spells from the carried set | async lowering → carried set → emitter (spelling) |
| **Lvalue address-taking** (`lower.zig`) | one checked address-taking path for aggregate/index/field/deref chains (roots D5; closes the sibling `-fsafe` gap) | lowerer |

## §5 Increment catalog (preflight fixes the execution order)

- **P1 Identifier authority** — revive `name_mangler.zig` as the single minter; route union tags, **struct fields**, locals, temps, synthetic type names, module/printer symbols through it; delete the dead stub usage. Fixes D1 (incl. struct fields), D2 (synthetic names), the fragmentation class.
- **P2 Type-reference relation + ordering** — add `typeRefs`/`typeNeedsFullDef` to `type_registry`; make the resolver graph and the emitter's `tstTopologicalSort` both derive from it; add `fn_type` + `packed_union`; delete the dead `typeResolverGetSorted` and the divergent `c89NeedsEmitEdge`. Fixes D8.
- **P3 Canonical `typeCName`** — one derivation; emitter stops writing `c_name_map`; dedup `emitArrayType`/`emitOptionalType`. Closes D2 residue.
- **P4 Single classification pass** (amended 2026-10-12 — operator ruling option (a) + placement correction) — one classification mechanism in `type_resolver` (`classifyTypeEmissionGroups` resolution-time + `classifyTypeEmissionFinalize` completed at the backend-neutral `phase_EmissionClassification` boundary between LIR lowering and emission; **never invoked by the emitter**); state (`shared_set`/`pointer_only_map`/`needs_def_map`/`needed_tuple_set`) in `EmissionClassification` on `CompilerContext`; `collectNeededTuples` moves to `type_resolver`; remove emitter `computeSharedSet`/`shouldSkipTypeEmission`. P4 fix round 2 corrects the landed emitter-invoked-finalize placement (a Decision-vs-spelling deviation).
- **P5 Predicates + promotion centralized** — expose canonical `type_registry` predicates and `coercion` promotion; delete emitter truth tables.
- **P6-pre C89 spelling planner** (NEW, operator ruling 2026-10-12 (ii); execution position after P4, before P6) — new module `sf/src/c89_plan.zig` at the backend-neutral `phase_EmissionClassification` boundary: LIR carries semantic int facts only (width-bits/signedness/value); carrier derivation moves OUT of `lowerExactIntArg`/lowering INTO the planner (C-spelling choice, side-table state read by the emitter); an asm backend gets its own planner over the same semantic LIR.
- **P6 Lowerer carries decisions** (amended 2026-10-12 — semantic-only LIR) — record field ordinal/name, callee fn type, temp result types, int-const semantic width/signedness, saturation semantic op on LIR; emitter reads and spells only. Removes `resolveFieldAccess`/`findCalleeFnTypeId`/`getTemp*` re-resolution; `emitSatBinary` semantics are recorded at lowering and spelled by the emitter (no emit-time deciding helper).
- **P12 Typedef ordering planning** (NEW 2026-10-12; after P6-pre, before P6) — compute the typedef emission order once at the `phase_EmissionClassification`/`c89_plan` boundary and carry it; emitter walks, never sorts (kills the emit-time double sort; P2's popped/append moves with it).
- **P11 Promotion spelling from carried result types** (NEW 2026-10-12; after P6, before P10) — replace `coercionUsualArithPromote`'s emit-time C-UAC cast-direction decision with mechanical cast-to-carried-result-type spelling; `coercion.zig` loses the C-specific rule.
- **P7 Front-end module-scope-first name resolution** — roots D7.
- **P8 Builtin arity/descriptor table** — roots D6 and closes the ~20 unchecked builtins.
- **P9 Structural frame-save rule** (amended 2026-10-12 — WHAT/HOW split): WHAT to save/restore (only declared temps; no global by-value round-trip) is decided in `async_state_machine`/`lower.zig` and carried on the frame layout/LIR (roots D3/D4); the emitter spells save/restore from the carried set; the `nest_inl` guard is C-shape spelling with carried inputs only.
- **P10 Lvalue unification** — single checked address-taking path; add the `-fsafe` root check to the sibling `lowerFieldStore` index arm (D5 residue).

## §6 Gates

Per increment (and at closeout) the **runtime** battery of §1. Because emitted C may change, each increment records the pin/example-md5 delta (old→new) with the runtime proof. Because naming/order changes can move the self-emission fixed point, the seed rotates at closeout (and any increment that moves it may rotate early, recorded + verified `hop1==hop2`).

## §7 Risks

1. **Self-hosted bootstrap.** The compiler builds itself; a wrong emitter change can break hop1==hop2 in ways that are hard to bisect. Mitigation: one responsibility per increment; full runtime battery; commit per increment.
2. **Runtime-equivalence oracle breadth.** "Runtime correct" must be demonstrated across corpus + goldens + examples; some paths (sparse/DHT/audio) are only covered by specific tiers. Mitigation: run the full battery, not a subset.
3. **Byte drift is expected and must be *proven benign*** — every moved pin needs runtime evidence, never a silent re-baseline.
4. **Dead-code deletion** (`typeResolverGetSorted`, `name_mangler` stub, `isValueDependency`) must be confirmed truly dead first.
5. **Scope creep into a rewrite.** The milestone moves responsibilities; it does not redesign the pipeline.

## §8 Out of scope
Language semantics; new features; z9play M5+; the parked D7/D8 example workarounds (they become unnecessary once P7/P2 land, but the examples need not change); performance tuning unrelated to a relocated responsibility.

## §9 Milestone index (updated)
`2026-10-12 zig1 emitter sanitization & compiler-debt` → `docs/superpowers/plans/2026-10-12-zig1-emitter-sanitization-plan.md`. Ordered P0→P10→closeout; **Task 0 (preflight) fixes the execution order** and finalizes the runtime-equivalence battery. **z9play is PAUSED**; **after this milestone the next plan is to continue the z9play plan at M5** (`docs/superpowers/plans/2026-10-11-z9play-m5-cli-plan.md`, the CLI frontend), then M6+.

**Amendment (operator ruling, 2026-10-12):** §4.1 Decision-vs-spelling rule binding; P4 amended + P4 fix round 2 (placement correction — classification completes at a backend-neutral boundary, never emitter-invoked); NEW P6-pre (C89 spelling planner `sf/src/c89_plan.zig`, ruling (ii): carriers are C-spelling, never LIR fields); P6 semantic-only LIR; P9 WHAT/HOW split. Execution position: P4 fix round 2 → P6-pre → P6.

**Amendment 2 (operator ruling, 2026-10-12):** NEW **P12 Typedef ordering planning** (order computed once at the `phase_EmissionClassification`/`c89_plan` boundary and carried — ordering is on the emitter's never-decides list; kills the emit-time double sort `c89_emit.zig:2291` + `main.zig:1379`) and NEW **P11 Promotion spelling from carried result types** (replaces `coercionUsualArithPromote`'s emit-time C-UAC decision with mechanical cast-to-carried-result-type; `coercion.zig` loses the C-specific rule). P13 (C-naming residue consolidation) stays DEFERRED. Execution order now: P4 fix round 2 → P6-pre → P12 → P6 → P11 → P10 → P9 → P8 → P7 → Task C.

**Amendment 3 (operator ruling, 2026-10-14):** latent-class closures execute as ONE combined fix dispatch (P6-pre fix round 3 + P12 fix round 1) with ONE battery/gates run — H1: `.int_const` facts populated at every construction site (completes "LIR carries semantic int facts only" structurally; "gate-unreadable today" optimism retired); H2: header walk bounded on the sort snapshot length (P2 follow-up, named owner); H3: comment truth-up. One review covers the combined diff + P12 round-0. Ruling (b) superseded — P6 stays lean. Execution: … P6-pre → P12 → **combined fix + review** → P6 → P11 → P10 → P9 → P8 → P7 → Task C.

**Amendment 4 (operator ruling, 2026-10-14):** P6 touch-set clarification — "lean" excludes only the facts-fill work (already closed by combined fix H1). P6 deliverable unchanged: record semantic decisions on LIR in `lower.zig`+`lir.zig` AND remove the named emitter re-derivations (`resolveFieldAccess` re-resolution, `findCalleeFnTypeId`, `getTemp*`/`hoisted*` re-derivation, `emitSatBinary` emit-time semantics) in `c89_emit.zig` — touch set `lower.zig` + `lir.zig` + `c89_emit.zig` (named removals/consumption only).

**Amendment 5 (operator ruling, 2026-10-14):** P6 STOP resolution — (1a) touch set extended with `async_state_machine.zig` **copier-only** (`remapInst`/sibling reconstructor payloads copy every new P6 record field, `int_const`-facts copier precedent `82ff0743`); (2) saturation semantic op = **A15-pattern**: sat-family LIR payloads carry `result_type`/`width`/`is_signed` recorded at lowering (like `*_with_overflow`, `lir.zig:122-127`); `emitSatBinary` spells only from carried fields; `getTempTypeInfo` emit-time re-derivation (`c89_emit.zig:6827`) removed.
