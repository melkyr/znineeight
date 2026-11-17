# Win9x C-emission restore — diagnosis + fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restore two broken Win9x (`-osw`) build paths: (A) OpenWatcom C89 rejection of generated `main()` (rogue_mud / rogue_mud_upgraded), and (B) z9gb `-osw` emission dying before writing any `.c` on Windows-hosted compilers (`z1.exe`, `z1_mg.exe`).

**Architecture:** (A) is a proven emitter ordering bug. (B) is classified by Task 1: the v149 seed's `lib/std_dinput*.zig` are stale (no `dinputPollRaw`), so the fix is a seed rotation to v150 carrying the current `lib/`. The misleading `3042` + `3023` pair is fixed properly in the semantic analyzer (level-0 `error[3060] … in module`, so lowering never runs), replacing and deleting the interim lowering-stage patch.

**Tech Stack:** Z98 seed v149 (`/tmp/zig1-m1/zig1_5_clean`, md5 `73c75a65…`), Wine (`WINEPREFIX=/tmp/wine-z9gb`), MinGW objdump, `gcc -std=c89 -pedantic`.

**Spec:** none — compiler defect repair; all changes confined to `sf/src/` plus tests/gates.

**Sequence:** standalone hotfix branch `fix/osw-emission` off `zig1_start` (`088eebb9`). Does not touch Undersanded milestones.

## Global Constraints

- Fix only what a task authorizes; no opportunistic refactors, no unrelated compiler changes.
- Compiler source is `-fsafe -W` clean; the self-emission two-hop fixed point **moves** with any compiler-source change
  (Task 2 takes it from `73c75a65…` to `4aa14bfbf37e101b7d0bb80111b18edb`; every later compiler-source task records its own hop1==hop2 md5). Task 3 rotates the seed to v150 at the final point.
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

### Task 3b-R: Diagnose a missing module member in sema; delete the lowering patch

**Files:** `sf/src/semantic_analyzer.zig` (new emit points + helper), `sf/src/lower.zig` (revert only), regression fixtures/gate.

Why sema, not lowering: a level-0 sema error trips the post-sema `hasErrors` gate, so the compile exits rc 2 with 0 `.c` and **LIR lowering never runs**. The previous patch (commit `74ee06e0`, helper `lowerReportMissingModuleMember` + 4 call sites in `lowerExprField`/`lowerFieldAccessStep`) merely re-worded a lowerer fallback and left the diagnostic split across two stages. This task moves the diagnostic to the analyzer and deletes that patch.

Proven silent-accept points (Task 1 + controller inspection): `semanticAnalyzerResolveFieldAccess` (`sf/src/semantic_analyzer.zig:1769`) has a module-symbol branch (`s.kind == SymbolKind.module`, `:1820-1872`) and an `import_expr` branch (`:1875-1905`); when `symbolRegistryQualifiedLookup` misses, both fall through and return `TYPE_VOID` with no diagnostic (markers `Q1VF:FN` / `FB`). z9gb's `dinput.dinputPollRaw(...)` (call position) and `_ = h.nope` (read position) both reach this.

