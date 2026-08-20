# Self-Compile C-Emission Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 5 C-emission defect classes so `zig1` produces a compilable `zig1_5` (self-compiled compiler): `build_zig1_5.sh` completes with 0 gcc errors, both binaries smoke on hello, and the 4 MD5 + corpus 287 + matrix 21/21 byte-identity gate holds.

**Architecture:** Single D → R → I → F → GATE pipeline. D maps the 5 error classes to root causes and emitter sites (read-only); R builds one minimal RED fixture per independent root cause; I pins the upstream-correct emitter fix per root cause (read-only, STOP on design forks); F applies the fixes and runs the full gate; GATE reconciles docs.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, `bash sf/scripts/build_release.sh`, 4 MD5 gates, corpus 287, matrix 21/21.

## Global Constraints

- **Emission-only.** Zero memory (AST-spill/16 MB) work; zero determinism/runtime/memory (correctness-plan T3-T6) work. Do NOT touch `sf/src` except `c89_emit.zig` (and only in the F task).
- **Hard byte-identity gate:** 4 MD5s byte-identical — gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3` (repo-root CWD), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4`. Matrix 21/21.
- **Runtime-priority override:** if a fix changes an MD5 but the emitted C is still correct AND runtime-identical, STOP and report to operator + propose a re-baseline. If MD5 changes with any runtime/correctness doubt, STOP without proposing.
- **`sf/build/out_release/` is WEDGED — NEVER touch/list/build into it.** All compiler runs `timeout 120`.
- **Build:** `bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; then reinstall std: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top; fastedit: re-read after every edit, never `end_line = start_line - 1`).
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` for i32↔usize; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Do not fix anything outside the 5 classes.
- **Commit messages verbatim per task.**

---

### Task D: discovery — map 5 error classes to root causes

**Files:**
- Read: `sf/src/c89_emit.zig` (emitter), `sf/src/lir.zig`, `sf/src/lower.zig` (as needed to trace)
- Create: `.superpowers/sdd/task-D-emission-report.md` (report, read-only — no commit)

**Consumes:** the 5-class table in the spec. **Produces:** `class → root-cause → emitter-site` map + which classes share a root cause + which classes are self-compile-only vs latent-in-corpus.

- [ ] **Step 1: Regenerate the failed build, capture per-class error list**

Run: `bash scripts/self_compile/build_zig1_5.sh` — expected to FAIL at `gcc -c` (rc=1). Then run:

```bash
cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2> /tmp/emit_errs.txt; echo "rc=$?"
```

- [ ] **Step 2: Bucket every error into its class**

For each of the 5 classes, count errors and collect representative `file:line` examples + the exact emitted-C text + the mangled identifier involved. Verify the counts are stable vs the T2 baseline (1195 errors / 16 files; class 1 ~190, class 2 ~200, class 5 = 9).

- [ ] **Step 3: Trace each class to its emitter site**

For class 1 (`zG_` enum globals): identify where enum constants are referenced as globals (kind-1 mangling, `nameManglerMangle` `c89_emit.zig:400-475`) vs where their definition SHOULD be emitted but isn't. Grep `c89_emit.zig` for the enum-constant emission path and the `.enum_const => |ec|` arms (`:2672`, `:5058`). For classes 2-5, trace the corresponding temp-decl / anon-type / payload / void-as-value emission sites.

- [ ] **Step 4: Determine shared vs distinct root causes**

Write the report with a `class → root-cause → site(s)` table, marking which classes are distinct root causes and which are the same bug. This table drives the R-task fixture count (one fixture per *independent* root cause).

- [ ] **Step 5: Write report**

Report at `.superpowers/sdd/task-D-emission-report.md`. No commit (read-only).

---

### Task R: repro — one RED fixture per root cause

**Files:**
- Create: `repro/mi_matrix/<name>_xmod/{main.zig,NOTES.md}` (one dir per independent root cause, named per the D report)
- Report: `.superpowers/sdd/task-R-emission-report.md`

**Consumes:** D report (root-cause list). **Produces:** RED fixtures — each minimal input that reproduces its class's bad C emission under the current `/tmp/fx_subfolder/zig1`.

- [ ] **Step 1: For each root cause, write a minimal fixture**

Each fixture is the smallest Z98 program that triggers the class (e.g. for class 1: an enum with many variants, some referenced as compile-time globals; for class 2: a function with enough temps to collide; for class 3: a `switch` producing an anonymous type; for class 4: a tagged-union payload field access; for class 5: a void-fn call in value position). Mirror the existing `xmod` fixture style (see `repro/mi_matrix/widthbits_union_intconst_xmod/`).

- [ ] **Step 2: Verify RED on each fixture**

