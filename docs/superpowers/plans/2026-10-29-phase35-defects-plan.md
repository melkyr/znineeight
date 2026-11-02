# Phase 3.5 — Defect Closure + Documentation Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all seven open defects (D3, D4, D5, D7.3, D8, D10, D12) and restore documentation truth (one self-host doc home, a spec that describes the real compiler), then rotate seed v130.

**Architecture:** Risk-ordered single pass — safe emitter fixes first, then the two emission-wide shifts (D8 PAL routing, D3 lazy import), then the calling-convention language feature, then the analyzer audit→upgrade pair, then docs, then one closeout re-baseline. Emission shifts accumulate; the 8 pins move once, at closeout.

**Tech Stack:** Z98 (strict Zig subset) compiler `sf/src/*.zig` emitting C89; PAL runtime (`zig_pal.c`, `zig_nocrt.c`, `zig_runtime.c` via `sf/src/emit_support.zig` single source); shell gates under `scripts/compiler/`; fixtures under `repro/mi_matrix/`; Wine/i686-w64-mingw32-gcc for Win32 checks.

**Spec:** `docs/superpowers/specs/2026-10-29-phase35-defects-design.md` (the plan argues from the spec; executors read both).

## Global Constraints

- Only this plan is authorized. STOP and present on ambiguity; if the plan says A, do A. `edit`/`fastedit` only (no sed/perl/python/awk source transforms); one edit at a time; no subagents inside implementers; explicit-path staging only; no push; `run.err` untouched; sequential `zig1` runs in separate CWDs (`.zig1_*.tmp` collide).
- **Runtime single source:** any edit to emitted C support files goes through `sf/src/emit_support.zig` → `bash scripts/gen_emit_support.sh <zig1>` → `bash scripts/check_emit_support.sh <zig1>` = 8/8. Never edit `sf/src/include/*` by hand.
- **Single re-baseline:** the 8 pins move exactly once, in Task 10. Tasks 3 and 4 change emission; verify them functionally and record interim diffs — do NOT touch `gate_lower_depth.sh` pins or the QUICK_REF pin table before Task 10.
- Anchors (hold unless Task 10 re-anchors them): frozen-1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` NEVER moves; **seed baseline is v129** (the operator-authorized Win9x truth hotfix, executed inside the 0.21.0 release plan, rotates v128 → v129 first and moves the fixed point, pins, and possibly corpus/marker anchors — re-read the hotfix report for the new values before starting Task 1); corpus live 1193 = 1017/58/118/0/0, class md5 `5167393439ffb80049ba5d3d87a2773f`; markers 3304 lines / 37896 B; stdlib 339 + crosscheck 10; examples 26/26; 8 pins = spec §4 list.
- **Reserved-word escape coordination (hotfix ↔ D5/D10):** the Win9x hotfix extends the mangler's C-keyword escape to the Microsoft/OpenWatcom extension words (`cdecl`, `pascal`, `near`, `far`, `huge`, `fortran`, `interrupt`, `export`, `readonly`, `stdcall`, `self`, `segment`, …) and to the Z98 runtime names (`Z98_*`, `zig_*`, `pal_*`). It escapes **source identifiers only**; emitter template tokens and convention spellings stay raw. Task 5's `extern "stdcall"` definitions must write `Z98_STDCALL` as raw template text and must not route the convention token through the mangler; its fixtures may freely use `cdecl`/`stdcall` as local names.
- Byte-identity between two compilers: shared `--lib-dir`, sequential runs.
- New fixtures: `repro/mi_matrix/` (corpus-visible) or `repro/mi_matrix/known_excluded/` (kept out). The live corpus count/class md5 is re-anchored in Task 10 only.
- Defects doc `examples/torrent_example_defects.md` stays open-only: each fixed entry is deleted in the same commit as its fix; history lives in git + the SDD report.
- Windows-facing checks run under Wine (timeout-guarded, sequential); real Win98/MSVC/OWC validation is operator-owned.
- SDD workspace: `.superpowers/sdd/2026-10-29-phase35-defects-plan/` (ledger `progress.md`, per-task briefs/reports). Every task appends its report there.

## Review Focus

| # | Input class / failure mode | Owning task + test |
|---|---|---|
| 1 | Mixed stdout traffic ordering (the D8 defect being fixed): `std.io.print` + `@stdoutWrite` + `@putChar` on one stream must interleave in program order on BOTH the CRT and no-CRT paths; buffered data must not be lost on a trap | Task 3: ordering fixture run under gcc-CRT and `cross_nocrt.sh` |
| 2 | D3 intern-order landmine: moving module resolution flips `stdlib_crypto_modpow_xmod` OK→GREEN (F1 class) | Task 4 step 1 re-verification; full corpus run before/after |
| 3 | D3 false-load surface: a dead arm importing a file that EXISTS but is unparsable on this target must also not load (not just missing files) | Task 4: fixture with an unparsable dead-arm import |
| 4 | D5/D10 ABI balance: a `extern "stdcall"` definition called directly (not via fn pointer) and registered as a Win32 callback must both clean the stack correctly; prototype and definition conventions must agree | Task 5: objdump `ret $N` check + Wine C-host callback run |
| 5 | D12/D7.3 non-regression: the already-working typed array-literal and simple aggregate-write paths must stay byte-identical | Tasks 1–2: emitted-C diff on the working shapes (must be empty) |

---

### Task 1: D12 — module-scope untyped array literal

**Files:**
- Modify: `sf/src/lower.zig` (module-init / global-store lowering of array-literal values)
- Test: `repro/mi_matrix/module_untyped_array_init_ok_xmod/main.zig` (+ `expected.txt`/`expected.rc`)

**Interfaces:**
- Consumes: the existing typed array-literal path (the one `repro/mi_matrix/multiarray_literal_init_xmod` exercises — element-wise copy, no whole-aggregate `=`).
- Produces: `pub var arr: [3]u32 = .{ 1, 2, 3 };` compiles rc=0 and the emitted C builds with gcc. Later tasks rely on nothing else from this fix.

- [ ] **Step 1: Write the failing fixture.** `pub var arr: [3]u32 = .{ 1, 2, 3 };` + a `main` that mutates `arr[0]` and prints `arr` values; expected output is the mutated values.
- [ ] **Step 2: Verify RED.** `zig1 -o out module_untyped_array_init_ok_xmod/main.zig` → rc=0 today but gcc rejects the emitted C with `assignment to expression with array type` (the defect). Record the exact C (`zG_..._arr = zT_...;`).
- [ ] **Step 3: Fix** so the module-init path applies the declared array type's literal annotation (or lowers through the typed array-literal path) instead of materialising a `Tup_*` temp + whole-aggregate assignment. The emitted form must be the element-wise copy the typed literal already uses.
- [ ] **Step 4: Verify GREEN** — fixture compiles, gcc-clean, output matches `expected.txt`, rc matches. Re-emit `multiarray_literal_init_xmod` and diff its C against the pre-fix emission: **must be unchanged** (Review Focus 5).
- [ ] **Step 5: Commit** `fix(lower): module-scope untyped array literal emits element-wise init (Phase3.5 D12)` + delete D12 from `examples/torrent_example_defects.md` + SDD report.

### Task 2: D7.3 — nested aggregate write targets a by-value temp

**Files:**
- Modify: `sf/src/lower.zig` and/or `sf/src/c89_emit.zig` (lvalue/temporary materialisation for nested aggregate field indexing)
- Test: `repro/mi_matrix/known_excluded/nested_agg_write_ok/main.zig` (+ expected)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `arr[i].field[0..] = ...` / `arr[i].field = ...` writes land in `arr`'s storage. The wireguard demo's explicit-pointer workaround becomes unnecessary (but is left in place).

- [ ] **Step 1: Minimal repro** (RED). Program: `var arr: [2]S = ...; arr[0].field[0..] = ...` (S has a slice/array field) then print `arr[0].field` values. The demo's shape (`examples/z98/demo/wireguard_demo/NOTES.md`) is the source. Today the store is lost (output shows pre-write values).
- [ ] **Step 2: Locate the temp** — identify where the nested write materialises a by-value temp (lowering of `field_access`/`index_access` lvalues, emitter `emitBaseIdxAccess` family). Record the mechanism in the report before fixing.
- [ ] **Step 3: Fix** so the write targets the storage address (compose the lvalue instead of copying).
- [ ] **Step 4: Verify GREEN** — repro output shows the mutated values; the simple working shapes (`s.f = v`, `a[i] = v`, typed slice writes) re-emit **byte-identical** (Review Focus 5).
- [ ] **Step 5: Commit** `fix(lower): nested aggregate writes target storage, not temporaries (Phase3.5 D7.3)` + delete D7.3 + report.

### Task 3: D8 — stdout builtins through the PAL + runtime-C surface doc

**Files:**
- Modify: `sf/src/c89_emit.zig` (builtin lowering `@stdoutWrite`/`@stderrWrite`/`@putChar`/`@getChar` → PAL calls; the `#include <stdio.h>` decision those builtins trigger)
- Modify: `sf/src/emit_support.zig` (PAL putchar/getchar additions; any `zig_nocrt.c` shim adjustment) → regenerate `sf/src/include/*`
- Modify: `sf/docs/tech_docs/10_c_runtime.md` (C-runtime surface inventory + reduction path)
- Test: `repro/mi_matrix/known_excluded/stdout_order_ok/main.zig` (mixed `std.io.print` + `@stdoutWrite` + `@putChar`)

