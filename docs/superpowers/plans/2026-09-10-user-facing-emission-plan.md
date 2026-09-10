# User-Facing Emission + Companion Build Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `zig1 -o DIR prog.zig` (no debug flag) emit a complete, self-contained, buildable tree — only the reachable modules' C89 + runtime/platform headers + runtime sources + a companion build script per target (linux / windows / OpenWatcom) — so a user builds without the source tree and without a manual.

**Architecture:** The emitter's contract becomes "emit the generated code for the chosen backend, plus a companion build script showing how to use it" (backend-general; C89 is the first instance). A pre-emission reachability pass prunes unreferenced std modules (so a stdio-only `@import("std")` program emits no `std_net` and needs no `-lwsock32`). The emit phase copies the runtime/platform support it needs into `DIR`; the revived script templates enumerate exactly what was emitted.

**Tech Stack:** Z98 (`sf/src/*.zig`), the zig1 self-hosted C89 backend (`sf/src/c89_emit.zig`, `sf/src/main.zig`), the seed rebuild model (`scripts/seed/`), the corpus/golden gates.

**Spec:** `docs/superpowers/specs/2026-09-10-user-facing-emission-design.md`

> **Task-1 findings folded (2026-09-10, operator-approved):** spec §5–§7 finalized and Tasks 3/4/5 steps amended per the Task-1 feasibility report (`.superpowers/sdd/task-EMITEMIT-report.md` `## Task 1`), decisions 1–8. Key: module-level LIR value-ref prune hook at `main.zig:855-890`; value-ref header includes (MUST-FIX); header/runtime embedded as canonical bytes + equality gate (do not revive the stale mirrors); companion scripts compiler-enumerated, `.sh` always + `.bat`/owc on `-osw`, `prog`/`prog.exe` default.

## Global Constraints