- [ ] Delete the lowering patch: revert the `74ee06e0` changes to `sf/src/lower.zig` (helper `lowerReportMissingModuleMember` and all four `return lowerReportMissingModuleMember(...)` sites in `lowerExprField` and `lowerFieldAccessStep`); leave the rest of `lower.zig` untouched.
- [ ] Add `semanticAnalyzerReportMissingModuleMember(self: *SemanticAnalyzer, node_idx: u32, field_name_id: u32) void` next to `semanticAnalyzerReportUnknownMember` (`:1587`): `diagnosticCollectorMarkNodeOnce` guard; message parts `"no field or member function named '"`, interned field name (`interner_mod.stringInternerGet(self.interner, field_name_id)`), `"' in module"`; `diagnosticBuilderMakeMsg(..., 3)`; level 0; code `@enumToInt(diag_mod.ErrorCode.ERR_3060_METHOD_SYNTAX_NOT_SUPPORTED)`; `self.source_file_id`; span `node.span_start .. node.span_start + node.span_len` (the field-access node).
- [ ] Emit it at the module-branch miss (after the `field_sym` lookup fails, replacing the silent `Q1VF:FN` → `TYPE_VOID` fall-through) and at the `import_expr`-branch miss. Both keep returning `TYPE_VOID` (typed void in `self.type_table` as today) so sema continues deterministically; the level-0 error stops the pipeline.
- [ ] Module-chain base (`h.sub.nope`): add `semaResolveModuleBase(self, base_node_idx) u32` mirroring `lower.zig:8637-8654` (`ident_expr` → module symbol's `module_id`; `import_expr` → `moduleRegistryPathToIdGet`; `field_access` → recurse on its base + qualified member lookup only when the member is itself a module). In `semanticAnalyzerResolveFieldAccess`, before the generic base-type path, when the base is not an ident/import but `semaResolveModuleBase` yields a module id, resolve `field_name_id` in that module: found → existing member resolution; missing → report + `TYPE_VOID`.
- [ ] Position coverage (fixtures prove each): read `_ = h.nope;`, call `h.nope();`, store `h.nope = 1;`, address `const p = &h.nope;`, and chain `_ = h.sub.nope;` → exactly one `error[3060] … in module` each, no `error[3042]`, no `warning[3023]`. If the call-callee path (`semanticAnalyzerResolveFnCall`, field-access callee) or the lvalue/address path does not route through `ResolveFieldAccess`, add the same lookup+report at that site — same helper, same wording.
- [ ] Accepted shapes unchanged: real module members/constants/functions, `@import("…").member`, nested real members (`h.sub.answer`) all compile with byte-identical emission for the 4 documented programs.
- [ ] Scope boundary (recorded in the defects ledger as D19 by Task 3b-D, not fixed here): a member that EXISTS but is a type/module used as a value (`_ = h.sub;`) keeps today's behaviour.
- [ ] Fixtures: extend `repro/mi_matrix/module_member_missing_reject_xmod/` (main.zig gains the call/store/address/chain sites; `helper.zig` gains `pub const sub = @import("sub.zig");` plus a new `sub.zig`) and set `expected_error.txt` to `3060 <site count>` (force-add with `git add -f`). Extend `repro/mi_matrix/module_member_ok_xmod/` with a real member call. Both must stay listed by `scripts/corpus/list_corpus_dirs.sh`.
- [ ] Update `scripts/compiler/gate_module_member_diag.sh` comments to say sema-stage; keep the assertions (rc 2, 0 `.c`, exact count of `error[3060] … in module`, no 3042/3023; ok fixture rc 0 and ≥1 `.c`). The gate must FAIL on the pre-change build (non-vacuity).
- [ ] Re-run the Task 1 z9gb `-osw` repro with the stale v149 `lib/`: rc 2, 0 `.c`, one `error[3060] … in module` per call site (2), no 3042/3023.
- [ ] Rebuild the compiler (hop1==hop2 closure; record the new fixed-point md5; it supersedes `790090eb…`), and verify with `--dump-c89` that the 4 documented programs are byte-identical to the pre-task build **when both use the same lib** (`--lib-dir /tmp/seed149/zig1-seed/lib` if that unpacked seed lib is present; otherwise compare two builds of the same tree before/after the edit). Run `gate_module_member_diag.sh`, `gate_warn_clean.sh`, and `tier_edit.sh` (38/0, lexer md5 `dcc81009e9a36c86e4d90e104c439871`).
- [ ] Commit `fix(sema): diagnose missing module member as error[3060]` (includes the `lower.zig` revert).

**Gate:** every fixture site and the z9gb stale-lib repro report `error[3060] … in module` with no 3042/3023 and no `.c`; ok fixture compiles; lowering no longer contains `lowerReportMissingModuleMember`; corpus/gates green; fixed point closes; accepted-shape emission unchanged.

### Task 3b-C: Suppress dependent diagnostics after a level-0 error (cascade)

**Files:** `sf/src/diagnostics.zig` (one query), `sf/src/semantic_analyzer.zig` (decl check + helper), reject fixture/gate.

Zig reports one error per root cause. Today a level-0 error whose expression resolves to `TYPE_VOID` also trips the const/var-decl check (`semantic_analyzer.zig:7007-7012`), so `const p = &h.nope;` reports `error[3060]` **plus** `error[3000] cannot declare variable of type void`. Measured in Task 3b-R.

- [ ] Add `pub fn diagnosticCollectorNodeWasMarked(self: *DiagnosticCollector, node_idx: u32) bool` to `sf/src/diagnostics.zig`: scan the existing `diag_seen_items[0..diag_seen_len]` mark set used by `diagnosticCollectorMarkNodeOnce` (`:544-561`). Read-only, no new storage.
- [ ] Add `fn semaInitializerReportedError(self: *SemanticAnalyzer, node_idx: u32, depth: u8) bool` in `semantic_analyzer.zig`: true when the node is marked, else recurse (depth-limited to 8) over `child_0`, `child_1` and the extra children via `astStoreNodeExtraChildCount`/`astStoreNodeExtraChildAt`; return false at the limit.
- [ ] In the `decl_type == type_mod.TYPE_VOID` check (`:7007-7012`), skip the `cannot declare variable of type void` diagnostic when `semaInitializerReportedError(self, node.child_1, 0)` is true (the initializer already reported). Behaviour for genuine void initializers (e.g. `const x = voidFn();`) is unchanged — keep the diagnostic there.
- [ ] Fixture `repro/mi_matrix/module_member_missing_reject_xmod/`: the `const p = &h.nope;` site must produce exactly ONE diagnostic (`error[3060]`), no `error[3000]`. `expected_error.txt` stays `3060 5`.
- [ ] `scripts/compiler/gate_module_member_diag.sh`: assert the reject stderr has **no** `error[3000]` anywhere and exactly 5 `error[3060]` lines. Gate must FAIL on the pre-task build `/tmp/zig3bR/zig1_5_clean` (which prints the extra 3000).
- [ ] Non-vacuity probe (scratch, `/tmp`): `fn f() void {} pub fn main() void { const x = f(); _ = x; }` still reports `cannot declare variable of type void`.
- [ ] Rebuild (hop1==hop2, record md5), rerun the fixture gate, `gate_warn_clean.sh`, `tier_edit.sh` (38/0, lexer md5 unchanged); confirm the 4-program emission is unchanged under the same lib.
- [ ] Commit `fix(sema): suppress dependent diagnostics after a level-0 error`.

**Gate:** reject fixture emits exactly its five 3060s with no 3000/3042/3023 and no `.c`; genuine void-var diagnosis still fires; gates green; fixed point closes.

### Task 3b-D: Audit the defects ledger; document the deferred gaps

**Files:** `examples/torrent_example_defects.md` (only).

The ledger (`D16`, `D17`, `D18`, header) must reflect today's code. Verify before deleting; hard-delete resolved text (IDs stay stable, never reused).

- [ ] **Verify D16 sub-items** against the current compiler with scratch probes (`/tmp`), one per bullet: (a) assignment-expression/assignment-ending block typing; (b) mixed statement switch `switch { 0 => 1, else => true }`; (c) comptime-known selector with an untaken mismatching prong; (d) `anyerror!i32`; (e) `const y: ?i32 = { g = 1; };` and its `E!i32` form. Delete each bullet the current compiler now matches on Zig 0.17.1; keep the rest. Replace brittle line numbers (`semantic_analyzer.zig:4725/:4729/:5039-5044`, `lower.zig:6105`, `async_analysis.zig:396`) with symbol names (`semanticAnalyzerResolveAssign`, `sw_is_stmt_expr`, the compound-assign lowering, async frame sizing). Keep the Task 9j/9l/9k/9f evidence intact.
- [ ] **Verify D17** (optional array return `?[2][]const u8`): current inspection shows `wrap_optional`/`unwrap_optional` still emit a plain C assignment (`c89_emit.zig` optional arms), so the repro should still fail with `assignment to expression with array type`. Keep the entry if it reproduces; delete it only if it now builds and runs correctly.
- [ ] **Verify D18** (indexed write into a nested array field): repro the `s.exp.hold[i] = 0` shape; confirm dump/build rc 0 and the lost store (emitted by-value temp). Keep if it reproduces.
- [ ] **Add D19 — Module/type values (parity gap, deferred):** `const a = h.sub;` (legal Zig) is falsely rejected with `error[3042]` + `warning[3023]`; `_ = h.sub;` / `&h.sub` reject with the same misleading pair instead of `expected value, found type`; `_ = i32;` is silently accepted. Record the measured rc/`.c` table from Task 3b-R, note that `typeRegistryGetOrCreateModule` exists, and that the scoped fix + oracle probe pack were deferred out of the `-osw` hotfix.
- [ ] **Add D20 — Sema error cascades:** a level-0 error whose expression resolves to `void` can emit a second, Zig-absent diagnostic; cite the `const p = &h.nope;` case and the general TYPE_VOID-returning rejects. If Task 3b-C is already merged, state the fixed scope and list only the remaining cases.
- [ ] **Add D21 — Oracle-claim staleness:** current-source comments/docs cite Zig 0.15.2 while the recorded oracle is **Zig 0.17.1** (D16 / Task 9j, archive sha256 `3581863e…`, binary `58959f01…`); `grep -rn '0\.15\.2' sf/src sf/docs/tech_docs docs/reference docs/sf` counts the sites; rebase deferred. Historical plans/specs/repro stay frozen.
- [ ] Update the header: next free slot (`D22`), the Open list, and the "Tracks only open defects" note; hard-delete any resolved text and confirm `git diff` shows no ID renumbering.
- [ ] Commit `docs(examples): audit defect ledger; record deferred parity gaps`.

**Gate:** every deletion is backed by a reproduction recorded in the entry's evidence (or the entry is kept); D16–D18 current; D19–D21 added; header consistent.

### Task 3b-G: Pin `gate_lower_depth.sh` emission goldens to the committed seed lib

**Files:** `scripts/compiler/gate_lower_depth.sh`.

Established by inspection during Task 3b: case 5's 8 pins are correct for the seed's `lib/`, but the gate silently uses the tested compiler's sibling `lib/`. Dev tooling overwrites that `lib/` (e.g. `/tmp/zig1-m1/lib` was synced to the current tree during the Undersanded work), producing a false red on all 8 pins. Make the gate environment-independent.

- [ ] In case 5, unpack `release/seed/zig1-seed.tgz` into `$WORK/seed_lib` (or accept an already-unpacked dir), resolve `zig1-seed/lib`, verify `lib/manifest.md5` exists, and pass `--lib-dir "$SEED_LIB"` to both `--dump-c89` invocations for every pinned program.
- [ ] If the archive cannot be unpacked or the manifest is missing, fail the case with a clear message (never silently fall back to the sibling lib).
- [ ] Verify: case 5 is green with the current pins; case 5 is red when one pin is deliberately corrupted in a `/tmp` copy (non-vacuity); `git diff --check` clean.
- [ ] Commit `fix(gate): pin lower-depth emission goldens to the seed lib`.

**Gate:** case 5 green via the seed lib; corruption check red; no other case changes.

### Task 3: Rotate the committed seed to v150

**Files:** `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `release/seed/CHANGELOG.md`, `README.md`, `docs/sf/QUICK_REF.md`.

Why: the committed v149 seed ships a `lib/` whose `std_dinput.zig` / `std_dinput_pal.zig` predate `dinputPollRaw`/`pollRaw` (added later in `62aa0329`), so z9gb `-osw` fails on any Windows-hosted compiler using that seed. Tasks 2 and 3b-R moved the compiler fixed point; the rotation publishes the new compiler **and** a current `lib/`.

- [ ] Build from the current tree: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed150_build` → `/tmp/seed150_build/{zig1_5_clean,gen,lib}`; confirm hop1==hop2 (record the md5 — the Task 3b-R fixed point) and that `lib/std_dinput*.zig` md5-match `sf/src/` (65 files).
- [ ] Package: `bash scripts/seed/archive_seed.sh /tmp/seed150_build/zig1_5_clean /tmp/seed150_build/gen release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`. Record the printed archive md5, zip md5, win/ C counts, lib count, and the auto-prepended CHANGELOG entry.
- [ ] Verify the archive from scratch: unpack to `/tmp/seed150`; check `zig1` md5, `gen/` counts/bytes, `lib/manifest.md5` (65 files), and that `lib/std_dinput.zig` matches `sf/src/std_dinput.zig`.
- [ ] Verify the Win9x companion zip: its `win/` C builds a working compiler with the shipped `build_target_crt.bat` / `build_owc_crt.bat`, and its `lib/` is the current one.
- [ ] Update public records to match the printed entry: `release/seed/CHANGELOG.md` (v150 entry at top), `README.md` (Current Status + Determinism: new fixed point, seed **v150**, archive/zip/lib-manifest md5s, note the c89_emit declaration-order fix, the sema module-member diagnostic, and the current `lib/`), `docs/sf/QUICK_REF.md` (fixed-point reference md5 + 8-pin table header).
- [ ] Re-measure the 8 emission pins with the v150 seed-built compiler. **The pins WILL move** from the v149 values: v150 ships the current `lib/`, which post-dates the v149 std payload (M1 additions such as `splitOnce`, `crc32`, `modulePath`, the gfx/debug changes). Update the pin values in `scripts/compiler/gate_lower_depth.sh`, the README 4-program table, and the QUICK_REF 8-pin table, and record old→new plus the reason in the CHANGELOG entry. STOP-present only if two builds of the same seed/lib disagree (then the emission is non-deterministic).
- [ ] End-to-end repro with the **new** seed's `lib/`: in a `/tmp` copy, replace `lin_bin/z9gb/lib` with `/tmp/seed150/lib`; `-osw` now emits `.c` (verify with the seed binary and, where available, the user's `z1.exe`/`z1_mg.exe`), and `sh examples/z98/z9gb/tests/tier_win32.sh --smoke` is green.
- [ ] Commit `chore(seed): rotate v150 (c89_emit main decl order + sema module diagnostic + current lib)`.

