# zig1 C89-Codegen Defect Fixes Implementation Plan

**Status:** Implemented (2026-10-10, operator). All five defects D1–D5 fixed
(F1 `69e82cd8`, F2 `e21dd31b`, F3 `06a7a793` = D3+D4, F5 `ae156d26`; F4 merged
into F3); seed rotated **v94 → v95** (fixed point / archive binary md5
`6efc9524c6caf0bb9484565082170ed5`, archive md5
`ee4e9763d51f76b2b2058dd254377b20`). Closeout report:
`.superpowers/sdd/2026-10-09-zig1-codegen-defects-plan/closeout-report.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix five confirmed `zig1` compiler defects (D1–D5) so the emitted C reproduces **proper Zig semantics**, keeping the full compiler battery green, then rotate the seed.

**Architecture:** Five **Investigate** tasks run first (I1–I5) — each creates a reproducer (added to the corpus) and localizes the defect with `file:line`, so correlation is visible before any fix. Then five **Fix** tasks (F1–F5) each land one compiler fix, running the full compiler-moving battery. A closeout re-baselines the dump-MD5 pins, updates the defect ledger, and rotates the seed.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), seed-built `zig1`, `gcc -m32 -std=c89`, the corpus/classify + stdlib + examples + dump-MD5 harnesses, `sh` gates.

**Spec:** `docs/superpowers/specs/2026-10-09-zig1-codegen-defects-design.md` (binding).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-09-z9torr-m4-real-swarm-compat-plan.md`. NEXT: resume the parked z9torr M4 items (MSE real-peer diagnostics; non-blocking handshake).

## Global Constraints

- **The spec is binding; each fix must reproduce Zig semantics (§2 of the spec), not merely satisfy `gcc`.** Plan says A → do A; if you believe X/Y is better, STOP and present.
- **Compiler is no longer frozen.** `sf/src/**` may change. The seed rotates only at closeout.
- **Seed under test:** rebuild with `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` (no `FIXED_POINT_MD5` pin) → `<out>/zig1_5_clean`; gate `hop1 == hop2`. Seed **v94** at plan start (fixed point `296c48f676deec290387b57132e4e2bd`); **rotated to v95 at closeout** (fixed point / archive binary md5 `6efc9524c6caf0bb9484565082170ed5`, archive md5 `ee4e9763d51f76b2b2058dd254377b20`).
- **Compiler-moving battery (every F-task, and the closeout):** (1) seed rebuild `hop1==hop2`; (2) `bash scripts/corpus/classify <zig1> <out>` → baseline **1120 = 946 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** (closeout-measured with the seed-built binary; the plan-start `1115 = 941…` at HEAD `395d12ff` predated the I-task repro additions; **FAIL must not increase**); (3) `bash scripts/stdlib/verify_stdlib.sh <zig1>` → **283 PASS / 0 FAIL**; (4) the `examples/z98/*/` matrix (currently 25) dump+gcc+link clean; (5) runtime goldens gol/lisp/json/mud byte-identical; (6) the **8 `--dump-c89` MD5 pins** (4 programs × `-fsafe`/`-ffast`) — **re-baseline only with operator authorization + runtime-golden proof**; (7) `bash scripts/closeout/verify_upgraded.sh` `CLOSEOUT OK` + `scripts/check_emit_support.sh` 7/7; (8) the z9torr tiers that are in scope for the fix.
- **Repro producers live in `repro/mi_matrix/<name>_xmod/`** (`main.zig` + optional `expected*.txt/.rc` + `NOTES.md`); they are auto-discovered by `scripts/corpus/list_corpus_dirs.sh` — **no manifest**. Stdlib fixtures (the `stdlib_*_xmod` names) are pinned in `scripts/stdlib/expected_dirs.txt`; these defect repros are **not** stdlib fixtures.
- **A D5-class defect is a runtime defect** — the compile-only corpus classify cannot see a lost write; such repros carry a runtime assertion (print + expected output) and are gated by running, not only compiling.
- **Editing:** `edit`/`fastedit` only (re-read the region immediately before each edit; bottom-to-top; INSERT = replace anchor line with `[new content + original anchor line]`). No `sed`/python/bulk transforms. No scope creep.
- **Tech-doc maintenance (AGENTS §1.1.1):** each I and source-changing F task updates the covering `sf/docs/tech_docs/*.md` with corrected line refs + `[updated: 2026-10-09]`.
- **I-tasks do not change compiler source.** All five I-tasks complete (and STOP for a correlation ruling) before any F-task starts.
- **NO push.** Reports under `.superpowers/sdd/2026-10-09-zig1-codegen-defects-plan/` (commit via `git add -f`). **No compression during the build session.**
- **GIT HARD RULE:** never `git reset --hard/--keep`, `git checkout --`, `git restore`, `git clean`, `git stash drop/clear`, force-push, or any destructive/history-rewriting command; only `git commit --amend` on your OWN just-created commit. STOP and report otherwise.
- **STOP on any unforeseen divergence** (unexpected emitted-C change, corpus regression, fixed-point mismatch).

