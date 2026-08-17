# Parser Gaps, Example Quirks & Code-Reuse Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 parser gaps blocking self-compile, resolve 2 example quirks (root-cause-decides), and audit all compiler module clusters for code-reuse opportunities — investigation-first, one consolidated STOP, then fixes and gate sweep.

**Architecture:** Three workstreams (A=3 parser gaps, B=2 example quirks, C=7 code-reuse cluster audits). All 12 I tasks are read-only (reports only, no source changes, no commits). After all I tasks report, ONE consolidated STOP gathers operator rulings; then the F tasks (A-F1..A-F3 are placeholders to be filled from the rulings; B-F1/B-F2 and C-F\* likewise) are executed, followed by the gate sweep.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, parser (`parser.zig`), example sources (`examples/z98/`), repros (`repro/mi_matrix/`), `--dump-c89`, `--markers`, gcc `-m32` build recipe, 4 MD5 gates.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-70) is MANDATORY. Copy exact commands. **Compiler under test is `/tmp/fx_subfolder/zig1`** (NOT `sf/build/out_release/zig1`).
- **`sf/build/out_release/` is WEDGED — any command touching it HANGS; NEVER touch/list/build into it. Use `timeout` on all risky commands.**
- **Build:** `bash sf/scripts/build_release.sh` → gate line `=== [release] Done: /tmp/fx_subfolder/zig1 ===`. **The script wipes `/tmp/fx_subfolder/` (including `lib/`) — reinstall the std lib after every rebuild:** `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top). NO sed/python/bulk transforms.
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps (`U32ToU32Map` etc.); `@intCast` for i32↔usize; no pointer captures; switch requires `else`.
- **I tasks are READ-ONLY.** Each I task writes its report to `.superpowers/sdd/task-*-report.md` (git-ignored), makes ZERO source changes, and leaves the working tree clean. I tasks do NOT commit.
- **The plan is the ONLY authority.** STOP on any issue. All I tasks re-verify their locus against current HEAD (line numbers shifted after F-PARSERGAP `b33f412a`).
- **MD5 gate recipe:** single-file `--dump-c89` to stdout piped to `md5sum`. Baselines (unchanged since memory-optimization closure, HEAD `de630979`):
  - gol `9cf758d96f25d41980379564a5501bc8`
  - lisp `524d2872daefb2677c8ddc1ac8f34cf5`
  - json `066c99974f6052317636854dc4c2a2d5`
  - mud `a1d0dd55aada9c3fd904ae33f54de32e`
- **Baselines to preserve:** corpus 255 dirs `OK=249 / FAIL=2 / ICE=0 / CRASH=0 / GG=4` (FAIL=2 = `field_store_drop` + `self_embed_optional_cycle`; GG=4 = `eu_assign_incompat_payload`, `euvoid_val_catch`, `field_access_optional`, `var_declared_void`). Corpus recipe is **per-module** (`--dump-c89 --output-dir DIR` then gcc each `.c`); the stdout-concat recipe falsely fails `fn_ptr_struct_field`. 21-example matrix 21/21; `test_analyzer_bin` "5 passed, 4 failed".
- **json_parser is a hard MD5 gate.** Any B2 fix that changes its emitted C requires an operator re-baseline ruling at the STOP.

---

### Task A-I1: Investigate discard-capture `if (x) |_|` gap

**Files:**
- Read: `sf/src/parser.zig` (if-stmt/if-expr capture paths, switch-prong `:893`, var-decl `:1337`), `sf/src/lexer.zig` (`_` → `TokenKind.underscore`), `repro/mi_matrix/parsergap_discard_if_xmod/{main.zig,NOTES.md}`, `sf/src/cinclude.zig:23` (self-compile hit)
- Report: `.superpowers/sdd/task-A-I1-report.md`

**Interfaces:**
- Consumes: repro `parsergap_discard_if_xmod` (RED baseline + named-capture GREEN control, documented in NOTES.md at commit `583a081e`).
- Produces: verified locus + fix design for `parserParseIfStmt`/`parserParseIfExpr` capture-name handling; decision parser-only vs cascade.

- [ ] **Step 1: Confirm current locus against HEAD**

Run the repro to re-confirm the RED diagnostic:
```
cd repro/mi_matrix/parsergap_discard_if_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[2000]: expected identifier but found token` at the `|_|`, 0-byte `/tmp/x.c`.

Read the current `parserParseIfStmt` capture block (`sf/src/parser.zig` — the pipe check and capture-name expect, previously `:1485-1499`, shifted after `b33f412a`) and `parserParseIfExpr` capture (previously `:787-797`). Record exact current line numbers.

- [ ] **Step 2: Confirm the `_` lexing + working analogues**

Verify `_` lexes as `TokenKind.underscore` (`sf/src/lexer.zig`, previously `:422`) and that switch-prong (`parser.zig`, previously `:893-897`) and var-decl name (`parser.zig`, previously `:1337`) accept `underscore`. Confirm both if-stmt AND if-expr capture paths use `parserExpect(identifier)`.

- [ ] **Step 3: Design the fix + cascade analysis**

Specify the fix: accept `TokenKind.underscore` for the capture name in `parserParseIfStmt` and `parserParseIfExpr`, mirroring the switch-prong pattern:
```zig
if (parserPeek(self).kind == TokenKind.underscore) {
    name_tok = try parserExpect(self, TokenKind.underscore);
} else {
    name_tok = try parserExpect(self, TokenKind.identifier);
}
```
Verify downstream: sema `semanticAnalyzerResolveIfHeader` reads `node.payload` and registers the capture via `registerLocalDecl` — confirm an `_` capture (discard, never referenced) needs no sema/lower change (the F-PARSERGAP lesson: check the lowerer's `bindOptionalCapture` path for both if_stmt and if_expr). State the verdict: parser-only, or enumerate the cascade with file:line.

- [ ] **Step 4: Byte-identity check**

Confirm the fix is behavior-preserving for all non-discard inputs: named captures (`|cap|`), no-pipe ifs, and value-position `if` without capture all parse identically (the `peek==underscore` branch only fires for `|_|`, which today errors). Note any construct where byte-identity could change.

- [ ] **Step 5: Write report + STOP**

Write `.superpowers/sdd/task-A-I1-report.md`: current line numbers, confirmed locus, fix design (code block), cascade verdict, byte-identity note, and any deviation from the NOTES.md sketch. Verify `git status` clean. Return status (DONE/DONE_WITH_CONCERNS/BLOCKED) + one-line summary.

---

### Task A-I2: Investigate bare array type as expression (`const Buf = [10]u8`)

**Files:**
- Read: `sf/src/parser.zig` (primary-expr `[` dispatch, `parserParseArrayLiteral`, `parserParseBracketType`, `parserParseType`), `repro/mi_matrix/parsergap_array_type_xmod/{main.zig,NOTES.md}`, `sf/src/lower.zig:2283` (cascade site)
- Report: `.superpowers/sdd/task-A-I2-report.md`

**Interfaces:**
- Consumes: repro `parsergap_array_type_xmod` (RED baseline + var-annotation GREEN control).
- Produces: verified locus + fix design for `parserParseArrayLiteral` no-`{` branch; decision parser-only vs type-alias sema work.

- [ ] **Step 1: Confirm current locus against HEAD**

Run the repro:
```
cd repro/mi_matrix/parsergap_array_type_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[2000]: expected '{' after array type`, 0-byte `/tmp/x.c`.

Read current `parserParsePrimaryExpr` `[` dispatch and `parserParseArrayLiteral` (previously `:752-759`). Record exact current line numbers.

- [ ] **Step 2: Verify the type-path difference**

Confirm `parserParseType` → `parserParseBracketType` (annotation path) produces `array_type`/`slice_type` without a `{` check, while `parserParseArrayLiteral` (expression path) requires `{` after the bracket type. Run the NOTES.md controls to confirm GREEN for `var b: [10]u8 = undefined;`, `var s: []const u8 = "abc";`, `[10]u8{1,2,3}` and RED for `const Buf = [10]u8;` and `const S = []const u8;`.

- [ ] **Step 3: Design the fix + cascade analysis**

Specify the fix: in `parserParseArrayLiteral`, after `parserParseBracketType`, if the next token is NOT `{`, return the bracket-type node (`array_type`/`slice_type`) directly. Verify downstream consumers of the returned node accept an `array_type` node as a const-value expression (sema `resolveTypeExprFull`-style paths, const alias registration) — confirm no `expected expression`-class rejection remains. State the verdict: parser-only, or enumerate the cascade.

- [ ] **Step 4: Byte-identity check**

Confirm array literals `[N]T{...}` (with `{`) still parse identically (the no-`{` branch never fires when `{` follows). Note the lower.zig:2283 cascade disappears only after A-F1 lands; independent A2 correctness is proven by the repro alone.

- [ ] **Step 5: Write report + STOP**

Write `.superpowers/sdd/task-A-I2-report.md`: current line numbers, confirmed locus, fix design (code block), cascade verdict, byte-identity note. Verify `git status` clean. Return status + one-line summary.

---

### Task A-I3: Investigate trailing comma in fn-call args

**Files:**
- Read: `sf/src/parser.zig` (`parserParseFnCall` arg loop, array-literal/tuple-literal comma pattern, switch-prong list), `repro/mi_matrix/parsergap_trailing_comma_xmod/{main.zig,NOTES.md}`, `sf/src/main.zig:749-759` (self-compile hit)
- Report: `.superpowers/sdd/task-A-I3-report.md`

**Interfaces:**
- Consumes: repro `parsergap_trailing_comma_xmod` (RED baseline + no-trailing-comma GREEN control).
- Produces: verified locus + fix design for `parserParseFnCall` arg loop; decision parser-only vs cascade.

- [ ] **Step 1: Confirm current locus against HEAD**

Run the repro:
```
cd repro/mi_matrix/parsergap_trailing_comma_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[2000]: expected expression` at the trailing comma, 0-byte `/tmp/x.c`.

Read current `parserParseFnCall` arg loop (previously `:401-407`). Record exact current line numbers.

- [ ] **Step 2: Verify the working analogues**

Confirm the array-literal (`parser.zig`, previously `:766`), anonymous/tuple-literal (`:731`), and switch-prong (`:827-829`) loops consume an optional trailing comma before the closing delimiter. Confirm `parserParseFnCall` currently breaks only on `rparen` immediately after an arg.

- [ ] **Step 3: Design the fix + cascade analysis**

Specify the fix, mirroring the array/tuple pattern:
```zig
if (parserPeek(self).kind == TokenKind.rparen) break;
_ = try parserExpect(self, TokenKind.comma);
```
(or restructure so a comma is only consumed when a real argument follows). Verify no sema/lower change is needed for an args count that now includes the trailing-comma form. State the verdict: parser-only, or enumerate the cascade.

- [ ] **Step 4: Byte-identity check**

Confirm non-trailing-comma calls parse identically (the added `rparen`-break fires only when a trailing comma preceded it; call sites without trailing commas hit the same path as today). Note the self-compile unblocking at `main.zig:759`.

- [ ] **Step 5: Write report + STOP**

Write `.superpowers/sdd/task-A-I3-report.md`: current line numbers, confirmed locus, fix design (code block), cascade verdict, byte-identity note. Verify `git status` clean. Return status + one-line summary.

---

### Task B-I1: Investigate `days_in_month` u8 `{}` raw-byte output

**Files:**
- Read: `examples/z98/days_in_month/main.zig`, `sf/src/std_io.zig` (print/printInt), `sf/src/lower.zig` (enhanced print lowering, previously `:2403`), `sf/src/print_decomposition.zig`
- Report: `.superpowers/sdd/task-B-I1-report.md`

**Interfaces:**
- Consumes: example `days_in_month` (prints `std.io.print("  Month {}: {} days\n", .{ month, days })` with `u8` args).
- Produces: root-cause verdict (example source vs compiler print-lowering) + fix design.

- [ ] **Step 1: Reproduce the quirk**

Build `days_in_month` per QUICK_REF recipe and run it. Capture the exact output:
```
cd /tmp/out && timeout 120 /tmp/out/prog
```
Expected (quirk): `Month`/`days` values render as raw bytes (display corruption) rather than decimal integers.

- [ ] **Step 2: Trace the print lowering for u8**

Read the enhanced print lowering in `sf/src/lower.zig` (keyed on fn name `print`, previously `:2403`; the `{}` specifier path). Determine how a `u8` argument is decomposed: does `{}` render it as a raw byte (char) instead of a decimal integer? Compare with how `i32`/`u32`/`usize` render. Also inspect `sf/src/print_decomposition.zig` for the `{}` handling.

- [ ] **Step 3: Verdict — example source vs compiler**

Decide: (a) **compiler defect** — `{}` with a `u8` (and possibly other small int types) prints a raw byte; fix = compiler (lower/print decomposition) + gate sweep; or (b) **example source** — `{}` is not the correct specifier for `u8` numeric output; fix = `days_in_month/main.zig` (e.g. use `printInt` or cast to a wider int). Present both sides with the trace evidence.

- [ ] **Step 4: Gate-impact analysis**

`days_in_month` is NOT a hard MD5 gate. If the verdict is compiler-side, assess which MD5 gates (gol/lisp/json/mud) emit a `{}`-with-`u8` pattern and would change emitted C → flag for re-baseline ruling at the STOP. If example-side, confirm no gate impact.

- [ ] **Step 5: Write report + STOP**

Write `.superpowers/sdd/task-B-I1-report.md`: quirk reproduction, print-lowering trace with file:line, verdict with reasoning, gate-impact note. Verify `git status` clean. Return status + one-line summary.

---

### Task B-I2: Investigate `json_parser` missing object-field commas

**Files:**
- Read: `examples/z98/json_parser/main.zig` (printValue `.Object` arm), `examples/z98/json_parser/json.zig`, `sf/src/lower.zig` (for-loop lowering, index + compare), `sf/src/parser.zig` (for-loop parse), `sf/src/c89_emit.zig` (for-loop C89 emission)
- Report: `.superpowers/sdd/task-B-I2-report.md`

**Interfaces:**
- Consumes: example `json_parser` (NOTES records "missing commas between object fields"; source has `if (i < obj.len - 1) std.io.print(",")`).
- Produces: root-cause verdict (example source vs compiler for-index) + fix design.

- [ ] **Step 1: Reproduce the quirk**

Run `json_parser` from `examples/z98/json_parser/` (needs `test.json` in CWD) per QUICK_REF recipe. Capture output. Confirm object fields print WITHOUT the comma separator while array elements print WITH commas (per NOTES). Dump the emitted C for the `.Object` arm's for-loop and record whether the `i < obj.len - 1` condition is emitted correctly.

- [ ] **Step 2: Trace the for-index compare**

Read the for-loop lowering in `sf/src/lower.zig` (index variable, `i += 1`, `i < len - 1` condition) and the emitted C89 in `sf/src/c89_emit.zig`. Verify whether the emitted condition is `i < obj.len - 1` (correct) or something that always/never fires. Compare the `.Array` arm (commas present) vs `.Object` arm (commas absent) — both use the identical `if (i < …len - 1) std.io.print(",")` pattern, so isolate the difference.

- [ ] **Step 3: Verdict — example source vs compiler**

Decide: (a) **compiler defect** — the for-index/compare mis-lowers (e.g. index resets, compare operand swapped, multi-line print sequence reordered); fix = compiler + gate sweep; or (b) **example source** — the condition or loop structure is wrong in `main.zig`; fix = example source. Present both sides with the emitted-C evidence.

- [ ] **Step 4: Gate-impact analysis**

`json_parser` IS a hard MD5 gate (`066c9997…`). Any B2 fix changing its emitted C → operator re-baseline ruling required at the STOP. If compiler-side, assess whether OTHER gates (gol/lisp/mud) contain the same mis-lowered for-index pattern. If example-side, the fix is in example source only but still changes the emitted C of the example → re-baseline ruling still required.

- [ ] **Step 5: Write report + STOP**

Write `.superpowers/sdd/task-B-I2-report.md`: quirk reproduction, for-index trace + emitted C evidence with file:line, verdict with reasoning, gate-impact note (mandatory re-baseline flag). Verify `git status` clean. Return status + one-line summary.

---

### Task C-I1: Code-reuse audit — Frontend/parse cluster

**Files:**
- Audit: `sf/src/lexer.zig`, `sf/src/parser.zig`, `sf/src/token.zig`, `sf/src/ast.zig`
- Report: `.superpowers/sdd/task-C-I1-report.md`

**Interfaces:**
- Consumes: cluster module list + audit rubric (below).
- Produces: per-cluster duplication catalog + ranked consolidation candidates.

- [ ] **Step 1: Catalog duplicated logic**

For each module in the cluster, identify repeated patterns: repeated token/position advancement, repeated `parserExpect`/peek idioms, repeated node-construction (`astStoreAddNode` call shapes), repeated switch/`else` structures. List each with `file:line` (both occurrences).

- [ ] **Step 2: Catalog helper-consolidation opportunities**

Identify near-identical local helpers across the 4 modules that could be consolidated into `sf/src/util/` or an existing shared module (e.g. two modules implementing the same peek/advance/skip pattern, duplicated `isDigit`-style predicates). List candidates with `file:line`.

- [ ] **Step 3: Catalog duplicate allocations**

Identify repeated alloc/grow/reset patterns and double-buffering (e.g. re-allocating a buffer that a sibling module also holds). Note the prior memory work (`sandReallocInPlace`, MapInitCap, pre-size) — flag any spot that still double-allocates.

- [ ] **Step 4: Rank + byte-identity risk**

Rank candidates by reuse benefit ÷ refactor risk. For each, note whether a refactor preserves emitted-C byte-identity (STOP-flag any that would change MD5 gates).

- [ ] **Step 5: Write report + STOP**

Write `.superpowers/sdd/task-C-I1-report.md`. Verify `git status` clean. Return status + one-line summary.

---

### Task C-I2: Code-reuse audit — Module/import cluster

**Files:**
- Audit: `sf/src/import_resolver.zig`, `sf/src/module_registry.zig`, `sf/src/source_manager.zig`, `sf/src/string_interner.zig`
- Report: `.superpowers/sdd/task-C-I2-report.md`

Same audit rubric as C-I1 (Steps 1-5), applied to this cluster. Pay attention to: `joinPath`/`normalizePath` usage (is normalization duplicated or centralized? `util/path.zig` vs `module_registry.zig`), interner-vs-source-manager string handling, module-entry-vs-import-queue duplication, and any duplicate `readFile`/hash patterns (the resolve-time content-hash dedup from `8e492d90`).

---

### Task C-I3: Code-reuse audit — Semantic cluster

**Files:**
- Audit: `sf/src/semantic_analyzer.zig`, `sf/src/analyzer.zig`, `sf/src/semantic.zig`, `sf/src/coercion.zig`, `sf/src/const_alias_prepass.zig`
- Report: `.superpowers/sdd/task-C-I3-report.md`

Same rubric as C-I1 (Steps 1-5). Pay attention to: the duplicated bare-ident resolution patterns (the fallback-demotion 4-site fix `5c1e17e4`/`1c588c9d` — are resolve-lookups now routed through one helper or still hand-duplicated?), `registerLocalDecl`/local-decl bookkeeping duplication across sema + lowerer, coercion vs constraint-checker overlap, and `semantic.zig` vs `semantic_analyzer.zig` duplication.

---

### Task C-I4: Code-reuse audit — Type system cluster

**Files:**
- Audit: `sf/src/type_resolver.zig`, `sf/src/type_registry.zig`, `sf/src/resolved_type_table.zig`, `sf/src/symbol_table.zig`, `sf/src/symbol_registrator.zig`
- Report: `.superpowers/sdd/task-C-I4-report.md`

Same rubric as C-I1 (Steps 1-5). Pay attention to: name_cache vs symbol-table lookup duplication, `(module_id<<32)|name_id` key arithmetic repeated across modules (could be a shared helper), type-id/type-db map access patterns, and resolved-type-table vs type-registry overlap.

---

### Task C-I5: Code-reuse audit — Lowering cluster

**Files:**
- Audit: `sf/src/lower.zig`, `sf/src/lir.zig`, `sf/src/comptime_eval.zig`, `sf/src/constraint_checker.zig`, `sf/src/state_map.zig`
- Report: `.superpowers/sdd/task-C-I5-report.md`

Same rubric as C-I1 (Steps 1-5). Pay attention to: repeated temp-allocation idioms (`LirFunction` list growth, `hoisted_temps`), the `bindOptionalCapture`/optional-conversion patterns now duplicated across if_stmt/if_expr/while/catch (`b33f412a` added a second copy — consolidation candidate), comptime-fold vs runtime-path duplication, and `state_map.zig` vs `growable_array.zig` overlap.

---

### Task C-I6: Code-reuse audit — Emission cluster

**Files:**
- Audit: `sf/src/c89_emit.zig`, `sf/src/name_mangler.zig`, `sf/src/c89_types.zig`, `sf/src/assign_helper.zig`, `sf/src/print_decomposition.zig`, `sf/src/cinclude.zig`
- Report: `.superpowers/sdd/task-C-I6-report.md`

Same rubric as C-I1 (Steps 1-5). Pay attention to: repeated C-string/identifier emission idioms, the `#ifdef`-arm patterns (socketSelect `b19562a4`-era arms), mangler-vs-emitter naming duplication, assign-helper vs emission-assignment patterns, and the `print`/`printInt` decomposition paths.

---

### Task C-I7: Code-reuse audit — Infra/util cluster

**Files:**
- Audit: `sf/src/allocator.zig`, `sf/src/growable_array.zig`, `sf/src/diagnostics.zig`, `sf/src/config.zig`, `sf/src/panic.zig`, `sf/src/util/*.zig` (`hash.zig`, `itoa.zig`, `mem.zig`, `path.zig`, `sort.zig`, `util.zig`, `format.zig`, `growable_array.zig`, `diagnostic_sort.zig`)
- Report: `.superpowers/sdd/task-C-I7-report.md`

Same rubric as C-I1 (Steps 1-5). Pay attention to: `sf/src/growable_array.zig` vs `sf/src/util/growable_array.zig` duplication, `itoa` vs `format` number-formatting overlap, hash-map instantiation boilerplate (`U32ToU32Map`/`U32ToU64Map`/`U64ToU32Map` init/grow duplication), panic-vs-diagnostics reporting paths, and `allocator.zig` grow/reset patterns.

---

### Task STOP: Consolidated findings — operator ruling

**Files:**
- Read: all 12 I reports (`.superpowers/sdd/task-A-I1-report.md` … `.superpowers/sdd/task-C-I7-report.md`)
- Write: `.superpowers/sdd/consolidated-STOP-report.md`

**Interfaces:**
- Consumes: all I-task reports.
- Produces: the operator's rulings that fill the F placeholders.

- [ ] **Step 1: Read all 12 I reports**

Read every `.superpowers/sdd/task-*-report.md` from A-I1 through C-I7. Summarize each verdict (root cause, fix design, cascade, byte-identity, gate impact).

- [ ] **Step 2: Present consolidated findings to the operator**

Present, one section per workstream:
- **A (3 parser gaps):** verified locus + fix design + parser-only-vs-cascade verdict for each. Ask: approve the sketch fixes as-is, or adjust?
- **B (2 example quirks):** root-cause verdict (compiler vs example source) + fix design for each. Ask: approve; and **mandatory** json_parser MD5 re-baseline ruling if the fix changes its emitted C.
- **C (7 code-reuse audits):** the ranked consolidation candidates per cluster. Ask: which consolidations to pursue, in what order (likely a follow-up plan), and whether any are byte-identity-risky.

- [ ] **Step 3: Record the rulings in the plan**

Edit `docs/superpowers/plans/2026-08-17-parser-gaps-code-reuse-plan.md` to fill A-F1..A-F3, B-F1..B-F2, and the approved C-F consolidation tasks with full details (files, exact edits, test steps, commit) per the operator's rulings. Mark each filled task's source in the plan (`RULED by operator, DATE`).

- [ ] **Step 4: Write the consolidated STOP report**

Write `.superpowers/sdd/consolidated-STOP-report.md` recording the findings summary + operator rulings. Return status.

---

### Task A-F1: Fix discard-capture `if (x) |_|` *(PLACEHOLDER — fill from STOP ruling)*

**Files:** Modify `sf/src/parser.zig` (if-stmt + if-expr capture-name acceptance), possibly more per A-I1 cascade verdict.

**Interfaces:**
- Consumes: A-I1 report + STOP ruling.
- Produces: parser accepts `|_|` capture; repro GREEN.

- [ ] **Step 1: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 2: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 3: (FILLED BY STOP)** — *[written after operator ruling]*

---

### Task A-F2: Fix bare array type as expression *(PLACEHOLDER — fill from STOP ruling)*

**Files:** Modify `sf/src/parser.zig` (array-literal no-`{` branch), possibly more per A-I2 cascade verdict.

**Interfaces:**
- Consumes: A-I2 report + STOP ruling.
- Produces: `const Buf = [10]u8;` parses; repro GREEN.

- [ ] **Step 1: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 2: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 3: (FILLED BY STOP)** — *[written after operator ruling]*

---

### Task A-F3: Fix trailing comma in fn-call args *(PLACEHOLDER — fill from STOP ruling)*

**Files:** Modify `sf/src/parser.zig` (`parserParseFnCall` arg loop), possibly more per A-I3 cascade verdict.

**Interfaces:**
- Consumes: A-I3 report + STOP ruling.
- Produces: trailing-comma fn-call parses; repro GREEN.

- [ ] **Step 1: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 2: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 3: (FILLED BY STOP)** — *[written after operator ruling]*

---

### Task B-F1: Fix `days_in_month` quirk *(PLACEHOLDER — fill from STOP ruling)*

**Files:** Per B-I1 verdict — `examples/z98/days_in_month/main.zig` and/or compiler file(s) per the root-cause decision.

**Interfaces:**
- Consumes: B-I1 report + STOP ruling.
- Produces: `days_in_month` renders decimal month/day numbers.

- [ ] **Step 1: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 2: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 3: (FILLED BY STOP)** — *[written after operator ruling]*

---

### Task B-F2: Fix `json_parser` object-comma quirk *(PLACEHOLDER — fill from STOP ruling)*

**Files:** Per B-I2 verdict — `examples/z98/json_parser/main.zig` and/or compiler file(s) per the root-cause decision.

**Interfaces:**
- Consumes: B-I2 report + STOP ruling (incl. json MD5 re-baseline if required).
- Produces: object fields print with comma separators.

- [ ] **Step 1: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 2: (FILLED BY STOP)** — *[written after operator ruling]*
- [ ] **Step 3: (FILLED BY STOP)** — *[written after operator ruling]*

---

### Task C-F: Code-reuse consolidations *(PLACEHOLDER — fill from STOP ruling)*

**Files:** Per the operator's approved consolidation candidates from the 7 C-I audits.

**Interfaces:**
- Consumes: C-I1..C-I7 reports + STOP ruling (which candidates, in what order).
- Produces: approved helper consolidations implemented, byte-identity preserved.

- [ ] **Step 1: (FILLED BY STOP)** — *[written after operator ruling — likely a follow-up plan]* 
- [ ] **Step 2: (FILLED BY STOP)** — *[written after operator ruling — likely a follow-up plan]*
- [ ] **Step 3: (FILLED BY STOP)** — *[written after operator ruling — likely a follow-up plan]*

---

### Task GATE: Final sweep + reconciliation

**Files:**
- Read: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Modify (if gate numbers moved): `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: all completed F tasks.
- Produces: verified gates + reconciled docs.

- [ ] **Step 1: Rebuild + reinstall std**

`bash sf/scripts/build_release.sh` → `=== [release] Done: /tmp/fx_subfolder/zig1 ===`, then `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.

- [ ] **Step 2: Run the 4 MD5 gates**

Single-file `--dump-c89` | `md5sum` on gol/lisp/json/mud. Expected: byte-identical to the Global Constraints baselines, UNLESS the STOP ruling re-baselined (then record the new values + runtime-identity proof per AMENDMENT B precedent).

- [ ] **Step 3: Run the corpus gate (per-module recipe)**

For each `repro/mi_matrix/*/main.zig`: `--dump-c89 --output-dir DIR` then gcc each `.c`. Classify by gcc exit code (ICE regex `error\[(48|3042|9001|3043)\]|AddressSanitizer`; GG = `error[3000]` + 0 `.c`; FAIL = 0 `.c` with other error). Expected: 255 dirs `OK=249/FAIL=2/ICE=0/CRASH=0/GG=4`. The 3 parsergap repros must now be OK (A-F1..A-F3) or remain RED-only-if-ruled-deferred.

- [ ] **Step 4: 21-example matrix + test_analyzer**

All 21 `examples/z98/` dump/gcc/link rc=0 (mud rc=124; rogue_mud boots+exits). `test_analyzer_bin` = "5 passed, 4 failed". Re-check `days_in_month` and `json_parser` runtime output per the B fixes.

- [ ] **Step 5: Self-compile progress re-check**

`mkdir -p /tmp/sc && timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` — record how far it progresses vs `de630979` baseline (cinclude.zig:23, lower.zig:2283, main.zig:759 were the pre-fix blockers; A-F1/A-F2/A-F3 should clear them). Even if a new pre-existing gap appears, record it; do NOT expand scope.

- [ ] **Step 6: Reconcile docs + commit**

If any gate number moved, update `EXPECTED_FAIL.md` (version bump + closeout entry) and `QUICK_REF.md` (corpus/MD5 lines) to the measured values. Commit all F-task + gate changes with a summary message listing the tasks included.
