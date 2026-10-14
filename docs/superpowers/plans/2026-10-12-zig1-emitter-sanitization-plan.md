# zig1 Emitter Sanitization & Compiler-Debt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `sf/src/c89_emit.zig` a pure "spell decided semantics as C" stage by relocating seven categories of emitter-held responsibility into canonical single mechanisms, and re-fixing compiler defects D1–D8 at root cause — gated on **runtime correctness** (emitted C may change).

**Architecture:** Task 0 (preflight) freezes the baseline, builds the runtime-equivalence battery, completes the emitter smell inventory, and **fixes the execution order** of increments P1–P10 (extended 2026-10-12 with P4-fix-2/P6-pre/P12/P11 per operator rulings). Each increment is one responsibility, implemented as a separate compiler-moving commit with the full runtime battery; the seed rotates at closeout.

**Tech Stack:** Z98 self-hosted `zig1` (C89 emission), the seed bootstrap (`scripts/seed/build_from_seed.sh`), `gcc -m32 -std=c89`, `repro/mi_matrix` + stdlib + examples harnesses.

**Spec:** `docs/superpowers/specs/2026-10-12-zig1-emitter-sanitization-design.md` (binding). Prior art: `docs/superpowers/plans/2026-10-09-zig1-codegen-defects-plan.md`; `examples/torrent_example_defects.md` (D1–D8).

**Sequence:** PREVIOUS: z9play M0–M4 (`examples/z98/z9play/**`). Branch `zig1_improvements`, base seed **v97** (`bafbba9454cd2b134bdc3d50c65384e0`).

**z9play is PAUSED for this milestone.** **After this emitter-sanitization milestone is complete, the NEXT plan is to CONTINUE the z9play plan at M5** (`docs/superpowers/plans/2026-10-11-z9play-m5-cli-plan.md` — the CLI frontend), then M6+ (Win9x, TUI, optional FLAC).

## Global Constraints

