# Parser-Gaps Corrections & Self-Compile Blocker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the 6 execution gaps from the parser-gaps plan whole-branch review (many_ptr registration, A-F3 strict diagnostics, B-F1 specifier validation, B-F2 Site B, self-compile blocker pin+fix, EXPECTED_FAIL json pointer) — repro-first, I-first for low-confidence items.

**Architecture:** Phase R creates 5 RED repros (one per issue). Phase I investigates the 3 low-confidence items (specifier validation, Site B, self-compile blocker) → one STOP → rulings. Phase F implements per ruling (2 confident fixes go straight through). Phase GATE sweeps + reconciles docs.

**Tech Stack:** Z98 self-hosted compiler `zig1` (Z98 source, emits C89); zig0 C++98 bootstrap; gcc C89 link. No external deps.

## Global Constraints

- Z98 dialect: NO `anytype`, NO `@Type`. Use `fastedit`/`edit` ONLY for file edits (no sed/python/awk).
- `sf/build/out_release/` WEDGED — NEVER touch/ls/build into it; always use `timeout`.
- Compiler under test = `/tmp/fx_subfolder/zig1`. Build via `bash sf/scripts/build_release.sh`, gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===` (wipes /tmp/fx_subfolder; reinstall std after every rebuild: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`).
- Byte-identity is the hard gate unless an operator ruling re-baselines. Baselines: gol `9cf758d96f25d41980379564a5501bc8`, lisp `524d2872daefb2677c8ddc1ac8f34cf5`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus (258 dirs): OK=252/FAIL=2/ICE=0/CRASH=0/GG=4 expected; new repros flip FAIL→OK as fixed. Corpus recipe MUST be per-module (`--dump-c89 --output-dir DIR` then gcc each .c).
- 21-example matrix 21/21; test_analyzer_bin "5 passed, 4 failed".
- NO scope creep beyond the six spec items. Every F task passes its repro RED→GREEN + all gates before commit.
- Operator rulings: (1) Site B in scope; (2) invalid Zig specifier = compile error.

---

### Task R1: Repro `parsergap_many_ptr_xmod` (RED `error[3000]`)

**Files:**
- Create: `repro/mi_matrix/parsergap_many_ptr_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec §3.R1; A-F2 context (array_type/slice_type now register as `type_alias`; many_ptr does not).
- Produces: RED baseline proving `const P = [*]u8;` still hits spurious `error[3000]` at use; gate for F1.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/parsergap_many_ptr_xmod/main.zig`:
```zig
const std = @import("std");
const P = [*]u8;
pub fn main() void {
    var arr: [4]u8 = .{ 1, 2, 3, 4 };
    var q: P = @ptrCast(P, &arr);
    std.io.printInt(@intCast(i32, q[0]));
}
```
Controls (must stay GREEN): `const A = [10]u8;` and `const S = []const u8;` annotated uses.

- [ ] **Step 2: Run RED baseline**

```
cd repro/mi_matrix/parsergap_many_ptr_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: `rc=2`, `error[3000]: cannot declare variable of type void` (or the closest current message) at the `P` use; 0-byte `/tmp/x.c`. Record exact output in NOTES.md.

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/parsergap_many_ptr_xmod
git commit -m "repro: many_ptr type alias spurious error[3000] (parsergap_many_ptr_xmod)"
```

---

### Task R2: Repro `parsergap_strict_comma_xmod` (A-F3 diagnostic regression)

