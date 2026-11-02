# Win9x Emission Fixes (E1-E5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `-osw` emission compile and link under MSVC 6 / OpenWatcom 1.9 (and keep MinGW working), with the emitted build scripts fully self-sufficient (no manual edits), then rotate seed v130.

**Architecture:** Two verified defect classes leak Linux/POSIX constructs into Windows-target C (unconditional `@cInclude("<dirent.h>")`; dead POSIX calls surviving in `std_os`), plus two emitter defects (invalid `ZIG_*` guard macro identifiers; wrong `__w_FILE`/`__iob` for OpenWatcom no-CRT). Fix at the four source sites; bake the validated manual script improvements into the emitter templates in `c89_emit.zig`; verify claims with fresh runs first (Task I), then gates + full battery + v130 rotation.

**Tech Stack:** Z98 subset sources, emitted C89, gcc/i686-w64-mingw32-gcc, Wine 8.0, MSVC 6/OpenWatcom 1.9 (operator VM), `scripts/seed/build_from_seed.sh`, `scripts/gen_emit_support.sh`, `scripts/check_emit_support.sh`.

**Spec:** none (defect-fix milestone). Evidence: `.superpowers/sdd/2026-11-02-win9x-emission-fixes-plan/i-report.md` (Task I output) and the preserved `-osw` dumps under `lin_bin/examples/{hello,z9play}/out` + `lin_bin/seedbuild/win`.

## Global Constraints

