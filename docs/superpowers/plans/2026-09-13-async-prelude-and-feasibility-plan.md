# Z98 Async Coroutines + Win9x Calling-Convention Prelude — Feasibility Spike Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the design/census and hand-written C89 prototype evidence needed to make a Go/No-Go decision on Z98 async coroutines, and to lock the Win9x calling-convention prelude design — with no compiler implementation.

**Architecture:** One shared investigation plan. Every task is record-only (no `sf/src` edits). Tasks P1–P2 census the compiler attachment points and resolve the open design questions; P3 builds three throwaway C89 prototypes in `/tmp` that exercise the frame/step/nesting/scheduler model; P4 synthesizes findings, amends the spec, and STOP-presents a Go/No-Go plus a recommended implementation decomposition. The Win9x prelude design (calling convention, `error[3020]` rule, `extern struct` ABI stance, inline-asm status) stands even if async is No-Go.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, `i686-w64-mingw32-gcc`, `wine`, git.

## Global Constraints

- **Investigation-only.** No `sf/src` edits, no compiler change, no fixed-point movement, no seed rotation, no `EXPECTED_FAIL` bump. The only code written is throwaway C89 under `/tmp`.
- **Baseline (re-verify at Task 1):** HEAD `14129e68`; compiler fixed point `1467d932a876402f40a56316dfcad0e5`; seed v10 archive `ca18fc9f9af55d58147fcb7ff7a662b6`; corpus 570 = 541 OK / 29 GREEN / 0 FAIL; `repro/mi_matrix/EXPECTED_FAIL.md` header v77.
- **`timeout 120` on every binary execution.**
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted).
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Gate/flag rules for any compiler run:** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; compiler builds only via `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>` (never invoke `zig0`).
- **Win32 oracle:** `i686-w64-mingw32-gcc` with `<windows.h>`; run under `wine` only if a runnable check is needed.
- **Artifacts:** report `.superpowers/sdd/task-ASYNCPRELUDE-report.md` (gitignored); ledger `.superpowers/sdd/progress.md` (gitignored); memory agent `asyncprelude-session` via `mnemoria --path .opencode/memory add --agent asyncprelude-session --type <type> --summary <one-line> <content>`. Review packages via the SDD `scripts/review-package BASE HEAD`.
- **Spec of record:** `docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md`. Locked decisions L1–L9 and open items §6/§15 govern every task.
- **STOP-present protocol:** each task ending in STOP must present findings to the operator and await GO before the next task begins.

---

### Task 1: Commit the seed ideas doc + prelude census/designs (A–D)

**Files:**
- Create: `docs/superpowers/specs/2026-09-13-z98-coroutine-ideas.md` (verbatim copy of `sf/docs/corroutines.txt`)
- Modify: `.superpowers/sdd/task-ASYNCPRELUDE-report.md` (gitignored; `## Task 1`)
- Modify: `.superpowers/sdd/progress.md` (gitignored; one ledger line)

**Interfaces:**
- Consumes: spec §7, §8, §9, §10, §11 and recon anchors.
- Produces: (a) tracked ideas doc at the path above; (b) prelude census with exact anchors and a design per item A–D; (c) the Win32 PAL call-coverage audit and the `WNDCLASSEX` ABI-oracle result; (d) a STOP-present.

- [ ] **Step 1: Re-verify baseline**