---

### Task I1: Investigate D1 — C-keyword `union(enum)` tag

**Files:** Create `repro/mi_matrix/union_keyword_tag_xmod/{main.zig,NOTES.md}`; Modify `sf/docs/tech_docs/08_c89_emission.md`; Report `task-I1-report.md`

**Interfaces:** Produces the D1 reproducer + the exact emission site + the Zig-semantics statement + correlation notes.

- [x] **Step 1: Baseline (first task only).** Record HEAD, seed v94 fixed point, the 8 dump-MD5 pins, corpus `1097=923/58/116/0/0` (closeout-corrected to `1120=946/58/116/0/0`), stdlib `283/0`, examples matrix count (25). (These are the references every later task diffs against.)
- [ ] **Step 2: Write the reproducer.** `union(enum){ int: i64, bytes: []const u8 }` + a `switch`/construction that a pre-fix build emits as `struct{ long long _0; } int;` (gcc `expected identifier before 'int'`). Include the exact emit+gcc commands in `NOTES.md`.
- [ ] **Step 3: Confirm the pre-fix failure** on the seed-built compiler; classify the repro (it is expected to be a genuine FAIL pre-fix — record it; it must go green after F1).
- [ ] **Step 4: Localize.** Read `sf/src/c89_emit.zig` `~:2008-2024` (union member emission) and every access site; state the Zig semantics (any identifier is a valid tag). Note whether member names appear elsewhere (init/switch/`==`).
- [ ] **Step 5: Update `08_c89_emission.md`** with the locus + `[updated: 2026-10-09]`.
- [ ] **Step 6: Report + commit.** `git add -f repro/mi_matrix/union_keyword_tag_xmod sf/docs/tech_docs/08_c89_emission.md`; `git commit -m "repro: D1 C-keyword union tag emits invalid C89 (union_keyword_tag_xmod)"`.

**Gate:** repro present + pre-fix failure recorded; locus identified with `file:line`; tech doc updated; no compiler change.

---

### Task I2: Investigate D2 — synthetic slice-element typedef collapse

**Files:** Create `repro/mi_matrix/slice_of_slice_xmod/{main.zig,NOTES.md}` and `repro/mi_matrix/slice_of_array_xmod/{main.zig,NOTES.md}`; Modify `sf/docs/tech_docs/08_c89_emission.md`; Report `task-I2-report.md`

- [ ] **Step 1: Write both reproducers.** One struct with `[][]const u8` + `[][20]u8`; confirm the shared `Slice_*` typedef and the `-Wincompatible-pointer-types` warning pre-fix.
- [ ] **Step 2: Classify** both pre-fix (expect OK-by-compile but with the warning; record the exact warning).
- [ ] **Step 3: Localize** `getCTypeName` slice branch `c89_emit.zig:1028-1036` vs array branch `:959-967`/`emitArrayType:2116-2137`; state the Zig semantics (`[][]const u8` ≠ `[][20]u8`); capture the exact emitted typedefs.
- [ ] **Step 4: Update the tech doc.**
- [ ] **Step 5: Report + commit** (`repro: D2 slice-of-synthetic element typedef collapse (slice_of_slice/array_xmod)`).