**Gate:** seed v150 at the Task 3b-R fixed point; archive/zip/lib-manifest md5s recorded and consistent across CHANGELOG/README/QUICK_REF; all 8 pins re-measured and updated with the reason recorded; z9gb `-osw` emits `.c` from the new seed; `tier_win32.sh --smoke` green.

### Deferred (out of scope for this hotfix — recorded as D19–D21 in `examples/torrent_example_defects.md`)

None of these is a compile/emit failure for accepted code, so they do not belong in the `-osw` restore:

- **3b-V (was: module/type values).** Support `const a = h.sub;` (legal Zig, currently a loud false reject), reject `_ = h.sub;` / `&h.sub` with `expected value, found type`, and stop silently accepting `_ = i32;`. Needs a real oracle-verified probe pack first. → **D19**.
- **3b-E (oracle probe pack).** Committed probes + operator-run Zig 0.17.1 transcript for the module/type-value shapes (the ledger's D16 already proves 0.17.1 is the oracle). → feeds **D19**.
- **3b-O (oracle-claim rebase).** ~95 current-surface comments/docs still cite Zig 0.15.2 while the recorded oracle is 0.17.1; historical plans/specs/repro stay frozen. → **D21**.

### Task 4: Verification + close

- [ ] Full evidence set: Task 1 repro commands, Task 2/3b-R/3b-C/3b-D/3b-G/3 gates, strict-C89 scans, seed fixed point, `tier_edit.sh`, `tier_win32.sh --smoke`, and (if cheap) `tier_m1_std.sh` on the rebuilt compiler.
- [ ] Write a short `KNOWN_GAPS`/notes entry only if a residual limitation remains (e.g. OWC-only syntax classes not gated).
- [ ] Commit final evidence notes; STOP for review/merge decision (target `zig1_start`, no push).
