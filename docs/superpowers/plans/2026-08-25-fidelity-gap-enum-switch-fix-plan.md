# Fidelity-Gap Fix: Enum-Switch Case-Label Drop + Extension Runtime Correctness

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the enum-value stmt-switch case-label drop so self-compiled `zig1_5` correctly handles qualified enum-literal switch cases, then add runtime-correctness fixtures for the extension shapes (tagged-union switch, labeled statements, nested for/if/switch-with-enums).

**Architecture:** Read-only investigate the exact fix locus, apply the minimal fix at both switch-lowering sites, then R-first runtime-correctness fixtures for extension shapes — fix only shapes that are RED (wrong runtime output). Verification is runtime-behavior only (NOT byte-identity vs zig0, whose emission architecture differs).

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32, bash.

## Global Constraints

- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild = `bash sf/scripts/build_release.sh` (gate `=== [release] Done ===`). Rebuild WIPES `/tmp/fx_subfolder/lib` — reinstall canonical std after each rebuild: `cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.
- Byte-identity gates (QUICK_REF.md): gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Must remain byte-identical after the fix.
- Compile recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 X.zig`; multi-module `gcc -m32 -std=c89 -c` INSIDE output dir with absolute `-I /workspace/znineeight/sf/src/include`; link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- Z98 dialect for fixture `.zig`: no anytype/@Type; `@intCast` for int casts; `switch` requires `else`; no method syntax; no pointer captures.
- Editing discipline: `edit`/`fastedit` only; re-read region before each edit; edit bottom-to-top; never `end_line=start_line-1`; insert via replacing an anchor line.
- Markers extract with `grep -a`, never `strings`.
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory` entry per completed task (agent `r2r1-session`; types discovery/decision/intent/problem/pattern).
- Reports written to `.superpowers/sdd/task-<N>-report.md` (gitignored); return only status + one-line gate summary from implementers.
- **Runtime-correctness bar** (NOT zig0 byte-parity): a fixture is GREEN iff the compiled+run program prints the expected value; RED iff it prints a wrong value, errors, or crashes.
- `sf/src_sh/` self-containment work is Plan 2 — do NOT do it here.

---

### Task 1: I-ENUMFIX — pin the exact fix locus (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ENUMFIX-report.md` (gitignored)

**Interfaces:**
- Consumes: verified mechanism (both switch-lowering sites: `lower.zig:3946-3976` expr-switch in `lowerExprImpl`, `lower.zig:4777-4806` stmt-switch in `lowerStmt`; case collection accepts only int/char/enum/error_literal, `else { continue; }` drops `field_access`).
- Produces: exact single-locus (or two-locus) fix design with `file:line`, and byte-identity verdict.

- [ ] **Step 1: Read the two case-collection loops**

Read `sf/src/lower.zig:3946-3976` and `sf/src/lower.zig:4777-4806`. Confirm both have the identical `else { continue; }` drop for non-int/char/enum/error case items. Also read `sf/src/semantic_analyzer.zig:1032-1101` (`semanticAnalyzerResolveEnumLiteral`) and `:1307-1311` (only `enum_literal`/`undefined_literal` case items resolved into `enum_value_table`).

- [ ] **Step 2: Evaluate fix candidates**

