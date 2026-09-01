# Parser Gaps & Example Quirks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **OPERATOR RULINGS (2026-08-17):** (1) Workstream C (code-reuse audits) MOVED to a separate plan `docs/superpowers/plans/2026-08-17-code-reuse-consolidation-plan.md`. This plan covers Workstream A (3 parser gaps) + Workstream B (2 example quirks) only. (2) **B-F1 is COMPILER-SIDE** (specifier-driven print dispatch), NOT example-source — due diligence showed `{}`/`{d}`+u8 renders a raw byte, contradicting upstream Zig AND the compiler's own `Design_p2.md:1361` ("integer types → print_int"); the fix parses the specifier and dispatches on specifier+type, leaving all 4 MD5 gates byte-identical (no re-baseline). (3) json_parser is a hard MD5 gate — B-F2's emitted-C change requires re-baselining json `066c9997…`.

> **EXECUTION STATUS (2026-08-17):** All 12 I tasks (A-I1/A-I2/A-I3/B-I1/B-I2 + the 7 C-I audits moved to the code-reuse plan) COMPLETE. Reports at `.superpowers/sdd/task-*-report.md`. A-I1/A-I3 = parser-only; A-I2 = cascade (parser + symbol_registrator); B-I1 = compiler-side per ruling; B-I2 = compiler for-index disambiguation (Site A). Next: fill A-F1..A-F3 + B-F1..B-F2 per the confirmed findings below, then GATE.

**Goal:** Fix 3 parser gaps blocking self-compile completion, resolve 2 example quirks (root-cause-decides, both compiler-side), investigation-first with one consolidated STOP, then fixes and gate sweep.

**Architecture:** Two workstreams (A=3 parser gaps, B=2 example quirks). All I tasks were read-only (reports only, no source changes, no commits). The consolidated STOP gathered operator rulings; the F tasks (A-F1..A-F3, B-F1..B-F2) are now specified from the confirmed I findings and executed, followed by the gate sweep. Code-reuse consolidation is a separate plan.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, parser (`parser.zig`), print lowering (`lower.zig` + `c89_emit.zig`), example sources (`examples/z98/`), repros (`repro/mi_matrix/`), `--dump-c89`, `--markers`, gcc `-m32` build recipe, 4 MD5 gates.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-70) is MANDATORY. Copy exact commands. **Compiler under test is `/tmp/fx_subfolder/zig1`** (NOT `sf/build/out_release/zig1`).
- **`sf/build/out_release/` is WEDGED — any command touching it HANGS; NEVER touch/list/build into it. Use `timeout` on all risky commands.**
- **Build:** `bash sf/scripts/build_release.sh` → gate line `=== [release] Done: /tmp/fx_subfolder/zig1 ===`. **The script wipes `/tmp/fx_subfolder/` (including `lib/`) — reinstall the std lib after every rebuild:** `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top). NO sed/python/bulk transforms.
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps (`U32ToU32Map` etc.); `@intCast` for i32↔usize; no pointer captures; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue.
- **MD5 gate recipe:** single-file `--dump-c89` to stdout piped to `md5sum`. Baselines (unchanged since memory-optimization closure, HEAD `de630979`):
  - gol `9cf758d96f25d41980379564a5501bc8`
  - lisp `524d2872daefb2677c8ddc1ac8f34cf5`
  - json `066c99974f6052317636854dc4c2a2d5` (RE-BASELINED by B-F2 — see below)
  - mud `a1d0dd55aada9c3fd904ae33f54de32e`
- **Baselines to preserve:** corpus 255 dirs `OK=249 / FAIL=2 / ICE=0 / CRASH=0 / GG=4` (FAIL=2 = `field_store_drop` + `self_embed_optional_cycle`; GG=4 = `eu_assign_incompat_payload`, `euvoid_val_catch`, `field_access_optional`, `var_declared_void`). Corpus recipe is **per-module** (`--dump-c89 --output-dir DIR` then gcc each `.c`); the stdout-concat recipe falsely fails `fn_ptr_struct_field`. 21-example matrix 21/21; `test_analyzer_bin` "5 passed, 4 failed".
- **json_parser is a hard MD5 gate.** B-F2 changes its emitted C → json gate re-baseline (`066c9997…`) with runtime-identity proof per AMENDMENT B precedent. gol/lisp/mud unaffected by B-F2 (no for-index collision).

---

### Task A-F1: Fix discard-capture `if (x) |_|` — PARSER-ONLY

**Files:**
- Modify: `sf/src/parser.zig` (if-stmt capture `parserParseIfStmt` previously `:1497-1506`; if-expr capture `parserParseIfExpr` previously `:787-797`)
- Test: `repro/mi_matrix/parsergap_discard_if_xmod` (RED → GREEN)

**Interfaces:**
- Consumes: A-I1 report (`.superpowers/sdd/task-A-I1-report.md`) — verdict: parser-only, mirror switch-prong `:893-897`, both if-stmt AND if-expr paths.
- Produces: parser accepts `|_|` discard capture; repro prints `1` rc=0.

- [ ] **Step 1: Reproduce RED baseline**

```
cd repro/mi_matrix/parsergap_discard_if_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[2000]: expected identifier but found token` at `|_|`, 0-byte `/tmp/x.c`. (May already be verified — record current.)

- [ ] **Step 2: Implement the parser fix**

In `parserParseIfStmt` and `parserParseIfExpr`, after advancing over the leading pipe and BEFORE `parserExpect(TokenKind.identifier)`, accept `TokenKind.underscore`, mirroring the switch-prong pattern (`parser.zig:893-897`):
```zig
if (parserPeek(self).kind == TokenKind.underscore) {
    name_tok = try parserExpect(self, TokenKind.underscore);
} else {
    name_tok = try parserExpect(self, TokenKind.identifier);
}
```
Do NOT disturb the pre-existing debug `markerWrite` instrumentation in `parserParseIfStmt` (A-I1 noted `parser.zig:1478-1493/:1515`). No sema/lower/emit change (A-I1 proved shared discard-agnostic `bindOptionalCapture` at `lower.zig:1257`).

- [ ] **Step 3: Build + GREEN verify**

`bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; reinstall std lib. Re-run the repro: `rc=0`, `.c` emitted, gcc rc=0, run prints `1`. Also run the named-capture control (`|cap|`) — unchanged GREEN.

