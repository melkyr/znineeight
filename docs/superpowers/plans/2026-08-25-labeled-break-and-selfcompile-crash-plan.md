# Labeled-Block Break + Self-Compiled Lowering Crash — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (A) make `break :blk` on labeled blocks behave correctly (jump to block exit) instead of silently dropping; (B) find and fix the single emission defect that makes the self-compiled `zig1_5` SEGV in lowering for std-importing programs.

**Architecture:** Phase A extends the `loop_stack` label-resolution machinery so labeled blocks are breakable (block-exit jump) while `continue` stays loop-only. Phase B reproduces the self-compiled crash with a minimal fixture, traces the emission defect by diffing self-emitted frontend C against the reference, then fixes the single locus. No `sf/src` changes outside the pinned fix loci.

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32, bash (build scripts), ASan.

## Global Constraints

- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild = `bash sf/scripts/build_release.sh` (gate `=== [release] Done ===`). Rebuild WIPES `/tmp/fx_subfolder/lib` — reinstall canonical std after each rebuild: `cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.
- **No `sf/src` fixes outside the plan's pinned loci.** Never touch `sf/build/out_release/` (WEDGED).
- Byte-identity gates (QUICK_REF.md): gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Must remain byte-identical; fixtures are new-only.
- Correctness bar = RUNTIME behavior (program prints the expected value), not byte-parity vs zig0.
- Compile recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 X.zig`; multi-module `gcc -m32 -std=c89 -c` INSIDE output dir with absolute `-I /workspace/znineeight/sf/src/include`; link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- Z98 dialect for all probe/fixture `.zig`: no anytype/@Type; `@intCast` for int casts; `switch` requires `else`; no method syntax; no pointer captures.
- Editing discipline: `edit`/`fastedit` only; re-read region before each edit; edit bottom-to-top; never `end_line=start_line-1`; insert via replacing an anchor line.
- Markers extract with `grep -a`, never `strings`.
- Enforce `timeout 120` on ALL compiler/binary invocations.
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent r2r1-session --type <discovery|decision|bugfix|problem|pattern> --summary "..." "..."` per task.
- Reports to `.superpowers/sdd/task-<N>-report.md` (gitignored). WARNING: `.superpowers/sdd/task-1-report.md` is TRACKED and holds an unrelated prior report — never reuse that exact name; use descriptive names like `task-LABELBREAK-report.md`.
- Self-compiled build: `scripts/self_compile/build_zig1_5.sh` → `/tmp/zig1_5/{zig1_5_asan,zig1_5_clean,lib/,gen/}`.
- Reference emission: `/tmp/ref_zig1.c` (zig0, 40-module concatenation); actual zig1 build emission at `/tmp/fx_subfolder/*.c`.

---

### Task A1: I-LABELBREAK — pin labeled-block break fix (read-only)

**Files:**
- Report: `.superpowers/sdd/task-LABELBREAK-report.md` (gitignored)

**Interfaces:**
- Consumes: `lower.zig:5018-5069` (break/continue), `lower.zig:4441-4447` (labeled_stmt), `LoopInfo` (`lower.zig:73-78`), fixture `repro/mi_matrix/emission_labeled_ctrl_xmod`.
- Produces: pinned fix design (A1a support vs A1b reject) with byte-identity + scope verdict.

- [ ] **Step 1: Verify the silent-drop mechanism**

Read `sf/src/lower.zig:5018-5069` (break_stmt/continue_stmt), `:4441-4447` (labeled_stmt), `:4583-4604` + `:4700-4704` + `:4755-4757` (loop_stack pushes), `:73-78` (LoopInfo). Confirm: `break :blk` resolves only against loop_stack; labeled_stmt never pushes; silent `return` at :5019/:5037.

- [ ] **Step 2: Reproduce the shape-A RED**

Run fixture `repro/mi_matrix/emission_labeled_ctrl_xmod` (dump → gcc -c → link → run). Confirm current output `3\n6\n10\n` (shape A adapted prints 2, not 1). Also confirm a standalone `blk: { var a = 1; break :blk; a = 2; }` prints `2` (expected `1`), all rc=0.

- [ ] **Step 3: Design both candidates, evaluate byte-identity + scope**

- **A1a (support):** extend `LoopInfo` with `is_loop: u8`; `labeled_stmt` with block body creates exit BB + pushes breakable entry (`header_bb = exit_bb = block-exit BB`, `is_loop=0`); `break` resolves labeled entry → jump to exit; `continue` skips `is_loop==0` entries. Determine: where exactly the push/pop happens (around `lowerStmt` of `node.child_0` at :4444-4446), how the block exit BB is created and connected (jump after body if not terminated), scope_depth semantics.
- **A1b (reject):** in `break_stmt`/`continue_stmt`, replace the silent `return` at :5019/:5037/:5045/:5063 with a diagnostic. Determine error code (new or existing) and message.
- **Byte-identity:** verify neither candidate fires on any GREEN program (grep corpus for `break :`/`continue :` on labeled blocks — labeled while/for only in corpus; labeled-block break appears ONLY in the RED fixture). Confirm 4 MD5 gates unchanged either way.
- **Scope fork check:** if A1a and A1b differ in runtime/scope on any in-scope program, record a FORK and STOP-present. Otherwise pick the recommended candidate (default: A1a support, real-Zig-faithful) and state it.

- [ ] **Step 4: Report + ledger + memory**

Report: mechanism verification, RED reproduction, both candidate designs with file:line, byte-identity verdict, fork-or-pin. Ledger + mnemoria entries.

---

### Task A2: F-LABELBREAK — apply the pinned fix

**Files:**
- Modify: `sf/src/lower.zig` (pinned locus from A1)
- Fixture (if A1a): `repro/mi_matrix/emission_labeled_ctrl_xmod/main.zig` + NOTES.md
- Commit: `fix: labeled-block break resolves to block exit (was silently dropped)` (or per A1b: `fix: labeled break/continue emits diagnostic instead of silent drop`)

**Interfaces:**
- Consumes: A1 pinned design.
- Produces: shape A GREEN; `break :blk` prints `1`; labeled while/for break/continue unaffected.

- [ ] **Step 1: Apply the fix**

Per A1's pinned design, modify `sf/src/lower.zig` only (single locus; A1a touches LoopInfo + labeled_stmt + break_stmt + continue_stmt; A1b touches break_stmt/continue_stmt only). Z98-clean; no anytype/@Type.

- [ ] **Step 2: Update/verify the fixture**

If A1a: extend `emission_labeled_ctrl_xmod` with the literal `blk: { break :blk }` shape printing `1`. If A1b: the shape becomes a green-guard (clean diagnostic). Update NOTES.md.

- [ ] **Step 3: Gate verification**

Run: fixture dump rc=0, gcc -c rc=0, link rc=0, run prints expected; 4 MD5s byte-identical (gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` repo-root CWD, json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`); matrix 21/21; self-compile re-count 0 errors.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit with verbatim message. Report: fix summary, gate evidence, commit. Ledger + mnemoria entries.

---

### Task B1: R-LOWERCRASH — minimal self-compiled crash fixture

**Files:**
- Create: `repro/mi_matrix/emission_lower_crash_xmod/{main.zig,NOTES.md}`
- Commit: `repro: self-compiled compiler lowering crash fixture (std import, zero switch)`

**Interfaces:**
- Consumes: the adjudicated R-B finding (std-importing zero-switch program crashes self-compiled zig1_5 at lower.zig:2261-2269).
- Produces: committed minimal repro; reference rc=0 vs self-compiled rc=139 documented.

- [ ] **Step 1: Write minimal `.zig`**

Minimal std-importing program with zero switches that still crashes the self-compiled binary. Candidates: `binexpr_test.zig`-style (`var a: i32 = 1 + 2; std.io.printInt(a);`) or `t_simple.zig`-style. Keep it minimal but faithful to the crash class (std import is the trigger).

- [ ] **Step 2: Verify reference vs self-compiled**

Reference: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → rc=0, emits .c, gcc/link/run rc=0, prints expected.
Self-compiled: rebuild via `scripts/self_compile/build_zig1_5.sh` (already-built `/tmp/zig1_5/zig1_5_clean` acceptable if current), then `timeout 120 /tmp/zig1_5/zig1_5_clean --dump-c89 main.zig` → rc=139. Capture ASan top frame (`zF_941073CF_lowerExprImpl` via `phase_LIRLowering`).

- [ ] **Step 3: NOTES.md + commit**

Convention: purpose / verbatim source / RED evidence (self-compiled rc=139 + ASan frame + reference rc=0) / root-cause status (adjudicated pre-existing masked self-emission gap; root not yet traced) / expected post-fix.

- [ ] **Step 4: Report + ledger + memory**

Report: fixture, both rc results, ASan evidence, commit. Ledger + mnemoria.

---

### Task B2: I-LOWERCRASH — trace the emission defect (read-only)

**Files:**
- Report: `.superpowers/sdd/task-LOWERCRASH-report.md` (gitignored)

**Interfaces:**
- Consumes: B1 fixture; self-compiled build; reference `/tmp/ref_zig1.c` + `/tmp/fx_subfolder/*.c`.
- Produces: pinned single-locus root cause with file:line, OR STOP-present if broad class.

- [ ] **Step 1: Reproduce under ASan + capture**

Build self-compiled binary fresh (or use `/tmp/zig1_5/zig1_5_asan`), run B1 fixture under ASan, capture the full backtrace and the emitted-C crash line (`lower_1EB7D337.c:37134` = `zT_4045 = zT_4043[zT_4044]` where zT_4043=types_items, zT_4044=stale id).

- [ ] **Step 2: Diff self-emitted frontend against reference**

Compare the SELF-EMITTED `front_resolution_*.c`, `resolved_type_table_*.c`, `semantic_analyzer_*.c` (and any module that populates `resolved_types`) against the reference (`/tmp/ref_zig1.c` and/or `/tmp/fx_subfolder/*.c`). Normalize mangled-name noise (Task-1 mangler schemes differ). Find the construct zig1 mis-emits that yields a stale node→type id.

- [ ] **Step 3: Trace to the emission site**

Map the divergent C back to its Zig source construct (candidates: a switch/enum/labeled/ident construct in front_resolution.zig, resolved_type_table.zig, semantic_analyzer.zig — same self-emission class as the enum-switch drop but different locus). Record `file:line` and the emission pattern.

- [ ] **Step 4: Single-locus vs broad class**

If the divergence is a single pin-able emission defect → pin it and recommend the F locus. If it reveals a BROAD self-emission class (multiple independent defects) → **STOP and present** to the operator (do not chase a chain in this plan).

- [ ] **Step 5: Report + ledger + memory**

Report: ASan capture, emission diff evidence, source anchor, pinned F locus (or broad-class STOP). Ledger + mnemoria.

---

### Task B3: F-LOWERCRASH — apply the pinned fix

**Files:**
- Modify: the pinned `sf/src/*.zig` locus from B2 (single file/locus)
- Fixture: `repro/mi_matrix/emission_lower_crash_xmod` RED→GREEN
- Commit: `fix: self-emitted <construct> produces stale resolved-type id (self-compile SEGV)` (adjust wording to the actual locus)

**Interfaces:**
- Consumes: B2 pinned locus.
- Produces: self-compiled `zig1_5` runs the B1 fixture rc=0; 4 MD5s byte-identical; self-compile re-count 0.

- [ ] **Step 1: Apply the fix**

Per B2's pinned locus, modify the single `sf/src` file. Z98-clean. Do NOT chase additional defects if the B2 STOP applied.

- [ ] **Step 2: Gate verification**

Rebuild `/tmp/fx_subfolder/zig1` (reinstall std into `/tmp/fx_subfolder/lib`). Rebuild self-compiled `zig1_5` via `scripts/self_compile/build_zig1_5.sh`. Run B1 fixture via BOTH reference (rc=0) and self-compiled (now rc=0). 4 MD5s byte-identical; matrix 21/21; self-compile re-count 0 errors; corpus re-count unchanged.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit with verbatim message. Report: fix summary, gate evidence (esp. self-compiled now rc=0), commit. Ledger + mnemoria.

---

### Task GATE-FINAL: full sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` + `docs/sf/QUICK_REF.md`
- Commit: `docs: labeled-break + self-compile crash plan GATE + reconciliation`

**Interfaces:**
- Consumes: A2 + B3 results.
- Produces: reconciled docs; both residuals closed (or documented).

- [ ] **Step 1: Full sweep**

4 MD5s byte-identical; matrix 21/21; corpus 323 dirs re-count (OK/FAIL/ICE/CRASH/GREEN); self-compile re-count 0 errors; self-compiled binary runs B1 fixture + a std-importing real program rc=0.

- [ ] **Step 2: Reconcile docs**

EXPECTED_FAIL: record Phase-A (labeled-block break) + Phase-B (self-compile lowering crash) resolutions with commit SHAs; QUICK_REF: post-plan baseline paragraph; corpus-gate header refresh.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit with verbatim message. Report + ledger + mnemoria.

---

## Self-Review (controller, before execution)

- **Spec coverage:** Phase A → Tasks A1-A2; Phase B → Tasks B1-B3; both → GATE-FINAL. All acceptance criteria covered.
- **Placeholder scan:** all steps carry exact commands/expected output; no TBD.
- **Type consistency:** artifact paths stable (`/tmp/fx_subfolder/zig1`, `/tmp/zig1_5/zig1_5_clean`, `/tmp/ref_zig1.c`); fixture dirs per convention.

---

## AMENDMENT 1 (2026-08-25, operator-ruled) — A1a guard accepted AS-IS; no refinement

**Context:** Task A1 (I-LABELBREAK) review surfaced an Important byte-identity concern: A1a's guard (`labeled_stmt` with `child_0.kind == AstKind.block` → push breakable loop_stack entry) ALSO fires on expression-position labeled blocks, which appear in the GREEN corpus fixtures `emission_orelse_labeled_xmod` and `emission_catch_labeled_xmod` (F-LABELED `2cbf1fd3`). Under A1a those emit an extra dead `z_bb_N` block (push + epilogue even though `return null` fires first); runtime stays correct but their emitted bytes change. Three guard-refinement options (R1 only-push-when-labeled-break-present / R2 skip-when-body-self-terminates / R3 exclude-expression-position) were presented.

**Operator ruling (verbatim intent):** "none makes sense, if the dead code its dead but runtime is correct i don't see a need to refine futher if harmless. so ammend and stop."

**Consequence:**
1. **A1a applied as specified** — NO guard refinement. The labeled_stmt block-body push stays unconditional on `child_0.kind == AstKind.block`.
2. **Dead-code emission is ACCEPTED** where the body self-terminates: the extra block is dead, runtime is correct, and per the operator's ruling this is harmless — no further refinement.
3. **Byte-identity scope re-stated:** the 4 MD5 gates (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json `089e4f04…`, mud `a1d0dd55…`) MUST remain byte-identical — none uses expression-position labeled blocks, so A1a does not affect them. The two GREEN corpus fixtures' emitted bytes MAY change (runtime-identical); they are runtime-correctness fixtures, and a byte change there is a re-baseline-default case, NOT a gate violation.
4. **A2 (F-LABELBREAK) verifies** `emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` still RUN correctly (prints 0 / 7) after the fix; their emitted-byte change is expected and accepted per this ruling.
5. **GATE-FINAL** records this ruling + any corpus byte-change in the reconciliation.