**Gate:** both repros present + warning recorded; locus + Zig semantics; tech doc updated; no compiler change.

---

### Task I3: Investigate D3 — undeclared frame-save temp (global struct address across a suspension)

**Files:** Create a committed regression guard `repro/mi_matrix/async_frame_global_xmod/` **if** a faithful standalone can be pinned (D3 is temp-layout sensitive — if not reducible, add the in-example patch + commands to `NOTES.md`); Modify `sf/docs/tech_docs/12_async_coroutines.md`; Report `task-I3-report.md`

- [ ] **Step 1: Confirm the reproducer.** Follow `examples/torrent_example_defects.md` D3: the minimal `peer.zig` patch (module-global `MsgReader`, `&g_reader` into `wire.readMessageAsync`). Record the exact gcc `'zT_NNN' undeclared`.
- [ ] **Step 2: Localize** the frame-save temp discipline: `async_state_machine.zig:254-265` (save), `:949-955`/`:926`/`:207-211` (temp seeding), `c89_emit.zig:3800-3906` (decl loop) + suppression paths (`:3709-3713`, `:3571`, `:8910`, `:8998`, `:3485`), `resolveTempName:6614-6628`.
- [ ] **Step 3: Zig semantics** — a save must store a declared temp.
- [ ] **Step 4: Correlation note** vs D4 (same site? yes/no).
- [ ] **Step 5: Tech doc + report + commit.**

**Gate:** faithful reproducer (standalone or in-example patch) recorded; locus + suppression path identified; correlation vs D4 stated; tech doc updated; no compiler change.

---

### Task I4: Investigate D4 — undeclared frame-save temp (struct-return temp across a suspension)

**Files:** Create a regression guard `repro/mi_matrix/async_frame_structret_xmod/` if reducible, else the in-example patch in `NOTES.md`; Modify `sf/docs/tech_docs/12_async_coroutines.md`; Report `task-I4-report.md`

- [ ] **Step 1: Confirm** the D4 patch (`g_reader = initMsgReader(...)` in the suspending function) → `'zT_NNN' undeclared`.
- [ ] **Step 2: Localize** the struct-return-temp path (same frame-save pass; identify where a by-value struct-return temp is produced and not materialised to a named local).
- [ ] **Step 3: Zig semantics + correlation vs D3.**
- [ ] **Step 4: Tech doc + report + commit.**

**Gate:** as I3, for D4; state whether I3 and I4 share one fix.

**STOP after I1–I5 complete — present the correlation findings for the operator ruling before any F-task.**

---

### Task I5: Investigate D5 — lost store through a slice-index aggregate lvalue

**Files:** Create `repro/mi_matrix/slice_index_field_store_xmod/{main.zig,expected.txt,expected.rc,NOTES.md}`; Modify `sf/docs/tech_docs/08_c89_emission.md`; Report `task-I5-report.md`

- [ ] **Step 1: Write the runtime reproducer.** A `struct` in a `[]T`, store `s[i].field[j] = x`, then read back and print `x` (expected output committed). Pre-fix the printed value is the pre-store value (the write is lost).
- [ ] **Step 2: Confirm** pre-fix (compile OK, **runtime output wrong** — crucial: classify alone is insufficient).
- [ ] **Step 3: Localize** `lower.zig:2484-2531` (value-read base; address only for tuples `:2493-2508`) vs the correct `lowerFieldStore:2878-2928`; plus the emission chain (`c89_emit.zig:204-267`, `:7456-7513`, `:7593-7596`, `:7226-7271`). State the Zig lvalue semantics.
- [ ] **Step 4: Cross-check** the emitted C pattern `zT = peers.ptr[i]; p = zT.field; p[j]=…` against the spec.
- [ ] **Step 5: Tech doc + report + commit** (`repro: D5 lost store through slice-index aggregate lvalue (slice_index_field_store_xmod)`).

**Gate:** runtime reproducer present + wrong pre-fix output recorded; locus + Zig semantics; correlation vs the async defects stated; tech doc updated; no compiler change.

---

### Task F1: Fix D1 (C-keyword `union(enum)` tag)