Run (from the fixture dir where the fixture imports `std`): `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx <fixture main.zig>` then `cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: the same gcc error class as the full self-compile. If a class cannot be reproduced minimally, record it in NOTES.md and report DONE_WITH_CONCERNS (do NOT fake a fixture).

- [ ] **Step 3: Write NOTES.md per fixture**

Each NOTES.md: fixture source, RED evidence (exact gcc error + rc), the root cause it pins, expected post-fix result.

- [ ] **Step 4: Commit**

Commit: `repro: self-compile emission defects (<class-name>_xmod fixtures)`

---

### Task I: investigate — pin the upstream-correct fix per root cause

**Files:**
- Read: `sf/src/c89_emit.zig` (targeted sites from D)
- Create: `.superpowers/sdd/task-I-emission-report.md` (report, read-only — no commit)

**Consumes:** D report + R fixtures. **Produces:** per-root-cause fix design (the correct emitter change, NOT a patch of emitted text), plus STOP if any design fork needs an operator ruling.

- [ ] **Step 1: For each root cause, identify the correct emitter fix**

Design the change in `c89_emit.zig` that makes the emitted C correct (e.g. for class 1: emit the `zG_` enum-constant definition when it is referenced — or stop referencing it as a global and use the existing `zT_` macro). For each, name the exact function/line to change and the shape of the change.

- [ ] **Step 2: Verify the fix would NOT change the 4 MD5s / corpus / matrix**

Reason about whether the fix path is also reachable from any of the 287 corpus dirs or 21 examples. If a fix WOULD change existing-correct output, flag it as a design fork.

- [ ] **Step 3: Flag design forks → STOP for operator ruling**

If any root cause has two valid fixes with different byte-identity risk, present them and STOP. Otherwise proceed.

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-I-emission-report.md`. No commit (read-only).

---

### Task F: fix — apply the emitter fixes

**Files:**
- Modify: `sf/src/c89_emit.zig` (only the sites named in the I report)
- Report: `.superpowers/sdd/task-F-emission-report.md`

**Consumes:** I report (per-root-cause fix design). **Produces:** self-emitted C that gcc-compiles with 0 errors, links, and smokes.

- [ ] **Step 1: Apply each fix**

Implement the I-report fixes in `c89_emit.zig` via `edit`/`fastedit` (re-read before each edit, bottom-to-top).

- [ ] **Step 2: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 3: R fixtures GREEN**

Re-run each R fixture: dump + gcc -c. Expected: 0 errors, `.c` compiles.

- [ ] **Step 4: Full self-compile build**

```bash
bash scripts/self_compile/build_zig1_5.sh
```

Expected: rc=0, `=== [zig1_5] Done: /tmp/zig1_5 ===`, both binaries produced. If any gcc error remains, it is either an incomplete fix (iterate) or a NEW class (STOP and report).

- [ ] **Step 5: Smoke both binaries**

```bash
timeout 120 /tmp/zig1_5/zig1_5_clean --dump-c89 --output-dir /tmp/sc5c examples/z98/hello/main.zig; echo "rc=$?"
timeout 120 /tmp/zig1_5/zig1_5_asan  --dump-c89 --output-dir /tmp/sc5a examples/z98/hello/main.zig; echo "rc=$?"
```

Expected: rc=0, `.c` emitted both.

- [ ] **Step 6: Byte-identity gate (4 MD5s + corpus 287 + matrix 21/21)**

Verify 4 MD5s byte-identical, corpus 287 unchanged, matrix 21/21. If an MD5 changed: check the emitted C is still correct + runtime-identical → STOP and propose re-baseline to operator; else STOP (defect).

- [ ] **Step 7: Commit**

Commit: `fix: self-compile C-emission defects (enum globals, temp redecls, anon types, payload, void-as-value)`

---

### Task GATE: reconcile docs + closeout

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATE-emission-report.md`

**Consumes:** F result. **Produces:** reconciled tracking docs.

- [ ] **Step 1: Final gate sweep**

Re-verify 4 MD5s byte-identical, corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4`, matrix 21/21, `test_analyzer_bin` "5 passed, 4 failed".

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + a closeout section: the 5 emission classes fixed, the R fixtures (now GREEN), the self-compile-now-buildable milestone, and the next frontier (resume correctness plan T3-T6).

- [ ] **Step 3: Update QUICK_REF.md**

Add a post-emission-fix baseline paragraph; note that self-compile now produces a *buildable* `zig1_5` (gcc-compilable emitted C), correcting the prior "FULLY GREEN" wording that only checked rc + file count.

- [ ] **Step 4: Commit**

Commit: `docs: self-compile emission-fix GATE closeout + reconciliation`