Run:
```bash
git log --oneline -1
git status --porcelain
md5sum release/seed/zig1-seed.tgz
bash scripts/corpus/list_corpus_dirs.sh | wc -l
sed -n '1p' repro/mi_matrix/EXPECTED_FAIL.md
```
Expected: HEAD `14129e68`; dirty set = pre-existing only (`M docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `M mnemoria/log.bin`, `M mnemoria/manifest.json`, `?? .zig1_res.tmp`, `?? .zig1_side.tmp`, `?? examples/z98/json_parser_upgraded/`); archive md5 `ca18fc9f…`; corpus count `570`; header `v77`. Record the observed values in the report; if any differ, STOP-present before continuing.

- [ ] **Step 2: Track the ideas doc**

Run:
```bash
cp sf/docs/corroutines.txt docs/superpowers/specs/2026-09-13-z98-coroutine-ideas.md
cmp sf/docs/corroutines.txt docs/superpowers/specs/2026-09-13-z98-coroutine-ideas.md
git add docs/superpowers/specs/2026-09-13-z98-coroutine-ideas.md
git commit -m "docs: add tracked Z98 coroutine ideas reference (ASYNCPRELUDE)"
```
Expected: `cmp` silent (byte-identical); commit contains exactly one file. Do not delete `sf/docs/corroutines.txt`.

- [ ] **Step 3: Prelude A census — calling convention**

Grep and read, recording exact anchors in the report:
```bash
grep -n 'extern' sf/src/parser.zig | head -40
grep -rn '__cdecl\|__stdcall\|WINAPI\|__attribute__' sf/src | head
grep -n 'WINAPI\|WSAStartup\|CreateFileA\|TerminateProcess\|ExitProcess' sf/src/include/zig_pal.c sf/src/include/net_prelude.h
grep -n 'is_extern\|flags_packed\|VOLATILE_FLAG\|MarkFnPtrUsed' sf/src/type_registry.zig | head
```
Deliver in the report: (a) confirmation the `extern` string is dropped at `parser.zig:1554-1556`; (b) the free-bit inventory (`FnPayload.flags_packed` and `Type.flags` bits 2-7); (c) the emission sites that would carry the convention (`c89_emit.zig:2134-2241`, `:1882-1910`, and the "no prototype for non-variadic extern" behavior at `:2418`/`:2566`); (d) the PAL/Win32 call-coverage audit table (each Win32 call in `zig_pal.c`/Winsock in `net_prelude.h`, marked "safe via include" vs "needs convention if declared directly"); (e) the design per spec §8 including the exact diagnostic trigger and the target-gating/portability rule for emitting the convention.

- [ ] **Step 4: Prelude B design — `error[3020]` at address-taking**

Locate the address-of/coercion path:
```bash
grep -n 'func_ref\|fn_ptr\|address_of\|markFnPtrUsed\|IsAssignable' sf/src/lower.zig | head -40
grep -n '3020\|3021\|3022\|3023\|3017-3029' sf/src/diagnostics.zig
```
Deliver: the exact AST/LIR site(s) where a function becomes a fn-pointer value (the intended error point), why the call site is NOT the right point, and how the rule depends on `is_suspending` from Stage 1. Recommend a free error code (3020 is taken).

- [ ] **Step 5: Prelude C — extern-struct ABI oracle**

Create `/tmp/abi_oracle.c`:
```c
#include <windows.h>
#include <stdio.h>
#include <stddef.h>
int main(void) {
    printf("WNDCLASSEX %u %u %u %u %u\n",
        (unsigned)sizeof(WNDCLASSEX),
        (unsigned)offsetof(WNDCLASSEX, cbSize),
        (unsigned)offsetof(WNDCLASSEX, lpfnWndProc),
        (unsigned)offsetof(WNDCLASSEX, hInstance),
        (unsigned)offsetof(WNDCLASSEX, lpszClassName));
    printf("POINT %u %u %u\n", (unsigned)sizeof(POINT),
        (unsigned)offsetof(POINT, x), (unsigned)offsetof(POINT, y));
    printf("MSG %u %u %u\n", (unsigned)sizeof(MSG),
        (unsigned)offsetof(MSG, hwnd), (unsigned)offsetof(MSG, message));
    return 0;
}
```
Run:
```bash
i686-w64-mingw32-gcc -o /tmp/abi_oracle.exe /tmp/abi_oracle.c
( cd /tmp && timeout 120 wine abi_oracle.exe )
```
Then build an equivalent Z98 normal struct fixture in `/tmp` (not in the repo) and dump `@sizeOf`/`@offsetOf` with the seed compiler:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/asyncprelude_seed
# fixture at /tmp/z98_abi/main.zig mirrors WNDCLASSEX field order/types
timeout 120 /tmp/asyncprelude_seed/zig1_5_clean -ffast --dump-c89 --output-dir /tmp/z98_abi/em /tmp/z98_abi/main.zig
gcc -m32 -std=c89 -O0 -I /tmp/z98_abi/em -o /tmp/z98_abi/oracle /tmp/z98_abi/em/*.c
( cd /tmp/z98_abi && timeout 120 ./oracle )
```
Deliver: the two offset/size tables side by side and a verdict — "Z98 normal struct matches Win32 ABI (no `extern struct` needed)" or the exact divergent field(s). If `wine` is unavailable, record that and use the compile-time `offsetof` output only.

- [ ] **Step 6: Prelude D — inline asm status**

Run:
```bash
grep -rn 'asm' sf/src/token.zig sf/src/parser.zig sf/src/semantic_analyzer.zig | head
```
Deliver: confirmation there is no `asm`/`__asm`/`@asm` token or builtin, and the exact statement to document ("inline assembly is not accepted; use an extern helper or a PAL/runtime helper").

- [ ] **Step 7: Write report section + ledger + memory**

Append `## Task 1` to `.superpowers/sdd/task-ASYNCPRELUDE-report.md` with the baseline values, the commit hash from Step 2, and the A–D deliverables. Append one line to `.superpowers/sdd/progress.md`. Add one mnemoria entry:
```bash
mnemoria --path .opencode/memory add --agent asyncprelude-session --type discovery \
  --summary "ASYNCPRELUDE Task 1: prelude A-D census + ABI oracle" \
  "<one-paragraph finding>"
```

- [ ] **Step 8: STOP-present**

Present to the operator: the tracked-doc commit, the calling-convention design + PAL audit result, the `error[3020]` error-site recommendation, the `WNDCLASSEX` ABI verdict, and the inline-asm statement. Await GO before Task 2.

---

### Task 2: Async Stage 1–6 census and design

**Files:**
- Modify: `.superpowers/sdd/task-ASYNCPRELUDE-report.md` (`## Task 2`)
- Modify: `.superpowers/sdd/progress.md` (one ledger line)

**Interfaces:**
- Consumes: spec §7, §12, §15; Task 1 report.
- Produces: anchors + a design per async stage, and explicit resolution (or a documented recommendation) for open items §15.1–§15.4 and §15.8; a STOP-present.

- [ ] **Step 1: Stage 1 — call graph + `is_suspending`**

Locate the attachment point and algorithm host:
```bash
grep -n 'phase_\|runCompiler' sf/src/main.zig | sed -n '1,40p'
sed -n '1,30p' sf/src/symbol_table.zig
grep -n 'fn_call\|call_direct\|func_ref' sf/src/ast.zig sf/src/lir.zig | head
```
Deliver: which phase hosts the worklist (recommend between import-resolution and lowering), the `is_suspending` storage choice (Symbol field vs side table), the AST edge-extraction plan, cross-module propagation, and the mutual-recursion termination argument.

- [ ] **Step 2: Stage 2 — frame layout on the LIR CFG**

Inspect the LIR CFG and liveness precedents:
```bash
grep -n 'BasicBlock\|is_terminated' sf/src/lir.zig | head
grep -n 'rc\[\|wc\[\|rd_bb\|scanAll\|computeNestMetadata' sf/src/lir_opt_pass.zig | head -30
grep -n 'hoisted_temps\|decl_local\|nextTemp' sf/src/lower.zig | head -20
```
Deliver: the exact LIR structures to walk, the liveness algorithm to use, the frame field synthesis rule (state width, alignment, declaration order), and a per-function memory estimate. Assess `-s<N>` spill impact and state whether a new spill level is needed.

- [ ] **Step 3: Stage 3 — state-machine transform + open item resolution**

Deliver a concrete LIR-transform sketch (block/state numbering, entry/exit, suspend/resume transitions) and resolve **open item §15.2 (implicit-await frame ownership)** with a recommendation and rationale (embedded child frame vs caller-allocated from a Task arena), including the frame-size composition consequence. Assess whether new LIR ops are needed and whether they fit `@sizeOf(LirInst)` ≤32 bytes and the `lir_stream` byte contract.

- [ ] **Step 4: Stage 4 — builtin plumbing + `@asyncFrameSize` recommendation**

Read the builtin pipeline:
```bash
sed -n '248,300p' sf/src/semantic_analyzer.zig
grep -n 'builtin_call\|builtin_exit\|async' sf/src/lower.zig | head
sed -n '110,175p' sf/src/lir.zig
```
Deliver: the exact files/lists to touch for the four builtins; the error-site rules; and a recommendation for **open item §15.1 (`@asyncFrameSize` timing/value)** chosen from spec §6, with the concrete mechanism (e.g. runtime-materialized integer emitted during lowering) and why the alternative (early AST pass) is or is not preferred. Recommend error/warn code assignments (open item §15.7).

- [ ] **Step 5: Stage 5 — `std.async` + install surface**

Deliver the `sf/src/std_async.zig` surface (concrete, no generics) and the full list of install touchpoints: `sf/src/std.zig`, seed `lib/`, `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `scripts/self_compile/build_zig1_5.sh`, QUICK_REF install recipe. Confirm no existing async code (`grep -niE 'task|scheduler|async|suspend' sf/src/std*.zig`).

- [ ] **Step 6: Stage 6 + gate strategy + `defer` ban check**

Deliver: the integration targets (`rogue_mud` NPC AI, `mud_server` handlers) and the fixture/prototype strategy. Resolve **open item §15.8**: verify whether any `break`/`continue`/`return`-inside-`defer` enforcement exists (the speculated `ERR_4002` is unreferenced):
```bash
grep -rn 'ERR_4002\|DEFER_IN_INVALID' sf/src
grep -n 'parserParseDeferStmt\|pushDefer\|expandDefers' sf/src/parser.zig sf/src/lower.zig
```
State whether the ban must be introduced before async `defer` rules can be enforced.

- [ ] **Step 7: Write report section + ledger + memory + STOP-present**

Append `## Task 2` with all stage designs, the open-item resolutions/recommendations, and the code-assignment proposal. Append one ledger line and one mnemoria entry. STOP-present the async design and await GO.

---

### Task 3: Hand-written C89 prototypes (P1–P3)

**Files:**
- Create: `/tmp/asyncspike/p1_minimal.c`, `/tmp/asyncspike/p2_nesting.c`, `/tmp/asyncspike/p3_scheduler.c`, `/tmp/asyncspike/build_run.sh`
- Modify: `.superpowers/sdd/task-ASYNCPRELUDE-report.md` (`## Task 3`)
- Modify: `.superpowers/sdd/progress.md` (one ledger line)

**Interfaces:**
- Consumes: Task 2 designs (frame shape, implicit-await ownership, scheduler surface).
- Produces: three buildable/run programs with deterministic stdout and md5 evidence proving the model; a STOP-present.

- [ ] **Step 1: P1 — minimal frame + step**

Write `/tmp/asyncspike/p1_minimal.c` implementing one coroutine with a single `@asyncSuspend`-equivalent yield:
```c
/* frame: { unsigned char state; int acc; }
   step(f, result): state 0=entry -> acc=1; yield (store state, return);
   resume: state 1 -> acc+=2; complete result=acc */
```
The program must print exactly `p1 3` and exit 0.

- [ ] **Step 2: Build and run P1**

Run:
```bash
timeout 120 gcc -m32 -std=c89 -O0 -Wall -o /tmp/asyncspike/p1 /tmp/asyncspike/p1_minimal.c
for i in 1 2 3; do ( cd /tmp/asyncspike && timeout 120 ./p1 ) | md5sum; done
```
Expected: three identical md5s; stdout `p1 3`.

- [ ] **Step 3: P2 — implicit-await nesting**

Write `/tmp/asyncspike/p2_nesting.c` where a caller coroutine awaits a callee coroutine (frame ownership per Task 2's recommendation). It must print exactly `p2 10` and exit 0, exercising: caller stores callee frame, drives it to completion, resumes its own state.

- [ ] **Step 4: Build and run P2** (same command shape as Step 2; expect identical md5s and `p2 10`).

- [ ] **Step 5: P3 — scheduler, cancel, error-union delivery**

Write `/tmp/asyncspike/p3_scheduler.c` with a 3-task scheduler (`tick`), one task cancelled mid-flight (cooperative `cancel_requested`), and one error-union result delivered to an await point. It must print exactly:
```
p3 start
p3 task0 done
p3 task1 canceled
p3 task2 err=OutOfMemory
p3 end
```
and exit 0.

- [ ] **Step 6: Build and run P3** (same command shape; expect identical md5s and the exact stdout above).

- [ ] **Step 7: Record evidence**

Create `/tmp/asyncspike/build_run.sh` that builds and runs all three with `timeout 120` and prints each program's stdout and md5. Run it and paste the output into `## Task 3`, together with the frame/step snippets that demonstrate the model (especially P2's ownership mechanism). Record any model divergence found (this is the spike's main feedback into Task 2's design).

- [ ] **Step 8: Write report/ledger/memory + STOP-present**

Append `## Task 3`, one ledger line, one mnemoria entry. STOP-present the prototype evidence and any design corrections; await GO.

---

### Task 4: Synthesis, Go/No-Go, spec amendment, final STOP-present

**Files:**
- Modify: `docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md` (amend §6/§12/§15 with findings and the resolved recommendations)
- Modify: `.superpowers/sdd/task-ASYNCPRELUDE-report.md` (`## Task 4`)
- Modify: `.superpowers/sdd/progress.md` (one ledger line)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: a Go/No-Go verdict, a recommended implementation decomposition, an amended spec, and the terminal STOP-present.

- [ ] **Step 1: Evaluate Go/No-Go**

Apply spec §14 criteria explicitly against the evidence: P1–P3 build+run deterministically; every stage has a bounded attach point; no fatal blocker; a decomposition emerges. Write the verdict with the supporting evidence line for each criterion.

- [ ] **Step 2: Recommend the decomposition**

Write the recommended split for implementation (default: (1) compiler core Stages 1–4, (2) `std.async` Stage 5, (3) integration Stage 6), with any adjustment the findings force.

- [ ] **Step 3: Amend the spec**

Use `edit`/`fastedit` to update the spec: resolve §6 open items, fill §12.4/§12.7 with the recommended mechanism and code assignments, and update §15 to "resolved (with evidence)". Keep the spec's design-only status.

- [ ] **Step 4: Verify no repo drift**

Run:
```bash
git status --porcelain
git diff --stat
```
Expected: only the two tracked docs (`docs/superpowers/specs/2026-09-13-z98-coroutine-ideas.md` from Task 1, and the amended spec) plus the pre-existing dirty set. No `sf/src` change.

- [ ] **Step 5: Commit the docs**

Run:
```bash
git add docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md
git commit -m "docs: ASYNCPRELUDE feasibility findings + Go/No-Go (ASYNCPRELUDE)"
```
(The ideas-doc commit already landed in Task 1.)

- [ ] **Step 6: Write report/ledger/memory + final STOP-present**

Append `## Task 4` with the Go/No-Go, decomposition, and amended-spec summary; add one ledger line and one mnemoria entry. STOP-present the final result — this is the plan's terminal state; no seed rotation and no fixed-point change occur.

---

## Self-Review

**Spec coverage:**
- Spec §1–§4 (problem/vision/scope/non-goals) → plan header + Global Constraints + Task 4.
- §5 locked decisions → carried into Global Constraints; no task re-litigates them.
- §6 open items → Task 2 (async) and Task 4 (resolution).
- §7 current reality → Task 1 baseline + Task 2 anchors (already cited in the spec).
- §8 Prelude A → Task 1 Steps 3, 8.
- §9 Prelude B → Task 1 Step 4.
- §10 Prelude C → Task 1 Step 5.
- §11 Prelude D → Task 1 Step 6.
- §12 async stages → Task 2 Steps 1–6.
- §13 testing → Task 3 prototypes + Task 1 oracle.
- §14 Go/No-Go + decomposition → Task 4 Steps 1–2.
- §15 open items → Task 2 + Task 4.

**Placeholder scan:** no "TBD/TODO/later"; each step names exact files, commands, and expected evidence. The only enumerated-by-reference content is the report prose, which the task itself specifies.

**Type/name consistency:** artifact paths, the report/ledger/memory names, the compiler fixed point, seed archive md5, corpus count, and the C prototype program names (`p1_minimal.c`/`p2_nesting.c`/`p3_scheduler.c`) are used identically across tasks.