**Files:** Modify `sf/src/c89_emit.zig` (union member emission/access, `~:2008-2024` + access sites); Modify `sf/docs/tech_docs/08_c89_emission.md`; Test `repro/mi_matrix/union_keyword_tag_xmod/`

- [ ] **Step 1: Red** — confirm the I1 reproducer fails pre-fix. **Step 2: Implement** C-keyword mangling (or stable non-keyword member names) consistently at declaration + access. **Step 3: Green** — repro dump rc=0, gcc rc=0, run rc=0.
- [ ] **Step 4: Battery** (Global Constraints): seed rebuild `hop1==hop2`; corpus (FAIL not increased); stdlib 283/0; examples matrix; goldens; dump-MD5 — **re-baseline if D1 changes any emitted C** (expect no gate program uses a keyword tag → likely byte-identical), operator-authorized if changed.
- [ ] **Step 5: Tech doc → FIXED; commit** `fix: C-keyword union(enum) tag compiles (union_keyword_tag_xmod)`.

**Gate:** repro green; no gate regression; dump pins explained; tech doc updated.

---

### Task F2: Fix D2 (synthetic slice-element typedef)

**Files:** Modify `sf/src/c89_emit.zig` (`getCTypeName` slice branch + `emitArrayType`/`syntheticTypeName`); Modify `sf/docs/tech_docs/08_c89_emission.md`; Test `repro/mi_matrix/slice_of_slice_xmod`, `slice_of_array_xmod`

- [ ] **Step 1: Red.** **Step 2: Implement** recursion / dense-id naming for synthetic slice elements so distinct element types get distinct typedefs; keep primitive/named slices byte-identical. **Step 3: Green** — both repros compile **warning-free** (no `-Wincompatible-pointer-types`) and run.
- [ ] **Step 4: Battery** incl. dump-MD5 (typedef names may appear in gate output → re-baseline if changed, with runtime proof).
- [ ] **Step 5: Tech doc → FIXED; commit** `fix: slice of synthetic element emits a distinct typedef (slice_of_slice/array_xmod)`.

**Gate:** repros warning-free + green; primitive/named slices unchanged; battery green; dump pins explained.

---

### Task F3: Fix D3 + D4 (merged — shared async frame-save root cause)

**Files:** Modify `sf/src/c89_emit.zig` (frame-save/decl temp discipline) and/or `sf/src/async_state_machine.zig`; Modify `sf/docs/tech_docs/12_async_coroutines.md`; Test `repro/mi_matrix/async_frame_structret_xmod/` (D4, standalone) + the D3 in-example patch