**Interfaces:**
- Consumes: PAL print entry points (`pal_print_stdout` in `zig_pal.c`); the runtime single-source loop.
- Produces: `pal_print_stderr`, `pal_putchar`, `pal_getchar` (or equivalent PAL read) usable by the emitter; emitted stdio dependency from the stdout family removed. Task 9 documents the new behavior in the spec.

- [ ] **Step 1: RED fixture** — interleaves `std.io.print("A\n")`, `@stdoutWrite("B\n")`, `@putChar('C')`, then reads one byte with `@getChar()`; asserts program-order output on stdout. Run once against the pre-fix compiler: it may pass or pass-by-luck; the ordering test's value is post-fix on BOTH CRT and no-CRT.
- [ ] **Step 2: Inventory the current surface** (write-first): which emitted symbols come from `stdio.h`, `zig_runtime.c`, `zig_pal.c`, `zig_nocrt.c`, `__bootstrap_*`. Record in the report; this becomes the doc body.
- [ ] **Step 3: Implement PAL routing** — lower the four builtins to PAL calls; add the missing PAL putchar/getchar in `emit_support.zig`; regen + `check_emit_support.sh` 8/8.
- [ ] **Step 4: Verify** — ordering fixture byte-exact under gcc CRT AND `scripts/win32_cross/cross_nocrt.sh` (no-CRT); existing stdlib/examples outputs unchanged (they use `std.io.print`, already PAL); `check_emit_support.sh` 8/8; gate `gate_warn_clean.sh` still GREEN (the new PAL calls must stay `-m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long`-clean). Record the emitted-C diff vs base (expected non-empty for std.io users — this is the authorized shift).
- [ ] **Step 5: Runtime-C surface doc** in `10_c_runtime.md`: the inventory + reduction path toward a C-free backend (which PAL calls would become raw syscalls / OS calls in an asm backend; what `__bootstrap_*` would become).
- [ ] **Step 6: Commit** `fix(emit): route stdout/stderr/getchar builtins through the PAL (Phase3.5 D8)` + delete D8 + report.

