# Self-Hosted zig1_5 Investigation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) Locate the lexer mis-emission that makes self-compiled `zig1_5` fail to tokenize operators/punctuation; (2) design an `sf/src_sh/` self-hosted tree so `zig1_5` depends only on `zig1` (zig0 + `__bootstrap_*` deps dropped), externs migrated to `@cInclude`.

**Architecture:** Two independent read-only investigation phases. Phase 1 diffs zig0's (correct) vs zig1's (buggy) C emission of `lexerNextToken`, confirms via intrusive `fprintf` on a temp copy of the generated lexer, produces a minimal RED repro fixture, and traces the divergence to its `sf/src` emission site. Phase 2 maps the zig0→zig1 dependency surface, computes the runtime-function delta for `zig1_5`, and produces a full `sf/src_sh/` + `@cInclude` migration design. No `sf/src` fixes in either phase.

**Tech Stack:** C++ (zig0 bootstrap via g++), Zig (sf/src), C89 (emitted code), gcc -m32, bash (build scripts).

## Global Constraints

- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild = `bash sf/scripts/build_release.sh` (gate `=== [release] Done ===`). Rebuild WIPES `/tmp/fx_subfolder/lib` — reinstall canonical std after each rebuild: `cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.
- **No `sf/src` source fixes in this plan.** Phase 1 = diagnosis + one repro fixture; Phase 2 = design doc only. Never touch `sf/build/out_release/` (WEDGED).
- Byte-identity gates (QUICK_REF.md): gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Must remain byte-identical; the repro fixture must not alter any GREEN program emission.
- Compile recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 X.zig`; multi-module `gcc -m32 -std=c89 -c` INSIDE output dir with absolute `-I /workspace/znineeight/sf/src/include`; link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- Editing discipline: `edit`/`fastedit` only; re-read region before each edit; edit bottom-to-top; never `end_line=start_line-1`; insert via replacing an anchor line.
- Z98 dialect for probe `.zig` (fixture + any temp repro): no anytype/@Type; `@intCast` for int casts; `switch` requires `else`; no method syntax; no pointer captures.
- Markers extract with `grep -a`, never `strings`.
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory` entry per completed task (agent `r2r1-session`; types discovery/decision/intent/problem/pattern).
- Reports written to `.superpowers/sdd/task-<N>-report.md` (gitignored); return only status + one-line gate summary from implementers.

---

### Task 1: I-LEXER-REF — generate reference and buggy C

**Files:**
- Run (no repo writes): `sf/` build of zig0, `/tmp/ref_zig1.c`
- Report: `.superpowers/sdd/task-LEXER-REF-report.md` (gitignored)

**Interfaces:**
- Consumes: `sf/scripts/build_release.sh` recipe, `/tmp/zig1_5/gen/` artifacts.
- Produces: `/tmp/ref_zig1.c` (zig0 monolithic correct emission); path to buggy `/tmp/zig1_5/gen/lexer_*.c`.

- [ ] **Step 1: Rebuild zig0**

Run (workdir `/workspace/znineeight/sf`):
```bash
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0
```
Expected: `build/zig0` created, rc=0.

- [ ] **Step 2: Generate reference C (zig0 emission)**

Run (workdir `/workspace/znineeight/sf`):
```bash
./build/zig0 --header-priority-include -o /tmp/ref_zig1.c sf/src/main.zig
```
Expected: `/tmp/ref_zig1.c` exists (monolithic; this is the CORRECT emission — reference `zig1` was built this way).

- [ ] **Step 3: Confirm buggy C**

Run (workdir `/workspace/znineeight`):
```bash
ls /tmp/zig1_5/gen/lexer_*.c
```
If stale/missing, regenerate:
```bash
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/zig1_5/gen sf/src/main.zig
```
Expected: `/tmp/zig1_5/gen/lexer_<hash>.c` present (this is the BUGGY emission — it compiled into the broken `zig1_5`).

- [ ] **Step 4: Record + report**

Confirm both artifacts exist; note zig0 emits monolithic vs zig1 per-module; the target function is mangled `zF_<hash>_lexerNextToken`. Write report: status, artifacts (paths + sizes), one-line gate note.

- [ ] **Step 5: Ledger + memory**

Append ledger line; `mnemoria` entry (context: fidelity-gap investigation artifacts).

---

### Task 2: I-LEXER-DIFF — isolate the mis-emission

**Files:**
- Report: `.superpowers/sdd/task-LEXER-DIFF-report.md` (gitignored)

**Interfaces:**
- Consumes: `/tmp/ref_zig1.c` (correct), `/tmp/zig1_5/gen/lexer_*.c` (buggy) from Task 1.
- Produces: pinned divergent construct (exact C lines in both outputs).

- [ ] **Step 1: Extract `lexerNextToken` from both outputs**

Run:
```bash
grep -a -n "lexerNextToken" /tmp/ref_zig1.c
grep -a -n "lexerNextToken" /tmp/zig1_5/gen/lexer_*.c
```
Capture the function body (switch dispatch + `lexerMatch` helpers) from each. Note: zig0 may inline/name differently; match by the char-literal dispatch body (`case ':'`, `case '<'` …).

- [ ] **Step 2: Diff the operator-switch + char-comparison bodies**

Run:
```bash
diff -u <(zig0-lexerNextToken-body) <(zig1-lexerNextToken-body)
```
Pin the FIRST semantic divergence (not hash/name noise): candidates are (a) char-literal case labels emitted with wrong constants, (b) `switch`-over-`u8` lowering (if/else chain vs jump table, wrong compare), (c) `TokenKind` enum ordinal mapping in `lexerMakeToken`, (d) `lexerMatch` char comparison. Record exact C lines from each side.

- [ ] **Step 3: Cross-check against source**

Read `sf/src/lexer.zig:47-166` and `sf/src/token.zig` (TokenKind enum order) + `sf/src/lexer.zig` `lexerMatch` body. Map the divergent C back to the Zig construct it came from.

- [ ] **Step 4: Report + ledger + memory**

Report: divergent construct, exact C lines both sides, Zig source anchor, candidate emission sites (`sf/src/lower.zig` switch lowering / `sf/src/c89_emit.zig` switch-case + char-literal emission), verdict on which is the likely mis-emission. Ledger + memory entries.

---

### Task 3: R-LEXER — minimal repro fixture

**Files:**
- Create: `repro/mi_matrix/emission_lexer_switch_xmod/{main.zig,mod_a.zig,NOTES.md}` (per fixture convention)
- Commit: `repro: lexer operator-switch mis-emission fixture`

**Interfaces:**
- Consumes: divergent construct pinned in Task 2.
- Produces: byte-identical RED fixture (gcc error or wrong emitted token kind matching the lexer bug class).

- [ ] **Step 1: Write minimal `.zig`**

Shape must reproduce the pinned construct with NO other dialect features: a `switch` over a `u8` with char-literal case labels (`':'`, `'<'`, `'+'`, `'-'` …) + an `else`, and a `lexerMatch`-style fn comparing a char. Drive it so the mis-tokenized chars (`:`/`<=`/`-`/`+`) are observable (e.g. print the resulting token kind).

- [ ] **Step 2: Verify RED**

Run (workdir fixture dir):
```bash
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig
gcc -m32 -std=c89 -c -I /workspace/znineeight/sf/src/include main_*.c
```
Expected: dump rc=0; gcc rc=1 (or emitted C that when run prints the wrong token kind) — byte-identical class to the `zig1_5` lexer bug. Confirm the same source compiles correctly under reference `zig1` behavior expectations (the bug is in emission, so fixture is RED at gcc/run stage).

- [ ] **Step 3: NOTES.md**

Convention: purpose / verbatim source / RED evidence (exact error text + emitted-C excerpt) / root-cause pin (from Task 2) / expected post-fix.

- [ ] **Step 4: Verify no GREEN impact**

Confirm the 4 MD5 gates unchanged (fixture is new-only). Quick spot-check one MD5 (gol) if in doubt.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit `repro: lexer operator-switch mis-emission fixture`. Report: status, commit, gate summary, concerns.

---

### Task 4: I-LEXER-TRACE — instrument, confirm, trace to emission site

**Files:**
- Run (temp only, NOT repo): `/tmp/lexer_trace.c`, `/tmp/lexer_trace_bin`
- Report: `.superpowers/sdd/task-LEXER-TRACE-report.md` (gitignored)

**Interfaces:**
- Consumes: buggy `lexer_*.c` (Task 1), divergent construct (Task 2), fixture (Task 3).
- Produces: confirmation of wrong token-kind per char + emission site `file:line`.

- [ ] **Step 1: Instrument a temp copy**

Copy the buggy `lexer_*.c` to `/tmp/lexer_trace.c`. Add `#include <stdio.h>` (top) and `fprintf(stderr, "c=%d kind=%d\n", c, kind)` immediately before each `lexerMakeToken` return inside `lexerNextToken`, plus at the `switch` entry. TEMP file only — never edit the repo's generated output.