- Edit via `edit`/`fastedit` only (AGENTS.md X.7: re-read before `fastedit`, bottom-to-top, insert = replace anchor with new content + anchor). No sed/perl/python/awk source transforms. Shell only for builds/gates. New standalone report files may be written directly.
- No push, no destructive git, explicit-path staging only. `run.err` untouched.
- Sequential `zig1` runs only (`.zig1_*.tmp` CWD collision); fresh scratch dirs under `/tmp`.
- **No compression during this build session** (operator standing order; overrides system alerts).
- Every Windows-facing text artifact (`.bat`, `.c`, `.h`, `.txt`, `.md`) must be CRLF where it ships to the VM.
- Operator is the sole authority; only this plan is authorized; STOP on any ambiguity, failed gate, pin movement, or unverifiable claim; present alternatives instead of improvising.
- **Operator decisions (binding):** (1) E2 fixes guard names by **sanitizing** the identifier (not skipping the guard); (2) E3 (`std_os` reshape) is in scope; (3) the `00.txt` logging and all manual script improvements land in the emitter templates (`c89_emit.zig`) — no manual scripts after E5; (4) a verification task (Task I) runs before any fix.
- Build recipe: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/<dir>` (compiles current `sf/src` with the seed compiler; prints hop1/hop2 closure). Runtime support comes from `sf/src/emit_support.zig` via `scripts/gen_emit_support.sh`; `scripts/check_emit_support.sh` must be 8/8 after any runtime edit.
- If the 8 dump pins move at any point: **STOP and present** (do not re-baseline silently). If the corpus/frozen-1124 moves: STOP.
- Emission changes are expected in `-osw` output only (D-new-1/3/4) plus shared-header guard text (D-new-2). Any Linux-target (`-osl`) emitted-C change beyond guard-name text is a STOP.
- Task order: **I → E1 → E2 → E4 → E3B → E5** (E5 = templates + gates + v130 rotation).

## Review Focus

- The `-osw` z9play dump must lose `dirent.h`, the `ZIG_TYPE_unsigned char` guards, and the dead `fork/execv/...` calls — but the `-osl` dump must keep them (Linux semantics unchanged).
- Guard sanitization must not change typedef names or ABI — only the macro identifier text.
- `zig_nocrt.c` OWC branch must compile against WATCOM's `<stdio.h>` (`FILE __iob`), MSVC branch unchanged, MinGW branch unchanged.
- Emitted scripts must run under `command.com`: no line > ~900 chars, `if errorlevel 1 goto z98_fail`, `BUILD FAILED` never followed by `Built:`, every command's output appended to `00.txt` in the build folder, `REM PREREQ` lines present.
- The 8 pins, corpus class md5 (`5167393439…` live list = 1193 = 1017/58/118), frozen-1124 (`518eca1a…`, dir list `scripts/corpus/frozen_1124.txt`), goldens, stdlib 339/0, crosscheck 10/10 must hold at E5.
- `check_emit_support.sh` 8/8 after every runtime edit; the `sf/src/include/*` mirrors stay in sync with `emit_support.zig`.

---

### Task I: Verify the six defect claims (I/F task, no repo edits)

**Why:** the fixes must land on verified defects, not the agent's earlier reading. This task re-derives every claim with fresh runs before any source change.

**Files:**
- Create: `.superpowers/sdd/2026-11-02-win9x-emission-fixes-plan/i-report.md` (the only write; no repo source edits, no commits)

**Interfaces:**
- Consumes: current `sf/src`, the preserved dumps (`lin_bin/examples/{hello,z9play}/out`, `lin_bin/seedbuild/win`), the VM artifacts (`lin_bin/compil/`, `lin_bin/outputs.txt`, `lin_bin/compil/owc/*.err`, `lin_bin/examples/*/out/*.err`).
- Produces: a verdict table (verified / refuted / corrected) for each claim, with fresh evidence.

- [ ] **Step 1: Build a fresh compiler and reproduce the dumps.**
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/w9fix_i` (hop1==hop2 closure must equal the current fixed point `2fc64ffe…`-class value — record it). Then, from the repo root, sequential runs:
`/tmp/w9fix_i/zig1_5_clean -osw -ffast --dump-c89 --output-dir /tmp/w9fix_i/z9play_osw examples/z98/z9play/main.zig` (needs `-I` for the example's own `lib/`? use the documented recipe: run from `examples/z98/z9play` with the compiler's sibling `lib/`) and the same for `hello`; plus one `-osl` z9play dump for the comparison. Record rc, counts (`.c`/`.h`), and every `#include <...>`.
- [ ] **Step 2: Verify D-new-1 (dirent).** In the fresh `-osw` dumps: `dirent.h` present in `std_file_*.h`? No `opendir/readdir/closedir` identifiers in the emitted `.c`? In the `-osl` dump: present and used?
- [ ] **Step 3: Verify D-new-2 (guard macro).** Fresh `-osw` z9play `zig_special_types.h`: count `#ifndef ZIG_TYPE_` lines whose macro contains a space (expect ≥1, e.g. `ZIG_TYPE_unsigned char`); hello/compiler dumps expect 0; identify the producing type kind and confirm `emitTypeDefinition` has no branch for it (`c89_emit.zig:1617-1647`) so a guard is emitted with no typedef.
- [ ] **Step 4: Verify D-new-3 (zig_nocrt OWC).** In `sf/src/emit_support.zig` / `sf/src/include/zig_nocrt.c`: the `__WATCOMC__` branch emits `__w_FILE __iob[3];`; cross-check against `lin_bin/examples/hello/out/zig_nocrt.err` (E1022/E1129, `C:\WATCOM\H\stdio.h(238)` note). Confirm the MSVC branch (`FILE _iob[3];`) and MinGW branch (`__acrt_iob_func`) are as described.
- [ ] **Step 5: Verify D-new-4 (dead POSIX in std_os).** In the fresh `-osw` `std_os_*.c`: `grep` for `fork|execv|waitpid|ptrace|getpid|kill|__errno_location|dup2` (expect present, dead after an unconditional `return`); in the `-osl` dump the same identifiers are live. Locate the wrapper shape in `sf/src/std_os.zig:100-167` and quote one.
- [ ] **Step 6: Verify D-new-5 (atexit).** `c_exit.c` guard `_WIN32 && ZIG_NO_CRT`; confirm the emitted script pairings (CRT scripts do not define `ZIG_NO_CRT`, no-CRT scripts link `-nostdlib`) from the current emitter templates; the collision is a mixed-link misuse, not a shipped pairing.
- [ ] **Step 7: Verify D-new-6 (include union).** `cinclude.zig:7-31` `cincludeUnionAll` has no target filter; confirm `module_registry.target_is_windows` exists (`module_registry.zig:248,312-313`) and is reachable from the emitter.
- [ ] **Step 8: Script forensics.** From `lin_bin/compil/{owc,msvc,mingw}`, `lin_bin/outputs.txt`, `lin_bin/examples/*/out/*.err`: which script shapes ran and what failed (OWC `string.h` env, MSVC `C:\WATCOM\H` env, MinGW `atexit`/`@rsp`, examples `dirent`/`E1141`). State definitively whether the `@z98_cc.rsp` response-file style works on the operator's MinGW (evidence: `z98_cc.rsp` written + compiled TUs) or not; this decides the E5 MinGW template.
- [ ] **Step 9: Report.** `i-report.md` with the verdict table (each claim: VERIFIED/REFUTED/CORRECTED + file:line + fresh evidence), the script-forensics answer, and any claim that changed. **STOP and present** if any claim is refuted.

---

### Task E1: Target-conditional `@cInclude` (dirent)

**Files:**
- Modify: `sf/src/cinclude.zig` (add `cincludeIsPosixOnly(name)` classifier; consult `target_is_windows` in `cincludeUnionAll`)
- Modify: `sf/src/c89_emit.zig` (module-header loop `:2918-2959`, single-file loop `:2409-2435`) — skip POSIX-only includes when the emitter's target is Windows
- Test: fresh `-osw` z9play dump has no `dirent.h`; `-osl` dump still has it

**Interfaces:**
- Consumes: `ModuleRegistry.target_is_windows` (`module_registry.zig:248`), the include emitters above.
- Produces: `cincludeIsPosixOnly` used by all three emission paths.

- [ ] **Step 1: RED.** Fresh `-osw` z9play dump contains `#include <dirent.h>` (Task I evidence).
- [ ] **Step 2: Implement** the classifier (POSIX-only set: `dirent.h` per Task I; add `unistd.h`/`sys/time.h` only if Task I proves they leak) and the three call sites. Keep `-osl` output byte-identical.
- [ ] **Step 3: Verify.** `-osw` z9play/hello dumps: no POSIX-only include; `-osl` z9play: unchanged vs Step 1; `git diff --check`; no pin movement.

---

### Task E2: Sanitize `ZIG_*` guard identifiers

**Files:**
- Modify: `sf/src/c89_emit.zig` (`ctypeGuardWrite` `:915-944`, `emitTypeDefOnce` `:964-988`) — sanitize the macro identifier (every char outside `[A-Za-z0-9_]` → `_`) in the guard text only

**Interfaces:**
- Consumes: `type_registry.typeCName` (`type_registry.zig:501`).
- Produces: valid preprocessor identifiers in `#ifndef/#define/#endif` guard text; typedef names untouched.

- [ ] **Step 1: RED.** Fresh `-osw` z9play `zig_special_types.h` contains `#ifndef ZIG_TYPE_unsigned char` (Task I).
- [ ] **Step 2: Implement** sanitization at the guard-composition site (tag + cname → sanitized macro id). Do not touch `typeCName` or any typedef name.
- [ ] **Step 3: Verify.** No guard macro contains a space in fresh dumps; typedef text unchanged (diff the dumps: only guard lines differ); pins **must not move** (STOP if they do); `git diff --check`.

---

### Task E4: OpenWatcom no-CRT `__iob` fix

**Files:**
- Modify: `sf/src/emit_support.zig` (the `__WATCOMC__` branch of the `zig_nocrt.c` text, ~`:271-272`)
- Regenerate: `sf/src/include/zig_nocrt.c` via `scripts/gen_emit_support.sh`; `scripts/check_emit_support.sh` must be 8/8

**Interfaces:**
- Consumes: WATCOM `<stdio.h>` declaring `FILE __iob[]` (evidence `lin_bin/examples/hello/out/zig_nocrt.err`).
- Produces: OWC no-CRT branch compiles; MSVC/MinGW branches unchanged.

- [ ] **Step 1: RED.** The `__WATCOMC__` branch emits `__w_FILE __iob[3];` (Task I).
- [ ] **Step 2: Implement** `FILE __iob[3];` (type from the already-included `<stdio.h>`). Keep the MSVC and MinGW branches byte-identical.
- [ ] **Step 3: Regenerate + verify.** `gen_emit_support.sh` + `check_emit_support.sh` 8/8; the regenerated `include/zig_nocrt.c` matches; no other support file changes.

---

### Task E3B: Folded-if terminator DCE (B3T; suppresses dead `-osw` POSIX calls)

**Why:** the folded `if_stmt` path lowers only the comptime-taken arm, but its phase-10 epilogue unconditionally clears `block_terminated` (`sf/src/lower.zig` ~:13049-13052), so the enclosing statement list keeps lowering unreachable statements (`return pal.fork();`, ...) and `lowerFn` (~:14956-14964) emits a fall-through epilogue. No source edit: `std_os.zig` stays as-is; the rule fires whenever a comptime-taken arm terminates, so it is target-agnostic and does not need `@isWindows()` special-casing.

**Files:**
- Modify: `sf/src/lower.zig` (folded-if phase-10 epilogue; the enclosing block/body statement loop that must stop after a folded-if taken arm terminated)

**Interfaces:**
- Consumes: `ctx.comptime_folds` / the folded-if path (`lower.zig` ~:13040-13060); `block_terminated`; the block/body child loop.
- Produces: a lowerer flag (e.g. `folded_arm_terminated: u8`) set when a comptime-taken `if` arm terminated; the enclosing block/body loop stops lowering further children (the block epilogue keeps the terminator), while runtime-if joins and non-terminating folds are unchanged.

- [ ] **Step 1: Baseline + RED.** Build the pre-change compiler; dump `examples/z98/z9play` `-osw` and `-osl` and `hello` `-osw`; record the `-osw` `std_os_*.c` POSIX identifiers (fork/execv/waitpid/ptrace/getpid/kill/__errno_location/open/dup2/close) and the `-osl` tree hashes.
- [ ] **Step 2: Implement.** (a) phase-10 epilogue: preserve `block_terminated` when the taken arm terminated (set the new flag); clear it only when no arm was taken / the arm did not terminate. (b) block/body loop: after a child, if the flag is set, skip the remaining children and finish the block scope normally (defers/pop). Do not change the runtime-if join path.
- [ ] **Step 3: Verify.** `-osw` z9play/hello: zero POSIX identifiers in `std_os_*.c`/all `.c` (same grep). `-osl` z9play: the delta must be **removals-only dead code** (no additions, no live statements removed); record the exact diff. Re-record the 8 pins **once** (operator-authorized 2026-11-02, B3T-G ruling) in `scripts/compiler/gate_lower_depth.sh` + `docs/sf/QUICK_REF.md`; `gate_lower_depth.sh` must then be 8/8. `git diff --check`. **STOP** if the `-osl` delta contains any addition or a live-code removal, or if runtime-if/try/loop emission changes.

---

### Task E5: Emitter script templates + gates + seed v130

**Files:**
- Modify: `sf/src/c89_emit.zig` (all build-script templates: `build_target_crt.bat`, `build_owc_crt.bat`, `build_mingw_crt.bat`, `build_mingw_nocrt.bat`, aliases, `build_target.sh`)
- Modify: `scripts/compiler/gate_win_compat.sh` (lint the new template invariants)
- Regenerate: `release/seed/` artifacts (seed **v130**) via `scripts/seed/archive_seed.sh … --update-changelog --win9x-zip`

**Interfaces:**
- Consumes: the validated manual shapes in `lin_bin/seedbuild/win/*` (PREREQ REMs, `z98_cc.rsp` response files, `/fpc` OWC, `/Op` MSVC, chunked MinGW link, `00.txt` logging).
- Produces: emitted scripts that need no manual edits; seed v130; full battery.

- [x] **Step 1: Template rewrite.** Every generated `.bat`: (a) `REM PREREQ:` line (OWC: `C:\WATCOM\OWSETENV.BAT`; MSVC: fresh window + `VCVARS32.BAT`, never with the Watcom env; MinGW: `MinGW bin on PATH` + the CRT/no-CRT rule); (b) MSVC/OWC compiler flags via `z98_cc.rsp` (`wcc386 @z98_cc.rsp`, `%CL_EXE% @z98_cc.rsp`) with `/fpc` (OWC) and `/Op` (MSVC); MinGW is `@file`-free (Task I verdict: gcc 3.4.5 has no `@file`) — direct compile lines + explicit object lists; (c) link: `z98_link.rsp` MSVC, `z98_link.lnk` OWC, MinGW explicit `gcc -r` partial links (<=18 objects/line) + one short final link; (d) **every command** logs to `00.txt` in the build folder: `echo <cmd> >> 00.txt` then the command with `>> 00.txt` (stdout only; Win9x `command.com` has no `2>&1`); start truncates (`echo === <script> === > 00.txt`); `z98_fail` appends `BUILD FAILED`, success appends `Built: prog.exe`; (e) no line exceeds ~900 chars; `if errorlevel 1 goto z98_fail` after every step.
- [x] **Step 2: Gate.** `gate_win_compat.sh` asserts the template invariants (PREREQ present, `@z98_cc.rsp` used, `/fpc`/`/Op` present, `00.txt` logging on every command, no `@z98_link.rsp`-style dead rsp, `BUILD FAILED` never followed by `Built:`).
- [x] **Step 3: Gates + battery.** `gate_win_compat.sh`, `gate_warn_clean.sh`, `check_emit_support.sh` 8/8, corpus live 1193 (class md5, frozen-1124 `518eca1a…`, 0 movers), goldens 5/5, **8 pins** (STOP if moved), markers, examples 26/26, stdlib 339/0 + crosscheck 10/10, tier suites as applicable.
- [x] **Step 4: Seed v130 → v131 (F1 fix wave).** `build_from_seed.sh` closure, full battery, `archive_seed.sh … --update-changelog --win9x-zip`; record new F_new/archive/zip/manifest md5s; verify every CHANGELOG claim; update `docs/sf/QUICK_REF.md` current-seed block.
- [x] **Step 5: Commits.** `fix(compiler): Win9x emission fixes (dirent include, guard identifiers, std_os pruning, OWC nocrt)`, `feat(c89_emit): self-sufficient Win9x build scripts (response files, /fpc, /Op, 00.txt logging)`, `chore(seed): rotate v130`, `docs(sdd)`; explicit-path staging; no push.