- [ ] **Step 4: Byte-identity gates**

Single-file `--dump-c89` | `md5sum` on gol/lisp/json/mud → all 4 byte-identical to Global Constraints baselines.

- [ ] **Step 5: Commit + report**

Commit `fix: accept discard capture |_| in if-stmt/if-expr (parser)`. Report to `.superpowers/sdd/task-A-F1-report.md` (files changed, gate results, byte-identity).

---

### Task A-F2: Fix bare array type as expression — CASCADE (parser + symbol_registrator)

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseArrayLiteral` previously `:752-759`), `sf/src/symbol_registrator.zig` (`registerDecl` previously `:236-285`)
- Test: `repro/mi_matrix/parsergap_array_type_xmod` (RED → GREEN)

**Interfaces:**
- Consumes: A-I2 report (`.superpowers/sdd/task-A-I2-report.md`) — verdict: CASCADE, NOT parser-only. The plan's prior "parser-only" premise is FALSE (A-I2 mirror of the F-PARSERGAP lesson).
- Produces: `const Buf = [10]u8;` parses and registers a real type; repro prints `3` rc=0.

- [ ] **Step 1: Reproduce RED baseline**

```
cd repro/mi_matrix/parsergap_array_type_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[2000]: expected '{' after array type`, 0-byte `/tmp/x.c`.

- [ ] **Step 2: Parser fix — no-`{` branch**

In `parserParseArrayLiteral`, after `parserParseBracketType`, if the next token is NOT `{`, return the bracket-type node (`array_type`/`slice_type`) directly instead of erroring:
```zig
var type_node = try parserParseBracketType(self);
if (parserPeek(self).kind != TokenKind.lbrace) return type_node;
// ... existing `{` array-literal body path
```

- [ ] **Step 3: symbol_registrator fix — real type for const type-alias**

Per A-I2: `registerDecl` (`symbol_registrator.zig:236-285`) leaves `const Buf = [10]u8;` as a `global` with `type_id 0`, so sema `ResolveIdent` (`semantic_analyzer.zig:280-284`) resolves the `Buf` annotation to `TYPE_VOID` → spurious `error[3000] cannot declare variable of type void`. Fix the type-alias registration so a const whose value is a type (AST `array_type`/`slice_type`/any type node) registers the resolved TypeId instead of leaving `type_id 0`. Follow the A-I2 report's exact design. Verify the latent lowerer site `lower.zig:5375/5383-5384` (no `array_type` handling → default return 0) — address only if A-I2's report requires it for end-to-end correctness.

- [ ] **Step 4: Build + GREEN verify**

Rebuild + reinstall std. Repro: `rc=0`, `.c` emitted, gcc rc=0, run prints `3`. Confirm the spurious `error[3000]` is gone.

- [ ] **Step 5: Byte-identity gates + control sweeps**

4 MD5s byte-identical. Confirm controls unchanged GREEN: `var b: [10]u8 = undefined;`, `var s: []const u8 = "abc";`, `[10]u8{1,2,3}`.

- [ ] **Step 6: Commit + report**

Commit `fix: allow bare array type as const value (parser + type-alias registration)`. Report `.superpowers/sdd/task-A-F2-report.md`.

---

### Task A-F3: Fix trailing comma in fn-call args — PARSER-ONLY

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseFnCall` arg loop previously `:401-407`)
- Test: `repro/mi_matrix/parsergap_trailing_comma_xmod` (RED → GREEN)

**Interfaces:**
- Consumes: A-I3 report (`.superpowers/sdd/task-A-I3-report.md`) — verdict: parser-only; **the plan's sketch snippet is byte-identical to the buggy code** (A-I3 correction). Use the corrected design.
- Produces: trailing-comma fn-call parses; repro prints `45` rc=0.

- [ ] **Step 1: Reproduce RED baseline**

```
cd repro/mi_matrix/parsergap_trailing_comma_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[2000]: expected expression` at the trailing comma, 0-byte `/tmp/x.c`.

- [ ] **Step 2: Implement the corrected fix**

Per A-I3, use the array/tuple mirror (loop-top `rparen` check + optional comma) or the minimal second-`rparen`-break variant. Recommended minimal (preserves strict `expected ','` diagnostic for genuinely missing commas):
```zig
// inside the arg loop, after parsing one argument:
if (parserPeek(self).kind == TokenKind.comma) {
    _ = try parserExpect(self, TokenKind.comma);
    if (parserPeek(self).kind == TokenKind.rparen) break;
} else if (parserPeek(self).kind == TokenKind.rparen) {
    break;
} else {
    return error.UnexpectedToken; // or parserExpect comma
}
```
Use the exact form the A-I3 report specifies. No sema/lower change (comma never stored in AST; `semantic_analyzer.zig:786`, `lower.zig:2416` read arg payload only).

- [ ] **Step 3: Build + GREEN verify**

Rebuild + reinstall std. Repro: `rc=0`, `.c` emitted, gcc rc=0, run prints `45`. Control (no trailing comma) unchanged GREEN.

- [ ] **Step 4: Byte-identity gates**

4 MD5s byte-identical.

- [ ] **Step 5: Commit + report**

Commit `fix: accept trailing comma in fn-call args (parser)`. Report `.superpowers/sdd/task-A-F3-report.md`.

---

### Task B-F1: Fix `days_in_month` u8 `{}` — COMPILER-SIDE (specifier-driven print dispatch)

**Files:**
- Modify: `sf/src/lower.zig` (`lowerPrintFmt` — parse specifier into `.fmt`; currently hardcodes `'d'` at `:549`), `sf/src/c89_emit.zig` (`getPrintFnName` `:3180-3190` — dispatch on specifier+type; and/or `.print_val` emission `:5111-5130`)
- Verify (no change): `examples/z98/days_in_month/main.zig`, `examples/z98/game_of_life/main.zig` (`{c}`+u8 must stay raw byte)
- Test: `examples/z98/days_in_month` (runtime output decimal)

**Interfaces:**
- Consumes: B-I1 report (`.superpowers/sdd/task-B-I1-report.md`) + operator ruling (compiler-side).
- Produces: `{}`/`{d}`+u8 → decimal (`std_print_u32`), `{c}`+u8 → char (`std_print_char`); `days_in_month` renders decimal months/days; all 4 MD5 gates byte-identical (no re-baseline).

- [ ] **Step 1: Reproduce the quirk**

Build + run `examples/z98/days_in_month`. Confirm raw-byte rendering (`cat -A` shows `^A`..`^L` month bytes).

- [ ] **Step 2: Implement specifier parsing in `lowerPrintFmt`**

In `sf/src/lower.zig:522-576`, parse the specifier character between `{` and `}` and store it in `.fmt` (currently hardcoded `'d'` at `:549`). Empty `{}` → `'d'` (default decimal for ints). Preserve all `print_str` segment emission exactly.

- [ ] **Step 3: Dispatch on specifier+type in `getPrintFnName`**

In `sf/src/c89_emit.zig:3180-3190`, pass the `.fmt` char into the type→helper dispatch:
- `{c}` + `u8` → `std_print_char` (raw byte — gol's `{c}`-with-u8 must stay raw byte)
- `{}`/`{d}` + `u8` → `std_print_u32` (decimal — fixes days_in_month)
- all other types unchanged (u32→`std_print_u32`, i32→`std_print_i32`, slice→`std_print_str`, etc.)

Check the `.print_val` emission at `c89_emit.zig:5111-5130` — it currently ignores `p.fmt`; wire it into `getPrintFnName` (or a wrapper).

- [ ] **Step 4: Build + runtime verify**

Rebuild + reinstall std. `days_in_month`: months `1..12`, days decimal. gol runtime still renders the grid correctly (its `{c}`+u8 stays raw byte).

- [ ] **Step 5: Byte-identity gates**

4 MD5s byte-identical (B-I1 already established no gate emits `{}`-with-u8 → no re-baseline).

- [ ] **Step 6: Commit + report**

Commit `fix: specifier-driven print dispatch ({} / {d} + u8 -> decimal, {c} + u8 -> char)`. Report `.superpowers/sdd/task-B-F1-report.md`.

---

### Task B-F2: Fix `json_parser` object commas — compiler for-index disambiguation + json MD5 re-baseline

**Files:**
- Modify: `sf/src/lower.zig` (for-loop index capture `:4328` — disambiguate like element capture `:4327`)
- Re-baseline: `docs/sf/QUICK_REF.md` json MD5 (`066c9997…` → new), `repro/mi_matrix/EXPECTED_FAIL.md`
- Test: `examples/z98/json_parser` (runtime output correct commas)

**Interfaces:**
- Consumes: B-I2 report (`.superpowers/sdd/task-B-I2-report.md`) — verdict: compiler defect, Site A (primary).
- Produces: object fields print comma-separated; json gate re-baselined with runtime-identity proof; gol/lisp/mud byte-identical.

- [ ] **Step 1: Reproduce the quirk**

Run `examples/z98/json_parser` from its dir (test.json in CWD). Confirm object fields lack commas while array elements have them; top-level object has a trailing comma after the last field.

- [ ] **Step 2: Implement Site A fix**

In `sf/src/lower.zig:4328`, run the for-loop INDEX capture name through `maybeDisambiguateCapture` exactly like the element capture at `:4327`:
```zig
addLocalDecl(self, maybeDisambiguateCapture(self, node.child_2, type_mod.TYPE_USIZE), ...)
```
The second loop's `i` becomes `i_1`; object body `i` resolves to the object counter. (Site B — LDS innermost-scan fix in `lower.zig:2058-2078` — is NOT required; Site A is narrower and precedent-matching. Only take Site B if the operator explicitly rules it.)

- [ ] **Step 3: Build + runtime verify**

Rebuild + reinstall std. `json_parser`: object fields now `"status": "alpha",` / `"bugs": null` with comma separators, no trailing comma after last field. Array elements unchanged.

- [ ] **Step 4: Byte-identity + json re-baseline**

- gol/lisp/mud: `--dump-c89` | `md5sum` byte-identical to baselines.
- json: NEW MD5 (emitted C changed). Re-baseline `docs/sf/QUICK_REF.md` json row + `repro/mi_matrix/EXPECTED_FAIL.md` with the new value. **Runtime-identity proof** per AMENDMENT B precedent (the fixed binary's runtime output = correct output; the old json MD5 is a stale reference by definition).

- [ ] **Step 5: Commit + report**

Commit `fix: name-disambiguate for-loop index capture (json_parser object commas)`. Report `.superpowers/sdd/task-B-F2-report.md` incl. old→new json MD5 + runtime proof.

---

### Task GATE: Final sweep + reconciliation

**Files:**
- Read: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Modify (if gate numbers moved): `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: all completed F tasks (A-F1..A-F3, B-F1..B-F2).
- Produces: verified gates + reconciled docs.

- [ ] **Step 1: Rebuild + reinstall std**

`bash sf/scripts/build_release.sh` → gate, then `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.

- [ ] **Step 2: Run the 4 MD5 gates**

gol/lisp/mud byte-identical to baselines; json = new B-F2 re-baselined value.

- [ ] **Step 3: Run the corpus gate (per-module recipe)**

255 dirs expected `OK=249/FAIL=2/ICE=0/CRASH=0/GG=4`. The 3 parsergap repros (discard_if, array_type, trailing_comma) must now be OK (A-F1/A-F2/A-F3).

- [ ] **Step 4: 21-example matrix + test_analyzer + self-compile re-check**

All 21 examples dump/gcc/link rc=0 (mud rc=124; rogue_mud boots+exits). `test_analyzer_bin` = "5 passed, 4 failed". `days_in_month` + `json_parser` runtime correct per B fixes. Self-compile re-check: `timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` — record progress past cinclude.zig:23 / lower.zig:2283 / main.zig:759 (the pre-fix blockers); do NOT expand scope if a new pre-existing gap appears.

- [ ] **Step 5: Reconcile docs + commit**

If any gate number moved, update `EXPECTED_FAIL.md` (version bump + closeout entry) and `QUICK_REF.md` (corpus/MD5 lines). Commit all F-task + gate changes with a summary message listing the tasks included.