**Context (I3/I4, operator ruling 2026-10-09 — one fix):** `saveAllFields` (`async_state_machine.zig:254-265`) stores a raw `fld.temp_id + base`; the decl loop (`c89_emit.zig:3800-3909`) suppresses that temp as a **`load_global` alias** while `temp_map`/`messageMap` state is empty at the save site. D3 = a module-global struct address crossing a suspension; D4 = the loop-carried `load_global` alias of a module global (D4's repro is standalone: `async_frame_structret_xmod`).

- [ ] **Step 1: Red** — D4 standalone repro emits `main_*.c:621 'zT_20' undeclared`; D3 in-example patch emits `'zT_NNN' undeclared`. **Step 2: Implement** — make the save/decl discipline declare the stored temp (or route the value so the temp is not suppressed): the fix must name the `load_global`-alias temp at the save site (resolve `temp_map`/global-alias before the save), mirroring how a local is handled. **Step 3: Green** — BOTH the D4 standalone and the D3 in-example patch link clean; and `examples/z98/z9torr` with the M2 workarounds reverted (in a scratch copy) links clean.
- [ ] **Step 4: Battery** (the async `stdlib_async_*` corpus fixtures must stay GREEN; the D3 NOTES-only guard stays NOTES-only; dump-MD5 re-baseline if async output changed, with runtime proof).
- [ ] **Step 5: Tech doc → FIXED; commit** `fix: async frame save declares the stored temp — D3+D4 (async_frame_structret_xmod)`.

**Gate:** D4 standalone + D3 in-example patch link clean; async corpus green; battery green; pins explained.

---

### Task F4: [MERGED INTO F3 — do NOT execute separately]

Operator ruling 2026-10-09: D3 and D4 share one root cause and are fixed by a single task (F3). F4's content is folded into F3 above. The task numbering F5.. stays as written (F5 = D5).

---

### Task F5: Fix D5 (lost store through a slice-index aggregate lvalue)

**Files:** Modify `sf/src/lower.zig` (`lowerAssignLValue` `index_access` arm `:2484-2531` — route non-tuple bases through address-taking like `lowerFieldStore:2878-2928`); Modify `sf/docs/tech_docs/08_c89_emission.md`; Test `repro/mi_matrix/slice_index_field_store_xmod`

- [ ] **Step 1: Red** — runtime reproducer prints the wrong value. **Step 2: Implement** the address-taking lvalue path. **Step 3: Green** — runtime reproducer prints the expected value; isolated repro links+runs.
- [ ] **Step 4: z9torr peer_id** — revert the Task-0 workaround in a scratch copy (or add the assertion) and confirm the sent handshake carries the real `-Z9T01-…` peer_id; run the z9torr tiers.
- [ ] **Step 5: Battery** (the lvalue path is core — corpus/examples/goldens are the net; dump-MD5 re-baseline if any emitted C changed, with runtime proof).
- [ ] **Step 6: Tech doc → FIXED; commit** `fix: store through slice-index aggregate lvalue writes through (slice_index_field_store_xmod)`.

**Gate:** runtime repro green; z9torr peer_id real + tiers green; corpus FAIL not increased; battery green; pins explained.

---

### Closeout (after F1–F5)

**Files:** Modify `examples/torrent_example_defects.md` (mark D1–D5 FIXED with commit ids + the Zig-semantics note); Modify `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table + seed); rotate `release/seed/zig1-seed.tgz` via `bash scripts/seed/archive_seed.sh <zig1> <gen> release/seed/zig1-seed.tgz --update-changelog`; Report `closeout-report.md`

- [x] **Step 1:** Full battery on the final compiler (all 8 items) + the z9torr tier set; runtime goldens; `verify_upgraded` `CLOSEOUT OK`. → seed closure `6efc9524…`; corpus `1120 = 946/58/116/0/0`; stdlib 283/0; matrix 25/25; goldens reproduced; `verify_upgraded` CLOSEOUT OK; emit support 7/7; all 8 z9torr tiers PASS.
- [x] **Step 2:** Re-baseline the 8 dump-MD5 pins (operator-authorized, measured with the seed-built binary `/tmp/z9_v95_seed/zig1_5_clean`) and record each old→new with runtime proof (gol/lisp/json/mud runtime goldens byte-identical).
- [x] **Step 3:** Update the defect ledger (D1–D5 FIXED) + QUICK_REF (baseline corrected to `1120 = 946/58/116/0/0`, seed v95).
- [x] **Step 4:** Rotate the seed **v94 → v95**; verified the archived binary rebuilds to itself (`hop1==hop2 == 6efc9524…`); fixed point / archive binary md5 `6efc9524c6caf0bb9484565082170ed5`, archive md5 `ee4e9763d51f76b2b2058dd254377b20`.
- [x] **Step 5:** Commit `docs: zig1 codegen defect fixes closeout + seed v95`; next work = the parked z9torr M4 items.

**Gate:** all gates green; dump pins re-baselined with proof; defect ledger + QUICK_REF consistent; seed v95 archived + self-consistent.

## Self-Review

- **Spec coverage:** spec §3 D1→F1(rep I1), D2→F2(I2), D3→F3(I3), D4→F4(I4), D5→F5(I5); §4 correlation via the I-tasks; §5 gates in Global Constraints; §6 risks addressed (dump re-baseline, in-example repros, D5 core path, seed rotation, D2 recursion).
- **Ordering:** all five I-tasks before any F-task (operator requirement).
- **No placeholders:** reproducer names, `file:line` sites, and gate commands are concrete; the only open items are the D3/D4 standalone-reducibility (explicitly conditional, with the in-example fallback) which the I-tasks resolve.