**Files:**
- Create: `repro/mi_matrix/parsergap_strict_comma_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec §3.R2; A-F3 context (loop-top mirror silently accepts malformed calls).
- Produces: RED baseline showing `f(1 2)` and `f(1` are SILENT today; gate for F2.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/parsergap_strict_comma_xmod/main.zig`:
```zig
const std = @import("std");
fn f(a: i32, b: i32) i32 { return a + b; }
pub fn main() void {
    var r1 = f(1 2);
    std.io.printInt(r1);
}
```
Plus a second fixture variant (or a second file/comment) for the unterminated case `f(1`. NOTES.md documents BOTH cases and the *expected* post-fix behavior (compile error).

- [ ] **Step 2: Run baseline**

```
cd repro/mi_matrix/parsergap_strict_comma_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: **rc=0** (SILENT — the A-F3 regression; `.c` emitted, gcc may or may not fail). Record the silent-success observation as the RED. Then note the expected post-fix RED: `error[2000] expected ','`.

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/parsergap_strict_comma_xmod
git commit -m "repro: fn-call missing-comma silently accepted (parsergap_strict_comma_xmod)"
```

---

### Task R3: Repro `parsergap_specifier_xmod` (B-F1 invalid specifier)

**Files:**
- Create: `repro/mi_matrix/parsergap_specifier_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec §3.R3; B-F1 context (specifier char captured blindly at lower.zig:549-556).
- Produces: RED baseline showing invalid specifiers silently degrade; gate for F3.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/parsergap_specifier_xmod/main.zig`:
```zig
const std = @import("std");
pub fn main() void {
    var v: u8 = 65;
    std.io.print("{x}\n", .{v});
}
```
NOTES.md documents: invalid specifier `{x}` (also test `"{} {}"` space specifier) silently degrades today; expected post-fix = compile error per operator ruling. Controls: `{d}`, `{c}`, `{}` all GREEN.

- [ ] **Step 2: Run baseline**

```
cd repro/mi_matrix/parsergap_specifier_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Expected: **rc=0** (silent degrade today — `{x}` treated as fmt char but only `'c'` is special, so u8 degrades to decimal). Record the silent-success as the RED (expected post-fix = error).

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/parsergap_specifier_xmod
git commit -m "repro: invalid print specifier silently degraded (parsergap_specifier_xmod)"
```

---

### Task R4: Repro `parsergap_shadow_local_xmod` (B-F2 Site B root cause)

**Files:**
- Create: `repro/mi_matrix/parsergap_shadow_local_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec §3.R4; B-I2 context (LDS scan lower.zig:2066-2086 forward-scans, breaks on FIRST/outermost match).
- Produces: RED baseline showing a general shadowed local mis-resolves; gate for F4.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/parsergap_shadow_local_xmod/main.zig` — a general shadowing (NOT for-index), where an outer `var x` shadows an inner `var x`, and a use inside the inner scope must resolve INNER:
```zig
const std = @import("std");
pub fn main() void {
    var x: i32 = 1;
    {
        var x: i32 = 2;
        std.io.printInt(x);
    }
    std.io.printInt(x);
}
```
Expected CORRECT output: `2` then `1`. Today (RED): verify whether it prints `1` then `1` (outer resolution) — record actual.

- [ ] **Step 2: Run baseline**

```
cd repro/mi_matrix/parsergap_shadow_local_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x && /tmp/x
```
Record actual output. If the compiler already handles plain block-shadowing correctly (because the LDS scan only misfires in specific shapes), adjust the fixture to a construct that DOES mis-resolve (document the exploration in NOTES.md — this is the Site B repro, it must reproduce the bug). If no general-local shape reproduces, escalate to the STOP that the Site B repro is the json for-index case itself (already proven).

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/parsergap_shadow_local_xmod
git commit -m "repro: shadowed local resolution (parsergap_shadow_local_xmod)"
```

---

### Task R5: Pin the self-compile `error[2000]` blocker + minimal repro

**Files:**
- Create: `repro/mi_matrix/parsergap_selfblok_xmod/{main.zig, NOTES.md}` (name TBD by finding)

**Interfaces:**
- Consumes: spec §3.R5; GATE context (self-compile aborts; the `type_resolver.zig:981` attribution is a marker-trace approximation).
- Produces: the actual parser-rejected construct pinned + a minimal RED fixture; input to I-SELFBLOK.

- [ ] **Step 1: Reproduce + isolate the root error**

Run self-compile, filter `error[9999]` noise:
```
timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig 2>/tmp/sc.err >/dev/null; grep -v "error\[9999\]" /tmp/sc.err | head -40
```
Identify the FIRST non-9999 `error[2000]` root and its file:line. (Known candidates already hit in prior runs: cinclude.zig:23 `if (x) |_|`; lower.zig:2283 array-type cascade; main.zig:759 trailing comma — all fixed by A-F1/A-F2/A-F3. The remaining root is the UNPINNED one.)

- [ ] **Step 2: Reduce to a minimal fixture**

Extract the minimal construct that reproduces the same `error[2000]` into `repro/mi_matrix/parsergap_selfblok_xmod/`. Record RED baseline + control in NOTES.md.

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/parsergap_selfblok_xmod
git commit -m "repro: self-compile blocker <construct> (parsergap_selfblok_xmod)"
```

---

### Task I-SPECIFIER: Investigate specifier-validation locus (F3) — READ-ONLY

**Files:**
- Read: `sf/src/lower.zig` (`lowerPrintFmt` :522-576, `SemanticContext` :77-89, print-lowering dispatch :2436), `sf/src/print_decomposition.zig` (whole), `sf/src/semantic_analyzer.zig` (diag usage pattern), `sf/src/main.zig` (lowerer init + `source_file_id` availability), `sf/src/diagnostics.zig` (ErrorCode enum + `diagnosticCollectorAdd` signature).

**Interfaces:**
- Consumes: spec §4.I-SPECIFIER; R3 fixture.
- Produces: exact fix design for F3 (validation locus + error code + diag/source_file_id threading) + gate impact. No source changes, no commits.

- [ ] **Step 1: Enumerate error-reporting options**

`ctx.diag` is available (SemanticContext lower.zig:83) but `source_file_id` is NOT in SemanticContext. Determine: (a) what must be threaded into SemanticContext (field + init-site in main.zig), (b) whether a node-index-based span is usable for `diagnosticCollectorAdd`, or (c) whether validation belongs in the semantic analyzer (already has diag + source_file_id) instead of the lowerer.

- [ ] **Step 2: Specify the exact error code + message**

Check `ErrorCode` enum in diagnostics.zig for an existing fit (e.g. ERR_0001-style or a new code). Specify the diagnostic message and level. Confirm no gate uses invalid specifiers → all 4 MD5s stay byte-identical.

- [ ] **Step 3: Write the report**

Report to `.superpowers/sdd/task-I-SPECIFIER-report.md`: exact fix design, code choice, threading detail, gate impact, blast radius. `git status` clean.

---

### Task I-SITEB: Investigate shadow-resolution blast radius (F4) — READ-ONLY

**Files:**
- Read: `sf/src/lower.zig` (LDS scan :2066-2086, `findLocalTemp` :1188-1196, `addLocalDecl` + `local_decl_scopes`, `maybeDisambiguateCapture` :638-659, `capture_shadow` get sites :793, :1899 + reset sites), corpus + examples + self-compile closure for shadowing patterns.

**Interfaces:**
- Consumes: spec §4.I-SITEB; R4 fixture; B-I2 report.
- Produces: exact fix design for F4 (scan direction + scope filter, capture_shadow scope-gate) + corpus/gate impact projection. No source changes, no commits.

- [ ] **Step 1: Fix-shape determination**

Confirm the minimal change: reverse the LDS scan (li from count→0), apply `self.local_decl_scopes[li] <= self.scope_depth`, break on innermost match — mirroring `findLocalTemp`. Determine whether the block can delegate to a shared helper (extract the loop) vs inline reversal. Preserve the existing markers (LDS/A3R output) or note their shift.

- [ ] **Step 2: Blast radius**

Enumerate all local-name shadowing patterns in corpus (grep repro/mi_matrix for nested same-name decls), examples, and self-compile closure that hit the LDS scan. For each candidate, classify: fixes-correctly / changes-output (re-baseline needed) / no-effect. Project which of the 4 MD5 gates move.

- [ ] **Step 3: capture_shadow scope-gating**

Quantify the function-wide remap blast radius (lower.zig:793, :1899). Specify the scope-gate design (per-scope vs reset-point) and its interaction with Site A (index disambiguation).

- [ ] **Step 4: Write the report**

Report to `.superpowers/sdd/task-I-SITEB-report.md`: fix design, blast-radius table, gate projection, capture_shadow design. `git status` clean.

---

### Task I-SELFBLOK: Investigate the pinned self-compile construct (F5) — READ-ONLY

**Files:**
- Read: the R5 fixture + its locus; `sf/src/parser.zig` (the rejecting parse path); `sf/src/semantic_analyzer.zig` + `sf/src/lower.zig` (cascade check).

**Interfaces:**
- Consumes: spec §4.I-SELFBLOK; R5 fixture.
- Produces: exact fix design for F5 (parser-only vs cascade) + gate impact. No source changes, no commits.

- [ ] **Step 1: Trace the rejection**

From the R5 minimal fixture, trace the exact parse rejection to its locus. Confirm whether it is parser-only (like A-F1/A-F3) or a cascade (like A-F2) — the A-I2 lesson.

- [ ] **Step 2: Fix design + gate impact**

Specify the exact fix (file:line + code sketch) and confirm byte-identity for all 4 MD5 gates.

- [ ] **Step 3: Write the report**

Report to `.superpowers/sdd/task-I-SELFBLOK-report.md`: locus, parser-only vs cascade, exact fix design, gate impact. `git status` clean.

---

### Task STOP: Consolidated ruling — COMPLETE (rulings 2026-08-18)

- [x] Findings from R1-R5 + I-SPECIFIER + I-SITEB + I-SELFBLOK presented to the operator.
- [x] **Operator rulings obtained:**
  - **F3 (specifier validation locus):** Option **a** — thread `source_file_id` into `SemanticContext`, validate in `lowerPrintFmt`, new `ERR_3013_INVALID_PRINT_SPECIFIER`.
  - **F4 (Site B blast radius):** implement the I-SITEB outA fix (max-scope LDS + shadowed-var C-name synth + switch-prong scope gate). **lisp re-baseline APPROVED if runtime-identical** (`524d2872…→88dcb7f9…` projected; runtime proof required at F4 Step 4).
  - **F5 (self-compile blocker):** Option **A** — parse brace-less if then/else bodies as **statements** (mirror zig0 `parseStatement`), giving correct nearest-if binding. NOT the Option-B lookahead.
- [x] F3/F4/F5 task placeholders filled from the I reports + rulings (see amended tasks below).
- [x] Commit the plan amendment documenting the rulings.

---

### Task F1: many_ptr type-alias registration — CONFIDENT

**Files:**
- Modify: `sf/src/symbol_registrator.zig` (registerDecl init-kind switch, currently `:284`)

**Interfaces:**
- Consumes: R1 fixture; A-I2/A-F2 context (array_type|slice_type → type_alias branch).
- Produces: `const P = [*]u8;` registers `type_alias`; R1 prints correct value rc=0.

- [ ] **Step 1: Reproduce RED baseline (R1)** — record current `rc=2` + error.
- [ ] **Step 2: Implement the fix**

In `symbol_registrator.zig:284`, extend the branch:
```zig
} else if (init_node.kind == AstKind.array_type or init_node.kind == AstKind.slice_type or init_node.kind == AstKind.many_ptr_type) {
```
(ast.zig:87 `many_ptr_type = 85`; downstream already handles it: type_resolver.zig:922, semantic_analyzer.zig:1561, varDeclInitNeedsNameCache returns true.)

- [ ] **Step 3: Build + GREEN verify**

`bash sf/scripts/build_release.sh` → gate; reinstall std. R1 repro: `rc=0`, gcc rc=0, run prints correct value. Controls (`const A = [10]u8;`, `const S = []const u8;`) unchanged GREEN.

- [ ] **Step 4: Byte-identity gates**

4 MD5s byte-identical (gol/lisp/json/mud baselines).

- [ ] **Step 5: Commit**

```bash
git commit -m "fix: register many_ptr_type const as type alias (parsergap_many_ptr_xmod)"
```
Report to `.superpowers/sdd/task-F1-report.md`.

---

### Task F2: Restore strict fn-call arg diagnostics — CONFIDENT

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseFnCall` arg loop, currently `:401-407`)

**Interfaces:**
- Consumes: R2 fixture; A-I3 report §3 (minimal second-rparen-break variant).
- Produces: `f(1 2)` → `error[2000] expected ','`; `f(1` → error; `f(1,2,)` trailing comma still GREEN; R2 fixture expected-RED now errors.

- [ ] **Step 1: Reproduce baseline (R2)** — record current silent-success.
- [ ] **Step 2: Implement the strict fix**

Replace the loop-top mirror at `parser.zig:401-407` with the second-`rparen`-break variant that preserves strict comma checking:
```zig
var saved_fncall: usize = self.child_buf_len;
while (true) {
    var arg = try parserParseExprPrec(self, Prec.none);
    u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
    if (parserPeek(self).kind == TokenKind.rparen) break;
    _ = try parserExpect(self, TokenKind.comma);
    if (parserPeek(self).kind == TokenKind.rparen) break;
}
var rparen = try parserExpect(self, TokenKind.rparen);
```
This restores `expected ','` for `f(1 2)`, errors on unterminated `f(1` (parserExpect rparen fails), and still accepts trailing comma `f(1,2,)` (second break fires after the comma).

- [ ] **Step 3: Build + GREEN verify**

Rebuild + reinstall std. R2 fixture: `f(1 2)` → `rc=2` `error[2000]`; unterminated `f(1` → `rc=2`. Control `f(1,2,)` trailing comma → `rc=0` GREEN. Full corpus: 3 parsergap repros (discard_if/array_type/trailing_comma) stay OK.

- [ ] **Step 4: Byte-identity gates**

4 MD5s byte-identical.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix: restore strict comma/close diagnostics in fn-call args (parser)"
```
Report to `.superpowers/sdd/task-F2-report.md`.

---

### Task F3: Specifier validation → compile error — per I-SPECIFIER (Option a: threaded lowerer + ERR_3013)

**Files:**
- Modify: `sf/src/lower.zig` (`lowerPrintFmt` :522-576 + `SemanticContext` :77-89), `sf/src/main.zig` (thread `source_file_id` into SemanticContext init :639/:695)
- Verify: `sf/src/diagnostics.zig` (`diagnosticCollectorAdd` :263, ErrorCode enum — new `ERR_3013_INVALID_PRINT_SPECIFIER`)

**Interfaces:**
- Consumes: I-SPECIFIER report + operator ruling (Option a — thread `source_file_id` into SemanticContext, validate in `lowerPrintFmt`); R3 fixture.
- Produces: invalid specifier → compile error `error[3013]`; `{d}`/`{c}`/`{}`/`{s}` unchanged; R3 expected-RED now errors; 4 MD5s byte-identical.

- [ ] **Step 1: Reproduce RED baseline (R3)** — record current silent-success (rc=0, prints decimal `65`).
- [ ] **Step 2: Implement the fix**

Per I-SPECIFIER report:
1. Add `ERR_3013_INVALID_PRINT_SPECIFIER` to the `ErrorCode` enum in `diagnostics.zig` (no existing fit; 3012 is varargs-specific). Level 0 (error).
2. Thread `source_file_id` into `SemanticContext` (`lower.zig:77-89`): add the field, set it at the `lowererInit` call sites in `main.zig:639/:695`.
3. In `lowerPrintFmt` (`lower.zig:522-576`), after capturing the specifier char at :549-556, validate it: allowed set is `'d'`, `'c'`, `'s'`; empty `{}` → `'d'` (unchanged). On an invalid char, emit the diagnostic via `ctx.diag` (threaded `source_file_id`) using the print-call span, then treat as error. Match the message to NOTES.md's expectation `invalid format specifier`.
4. Boundary: single-arg `print(fmt)` calls (`ec.len < 2`) bypass `lowerPrintFmt` (`lower.zig:2444` guard) — leave unvalidated (documented, out of scope; also the actual mechanism protecting json's `print("{")`/`print("}")`).

- [ ] **Step 3: Build + R3 GREEN (error)**

`bash sf/scripts/build_release.sh` → gate; reinstall std. R3 fixture `{x}`: `rc=2`, `error[3013]`, 0-byte `.c`. Space-specifier `{ }` also errors. Controls `{d}`/`{c}`/`{}` + `{s}` all unchanged GREEN.

- [ ] **Step 4: Byte-identity gates**

4 MD5s byte-identical (gol/lisp/json/mud baselines) — no gate/corpus/example program uses an invalid specifier (I-SPECIFIER blast-radius grep confirmed only `parsergap_specifier_xmod` has one).

- [ ] **Step 5: Commit**

```bash
git commit -m "fix: invalid print specifier is a compile error (parser-gaps followup F3)"
```
Report to `.superpowers/sdd/task-F3-report.md`.

---

### Task F4: Site B — max-scope LDS + shadowed-var C-name synth + switch-prong scope gate — per I-SITEB

**Files:**
- Modify: `sf/src/lower.zig` — LDS scan :2066-2086 (max-scope first-tie), shadowed-var C-name synthesis :4606-4638, switch-prong scope gate :3716-3723

**Interfaces:**
- Consumes: I-SITEB report + operator ruling; R4 fixture.
- Produces: shadowed locals resolve innermost; R4 GREEN (prints `2` then `1`); **lisp gate re-baselined `524d2872…→88dcb7f9…` under operator ruling (runtime-identical proof required)**; gol/mud/json stay byte-identical.

- [ ] **Step 1: Reproduce RED baseline (R4)** — record current mis-resolution (`22`).
- [ ] **Step 2: Implement the fix** (the empirically-verified `outA` patch from I-SITEB):

1. **LDS scan** (`lower.zig:2066-2086`): change to max-scope scan — iterate `li` from `count→0`, apply `self.local_decl_scopes[li] <= self.scope_depth`, break on the FIRST (i.e. innermost-matching) hit. NOT a plain full reversal (gol breaks on plain reversal — I-SITEB §1.1/§1.4). Keep the LDS/A3R markers or note their shift.
2. **Shadowed-var C-name synthesis** (`lower.zig:4606-4638`): the shadowed decl's C name must be synthesized (distinct slot) — LDS reversal alone fixes reads but still prints `22` because c89_emit dedups `decl_local` by name_id (`c89_emit.zig:2586`) and `assign` prefers `a.name_id` (:3730). Synth the shadowed var's C name so the inner and outer `x` get distinct C slots.
3. **Switch-prong scope gate** (`lower.zig:3716-3723`): the scope filter exposes a pre-existing bug where switch-as-expression captures register at `scope_depth+1` (:3704/:3708) but the prong body is lowered unscoped — gate it or mud/lisp emit `TEMP_NONE` reads.

- [ ] **Step 3: Build + GREEN verify**

`bash sf/scripts/build_release.sh` → gate; reinstall std. R4 fixture: `rc=0`, run prints `2` then `1`. All 4 R4 exploration shapes now correct (block `21`, while-loop `21`, capture `21`, for-index `0120`). gol glider + mud boot runtime-identical to pre-fix.

- [ ] **Step 4: Heavy gate battery** (per operator ruling: re-baseline allowed if runtime-identical)

4 MD5 gates: gol `9cf758d9…`, mud `a1d0dd55…`, json `fc357296…` byte-identical; **lisp `524d2872…` → NEW value (`88dcb7f9…` projected from I-SITEB) with runtime-identity proof (REPL output byte-identical to pre-fix)**. Full corpus (per-module recipe; I-SITEB measured OK=255/FAIL=3/GG=5@263 with selfblok FAIL + many_ptr new GG — record exact), 21-example matrix, test_analyzer. Update QUICK_REF + EXPECTED_FAIL lisp baseline if it moved.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix: innermost local resolution for shadowed vars (Site B)"
```
Report to `.superpowers/sdd/task-F4-report.md`.

---

### Task F5: Self-compile blocker fix — brace-less if then/else parsed as STATEMENT (Option A)

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseIfStmt`, then-body :1515-1520 and else-body :1532)

**Interfaces:**
- Consumes: I-SELFBLOK report + operator ruling (Option A = upstream, mirror zig0); R5 fixture.
- Produces: R5 fixture GREEN (prints `1` rc=0); self-compile passes `type_resolver.zig:981`; **nested brace-less `if (a) if (b) x=1; else y=2;` binds `else` to the INNER if (nearest-if, matching zig0 + Zig)**.

- [ ] **Step 1: Reproduce RED baseline (R5)** — record current `rc=2` error[2000] at the `else`.
- [ ] **Step 2: Implement the fix** (Option A — parse the brace-less then/else bodies as STATEMENTS, mirroring zig0 `parseStatement()` at parser.cpp:2056 which consumes the terminating `;` inside the then-body, then checks `else`):

In `parserParseIfStmt`, change the brace-less then-body branch (:1515-1520) from expression to statement:
```zig
    var then_body: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.lbrace) {
        then_body = try parserParseBlock(self);
    } else {
        then_body = try parserParseStatement(self);
    }
```
and the brace-less else-body branch (:1532) from expression to statement:
```zig
        } else {
            else_node = try parserParseStatement(self);
        }
```
Do NOT add the `then_braced` flag or the `parserPeekN(1)==kw_else` lookahead (the I-SELFBLOK Option-B sketch is superseded by this ruling). Keep the trailing `;` consume (:1535-1537) — it becomes a no-op for brace-less bodies (the statement parser already consumed the `;`) but remains for braced bodies. The `PIF:b` marker line (:1522) stays byte-identical.

Rationale: `parserParseStatement` (:1241-1272) on a plain `x=1;` goes through `parserParseExprStmt` (:1304-1310) which consumes the `;` and returns the same raw expr node as today (downstream AST shape unchanged for expr bodies); on a nested `if` it recurses into `parserParseIfStmt`, so the inner `if` consumes its own `else` — correct nearest-if. Matches zig0's `parseStatement()` (parser.cpp:1925-1986, then-branch via `parseStatement` :2056).

- [ ] **Step 3: Build + GREEN verify**

`bash sf/scripts/build_release.sh` → gate; reinstall std (`cp sf/src/std*.zig /tmp/fx_subfolder/lib/`). R5 fixture: `rc=0`, gcc rc=0, run prints `1`. Nested dangling-else control `if (a) if (b) x=1; else y=2;` → rc=0, else binds inner (prints `2` when b false). 7-form control battery from I-SELFBLOK §5.2 stays GREEN.

- [ ] **Step 4: Byte-identity gates**

4 MD5s byte-identical (gol/lisp/json/mud baselines) — verified in the I-SELFBLOK /tmp/ibuild patched build.

- [ ] **Step 5: Self-compile re-check**

`timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` → the pinned `type_resolver.zig:981` construct passes. The NEXT known gap is `*%` wrapping-multiply at `util/hash.zig:18` (no lexer token) — record but do NOT fix (out of F5 scope).

- [ ] **Step 6: Commit**

```bash
git commit -m "fix: parse brace-less if then/else bodies as statements (parser)"
```
Report to `.superpowers/sdd/task-F5-report.md`.

---

### Task GATE: Final sweep + reconciliation

**Files:**
- Read: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Modify: both (if numbers moved), incl. **F6**: EXPECTED_FAIL historical json `066c9997…` entries get the `→ fc357296…` forward-pointer (matching QUICK_REF's historical treatment).

**Interfaces:**
- Consumes: all completed F tasks + F6 doc pointer.
- Produces: verified gates + reconciled docs.

- [ ] **Step 1:** Rebuild + reinstall std.
- [ ] **Step 2:** 4 MD5 gates (json = `fc357296…` unless F4/F5 re-baselined per ruling, with runtime proof).
- [ ] **Step 3:** Corpus (per-module recipe). New repros (many_ptr, specifier, strict_comma, shadow_local, selfblok) flip FAIL→OK as fixed; record exact counts.
- [ ] **Step 4:** 21-example matrix + test_analyzer + days_in_month/json_parser runtime + self-compile re-check.
- [ ] **Step 5:** Reconcile EXPECTED_FAIL (version bump + closeout) + QUICK_REF (corpus/MD5 lines) + F6 json historical pointer. Commit summary message listing the tasks included.
- [ ] Report `.superpowers/sdd/task-GATE-followup-report.md`.

---

### Final whole-branch review

- [ ] Dispatch the whole-branch review on the range (`754d7ae4`..HEAD) using the requesting-code-review template.
- [ ] Fix findings per the review loop; present completion to the operator.