- [ ] **Step 2: Recompile + run on minimal input**

Compile `/tmp/lexer_trace.c` + the rest of `/tmp/zig1_5/gen/*.o` (or rebuild per `build_zig1_5.sh` recipe with the instrumented lexer swapped in) into `/tmp/lexer_trace_bin`. Run on `fn fib(n: u32) u32 {}` (or the Task 3 fixture). Capture the `c=... kind=...` trace. Compare against expected TokenKind ordinals for `:`, `<=`, `-`, `+`.

- [ ] **Step 3: Confirm divergence**

Identify which input chars produce wrong `kind` values and what those values are (map back via `token.zig` enum order). This confirms which of the Task-2 candidates is live.

- [ ] **Step 4: Trace to emission site**

Find the emission code responsible for the wrong output: `sf/src/lower.zig` (switch lowering — search `swt_ex`/`switch` lowering), `sf/src/c89_emit.zig` (switch-case emission, char-literal emission — search `case `/char emission). Record `file:line` and the emission pattern.

- [ ] **Step 5: Written finding**

Report: mechanism (source construct → wrong C → wrong runtime token), emission site `file:line`, repro (fixture path + minimal input), recommended fix locus (for a later F-session). Ledger + memory entries.

---

### Task 5: I-DEP-MAP — zig0→zig1 dependency surface