### Task 4: D3 — interner re-verification + full lazy `@import`

**Files:**
- Modify: `sf/src/parser.zig`, `sf/src/import_resolver.zig`, `sf/src/main.zig` (module closure / phase order), `sf/src/semantic_analyzer.zig` (sema import gate) — exact shape follows the verification result
- Test: `repro/mi_matrix/known_excluded/lazy_import_fold_ok/main.zig` (+ an unparsable-dead-arm variant)

**Interfaces:**
- Consumes: `parserFoldComptimeBool` / `dead_import_depth` (current probe), `comptimeEvalEvaluate`'s fold set (the superset), the F1 fix from `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/` (T4.1).
- Produces: a comptime-dead `@import` arm never opens its file. Task 9 documents the semantics.

- [ ] **Step 1: Re-verify the interner landmine (gate before any code).** With the current tree: confirm `stdlib_crypto_modpow_xmod` is OK; then perturb intern order (one extra intern before source lexing) in a throwaway build and confirm/deny the OK→GREEN flip. Result goes in the report. **If it still flips:** apply/extend the T4.1 F1 fix and re-verify before proceeding. If unfixable in-scope: STOP and present.
- [ ] **Step 2: RED fixtures** — `if (1 == 1) @import("exists.zig") else @import("missing.zig")` and a variant whose dead arm is an *unparsable* file; both must compile rc=0 today they fail with `error[3048]`-class diagnostics.
- [ ] **Step 3: Implement true lazy import** — resolution defers opening to the point where the arm survives evaluation (probe ⊂ evaluator is the bug: extend to the evaluator's fold class or restructure loading). Wrong-module selection must remain impossible.
- [ ] **Step 4: Verify GREEN** — both fixtures rc=0, no file open on the dead arm (strace/open-count evidence in report); the established conditional-import shapes (`@isWindows()` idiom, `conditional_import_lazy_xmod`) unchanged; full corpus run: only new fixtures move, `stdlib_crypto_modpow_xmod` stays OK, frozen-1124 md5 unchanged. Record emitted-C diff vs base (authorized shift).
- [ ] **Step 5: Commit** `fix(import): comptime-dead import arms never load files (Phase3.5 D3)` + delete D3 + report.

### Task 5: D5 + D10 — calling conventions on definitions

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseExternDecl`/`parserParseFnDecl` — extern-with-body becomes a definition), `sf/src/semantic_analyzer.zig` (definition/prototype convention agreement), `sf/src/lower.zig`, `sf/src/c89_emit.zig` (emit `Z98_STDCALL` on definitions; mirror the fn-pointer pattern at the `emitFnPtrType` call sites)
- Test: `repro/mi_matrix/known_excluded/stdcall_def_ok/main.zig` (+ cdecl extern-body variant), plus a Wine C-host callback harness under `examples/z98/` or `scripts/win32_cross/` evidence

**Interfaces:**
- Consumes: `Z98_STDCALL` macro (`sf/src/include/zig_compat.h` — via `emit_support.zig` if changed), existing convention strings on declarations/fn-pointer types.
- Produces: `extern "stdcall" fn f(...) { ... }` = stdcall definition; `extern fn f(...) { ... }` = cdecl definition; `callconv(...)` still rejects. Task 9 documents this.

- [ ] **Step 1: RED probes.** `pub extern "stdcall" fn cb(x: u32) i32 { return x + 1; }` today emits NO definition (the D5 silent-drop: `'cb' undeclared` at gcc, zero Z98 diagnostics). Record the current emission.
- [ ] **Step 2: Implement definitions.** Extern-with-body emits a real C definition; `"stdcall"` writes `Z98_STDCALL` on it; bare/`"c"` emits cdecl. Prototype and definition conventions must agree (sema check). `callconv(...)` still rejects `error[2000]`.
- [ ] **Step 3: ABI evidence.** Build the stdcall fixture with i686-w64-mingw32-gcc; objdump the definition showing the callee-cleanup epilogue (`ret $N`, N = arg bytes); a Wine run where a small C host registers the Z98-defined function as a callback and invokes it (balanced stack, correct return) — the shape z9play M6 needed.
- [ ] **Step 4: Verify GREEN** — both fixtures rc=0 gcc-clean; existing extern *declarations* unchanged (byte-identical C for declaration-only programs); corpus + stdlib green; `callconv` still rejects (fixture).
- [ ] **Step 5: Commit** `feat(sema): extern function definitions with calling conventions (Phase3.5 D5/D10)` + delete D5 and D10 + report.

### Task 6: D4-pre — analyzer audit (no code)

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-analyzer-audit.md`
- Inputs (read-only): `sf/src/analyzer*.zig`, `sf/src/semantic_analyzer.zig`, `docs/tech_debt/static_analyzers.md`, the D4 cluster entry in `examples/torrent_example_defects.md`, `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-5-report.md`, `sf/docs/initial_design/STATIC_ANALYZERS_p2.md` (after Task 8's move; else `docs/sf/STATIC_ANALYZERS_p2.md`)

- [ ] **Step 1: Contract inventory** — for each analyzer (Lifetime/Provenance, NullPointer, DoubleFree, Signature): what it *should* do (design intent + what the diagnostics promise).
- [ ] **Step 2: Reality map** — what each actually does; every inert path with `file:line` (symbol-table provenance dead for locals/params; unseeded param null state; un-walked `return`/init expressions; DoubleFree alias-chain blindness; the comptime-dead-arm gap).
- [ ] **Step 3: Lie list** — every confident-but-wrong or vacuous diagnostic class with repro evidence (anchor: the 44 false `WARN_6002` on self-source; measure the current count — it may have shifted). Include "silently passes real defect" classes.
- [ ] **Step 4: Bar + must-work set** — the gap to a real-analyzer bar, and the concrete must-work list Task 7 implements. Fixture-driven test strategy (`tests/analyzers/**`) replaces hand-fed symbols.
- [ ] **Step 5: Commit** `docs(specs): static-analyzer audit — contracts, inert paths, lie list (Phase3.5 D4-pre)`.

### Task 7: D4-upgrade — make them real analyzers

**Files:**
- Modify: `sf/src/analyzer*.zig`, `sf/src/semantic_analyzer.zig` (dead-arm parity plumbing), `sf/src/main.zig`/`sf/src/comptime_eval.zig` (AnalyzerContext fold plumbing if the audit requires it), `sf/src/tests/test_analyzer_bin.zig` (Symbol `file_id`, fixture-driven harness)
- Test: `tests/analyzers/**` fixtures (the T5 direction), self-source false-positive measurement

**Interfaces:**
- Consumes: Task 6's must-work set (binding — the audit is the bar).
- Produces: analyzers that match their contracts on the must-work set; `WARN_6002` false-positive count on self-source driven to the audit's target (the 44-class must collapse, not move).

- [ ] **Step 1: Write-first plan** — map each must-work item to its fix; append to the SDD report before editing.
- [ ] **Step 2: Fix the lies first** (wrong diagnostics), then **close the inert paths** (return/init walks, param seeding, alias propagation, local provenance), then **extend** to the audit's must-work set.
- [ ] **Step 3: Test migration** — fixture-driven cases under `tests/analyzers/**`; delete/retire the vacuous hand-fed-symbol tests (the (e) pattern); fix `Symbol` test-init `file_id` (the (g) item); docs residue (the (f) item) cleaned in `docs/tech_debt/static_analyzers.md`.
- [ ] **Step 4: Verify** — analyzer suites green; self-source `WARN_6002` false positives measured at the audit's target; no NEW false positives on corpus examples; corpus/stdlib/examples unchanged (analyzers are post-sema, no emission change — verify emitted C diff is empty).
- [ ] **Step 5: Commit** `fix(analyzer): contracts honored, lies removed, fixture-driven tests (Phase3.5 D4)` + rewrite the D4 entry out of the defects doc + report.

### Task 8: Doc consolidation

**Files:**
- Create dir: `sf/docs/initial_design/`
- Move (git mv) from `docs/sf/`: `Design_p2.md`, `AST_PARSER_p2.md`, `AST_LIR_Lowering_p2.md`, `LIR_C89_Emission_p2.md`, `TYPE_SYSTEM_p2.md`, `STATIC_ANALYZERS_p2.md`, `RUNTIME_PAL_p2.md`, `ERROR_HANDLING_p2.md`, `TEST_HARNESS_p2.md`, `Lexer_sf.md`, `Import_Symbol_reg.md`, `COMPLEMENT.md`, `z98_external.md`, `AI_TASKS_sf.md`
- Modify: cross-references in `docs/sf/AGENTS.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/INDEX.md` and any doc pointing at the moved paths
- Untouched: `docs/sf/{AGENTS.md,QUICK_REF.md,manuals/,std_lib/,Debugging.md,std_additions.txt,zig0_zig1_matriuska_bug.md}` (stay), `sf/docs/tech_docs/` (stays), `docs/reference/` + `docs/design/` zig0-era docs (stays as-is)

- [ ] **Step 1: Move** the 14 design-intent files into `sf/docs/initial_design/` (`git mv`, explicit paths).
- [ ] **Step 2: Add `sf/docs/INDEX.md`** (or extend tech_docs INDEX) stating the split: `tech_docs/` = observed implementation, `initial_design/` = design intent as first thought, and the zig0-era docs stay in `docs/reference/` + `docs/design/` for comparison until the future `zig0/` archive.
- [ ] **Step 3: Fix every cross-reference** that pointed at the old paths (grep for the moved filenames repo-wide; update `docs/sf/`, `sf/docs/`, `scripts/` comments only if they name paths).
- [ ] **Step 4: Verify** — no dangling references (grep pass); `git status` shows pure renames + reference edits; no file content changed except cross-refs and the new INDEX.
- [ ] **Step 5: Commit** `docs(sf): consolidate self-host docs — tech_docs (observed) + initial_design (intent) (Phase3.5)`.

### Task 9: Spec truth-up

**Files:**
- Modify: `docs/reference/Language_Spec_Z98.md` (only this spec; the other stale docs stay)

**Interfaces:**
- Consumes: Task 3's PAL routing (D8 semantics), Task 4's lazy import (D3 semantics), Task 5's conventions (D5/D10 syntax), Task 7's analyzer status (for the §5/§7 accuracy check).
- Produces: a spec that matches the compiler.

- [ ] **Step 1: Kill the lifting lie** — replace the `:435` "AST Lifting" bullet with the real mechanism (lowerer phase machines emit branches + result temporaries in LIR; no AST transformation pass exists).
- [ ] **Step 2: Barrel list** — `:352` re-exports 12 → 14 (`fmt`, `fold`); verify against `sf/src/std.zig`.
- [ ] **Step 3: Missing facts** — `error[3077]` (limit 130), `--check` mode, the §5.1 conventions rules, the §5.3 lazy-import semantics.
- [ ] **Step 4: Builtins reconciliation** — §4 list vs the compiler's real registration (sema `BuiltinDesc` + lower + `comptime_eval`); resolve `@addr`/`@name`/`@enumFromInt`/`@typeName`/`@cInclude` claims.
- [ ] **Step 5: §5/§7 re-verification** — every limitation and "Not Yet Supported" item re-checked against the current compiler and mi/corpus; correct stale claims; verify every fixture path named in the spec exists.
- [ ] **Step 6: Commit** `docs(spec): language spec truth-up — real lowering, current features (Phase3.5)` + report.

### Task 10: Closeout — battery, re-baseline, seed v130

**Files:**
- Modify: `scripts/compiler/gate_lower_depth.sh` (the 8 pins), `docs/sf/QUICK_REF.md` (pin table + counts), `README.md` (seed/fixed-point facts), `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `examples/torrent_example_defects.md` (final open-only state)
- Test: the full battery (below)

**Interfaces:**
- Consumes: every prior task's landed state.
- Produces: seed v129 → **v130** with a new fixed point (F_new moved by Tasks 3–5), re-anchored corpus counts/class md5, re-recorded markers, all gates green.

- [ ] **Step 1: Full battery on the current tree** (report-only at first): corpus live (record new count/class md5; expect growth from new fixtures; frozen-1124 md5 MUST still be `518eca1a...` with 0 movers), goldens, markers (record new value), examples 26/26, stdlib 339+3? (new fixtures land where they land — record actual), crosscheck 10/10, all compiler gates (`gate_lower_depth`, `gate_builtin_names`, `gate_mutable_for`, `gate_debug_map`, `gate_crlf`, `gate_warn_clean`, `gate_reserved_names`, `check_emit_support` 8/8), tiers (`tier_dbg`, `tier_dbg_core`, `tier_gfx`, `tier_edit`, `tier_edit_gui`) — GUI tiers only if std_gfx touched (it is not expected to be).
- [ ] **Step 2: STOP-check** — if anything unexpected moved beyond the known emission shifts (D8/D3), STOP and present. Expected movers: 8 pins (all), corpus additions, marker counts, any goldens touching stdout ordering.
- [ ] **Step 3: Single re-baseline** — re-record the 8 pins in `gate_lower_depth.sh` + `QUICK_REF.md` (the authorized once-only move); re-anchor corpus counts/class md5 and markers in the docs.
- [ ] **Step 4: Seed rotation** — `scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/phase35_close` → closure (moving point: hop2 == hop3 with hop1 from the prior seed); full battery values recorded; `scripts/seed/archive_seed.sh <bin> <gen> release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`; verify every CHANGELOG claim (the v121 false-status class must not repeat); lib/ counts (50 baseline + any new std file — expected unchanged); rebuild from the NEW archive reproduces the fixed point.
- [ ] **Step 5: Defects doc final state** — open-only; the fixed entries are gone; any new findings land at the next free slot (D13+).
- [ ] **Step 6: Commit** `chore(seed): rotate v130 (Phase3.5 defect closure + docs)` + `docs(sdd)` final report. No push, no tag.

---

**Execution note:** tasks run in the listed order (the operator fixed it: 1, 2, 3, 4, 5, then the analyzer pair, then docs, then closeout). Tasks 3 and 4 are the emission shifts — their diffs are expected and recorded, not re-baselined. Task 6 is investigation-only. Task 8 must land before Task 9's spec work references `sf/docs/initial_design/` paths.
