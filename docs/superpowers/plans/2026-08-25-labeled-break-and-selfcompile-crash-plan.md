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

### Task B3a: F-EMITMAP — growable fl_temps (F2 crash fix)

**Files:**
- Modify: `sf/src/c89_emit.zig` (fl_temps/fl_name_ids growable + name-dedup fix)
- Fixture: `repro/mi_matrix/emission_lower_crash_xmod` RED→GREEN
- Commit: `fix: growable fl_temps map for capture locals (self-compile SEGV)`

**Interfaces:**
- Consumes: B2 F2 finding (capture value unwrapped to temp; name-based read of never-assigned named local because fl_temps capped at [128] + name-deduped).
- Produces: self-compiled `zig1_5` runs B1 fixture rc=0; 4 MD5s byte-identical.

- [ ] **Step 1: Apply the fix**

In `sf/src/c89_emit.zig`: replace the fixed `fl_temps: [128]u32` / `fl_name_ids: [128]u32` / `fl_count: u32` (struct ~:548-550, init ~:582-584) with a growable structure (dynamic arrays via `sandAlloc`/grow, following the emitter's existing grow pattern), and drop the `if (local_count < 128)` cap at `:2690` and `:2711`. Fix the name-dedup guard (`:2712-2716`): the same name may legitimately be re-declared at different scopes (capture shadowing) — each `decl_local` must register its own temp→name entry rather than being skipped when the name already exists. Keep `resolveTempName` (`:3822-3830`) semantics (find by temp_id, return the mangled name). Z98-clean.

- [ ] **Step 2: Gate verification**

Rebuild `/tmp/fx_subfolder/zig1` (reinstall std into `/tmp/fx_subfolder/lib`). Rebuild self-compiled `zig1_5` via `scripts/self_compile/build_zig1_5.sh`. Run B1 fixture via BOTH reference (rc=0) and self-compiled (now rc=0, no SEGV). 4 MD5s byte-identical (gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` repo-root CWD, json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`); matrix 21/21; self-compile re-count 0 errors.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit with verbatim message. Report: fix summary, gate evidence (esp. self-compiled now rc=0), commit. Ledger + mnemoria.

---

### Task B3b: F-SCOPERES — architectural lexical scope chain (F1 fix)

**Files:**
- Modify: `sf/src/lower.zig` (scope-chain name resolution)
- Commit: `fix: lexical scope-chain local resolution (stale sibling capture)`

**Interfaces:**
- Consumes: B2 F1 finding (LDS loop forward-scan max-numeric-scope picks a stale sibling binding over the lexically-enclosing one; `findLocalTemp` backward scan returns the correct one).
- Produces: `findLocalTemp` and the LDS loop agree; re-captured names resolve to the lexically-enclosing binding; 4 MD5s byte-identical.

- [ ] **Step 1: Design the scope chain**

Add a real lexical scope identity: a parent-pointer scope node (or per-scope decl list). Each `addLocalDecl`/`addLocalDeclRenamed` records which scope node it belongs to; scope push/pop (`scope_depth += 1`/`-= 1` at block/while/for/labeled_stmt/swt_prong entry/exit) maintains the chain. Resolution walks the enclosing-scope chain outward (innermost first), returning the first binding whose scope is an ancestor of the current point — replacing BOTH the LDS forward-scan max-scope loop (`lower.zig:2288-2317`) and the `findLocalTemp` backward-scan (`:1309-1317`) with one shared resolver that returns `{temp, kind, tid}`. Do NOT change emission semantics for programs that currently resolve correctly (GREEN gates byte-identical).

- [ ] **Step 2: Apply the fix**

Modify `sf/src/lower.zig` per the design. Keep the `arr_kind`/`arr_tid`/`arr_temp` side effects the LDS loop currently produces (used downstream at `:2339-2343` array/slice/TU/struct checks). Z98-clean; no anytype/@Type; `@intCast` for casts.

- [ ] **Step 3: Gate verification**

Rebuild `/tmp/fx_subfolder/zig1` (reinstall std). Rebuild self-compiled `zig1_5`. Run B1 fixture via both reference and self-compiled rc=0 (post-B3a). 4 MD5s byte-identical; matrix 21/21; self-compile re-count 0 errors; corpus re-count unchanged.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit with verbatim message. Report: scope-chain design, fix summary, gate evidence, commit. Ledger + mnemoria.

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

- **Spec coverage:** Phase A → Tasks A1-A2; Phase B → Tasks B1-B2 + B3a/B3b (AMENDMENT 2); both → GATE-FINAL. All acceptance criteria covered.
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

---

## AMENDMENT 2 (2026-08-25, operator-ruled) — B3 split into B3a (F2 emit-map) + B3b (F1 scope-chain)

**Context:** Task B2 (I-LOWERCRASH) STOP-presented a BROAD class (2 independent self-emission defects). The plan's premise ("resolved_types corrupt; crash at lower.zig:2262-2269") was corrected by B2's triple-verified findings:

- **resolved_types is healthy.** The stale value is the emitted code's *variable* (temp vs name), not the type table.
- **Crash site is lower.zig:2136** (`s->kind`, s=0x1 uninitialized), not `:2269` (B1 attribution stale).
- **F2 (crash driver, c89_emit):** capture values unwrap to temps (`bindOptionalCapture` lower.zig:1437-1440/:1463), but name-based field access (`c89_emit.zig:4677` load_field / `:4339` assign, name-preferred) reads the named C local. The `fl_temps` temp→name map is capped `[128]` (`c89_emit.zig:550`, guard `:2690`/`:2711`) and name-deduped (`:2712-2716`); lowerExprImpl exceeds 128 decl_locals, so `s`/`sym`/`c0_rt` never register → `resolveTempName` returns the raw temp, the named local stays unassigned → SEGV. Reference emits `s = opt_tmp_41.value;` correctly.
- **F1 (latent, lower.zig):** the ident-path LDS loop (`:2288-2317`) forward-scans with `>=` max-numeric-scope selection, picking a stale sibling-scope binding (`t`→3065, sibling branch scope 3) over the lexically-enclosing `:2267` capture (4037, scope 2). `findLocalTemp` (`:1309-1317`) backward-scans first-match `scope <= current` → 4037 (correct). The two lookups disagree; numeric scope_depth cannot distinguish sibling scopes (they share a depth number).

**Operator rulings (verbatim intent):** "for F2, it think option b) could be the best. for F1 that kind of nonsense seems like trying and hoping isn't something like topo sort that sort this out once and for all?" → answers: **F1 = architectural (scope chain)**, **order = B3a (F2) first, then B3b (F1)**.

**Consequences:**
1. **Task B3 replaced by B3a + B3b** (above). B3a = F2 architectural fix (growable `fl_temps`/`fl_name_ids`, drop the 128 cap + name-dedup). B3b = F1 architectural lexical scope chain (parent-pointer scope nodes; resolution walks the enclosing-scope chain; replaces both the LDS loop and `findLocalTemp` with one shared resolver returning `{temp, kind, tid}`).
2. **B3a first, then B3b** (both required: B3a alone stops the crash; B3b alone restores byte-correct scope resolution — fixing only one still fails byte-identity on re-captured-name programs).
3. **Byte-identity gates stay authoritative** (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json `089e4f04…`, mud `a1d0dd55…`). B3a is expected to be byte-identical on all gates (none exceed 128 locals — small examples). B3b MUST be byte-identical on all gates (correctly-resolving programs unchanged).
4. **GATE-FINAL** records both fixes, the AMENDMENT-2 split, and re-verifies self-compiled binary runs std-importing programs rc=0.

---

## AMENDMENT 3 (2026-08-26, operator-ruled option A) — gol/lisp MD5 re-baseline for B3a (F-EMITMAP)

**Context:** B3a (F-EMITMAP, commit `ea6882ac`) verified the F2 fix (growable fl_temps, dedup removed) stops the self-compiled SEGV AND satisfies every gate EXCEPT gol/lisp MD5 byte-identity. Root cause = a plan-internal contradiction: the B3a pin MANDATES removing the fl_temps name-dedup (each decl_local registers its own temp→name entry, capture shadowing), which NECESSARILY changes emitted bytes for any function that re-declares a name — gol's `main` re-declares `var x` in two sibling while-loops (main.zig:95/:114), so the 2nd `x` now resolves to mangled `x` instead of raw `zT_274`. AMENDMENT 2 con.3 declared gol/lisp authoritative AND said "B3a expected byte-identical (none exceed 128 locals)" — the author accounted only for the growable-array effect, not the dedup-removal effect. Both requirements cannot hold.

**Operator ruling (verbatim):** "A" (re-baseline gol + lisp).

**Consequences (binding):**
1. **gol + lisp MD5 gates RE-BASELINED** (runtime-identical, verified: gol glider grid + lisp REPL outputs diff-clean pristine-vs-candidate, both rc=0). New authoritative hashes: gol `eed963e0640a073ed4eebb292f136e05` (old `4afb203fdde7a880ec6e7aed32543691`), lisp `c3c5847798e4553b2e34950e085bb6c6` (old `5f886646b164a70c52bf042eb54bda78`). json `089e4f04…` + mud `a1d0dd55…` UNCHANGED. QUICK_REF MD5 table + re-baseline note updated.
2. **B3a candidate committed as-is** (`ea6882ac`), pin-faithful, no deviation.
3. **F2 crash CLOSED:** self-compiled zig1_5 runs B1 fixture `emission_lower_crash_xmod` rc=0 (prints 3), reference rc=0. Matrix 21/21. Self-compile re-count 0 errors.
4. **GATE-FINAL** records this ruling + the gol/lisp re-baseline in the reconciliation.