**Files:**
- Report: `.superpowers/sdd/task-DEP-MAP-report.md` (gitignored)

**Interfaces:**
- Consumes: `sf/src/bootstrap/*.cpp`, `sf/scripts/build_release.sh`, `sf/src/include/`.
- Produces: dependency catalog (zig0 assets that make zig1 exist).

- [ ] **Step 1: Catalog the bootstrap compiler**

List `sf/src/bootstrap/` files (≈40 `.cpp`). One line each for the pipeline files: `bootstrap_all.cpp` (entry), `lexer.cpp`, `parser.cpp`, `type_checker.cpp`, `type_system.cpp`, `codegen.cpp`, `cbackend.cpp` (C89 emission), `source_manager.cpp`, `token_supplier.cpp`. Do NOT deep-dive; classify roles only.

- [ ] **Step 2: Enumerate zig0's build-time/runtime contributions**

From `sf/scripts/build_release.sh` + `sf/src/include/`: (a) monolithic C emission (`--header-priority-include` → single `zig1.c`), (b) linked `zig_pal.c` only, (c) headers `zig_compat.h` / `zig_special_types.h` referenced by emitted modules, (d) any zig0-emitted runtime helpers (search emitted `zig1.c` for `__bootstrap_*`).

- [ ] **Step 3: Record the exact link surface**

Note precisely which C files zig1 links vs which zig1_5 links (from `build_zig1_5.sh`). Report + ledger + memory.

---

### Task 6: I-DELTA — zig1_5 runtime-function delta

**Files:**
- Report: `.superpowers/sdd/task-DELTA-report.md` (gitignored)