- **Runtime correctness IS the gate; emitted-C byte-identity is NOT.** Every increment must keep: corpus classify runtime class unchanged (no new `FAIL`/`ICE`/`CRASH`), runtime goldens byte-identical stdout, the examples matrix building+running correctly, the stdlib gate green, and the compiler self-emission two-hop closure (`hop1==hop2`). The 8 `--dump-c89` MD5 pins and any example md5 are **recorded old→new with runtime proof**, not held fixed.
- **Runtime behavior must never change.** Every example stays runtime-correct; no functionality regresses.
- **Compiler work is authorized** for this milestone. **Seed rotates at closeout**; an increment that moves the self-emission fixed point may rotate early (record + verify `hop1==hop2`).
- **Build the seed:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` → `<out>/zig1_5_clean`.
- **Runtime battery** (defined once, referenced by every task):
  - seed rebuild `hop1==hop2`;
  - `bash scripts/corpus/classify <zig1> <outfile>` (runtime class; compare to the frozen baseline);
  - runtime goldens `game_of_life`/`lisp_interpreter_curr`/`json_parser`/`mud_server` byte-identical;
  - `repro/mi_matrix` runtime reproducers (incl. `slice_index_field_store_xmod` → `9/11/22/ok`);
  - the `examples/z98/*/` matrix (build **and run**);
  - `bash scripts/stdlib/verify_stdlib.sh <zig1>` (green);
  - record the 8 `--dump-c89` pin md5s (delta is allowed) + `--markers` telemetry.
- `edit`/`fastedit` only for source edits (AGENTS.md X.7: re-read region before each edit; bottom-to-top; INSERT = replace the anchor line with `[new content + original anchor line]`).
- **Decision-vs-spelling (operator ruling, 2026-10-12):** every phase decides only what that phase owns; the emitter **spells** decided semantics as C89 and never **decides** anything Zig/program-level (existence, membership, ordering, types, which values). A helper invoked at emit time whose output selects between semantics is FORBIDDEN — its decision must be recorded at its owning phase. C89-specific *spelling* (syntax surface, carrier application via `sf/src/c89_plan.zig`, labels, typedef-name application) is legitimate in the C layers. If a task's intent cannot be satisfied under this rule, the implementer **STOP-presents** in this exact form: `I found the intention is X, but this is impossible given Y` — with Y as evidence; never improvise a variant.
- **The plan is the only authority.** If the plan says A, do A; if a better X/Y surfaces, STOP-present. STOP on any issue or unforeseen divergence. No corner cuts. No unrelated fixes.
- **NO push. GIT HARD RULE:** never `git reset --hard/--keep`, `git checkout --`, `git restore`, `git clean`, `git stash drop/clear`, force-push, or history rewriting; only `git commit --amend` on your OWN just-created commit.
- Go with agents (SDD). Reports/ledger under `.superpowers/sdd/2026-10-12-zig1-emitter-sanitization-plan/` (commit via `git add -f`).
- Pre-existing untracked root strays and `lin_bin/` are not ours.

---

### Task 0: Preflight — baseline, runtime battery, inventory, and execution ORDER

**Files:** Read-only inventory of `sf/src/c89_emit.zig` + the upstream stages; Report + ledger.

- [ ] **Step 1: Baseline.** Build the seed (`bafbba9454cd2b134bdc3d50c65384e0`); freeze the §1 runtime baseline: corpus classify tally + runtime outputs, the 4 runtime goldens, the examples matrix build+run results, stdlib gate, the current 8 `--dump-c89` pin md5s, and the self-emission closure. Record every command + observed value.
- [ ] **Step 2: Inventory.** Complete the emitter smell inventory (the §3 categories + any more the survey missed): for each, `file:line`, what it duplicates, the upstream stage that should own it, and a runtime-risk/effort note.
- [ ] **Step 3: Order.** **Determine and record the execution order of P1–P10** (and any split/merge of an increment), justified by dependency + runtime-risk. Write the ordered list to the ledger; this order governs the remaining tasks.
- [ ] **Step 4: Report + commit** (report + ledger only; no `sf/src` change).

**Gate:** baseline + inventory recorded; the ordered increment list (P1–P10) committed to the ledger.

---

### Tasks P1–P12 (incl. P6-pre, P11, P12 — added 2026-10-12): The increments (execute in the recorded order — Task 0 order as amended 2026-10-12 + the 2026-10-14 amendment: P5, P1, P2, P3, P4, P4-fix-2, P6-pre, P12, **combined fix (P6-pre-f3 + P12-f1, one battery) + one review**, P6, P11, P10, P9, P8, P7)

Each increment is **one responsibility**: an **Investigate** (read-only census + precise edit plan) then an **Implement** (compiler-moving, one commit), always followed by the **runtime battery** and an old→new md5 record. Files below are the expected touch set; the Investigate step confirms them.

- [ ] **P1: Identifier authority.** Revive `sf/src/name_mangler.zig` as the single C-identifier minter (keyword escape + collision resolution + stable per-kind names); route union tags, **struct field names** (`c89_emit.zig:2091`, access `:468/:513/:524/:558`), locals (`:2431`), temps (`:3195`), synthetic type names (`:897/:931/:940`), module symbols (`:2795`) and printer symbols (`:5530`) through it; delete the dead stub usage (`ctx.name_mangler`). Fixes D1 (incl. struct fields), D2 (synthetic names), fragmentation. Gate: runtime battery.
- [ ] **P2: Type-reference relation + ordering.** Add `typeRefs(tid)` + `typeNeedsFullDef(tid)` to `sf/src/type_registry.zig` (covering all kinds incl. `fn_type` and `packed_union`); derive both `typeResolverBuildDependencyGraph` and the emitter's `tstTopologicalSort`/`tstEdgesWalk` from it; delete the dead `typeResolverGetSorted` and the divergent `c89NeedsEmitEdge`. Fixes D8. Gate: runtime battery.
- [ ] **P3: Canonical `typeCName`.** One derivation (in `type_registry`/`type_resolver`); emitter `getCTypeName` consumes it; remove the emitter's write-back into `type_registry.c_name_map` (`c89_emit.zig:2428`); dedup `emitArrayType:2145`/`emitOptionalType:2373`. Closes D2 residue. Gate: runtime battery.
- [ ] **P4: Single classification pass (amended 2026-10-12 — operator ruling option (a) + placement correction; supersedes the original one-liner).** One classification mechanism owned by `sf/src/type_resolver.zig`: `classifyTypeEmissionGroups` (resolution-time) plus `classifyTypeEmissionFinalize` completed at a backend-neutral `phase_EmissionClassification` boundary between `phase_LIRLowering` and `phase_C89Emission` (`sf/src/main.zig`) — **never invoked by the emitter**. Classification state (`shared_set`/`pointer_only_map`/`needs_def_map`/`needed_tuple_set`) lives in an `EmissionClassification` struct on `CompilerContext`; the emitter reads completed state only. `collectNeededTuples` moves out of `c89_emit.zig` into `type_resolver.zig`, driven from the LIR/ctx hoisted inventory at the same boundary. Remove emitter `computeSharedSet:1702`/`shouldSkipTypeEmission:1775`; consume the resolver classification. Gate: runtime battery.
- [ ] **P4 fix round 2 — placement correction (operator ruling 2026-10-12; the landed P4 shape with emitter-invoked `classifyTypeEmissionFinalize` at `c89_emit.zig:1140` is a Decision-vs-spelling deviation being corrected here).** Move the finalize call out of `emitTypePasses` into `phase_EmissionClassification`; move the four result maps off `C89Emitter` onto `CompilerContext`; move `collectNeededTuples` into `type_resolver.zig` with its loops in the boundary step; delete the late-type "snapshot whitelist" workaround (full-registry walk at the boundary). Gate: runtime battery (pins 0/8 expected).
- [ ] **P5: Predicates + promotion centralized.** Expose canonical `type_registry` int-kind/scalar/pointer predicates and `coercion` promotion; delete the emitter truth tables (`:9473-9496`, `:4712-4929`, `:4895`, `emitBinRvalueText:4385`). Gate: runtime battery.
- [ ] **P6-pre: C89 spelling planner (NEW, operator ruling 2026-10-12; execution position — after P4 completes, before P6).** New module `sf/src/c89_plan.zig`: a C-specific pre-emit planner at the same backend-neutral `phase_EmissionClassification` boundary. LIR carries **semantic** int facts only (width-bits/signedness/value); carrier derivation (i32/u32/i64/u64) moves OUT of `lowerExactIntArg`/lowering INTO the planner (side-table state, read by the emitter at spell time). Ruling (ii): carriers are C-spelling choices, never LIR fields — an asm backend gets its own planner over the same semantic LIR. Gate: runtime battery.
- [ ] **P6: Lowerer carries decisions (amended 2026-10-12 — semantic-only LIR per the Decision-vs-spelling rule).** Record on LIR (in `sf/src/lower.zig` + `sf/src/lir.zig`): field ordinal/name, callee fn type id, temp result types, int-const semantic width/signedness, saturation **semantic** op. Emitter reads them and spells only — remove `resolveFieldAccess:459` re-resolution, `findCalleeFnTypeId:2458`, `getTemp*`/`hoisted*` re-derivation; `emitSatBinary:5030-5400` semantics are recorded at lowering and spelled by the emitter (no emit-time helper may decide). Gate: runtime battery.
- [ ] **P12: Typedef ordering planning (NEW, operator ruling 2026-10-12; execution position — after P6-pre, before P6).** Compute the typedef emission order ONCE at the backend-neutral `phase_EmissionClassification`/`c89_plan` boundary and carry it (`sorted`); the emitter walks the carried order and never sorts. Moves `tstTopologicalSort` out of the emitter (today called at emit time `c89_emit.zig:2291` AND again `main.zig:1379` — double sort); P2's popped/append cycle-residue machinery moves with it. Ordering is on the "emitter never decides" list. Gate: runtime battery.
- [ ] **P11: Promotion spelling from carried result types (NEW, operator ruling 2026-10-12; execution position — after P6, before P10).** With P6's LIR-carried temp result types, the C usual-arithmetic cast direction becomes mechanical (cast to the carried semantic result type) — replace `coercionUsualArithPromote`'s emit-time decision (`coercion.zig:238`, called `c89_emit.zig:3622`) with the carried-type spelling (planner side-table or pure mechanical spelling from carried types); `coercion.zig` loses the C-specific rule (it was a P5 verbatim relocation made before the Decision-vs-spelling rule existed). Gate: runtime battery.
- [ ] **P7: Front-end module-scope-first name resolution.** Resolve unqualified type names lexically (module scope first) in `sf/src/semantic_analyzer.zig`/`type_resolver.zig`; root-causes D7. Gate: runtime battery (plus a reproducer proving the `Mode`-collision resolves module-locally).
- [ ] **P8: Builtin arity/descriptor table.** Central per-builtin expected-arity (and kind) table in `sf/src/semantic_analyzer.zig`, consulted before the dispatch ladder; close the ~20 unchecked builtins. Root-causes D6. Gate: runtime battery (plus arity reproducers).
- [ ] **P9: Structural frame-save rule (amended 2026-10-12 — WHAT/HOW split per the Decision-vs-spelling rule).** **WHAT:** the set of temps to save/restore is decided in `sf/src/async_state_machine.zig`/`sf/src/lower.zig` (save/restore only declared temps; remove the global by-value round-trip) and carried on the frame layout/LIR — never computed at emit time. **HOW:** the emitter spells the save/restore from the carried set; the `nest_inl` suppression-path guard (`c89_emit.zig:3827-3828`) is legitimate C-shape spelling ONLY with carried inputs (no emit-time decisions). Roots D3/D4. Gate: runtime battery.
- [ ] **P10: Lvalue unification.** `sf/src/lower.zig`: one checked address-taking path for aggregate/index/field/deref chains; add the `-fsafe` root-index check to the sibling `lowerFieldStore` index arm. Closes D5 residue. Gate: runtime battery.

**Per-increment commit:** `refactor(<file>): <increment one-line>` (compiler source only + tech docs).

**Amendment (operator, 2026-10-14):** P6-pre fix round 3 + P12 fix round 1 execute as **ONE combined fix dispatch with ONE battery/gates run**. Contents: **H1** — `width_bits`/`is_signed` populated at EVERY `.int_const` construction site (`lir_opt_pass.zig:2021/:2034/:2042` folds = folded op's width/sign; ~23 `async_state_machine.zig` own-consts = concrete temp type's width/sign; census for strays; copiers already fixed) — structurally completes "LIR carries semantic int facts only"; the hoist-gate argument is retired as insufficient ("non-exercised today" optimism). **H2** — `emitModuleHeaderFile` walk + any sibling live-bounded walker over `sorted` bounded on the sort snapshot length (named owner of the P2 deferred follow-up) — the over-read class becomes structurally impossible. **H3** — `type_registry.zig:1243` comment truth-up (planner attribution). Then ONE review covering the combined diff + P12 round-0 (two verdicts). **Ruling (b) SUPERSEDED:** the facts fill is NOT P6 scope — **P6 stays lean** (original `lower.zig` + `lir.zig` touch set).

**Amendment 4 (operator, 2026-10-14, "proceed with the plan … ammend and continue"): P6 touch-set clarification.** "P6 stays lean (original `lower.zig` + `lir.zig` touch set)" is clarified as: **lean = the facts-fill work (lir_opt_pass/async_state_machine sites) is NOT P6 scope** (already closed by the combined fix H1). P6's own deliverable text is unchanged and binding: record on LIR in `sf/src/lower.zig` + `sf/src/lir.zig` (field ordinal/name, callee fn type id, temp result types, int-const semantic width/signedness [done in P6-pre], saturation **semantic** op) **and** remove the named emitter re-derivations in `sf/src/c89_emit.zig` (`resolveFieldAccess` re-resolution, `findCalleeFnTypeId`, `getTemp*`/`hoisted*` re-derivation; `emitSatBinary` semantics recorded at lowering and spelled by the emitter — no emit-time helper may decide). Touch set = `lower.zig` + `lir.zig` (record) + `c89_emit.zig` (ONLY the named removals/consumption). Nothing else — no unrelated fixes, no P11 promotion work.

**Amendment 5 (operator rulings, 2026-10-14, "1. a) 2. A15-pattern"): P6 implementer STOP resolution.** The P6 Investigate STOP-presented that `async_state_machine.zig:316-365` `remapInst` rebuilds LIR payloads field-by-field (`.binary`/`.load_field`/`.store_field`/`.addr_of_field`/`.call`/`.func_ref`) — any new record field is dropped across the async user-body remap (same bug class as the P6-pre review-found copier bug `82ff0743`), making Amendment 4's closed touch set unable to deliver P6's record requirement. Operator ruled:
- **(1a)** Touch set EXTENDED with `sf/src/async_state_machine.zig`, **copier-only** edits: `remapInst` (and any sibling payload reconstructor in that file, e.g. `copyCallDirect`/`copyTailCall` side-table entries) must copy every new P6 record field 4-field-style exactly like the `int_const` facts copier precedent (`:352`, commit `82ff0743`). No other async_state_machine changes.
- **(2) A15-pattern for the saturation semantic op:** the sat-capable LIR payloads (the `binary` sat-op family, ops ≥ 19 / the `*_with_overflow` records' precedent `lir.zig:122-127`) carry `result_type`/`width`/`is_signed` **recorded at lowering** (semantic facts — matching the `add_with_overflow` shape where "Lowering computes `result_type`/`width`/`is_signed`"). The emitter's `emitSatBinary` (`c89_emit.zig:4166`) spells ONLY from the carried fields; the `getTempTypeInfo` re-derivation at `c89_emit.zig:6827` (and the `b.op >= 16` wty/wsg derivation path feeding it) is removed as an emit-time decision. `width`/`is_signed` are semantic (P5 predicates computed at lowering), never C carriers.
- P6 deliverable otherwise UNCHANGED (field ordinal/name, callee fn type id, temp result types recorded on LIR; named emitter removals `resolveFieldAccess` re-resolution, `findCalleeFnTypeId`, `getTemp*`/`hoisted*` re-derivation). Facts-fill remains out of scope (combined fix H1 closed it). P11 promotion work stays out of scope.

---

### Task C: Closeout

**Files:** `examples/torrent_example_defects.md` (mark D1–D8 FIXED with the root-cause mechanism + commit); `docs/sf/QUICK_REF.md` (re-baselined pins + seed); `release/seed/CHANGELOG.md`; rotate `release/seed/zig1-seed.tgz`; Report.

- [ ] **Step 1:** Full runtime battery on the final compiler; record the 8 pin md5s old→new with runtime proof.
- [ ] **Step 2:** Update the defect ledger: D1–D8 each marked **FIXED at root cause** (mechanism + commit); note any residual class item.
- [ ] **Step 3:** Rotate the seed (v97 → next); verify `hop1==hop2`; record the new fixed point + archive md5.
- [ ] **Step 4:** Commit `docs: zig1 emitter sanitization closeout + seed vNN`; commit the ledger via `git add -f`.

**Gate:** runtime battery green; defect ledger + QUICK_REF consistent; new seed archived + self-consistent.

---

### Final review

Dispatch the final whole-branch code review over the milestone range (base `3b7145d2` → HEAD) on the most capable model; adjudicate findings per the SDD breaker; then `finishing-a-development-branch` (operator keeps the branch as-is / no push per standing directive).

## Self-Review

- **Spec coverage:** §3 categories 1–7 → P1 (naming), P2 (dependency), P2/P3 (type-name), P4 (classification), P5 (predicates/promotion), P6 (carried decisions), P7 (front-end names), P8 (arity), P9 (frame-save), P10 (lvalue); D1–D8 each mapped.
- **Ordering:** Task 0 Step 3 fixes the P1–P10 order per operator ruling.
- **Gate:** §1 runtime battery is defined once in Global Constraints and referenced by every task; byte-identity explicitly not a gate.
- **No placeholders:** file:line sites are concrete (from the 2026-10-12 surveys); each increment's Investigate step re-derives exact sites before editing.