Candidate (a): add a `field_access` branch to both case-collection loops that resolves the qualified enum literal to its member value (lookup via the switch-cond enum type's member list / `enum_value_table`). Candidate (b): extend semantic-analyzer handling at :1307-1311 to also resolve `field_access` case items into `enum_value_table`, and add a `field_access` branch in lowering that reads `enum_value_table`. Determine: which is minimal? Do both lowering sites need the same change? Is the semantic analyzer needed at all (does `field_access` resolution exist elsewhere)?

- [ ] **Step 3: Byte-identity verdict**

Verify the fix candidate(s) fire only on currently-broken programs. The 4 MD5 gates + 21-example matrix must be byte-identical after the fix (no currently-GREEN program emits a qualified-enum switch case that currently collects correctly). Use the existing RED fixture `repro/mi_matrix/emission_enum_switch_xmod` as the repro.

- [ ] **Step 4: Report + ledger + memory**

Report: mechanism recap, exact fix design (locus file:line, candidate chosen, why), byte-identity verdict, any fork needing operator ruling. Ledger + memory entries.

---

### Task 2: F-ENUMFIX — apply the fix

**Files:**
- Modify: `sf/src/lower.zig` (both case-collection sites) and/or `sf/src/semantic_analyzer.zig` per Task 1 pin.
- Test: `repro/mi_matrix/emission_enum_switch_xmod` (existing RED fixture).
- Commit: `fix: qualified enum-literal switch cases no longer dropped (zT case labels)`

**Interfaces:**
- Consumes: Task 1 fix design.
- Produces: GREEN fixture; 4 MD5s byte-identical; matrix 21/21; self-compile re-count 0.

- [ ] **Step 1: Apply the pinned fix**

Apply the Task 1 locus exactly (candidate chosen). Re-read the region before each edit; edit bottom-to-top.

- [ ] **Step 2: Verify fixture GREEN**

Run (workdir fixture dir `repro/mi_matrix/emission_enum_switch_xmod`):
```bash
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig
gcc -m32 -std=c89 -c -I /workspace/znineeight/sf/src/include main_*.c
gcc -m32 -std=c89 main_*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/fix_bin
/tmp/fix_bin
```
Expected: dump rc=0; gcc rc=0; run prints `2` (was `0`). Also confirm emitted C now carries the 3 `case` labels.

- [ ] **Step 3: Verify no GREEN regression**

4 MD5 gates byte-identical (gol/lisp repo-root CWD, json `089e4f04…`, mud `a1d0dd55…`); matrix 21/21 (dump/gcc/link rc=0).

- [ ] **Step 4: Self-compile re-count**

Run `scripts/self_compile/build_zig1_5.sh`; confirm 40 `.c`, gcc -c 0 error lines; the previously-failing binary-operator parse errors (`+ - * / == != < <= > >= = and or`) are gone from the self-compiled binary.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit `fix: qualified enum-literal switch cases no longer dropped (zT case labels)`. Report: status, commit, gate summary (fixture print, 4 MD5s, matrix, re-count), concerns. Ledger + memory entries.

---

### Task 3: R-ENUMEXT — runtime-correctness fixtures for enum switches

**Files:**
- Create: `repro/mi_matrix/emission_enum_ext_xmod/{main.zig,mod_a.zig,NOTES.md}`
- Commit: `repro: enum-switch runtime-correctness fixtures (qualified + anonymous)`

**Interfaces:**
- Consumes: Task 2 fix (qualified enum cases now collect).
- Produces: GREEN runtime-correctness fixtures covering qualified + anonymous enum switch forms, multi-case, nested.

- [ ] **Step 1: Write fixtures**

Fixture A (qualified, multi-case, print): `switch (k) { Kind.plus => r=1, Kind.minus => r=2, Kind.star => r=3, else => r=9 }` with `printInt`. Fixture B (anonymous `.plus` form, print). Fixture C (nested switch on enum inside an if inside a for, print). Fixture D (enum-to-int print via `@intCast`). All print expected values.

- [ ] **Step 2: Verify GREEN**

Each fixture: dump rc=0, gcc rc=0, link rc=0, run prints expected value. If any is RED → this is a NEW divergence beyond Task 2's fix → STOP and escalate (fork: add I/F task or operator ruling).

- [ ] **Step 3: NOTES.md**

Convention: purpose / verbatim source / GREEN evidence (run output) / which shape each covers.

- [ ] **Step 4: No GREEN impact + commit**

Spot-check gol MD5 unchanged (fixture new-only). Commit `repro: enum-switch runtime-correctness fixtures (qualified + anonymous)`. Report + ledger + memory.

---

### Task 4: R-TUSWITCH — tagged-union switch runtime-correctness fixtures

**Files:**
- Create: `repro/mi_matrix/emission_tu_switch_xmod/{main.zig,mod_a.zig,NOTES.md}`
- Commit: `repro: tagged-union switch runtime-correctness fixtures`

**Interfaces:**
- Consumes: Task 2 fix.
- Produces: GREEN fixtures (or documented RED → fix).

- [ ] **Step 1: Write fixtures**

Fixture A: `switch (u)` over a tagged union with anonymous `.tag => |payload|` capture, access payload value, print. Fixture B: tagged-union switch + tag-to-int (`@intCast(u32, @enumToInt(...))` or the dialect's tag access), print. Fixture C: nested — `for` inside `if` inside `switch (tagged union)`, access payload, print. Use the existing `tests/test_union_dispatch.zig` or `repro/tagged_union_slice_payload/main.zig` as shape references.

- [ ] **Step 2: Verify GREEN**

Each: dump rc=0, gcc rc=0, run prints expected. RED → STOP + escalate (fork).

- [ ] **Step 3: NOTES.md + no GREEN impact + commit**

Convention NOTES.md; gol spot-check; commit `repro: tagged-union switch runtime-correctness fixtures`. Report + ledger + memory.

---

### Task 5: R-LABELED — labeled-statement runtime-correctness fixtures

**Files:**
- Create: `repro/mi_matrix/emission_labeled_ctrl_xmod/{main.zig,NOTES.md}`
- Commit: `repro: labeled-statement control-flow runtime-correctness fixtures`

**Interfaces:**
- Consumes: existing labeled_stmt lowering (lower.zig:4408-4414 stmt, :4315-4318 expr).
- Produces: GREEN fixtures for `blk: { break :blk }`, `loop: while … break :loop`/`continue :loop`.

- [ ] **Step 1: Write fixtures**

Fixture A: labeled block `blk: { … break :blk … }`, print. Fixture B: labeled while with `break :loop` + `continue :loop`, print loop iterations. Fixture C: labeled statement nested inside a switch-on-enum prong body, print. All print expected values.

- [ ] **Step 2: Verify GREEN**

Each: dump rc=0, gcc rc=0, run prints expected. RED → STOP + escalate (fork).

- [ ] **Step 3: NOTES.md + no GREEN impact + commit**

Convention NOTES.md; gol spot-check; commit `repro: labeled-statement control-flow runtime-correctness fixtures`. Report + ledger + memory.

---

### Task 6: GATE-FINAL — full sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Commit: `docs: fidelity-gap fix GATE + reconciliation`

**Interfaces:**
- Consumes: Tasks 1-5 results.
- Produces: reconciled docs + verified gate.

- [ ] **Step 1: Full sweep**

4 MD5 gates byte-identical; matrix 21/21; corpus re-count; test_analyzer_bin.

- [ ] **Step 2: Self-compile verification**

`build_zig1_5.sh`; confirm the self-compiled binary now parses binary operators correctly (the fidelity-gap observable). Record any remaining fidelity gaps (documented, out of scope).

- [ ] **Step 3: Docs reconciliation**

EXPECTED_FAIL.md version bump + closeout (fix SHA, fixtures, milestone); QUICK_REF.md baseline paragraph if corpus numbers changed.

- [ ] **Step 4: Commit + ledger + memory**

Commit `docs: fidelity-gap fix GATE + reconciliation`. Ledger + memory entries.

---

## Self-Review (controller, before execution)

- **Spec coverage:** Task 1 (I) + Task 2 (F) close the enum-switch drop; Tasks 3-5 cover the spec's extension shapes (enum switches, tagged-union switch, labeled statements, nested for/if/switch-with-enums) as runtime-correctness fixtures; Task 6 is the gate.
- **Placeholder scan:** all steps carry exact commands/expected output; no TBD.
- **Type consistency:** fixture dirs named per convention `emission_<shape>_xmod`; artifact paths stable.
- **Fork policy:** any RED extension fixture beyond the known drop → STOP + escalate (this plan fixes only the enum-switch drop; new divergence classes need their own I/F).