- **Z98-only, no new host dependencies.** All compiler logic in Z98.
- **Reference per the seed model.** Measurement compiler = the N-hop-converged binary, stated per report. Dump CWD = repo root, relative `sf/src/main.zig`.
- **Flag-set rule (binding):** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; `-Wall -Wextra -O3 -fsyntax-only` is a separate gate. Host runtime link set = `zig_runtime.c` + `zig_pal.c` + `c_exit.c`.
- **zig0 is RETIRED.** Verification is zig1-only (N-hop closure); no zig0/differential verification.
- **`timeout 120` on EVERY binary execution** (compiler dump, gcc, program run). The compiler can infinite-loop on bad input.
- **Fixed point:** this plan changes `sf/src`, so the self-emission fixed point WILL move — close the N-hop chain from the committed seed and rotate the seed (v7→v8) at the close.
- **Gates:** golden 9/9 + matrix 21/21 runtime byte-identity; corpus `-s0` zero-asymmetric vs the STDLIB-closed baseline (427 = 411 OK/9 GREEN/7 FAIL); 4-MD5 rows (gol `2cf07dea…`, lisp `f13bd982…`, json `f61bccfd…`, mud `68eee54c…`); re-baseline only when a gate program's emission moves (runtime-identical verification required).
- **Working conventions:** SDD mandatory; compression forbidden during build sessions; memories via `mnemoria --path .opencode/memory add`; edits via `edit`/`fastedit` only; no commit until review clean; the pre-existing dirty set is NEVER staged (`M docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `M mnemoria/*`, `?? .zig1_res.tmp`, `?? .zig1_side.tmp`, `?? examples/z98/json_parser_upgraded/`).
- **Self-contained sourcing (Task-1 decision 1; operator directive 2026-09-10):** Task 4 embeds the canonical bytes of `sf/src/include/*` + `sf/src/c_exit.c` in a **hand-written Z98 compiler helper module** (`sf/src/emit_support.zig`) exposing the emit functions; the compiler imports it and invokes it at emission time to write the support files into `DIR` — the compiler itself emits them (one self-sufficient app, like a std-kind helper). A `.sh` byte-equality gate under `scripts/` compares emitted files to the canonical sources. **NO host-side code generator, NO `perl`, NO generated source module, NO script binding other than `.sh`/`.bat`.** (Supersedes the reverted `0cca9158`, which used a perl generator and was rejected by the operator.)
- **Prune (Task-1 decisions 2/5, MUST-FIX 4):** module reachability from LIR value refs at the emission scan (`main.zig:855-890`), excluding `@import`/re-export edges; emitted headers must include headers of every value-referenced module; `emitModuleInitCalls` restricted to reachable modules.
- Report `.superpowers/sdd/task-EMITEMIT-report.md`; ledger `.superpowers/sdd/progress.md`; memory agent `emitemit-session`.

---

### Task 1 (I, record-only): Feasibility investigation — findings drive the spec. STOP-present.

**Files:**
- Read: `sf/src/main.zig` (`phase_C89Emission` :822, CLI parse, pipeline), `sf/src/c89_emit.zig` (`emitBuildTargetSh`/`Bat`/`OwcBat` :8475-8515, the emit entry points, module output), `sf/src/std.zig`, `sf/src/std_net.zig`, `sf/src/include/net_prelude.h`, `sf/src/module_registry.zig` (or wherever the import graph lives), the analyzer/lowering pipeline, `scripts/win32_cross/cross_build_run.sh`, `release/seed/SEED_README.txt`.
- Report: `.superpowers/sdd/task-EMITEMIT-report.md` (appended `## Task 1`)
- **No source edits, no commit, nothing staged.**

- [ ] **Step 1: Emit-gating + pipeline census.** Trace `sf/src/main.zig` from CLI parse to `phase_C89Emission`: exactly what runs when `--dump-c89` is absent; where the C89 emission phase sits relative to analyze/lower; what `-o/--output-dir` controls; whether any build artifact is written without the flag. Record the precise hook where "default emission" and a pre-emission reachability pass would live.
- [ ] **Step 2: Exact output-set census.** Enumerate every file the emitted tree currently produces and every file it *needs* to build: root `main_<HEX8>.c`, per-module `*.c/*.h`, `zig_special_types.h`; the runtime/platform headers (`zig_compat.h`, `zig_runtime.h`, `net_prelude.h`); the runtime sources (`zig_runtime.c`, `zig_pal.c`, root `c_exit.c`). For each, record where it is produced/found today and how a user currently gets it (`-I sf/src/include`, manual runtime link).
- [ ] **Step 3: Runtime/header sourcing feasibility.** Determine how the compiler can make the runtime/headers available in `DIR`: embed them as Z98 string constants, read them from a known path relative to the binary, or add a build-time staging step. Inspect how `zig_special_types.h` is currently emitted (embedded generator?) and whether `zig_runtime.c`/`zig_pal.c`/`c_exit.c` have in-repo canonical copies the compiler could emit. Record 2–3 options with feasibility + size/bloat trade-offs.
- [ ] **Step 4: Reachability + prune feasibility (the key unknown).** Inspect how modules and inter-module references are represented (module registry / import graph / symbol table / LIR `call`/`load_global` operands). Determine whether a **module-level** reachability prune is feasible, where it would hook (post-analyze, pre-C89), and whether `@import`/re-export edges can be excluded so `std.zig`'s `pub const net = @import("std_net.zig")` does not keep `net` alive when unused. Assess function-level pruning as a fallback. Record the fixed-point impact (compiler-source change).
- [ ] **Step 5: `@cInclude` / `net_prelude.h` resolution.** Read `sf/src/std_net.zig` + the `@cInclude` emit path. Confirm the emitted `std_net_*.h` `#include <net_prelude.h>`, how the include is resolved at compile time, and — critically — **confirm that pruning `std_net` removes the `-lwsock32` dependency** (Task-7 STDLIB probe: without the module, no socket refs).
- [ ] **Step 6: Companion-script mechanics.** Document who knows the emitted file list + selected target at emit time, and the exact toolchain flag sets for a multi-module build under: gcc (linux), `i686-w64-mingw32-gcc` (windows, `-lwsock32` iff net), MSVC `cl` (`.bat`), OpenWatcom `wcc386`/`wlink`. Confirm which of these toolchains exist on this box (mingw is present) vs emission-only-checkable.
- [ ] **Step 7: Report + ledger + STOP.** Append the full census/feasibility findings (with 2–3 options per open decision and a recommendation) to the report; append one ledger line. **STOP-present to the operator** — the spec (`docs/superpowers/specs/2026-09-10-user-facing-emission-design.md` §5–§7) and the exact steps of Tasks 2–6 are finalized from these findings before any implementation task is authored.

---

### Task 2 (F): Default emission (drop the flag gate)

**Files:**
- Modify: `sf/src/main.zig` (the `phase_C89Emission` gate)
- Report + ledger.

- [ ] **Step 1:** Remove the `if (!ctx.cli.dump_c89) return;` gate so C89 emission runs by default when an output dir is set; keep `--dump-c89` accepted as a debug alias (no behavioral difference).
- [ ] **Step 2:** TDD/gate: `timeout 120 <zig1> -o <dir> examples/z98/hello/main.zig` (NO `--dump-c89`) emits the multi-module tree; gcc-build+run byte-identical to the `--dump-c89` path. `zig1 hello/main.zig` with no `-o` still errors/usage (unchanged).
- [ ] **Step 3:** Full gate (golden/matrix/corpus/4-MD5) + N-hop fixed point; commit `feat: zig1 emits C89 by default (-o) — --dump-c89 becomes a debug alias`.
- [ ] **Step 4:** Report + ledger.

### Task 3 (F): Needed-only module emission (reachability prune)

**Files:**
- Modify: the emission LIR scan in `sf/src/main.zig` (`phase_C89Emission`, `:855-890`) per Task-1 decision 3 (co-located; NOT a separate phase); `sf/src/c89_emit.zig` header-dep include loop (`:2412-2422`) + `emitModuleInitCalls` (`:2708`).
- Fixtures: `repro/mi_matrix/...` (stdio-only vs net-using).
- Report + ledger.

- [ ] **Step 1:** Compute module reachability from **LIR value references** — the `module_id` on `call`/`call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` operands plus the defining `LirFunction`/`LirSlot`/`ModuleGlobalDecl` — seeded from the root `main`; exclude mere `@import`/re-export edges (so `std.zig`'s net reexport does not keep `std_net` alive). Emit only reachable modules. (Task-1 decision 2; fall back to function-level only if module-level proves insufficient.)
- [ ] **Step 2 (MUST-FIX):** Header dependencies must follow the **value-ref graph**: a module's emitted header includes the headers of every module it value-references (cross-module mangled prototypes live only in the callee header), not just reachable import-edge `dep_mod_ids` (`c89_emit.zig:2412-2422`); restrict `emitModuleInitCalls` (`:2708`) to reachable modules. TDD: a caller of a value-referenced module emits the callee `#include`; strict `-Wall -Wextra -O3 -fsyntax-only` shows no implicit declarations.
- [ ] **Step 3:** TDD: a stdio-only std fixture's output dir contains **no** `std_net_*.c/.h`; a net-using fixture **does**; both build+run byte-identical to PRE.
- [ ] **Step 4:** `-osw` of the stdio-only program links **without** `-lwsock32` (and without `net_prelude.h` on the include path); the net program links **with** it.
- [ ] **Step 5:** Full gate + N-hop fixed point; commit `feat: prune unreferenced modules from emission (needed-only std)`.
- [ ] **Step 6:** Report + ledger.

### Task 4 (F): Self-contained output dir (headers + runtime copied in)

**Files:**
- Create: `sf/src/emit_support.zig` — a hand-written Z98 compiler helper module: embedded canonical-byte string constants for `sf/src/include/{zig_compat.h,zig_runtime.h,net_prelude.h,zig_runtime.c,zig_pal.c}` + `sf/src/c_exit.c`, and the emit functions that write them to a `BufferedWriter`.
- Modify: `sf/src/c89_emit.zig` (import/use the helper) and the emission phase (`sf/src/main.zig`) to invoke it on the output-dir path.
- Test: a `.sh` byte-equality gate under `scripts/` comparing emitted support files to the canonical sources (must NOT generate the embedded data).
- **Forbidden:** any host-side code generator, `perl`, any generated source module, or any script binding other than `.sh`/`.bat`. The compiler itself holds and emits the bytes (one self-sufficient app).
- Report + ledger.

- [ ] **Step 1:** Add the hand-written Z98 helper `sf/src/emit_support.zig` with the canonical bytes of the six files as Z98 string constants + emit functions; import + invoke it at emission time (output-dir path) to write the files into `DIR` (Task-1 decision 1). Do NOT revive the stale `emitZigPalC`/`emitZigRuntimeC` CONTENT (missing `errno.h` + `pal_get_default_lib_path`, different runtime body). Add a `.sh` byte-equality gate that dumps the emitted support files and `cmp`s them to the on-disk canonical files (no generator).
- [ ] **Step 2:** Gate: from a copied output dir with **no** `-I` into the repo (other than `.`), `gcc -I . *.c ...` builds+runs the hello example byte-identical.
- [ ] **Step 3:** Full gate + N-hop fixed point; commit `feat: emitter writes a self-contained output dir (headers + runtime)`.
- [ ] **Step 4:** Report + ledger.

### Task 5 (F): Companion build scripts (linux / windows / OpenWatcom)

**Files:**
- Modify: `sf/src/c89_emit.zig` (`emitBuildTargetSh`/`Bat`/`OwcBat` — revive + modernize; call them from the emit phase)
- Report + ledger.

- [ ] **Step 1:** Make the templates emit correct multi-module build scripts: compiler-**enumerated** `.c` list (runtime sources last), pass the include path, link the runtime set, and add `-lwsock32` **iff `std_net` was emitted** (predicate: any emitted module's `c_includes` names `net_prelude.h`). Emit `build_target.sh` always and the `.bat`/OpenWatcom scripts only on `-osw` (Task-1 decisions 6/7); default output binary `prog`/`prog.exe`, overridable (decision 8). Fix the stale hardcoded `main.c` root → the real `main_<HEX8>.c` stem.
- [ ] **Step 2:** Gate: `build_target.sh` builds+runs a dumped example on host (gcc) and under mingw; MSVC/OpenWatcom scripts are shape-verified (toolchain absent → emission-only).
- [ ] **Step 3:** Full gate + N-hop fixed point; commit `feat: emit companion build scripts (sh/bat/owc) with target link libs`.
- [ ] **Step 4:** Report + ledger.

### Task 6 (I then F): Battery + docs GATE + seed rotation

- [ ] **Step 1 (I):** Full battery (golden/matrix/run24/corpus/4-MD5) on the fixed compiler; record the new fixed point; N-hop from the committed seed.
- [ ] **Step 2 (I):** STOP-present the re-baseline + rotation.
- [ ] **Step 3 (F):** Docs GATE (QUICK_REF newest bullet: default emission + companion scripts + needed-only modules; 4-MD5 rows as needed) + seed rotation v7→v8; `archive_seed.sh` already installs the 8-file lib.
- [ ] **Step 4:** Report + ledger close; STOP-present the plan close.

---

## Next-up items (NOT tasks of this plan)

- Non-C89 backends (asm/lisp/python) — each emits its code + a companion script under the same contract.
- `std_io.fileRead` error/EOF disambiguation; `std_arena` alignment/wrap hardening (recorded STDLIB Minors).
- String formatting beyond `std.io.print`; containers/parsers in std.