**Interfaces:**
- Consumes: `/tmp/zig1_5/gen/*.c` (Task 1), `/tmp/ref_zig1.c` (Task 1), `sf/src/include/` symbols.
- Produces: delta table (symbols zig1 emission references that zig0 emission doesn't).

- [ ] **Step 1: Extract external symbols from zig1 emission**

Run:
```bash
grep -a -ohE "\b(__bootstrap_[A-Za-z0-9_]*|pal_[A-Za-z0-9_]*|std_[A-Za-z0-9_]*|c_exit)\b" /tmp/zig1_5/gen/*.c | sort -u
```
Also grep libc calls if present (fopen/fread/fclose/fseek/ftell/write). Record the set.

- [ ] **Step 2: Extract external symbols from zig0 emission**

Run:
```bash
grep -a -ohE "\b(__bootstrap_[A-Za-z0-9_]*|pal_[A-Za-z0-9_]*|std_[A-Za-z0-9_]*|c_exit)\b" /tmp/ref_zig1.c | sort -u
```
Record the set.

- [ ] **Step 3: Build the delta table**

Set difference (zig1 − zig0). Classify each delta symbol: bootstrap (`__bootstrap_*_from_*` conversions, `__bootstrap_print*`), runtime (`pal_*`, `std_*`), libc. Also note which live in `zig_runtime.c` vs `zig_pal.c` vs `c_exit.c`.

- [ ] **Step 4: Report + ledger + memory**

Report: two symbol sets, delta table, per-symbol classification + residence file, which are true bootstrap deps (candidates to eliminate in `sf/src_sh/`).

---

### Task 7: I-SRCSH — design `sf/src_sh/`

**Files:**
- Report: `.superpowers/sdd/task-SRCSH-report.md` (gitignored)

**Interfaces:**
- Consumes: Task 5 dependency map, Task 6 delta table, `@cInclude` mechanism (`cinclude.zig`, `emitModuleHeader` `#include` emission, `parserParseCInclude`), `extern "c" fn` sites (`pal.zig:5-14`, `extern_c.zig`).
- Produces: full `sf/src_sh/` design (file list + `@cInclude` migration map + minimal runtime design).

- [ ] **Step 1: Enumerate extern surface**

List every `extern "c" fn` in `sf/src/pal.zig` and `sf/src/extern_c.zig` (+ `extern_c_z98.zig` as the existing `@cInclude` exemplar). For each: name, signature, which runtime `.c` provides it.

- [ ] **Step 2: Full `sf/src_sh/` file list**

Design the self-hosted tree. For each file: name, role, change summary (logic unchanged; only deps). Include: the `@cInclude`'d headers (contents in Step 3), the extern migration, any bootstrap-symbol elimination. State what is copied unchanged vs modified vs new.

- [ ] **Step 3: `@cInclude` migration map**

Map each `extern "c" fn` → which `@cInclude`'d header; write the header contents (C prototypes) for each. Note `#include` emission semantics (`c89_emit.zig:2204-2219`: quoted vs angle; per-module). Confirm `@cInclude` headers land in `sf/src/include/` or the sh-tree include dir.

- [ ] **Step 4: Minimal non-bootstrap runtime design**

Specify what remains as linked C (minimal, non-bootstrap), what zig1 must emit, and what becomes libc-only. Goal: `zig1_5` links only self-emitted `.o` (+ minimal runtime), no zig0, no `__bootstrap_*`.

- [ ] **Step 5: Written design + ledger + memory**

Report: dependency map (Task 5), delta table (Task 6), full `sf/src_sh/` file list, `@cInclude` migration map with header contents, minimal runtime design, and the exact dependency change ("logic won't change just the dependencies"). Ready to hand to a later F-session. Ledger + memory entries.

---

## Self-Review (controller, before execution)

- **Spec coverage:** Part 1 (fidelity gap) → Tasks 1-4; Part 2 (self-containment) → Tasks 5-7. All acceptance criteria covered.
- **Placeholder scan:** all steps carry exact commands/expected output; no TBD.
- **Type consistency:** artifact paths stable across tasks (`/tmp/ref_zig1.c`, `/tmp/zig1_5/gen/lexer_*.c`); fixture dir named per convention `emission_lexer_switch_xmod`.
