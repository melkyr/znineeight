# Win9x C-emission restore — diagnosis + fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restore two broken Win9x (`-osw`) build paths: (A) OpenWatcom C89 rejection of generated `main()` (rogue_mud / rogue_mud_upgraded), and (B) z9gb `-osw` emission dying before writing any `.c` on Windows-hosted compilers (`z1.exe`, `z1_mg.exe`).

**Architecture:** (A) is a proven emitter ordering bug. (B) is classified by Task 1: the v149 seed's `lib/std_dinput*.zig` are stale (no `dinputPollRaw`), so the fix is a seed rotation to v150 carrying the current `lib/`, plus a diagnostic fix so a missing module member reports `error[3060] … in module` instead of the misleading `3042` + `3023`.

**Tech Stack:** Z98 seed v149 (`/tmp/zig1-m1/zig1_5_clean`, md5 `73c75a65…`), Wine (`WINEPREFIX=/tmp/wine-z9gb`), MinGW objdump, `gcc -std=c89 -pedantic`.

**Spec:** none — compiler defect repair; all changes confined to `sf/src/` plus tests/gates.

**Sequence:** standalone hotfix branch `fix/osw-emission` off `zig1_start` (`088eebb9`). Does not touch Undersanded milestones.

## Global Constraints

- Fix only what a task authorizes; no opportunistic refactors, no unrelated compiler changes.
- Compiler source is `-fsafe -W` clean; the self-emission two-hop fixed point **moves** with any compiler-source change
  (Task 2 takes it from `73c75a65…` to `4aa14bfbf37e101b7d0bb80111b18edb`). Task 3 rotates the seed to v150 at the new point.
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
- [ ] Rebuild the compiler and confirm hop1==hop2 (new fixed point `4aa14bfbf37e101b7d0bb80111b18edb`; an emitter change necessarily moves it off v149's `73c75a65…`); rerun the gate and `tier_edit.sh` (38/0, lexer md5 unchanged), and confirm the 8 emission pins are byte-identical (declaration reorder only).
- [ ] Emit `examples/z98/rogue_mud` with `-osw` via the seed compiler; scan all generated `.c` with the strict command → zero mixed declarations; record in the report.
- [ ] Commit `fix(c89_emit): declare error-union main result before module init`.

**Gate:** strict-C89 scan clean on rogue_mud + the fixture; tier green; fixed point unchanged.

### Task 3b: Diagnose a missing module member as `error[3060]` (not `3042` + `3023`)

**Files:** `sf/src/lower.zig` (module-member resolution paths), plus regression fixtures/gate.

Task 1 evidence: z9gb's `-osw` failure surfaces as
`error[3042]: non-value base expression in field access` +
`warning[3023]: module used as value expression` at an empty span. Root cause is
diagnostic-only: `lowerModuleMemberValue` returns `TEMP_NONE` for a missing member,
the module-alias branch falls through to `lowerExpr`, and
`lowerFieldAccessRest` then reports 3042 for the resulting non-value temp.
Official Zig reports `no field or member function named 'x' in module`.

- [ ] In both module paths of the field-access lowering — the direct module-symbol branch (`sf/src/lower.zig:10238-10243`) and the nested alias/module-typed-global branch (`sf/src/lower.zig:10245-10257`) — when the base resolves to a module id and `lowerModuleMemberValue` returns `TEMP_NONE`, emit `ERR_3060_METHOD_SYNTAX_NOT_SUPPORTED` (3060) instead of falling through. Message: `no field or member function named '<name>' in module` built with `diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, parts, 3)` (parts: `"no field or member function named '"`, interned field name via `interner_mod.stringInternerGet`, `"' in module"`); level 0; `self.ctx.source_file_id`; span `node.span_start … node.span_start + node.span_len`; then `return nextTemp(self, type_mod.TYPE_VOID)` so 3042/3023 never fire. Mirror `semanticAnalyzerReportUnknownMember` (`sf/src/semantic_analyzer.zig:1587-1618`).
- [ ] Exactly one diagnostic per site: no duplicate 3060, no 3042/3023, no panic. Accepted shapes unchanged: real module members, module constants, `@import`-path direct access, and `module.fn()` calls all still compile with the same output.
- [ ] Regression fixtures: `repro/mi_matrix/module_member_missing_reject_xmod/` (`main.zig` + `helper.zig`; reads `h.nope`; `expected.rc` = 2; `expected_error.txt` = `3060 1`, force-added with `git add -f`) and `repro/mi_matrix/module_member_ok_xmod/` (same import shape, real member; `expected.rc` = 0). Both must be listed by `scripts/corpus/list_corpus_dirs.sh`.
- [ ] New `scripts/compiler/gate_module_member_diag.sh`: dump the reject fixture with `<zig1> --dump-c89` (rc 2, zero `.c`), assert stderr contains exactly one `error[3060]` with `in module` and no `error[3042]` / `warning[3023]`; dump the ok fixture, assert rc 0 and at least one `.c`. Exit 1 on mismatch.
- [ ] Re-run the Task 1 z9gb `-osw` repro with the stale v149 `lib/`: it must still fail, now reporting `error[3060] … in module`, with no 3042/3023 and no `.c`.
- [ ] Rebuild the compiler (hop1==hop2 == `4aa14bfbf37e101b7d0bb80111b18edb`; 8 emission pins unchanged), rerun `gate_module_member_diag.sh`, `gate_lower_depth.sh`, `gate_warn_clean.sh`, and `tier_edit.sh` (38/0, lexer md5 unchanged).
- [ ] Commit `fix(lower): diagnose missing module member as error[3060]`.

**Gate:** reject fixture and the z9gb stale-lib repro each print one `error[3060] … in module` with no 3042/3023 and emit no `.c`; ok fixture compiles; corpus and gates green; fixed point `4aa14bfb…`.

### Task 3: Rotate the committed seed to v150

**Files:** `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `release/seed/CHANGELOG.md`, `README.md`, `docs/sf/QUICK_REF.md`.

Why: the committed v149 seed ships a `lib/` whose `std_dinput.zig` / `std_dinput_pal.zig` predate `dinputPollRaw`/`pollRaw` (added later in `62aa0329`), so z9gb `-osw` dies on any Windows-hosted compiler using that seed. Task 2 moved the compiler fixed point to `4aa14bfb…`; the rotation publishes the new compiler **and** a current `lib/`.

- [ ] Build from the current tree: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed150_build` → `/tmp/seed150_build/{zig1_5_clean,gen,lib}`; confirm hop1==hop2==`4aa14bfbf37e101b7d0bb80111b18edb` and that `lib/std_dinput*.zig` md5-match `sf/src/` (65 files).
- [ ] Package: `bash scripts/seed/archive_seed.sh /tmp/seed150_build/zig1_5_clean /tmp/seed150_build/gen release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`. Record the printed archive md5, zip md5, win/ C counts, lib count, and the auto-prepended CHANGELOG entry.
- [ ] Verify the archive from scratch: unpack to `/tmp/seed150`; check `zig1` md5, `gen/` counts/bytes, `lib/manifest.md5` (65 files), and that `lib/std_dinput.zig` matches `sf/src/std_dinput.zig`.
- [ ] Verify the Win9x companion zip: its `win/` C builds a working compiler with the shipped `build_target_crt.bat` / `build_owc_crt.bat`, and its `lib/` is the current one.
- [ ] Update public records to match the printed entry: `release/seed/CHANGELOG.md` (v150 entry at top), `README.md` (Current Status + Determinism: fixed point `4aa14bfb…`, seed **v150**, archive/zip/lib-manifest md5s, note the c89_emit declaration-order fix and the current `lib/`), `docs/sf/QUICK_REF.md` (fixed-point reference md5 + 8-pin table header).
- [ ] Re-measure the 8 emission pins with the v150 seed-built compiler. Task 2/3b only reorder declarations and add diagnostics, so all pins must be byte-identical; if any pin moved → STOP-present before editing the table.
- [ ] End-to-end repro with the **new** seed's `lib/`: in a `/tmp` copy, replace `lin_bin/z9gb/lib` with `/tmp/seed150/lib`; `-osw` now emits `.c` (both user compiler equivalents; verify with the Wine binaries if available, otherwise the seed binary + the shipped `z1.exe`/`z1_mg.exe`), and `sh examples/z98/z9gb/tests/tier_win32.sh --smoke` is green.
- [ ] Commit `chore(seed): rotate v150 (c89_emit main decl order + current lib)`.

**Gate:** seed v150 at fixed point `4aa14bfb…`; archive/zip/lib-manifest md5s recorded and consistent across CHANGELOG/README/QUICK_REF; z9gb `-osw` emits `.c` from the new seed; 8 pins byte-identical; `tier_win32.sh --smoke` green.

### Task 4: Verification + close

- [ ] Full evidence set: Task 1 repro commands, Task 2/3b/3 gates, strict-C89 scans, seed fixed point, `tier_edit.sh`, `tier_win32.sh --smoke`, and (if cheap) `tier_m1_std.sh` on the rebuilt compiler.
- [ ] Write a short `KNOWN_GAPS`/notes entry only if a residual limitation remains (e.g. OWC-only syntax classes not gated).
- [ ] Commit final evidence notes; STOP for review/merge decision (target `zig1_start`, no push).
