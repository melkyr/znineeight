# Win9x C-emission restore — diagnosis + fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restore two broken Win9x (`-osw`) build paths: (A) OpenWatcom C89 rejection of generated `main()` (rogue_mud / rogue_mud_upgraded), and (B) z9gb `-osw` emission dying before writing any `.c` on Windows-hosted compilers (`z1.exe`, `z1_mg.exe`).

**Architecture:** (A) is a proven emitter ordering bug. (B) is unclassified: reproduce under Wine with the user's exact compiler binaries, then bisect the Windows-only module set before changing code.

**Tech Stack:** Z98 seed v149 (`/tmp/zig1-m1/zig1_5_clean`, md5 `73c75a65…`), Wine (`WINEPREFIX=/tmp/wine-z9gb`), MinGW objdump, `gcc -std=c89 -pedantic`.

**Spec:** none — compiler defect repair; all changes confined to `sf/src/` plus tests/gates.

**Sequence:** standalone hotfix branch `fix/osw-emission` off `zig1_start` (`088eebb9`). Does not touch Undersanded milestones.

## Global Constraints

- Fix only what a task authorizes; no opportunistic refactors, no unrelated compiler changes.
- Compiler source is `-fsafe -W` clean; two-hop fixed point must stay `73c75a65…` (seed v149).
- Every emitted-program change is checked with strict C89:
  `gcc -std=c89 -pedantic -Werror=declaration-after-statement -fsyntax-only` (long-long/pointer-sign diagnostics are pre-existing and excluded).
- No push. Repo artifacts: plans + code only; diagnostics go to `/tmp`.
- STOP-present if a diagnosis cannot be classified or a fix needs a scope change.

---

### Task 1: Classify the z9gb `-osw` failure (diagnosis only — NO code changes)

**Deliverable:** a report with the exact stderr and a localized offender (module or emitter construct).

- [ ] Copy `examples/z98/z9gb` to `/tmp/z9gb_repro`; copy the user's binaries `lin_bin/z9gb/z1.exe`, `z1_mg.exe` beside it (main checkout paths; read-only use).
- [ ] Run each under Wine and capture stderr:
  `WINEPREFIX=/tmp/wine-z9gb WINEDEBUG=-all wine ./z1.exe -I lib -osw -o out main.zig 2>&1 | tee /tmp/z9gb_z1.log`
  (repeat with `z1_mg.exe`; repeat one with `-ffast`). Record exit code, stderr text, whether any `.c`/`.h` appear in `out/`.
- [ ] Baseline with seed v149 on Linux: `/tmp/zig1-m1/zig1_5_clean -I lib -osw -o out main.zig` → does it reproduce (tmp-only) or emit `.c`?
- [ ] Run the existing gate: `sh examples/z98/z9gb/tests/tier_win32.sh --smoke` and record whether section (d) passes/fails/skips.
- [ ] If it reproduces: bisect with single-module entries under `-osw` — `platform/win32.zig`, `dynarec/dynarec.zig`, `std_ddraw`, `std_dsound`, `std_dinput`, `std_gfx` — first failing import localizes; record the exact emitter stage/error.
- [ ] Also diff `lin_bin/z9gb/lib/*` md5s against the seed v149 `lib/` (unpack `release/seed/zig1-seed.tgz` to `/tmp/seed149`) and report mismatches.
- [ ] Report classification: source-emitter bug (with offender) / compiler-binary issue / environment+lib mismatch / unclassified.

**Gate:** report contains exact stderr for both binaries, the Linux baseline result, the gate result, and a classification. No repo changes.

### Task 2: Fix (A) — error-union `main` declaration order + strict-C89 gate

**Files:** `sf/src/c89_emit.zig` (§ main wrapper emission), plus one gate script/fixture.

- [ ] Emit the local `zT_main_result` declaration **before** `emitModuleInitCalls()`; keep `void`/`int` branches unchanged (no local). Assignment/return stay after the init calls.
- [ ] Add a regression fixture + gate: emit a program with a module-global initializer **and** an error-union `main`, then
  `gcc -std=c89 -pedantic -Werror=declaration-after-statement -fsyntax-only <out>/*.c`
  and assert no `-Wdeclaration-after-statement` diagnostic. Wire into an existing emission/example tier (not a new slow tier).
- [ ] Rebuild compiler (two-hop fixed point still `73c75a65…`), rerun the gate and `tier_edit.sh` (38/0, lexer md5 unchanged).
- [ ] Emit `examples/z98/rogue_mud` with `-osw` via the seed compiler; scan all generated `.c` with the strict command → zero mixed declarations; record in the report.
- [ ] Commit `fix(c89_emit): declare error-union main result before module init`.

**Gate:** strict-C89 scan clean on rogue_mud + the fixture; tier green; fixed point unchanged.

### Task 3: Fix (B) — apply the Task 1 classification (only if classified)

- [ ] Apply the minimal fix for the localized offender; add a regression gate that fails on the pre-fix behaviour (the offending module/construct must be emitted in CI).
- [ ] Re-run Task 1 repro: user binaries under Wine now emit `.c`; Linux `-osw` baseline unchanged; `tier_win32.sh --smoke` green.
- [ ] If Task 1 says "unclassified" or the fix exceeds a localized change → STOP-present with the evidence.
- [ ] Commit `fix(<area>): restore z9gb -osw emission`.

**Gate:** repro emit succeeds for both user binaries; strict-C89 scan clean; existing z9gb/compile tiers green.

### Task 4: Verification + close

- [ ] Full evidence set: Task 1 repro commands, Task 2/3 gates, strict-C89 scans, seed fixed point, `tier_edit.sh`, `tier_win32.sh --smoke`, and (if cheap) `tier_m1_std.sh` on the rebuilt compiler.
- [ ] Write a short `KNOWN_GAPS`/notes entry only if a residual limitation remains (e.g. OWC-only syntax classes not gated).
- [ ] Commit final evidence notes; STOP for review/merge decision (target `zig1_start`, no push).
