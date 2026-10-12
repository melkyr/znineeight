# zig1 Emitter Sanitization & Compiler-Debt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `sf/src/c89_emit.zig` a pure "spell decided semantics as C" stage by relocating seven categories of emitter-held responsibility into canonical single mechanisms, and re-fixing compiler defects D1–D8 at root cause — gated on **runtime correctness** (emitted C may change).

**Architecture:** Task 0 (preflight) freezes the baseline, builds the runtime-equivalence battery, completes the emitter smell inventory, and **fixes the execution order** of increments P1–P10. Each increment is one responsibility, implemented as a separate compiler-moving commit with the full runtime battery; the seed rotates at closeout.

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

### Tasks P1–P10: The increments (execute in the Task-0 order)

Each increment is **one responsibility**: an **Investigate** (read-only census + precise edit plan) then an **Implement** (compiler-moving, one commit), always followed by the **runtime battery** and an old→new md5 record. Files below are the expected touch set; the Investigate step confirms them.

- [ ] **P1: Identifier authority.** Revive `sf/src/name_mangler.zig` as the single C-identifier minter (keyword escape + collision resolution + stable per-kind names); route union tags, **struct field names** (`c89_emit.zig:2091`, access `:468/:513/:524/:558`), locals (`:2431`), temps (`:3195`), synthetic type names (`:897/:931/:940`), module symbols (`:2795`) and printer symbols (`:5530`) through it; delete the dead stub usage (`ctx.name_mangler`). Fixes D1 (incl. struct fields), D2 (synthetic names), fragmentation. Gate: runtime battery.
- [ ] **P2: Type-reference relation + ordering.** Add `typeRefs(tid)` + `typeNeedsFullDef(tid)` to `sf/src/type_registry.zig` (covering all kinds incl. `fn_type` and `packed_union`); derive both `typeResolverBuildDependencyGraph` and the emitter's `tstTopologicalSort`/`tstEdgesWalk` from it; delete the dead `typeResolverGetSorted` and the divergent `c89NeedsEmitEdge`. Fixes D8. Gate: runtime battery.
- [ ] **P3: Canonical `typeCName`.** One derivation (in `type_registry`/`type_resolver`); emitter `getCTypeName` consumes it; remove the emitter's write-back into `type_registry.c_name_map` (`c89_emit.zig:2428`); dedup `emitArrayType:2145`/`emitOptionalType:2373`. Closes D2 residue. Gate: runtime battery.
- [ ] **P4: Single classification pass.** Remove emitter `computeSharedSet:1702`/`shouldSkipTypeEmission:1775`; consume the resolver `classifyTypeEmissionGroups`. Gate: runtime battery.
- [ ] **P5: Predicates + promotion centralized.** Expose canonical `type_registry` int-kind/scalar/pointer predicates and `coercion` promotion; delete the emitter truth tables (`:9473-9496`, `:4712-4929`, `:4895`, `emitBinRvalueText:4385`). Gate: runtime battery.
- [ ] **P6: Lowerer carries decisions.** Record on LIR (in `sf/src/lower.zig` + `sf/src/lir.zig`): field ordinal/name, callee fn type id, temp result types, int-const carrier, saturation op. Emitter reads them; remove `resolveFieldAccess:459` re-resolution, `findCalleeFnTypeId:2458`, `getTemp*`/`hoisted*` re-derivation, and move `emitSatBinary:5030-5400` semantics to lowering/a helper. Gate: runtime battery.
- [ ] **P7: Front-end module-scope-first name resolution.** Resolve unqualified type names lexically (module scope first) in `sf/src/semantic_analyzer.zig`/`type_resolver.zig`; root-causes D7. Gate: runtime battery (plus a reproducer proving the `Mode`-collision resolves module-locally).
- [ ] **P8: Builtin arity/descriptor table.** Central per-builtin expected-arity (and kind) table in `sf/src/semantic_analyzer.zig`, consulted before the dispatch ladder; close the ~20 unchecked builtins. Root-causes D6. Gate: runtime battery (plus arity reproducers).
- [ ] **P9: Structural frame-save rule.** `sf/src/async_state_machine.zig`/emitter: save/restore only declared temps; remove the global by-value round-trip; guard the `nest_inl` suppression path (`c89_emit.zig:3827-3828`). Roots D3/D4. Gate: runtime battery.
- [ ] **P10: Lvalue unification.** `sf/src/lower.zig`: one checked address-taking path for aggregate/index/field/deref chains; add the `-fsafe` root-index check to the sibling `lowerFieldStore` index arm. Closes D5 residue. Gate: runtime battery.

**Per-increment commit:** `refactor(<file>): <increment one-line>` (compiler source only + tech docs).

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
