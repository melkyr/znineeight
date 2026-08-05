# Corpus-RED Frontend Gaps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the frontend-gap repros (dump rc!=0) and reclassifications: reclassify 2 correct-rejection green-guards, defer 2 import-gap repros to the std-lib milestone, and investigate/fix the anonymous-error-set comparison and the value-producing catch-block gaps.

**Architecture:** Four tasks. P3-1 reclassifies `eu_assign_incompat_payload` + `field_access_optional` as green-guards. P3-2 documents the deferral of `field_store_drop` + `test_stub_0` to the std-lib milestone. P3-3 investigates the anonymous-error-set comparison (repro created in Plan 1). P3-4 is a standalone investigation+fix of the value-producing catch-block parser gap. P3-3 and P3-4 each end in a STOP for operator ruling.

**Design spec:** `docs/superpowers/specs/2026-08-04-corpus-red-remaining-design.md` (Plan 3 section)

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build in /tmp via the QUICK_REF bootstrap recipe (NOT `sf/build/out_release/` — that folder causes timeouts). See QUICK_REF "LISP refactor testing" ~line 244:
  ```bash
  OUT=/tmp/zb
  rm -rf "$OUT" && mkdir -p "$OUT"
  ./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
  ```
  Gate: 0 gcc errors (`error:` count == 0).
- 4 MD5 baselines byte-identical throughout: mud `4644ad1349c55af80fa1a18fe0e17989`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `f84c8748e6d0580ffac811d75e34e0e7`, json `3492a935883ee91258feece576ba23d5`
- Corpus: **raw 189/8/0/0 over 197 repros; effective OK=189/FAIL=6/green-guards=2** (post-Plan-2, 2026-08-04; green-guards `var_declared_void`, `euvoid_val_catch` counted separately). FAIL count must not increase. The 8 raw FAILs = 5 frontend gaps (`catch_block_value_producing`, `eu_assign_incompat_payload`, `field_access_optional`, `field_store_drop`, `test_stub_0`) + 1 documented residual (`self_embed_optional_cycle`) + 2 green-guards. The 3 emission defects (P2-2/P2-3/P2-4) are FIXED — no emission-defect FAILs remain.
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4). test_semantic_bin KNOWN pre-existing broken (operator ruling A).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- Z98 idioms: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains.
- QUICK_REF.md reference mandatory for all gates.

---

### Task P3-1: Reclassify 2 Green-Guard Repro Configurations

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

**Scope:** `eu_assign_incompat_payload` (error[3000] EU payload mismatch) and `field_access_optional` (error[3000] `.` on optional) are CORRECT rejections matching the zig0 oracle — green guards, not defects. Reclassify them out of the FAIL count into a distinct green-guard bucket.

- [ ] **Step 1: Verify both are correct rejections**

```bash
OUT=/tmp/p3
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3a repro/mi_matrix/eu_assign_incompat_payload/main.zig 2>&1 | head -3
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3b repro/mi_matrix/field_access_optional/main.zig 2>&1 | head -3
# Also verify zig0 oracle rejects identically:
./sf/build/zig0 -o /tmp/p3o1.c repro/mi_matrix/eu_assign_incompat_payload/main.zig 2>&1 | head -3
```
Confirm both zig1 and zig0 reject with error[3000] and emit 0 .c.

- [ ] **Step 2: Reclassify in EXPECTED_FAIL.md + QUICK_REF.md**

Move both to the existing "Green-guards (correct rejection, not a defect)" section (which already holds `var_declared_void` + `euvoid_val_catch` from P2-3). Update the corpus accounting: post-P3-1 effective **OK=189/FAIL=4/green-guards=4** over 197 (the 4 FAILs = 2 import-gap `field_store_drop`/`test_stub_0` + `catch_block_value_producing` + `self_embed_optional_cycle`; the 4 green-guards = `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`; raw FAIL stays 8 since green-guards are a sub-bucket of the raw 8). Document the classifier rule: green-guards are counted separately from FAIL (a green-guard moving to OK/FAIL is a regression).

- [ ] **Step 3: Verify + commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs(P3): reclassify eu_assign_incompat_payload + field_access_optional as green-guards"
```

---

### Task P3-2: Defer the 2 Import-Gap Repros (document only)

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

**Scope:** `field_store_drop` (error[3048] cannot import `"pal"`) and `test_stub_0` (error[3048] cannot import `"std"`) fail because user programs cannot import compiler-internal modules — no std lib exists yet. Defer to the std-lib milestone.

- [ ] **Step 1: Document the deferral**

Add a "Deferred to std-lib" section in EXPECTED_FAIL.md and a note in QUICK_REF.md listing both with the error[3048] cause and "will pass when zig1 gains a real std lib." These remain FAIL but are tracked as std-lib-deferred, not compiler defects.

- [ ] **Step 2: Verify + commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs(P3): defer field_store_drop + test_stub_0 to std-lib milestone"
```

---

### Task P3-3: Investigate anon-set comparison (anon_errset_comparison)

**Files:** investigation → `.superpowers/sdd/P3-anonerr-report.md`; possible fix in `sf/src/` per findings.

**Pre-requisites:** Plan 1 P1-1 Step 4 (repro exists).

**Scope:** Determine whether `err == error.Bad` on a bare-`!` anonymous error set produces semantically correct results. F-1 stores the raw error name_id as the C error code; multiple error names may collide or miscompare.

- [ ] **Step 1: Read + reproduce**

Read the repro from Plan 1 P1-1. Build and run both RED and GREEN:
```bash
OUT=/tmp/p3
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3r repro/mi_matrix/anon_errset_comparison/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p3r/*.c && gcc -m32 /tmp/p3r/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p3r/prog && /tmp/p3r/prog
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3g repro/mi_matrix/anon_errset_comparison/main_green.zig
# same gcc+run
```
Compare RED vs GREEN output. RED should print 1 (error.Bad == error.Bad) if `==` works; 0 if the raw code miscompares.

- [ ] **Step 2: Trace the error-code assignment**

Trace how the anonymous-set error code is assigned in lowering (lower.zig error_literal / wrap_error_err) and how `==` compares it in sema/coercion. Determine whether the raw name_id is a stable, unique code or collides across error sets.

- [ ] **Step 3: A/B/C options**

Options depend on findings:
- **A** (if `==` already correct): document, reclassify repro OK.
- **B** (if miscompare): add a per-program anonymous error-code registry — assign unique ints to distinct error names at sema/lowering, store in a map keyed by name_id.
- **C** (if only `!=` / exhaustiveness broken): partial fix + document.

Recommend the option with blast radius analysis. If a fix is needed, STOP for operator ruling before implementing.

- [ ] **Step 4: Report**

Write `.superpowers/sdd/P3-anonerr-report.md`. STOP for operator ruling on the recommended option if a fix is needed.

- [ ] **Step 5: Closeout (post-ruling, docs-only)**

Per the P3-3 operator ruling (2026-08-05): Option A adopted — the pure-anonymous `==`/`!=` is semantically correct (name_id is a unique-per-name, program-stable code; verified RED==GREEN==1, matches real-Zig subset→superset coercion semantics). Docs-only:
- Reclassify `anon_errset_comparison` as **OK (semantically verified)** in EXPECTED_FAIL.md + QUICK_REF.md with the justification (name_id uniqueness; matches oracle).
- Record the 2 adjacent defects as tracked follow-ups in EXPECTED_FAIL.md/QUICK_REF.md, pointing to P3-5 (switch-on-error upstream fix) and I3-5/P3-6 (error-code representation unification).
- Commit: `docs(P3): reclassify anon_errset_comparison OK + record adjacent defects`

---

### Task P3-4: Fix catch_block_value_producing (value-producing block) [AMENDMENT P3-2]

**Files:** investigation → `.superpowers/sdd/P3-catch-report.md`; fix in `sf/src/parser.zig` + `sf/src/lower.zig`. Sema: NO change (verified).

**Investigation complete (P3-catch-report.md, 2026-08-05):** root cause CONFIRMED — `parserParseExprStmt` (parser.zig:1258) unconditionally requires `;`, so the bare `99` (block's final value expression, no `;` before `}`) fails `error[2000]`. AND a second root cause in the lowerer: `lowerExprOrBlock` (lower.zig:3223-3238) lowers every block child via `lowerStmt` and returns `0`, dropping the block value (empirically proven: the `99;` variant parses today but prints garbage `-366458289`; emitted C `zT_5 = 99; zT_3 = result;`). Sema already computes block value = last child (semantic_analyzer.zig:1341-1353).

**OPERATOR RULING (2026-08-05):** Option A adopted, WIDE — upstream gap-filling (verified NOT a fallback chain): parser fix = grammar-level (real-Zig `BlockExpr: { Statement* Expression? }`), lowerer fix = completing `lowerExprOrBlock`'s own single-caller contract (catch err-path lower.zig:2625), zero emitter/sema changes. Scope = BOTH `lowerExprOrBlock` AND `lowerExpr`'s block case (lower.zig:3214-3217).

- [ ] **Step 1: Parser fix** — `parserParseExprStmt` (parser.zig:1256-1259): make the trailing `;` optional when the next token is `}`:
```zig
fn parserParseExprStmt(self: *Parser) ParserError!u32 {
    var result = try parserParseExprPrec(self, Prec.assignment);
    if (parserPeek(self).kind != TokenKind.rbrace) {
        _ = try parserExpect(self, TokenKind.semicolon);
    }
    return result;
}
```
Non-final statements still require `;` (`{ 1 2 }` still errors). Module root unaffected (never inside `}`). No AST change — the last extra child IS the block value.

- [ ] **Step 2: Lowerer fix** — `lowerExprOrBlock` (lower.zig:3223-3238): for a block, lower all-but-last children via `lowerStmt`; the LAST child goes through `lowerStmt` (return 0) if it is a statement/control-flow kind (return/break/continue/block/var_decl/expr_stmt/defer/if/while/for), else through `lowerExpr` (return its temp). Also fix `lowerExpr`'s block case (lower.zig:3214-3217) the same way — return the last child's temp instead of a VOID temp, so `if (c) {1} else {2}` block-branches produce values too (operator ruling: WIDE).

- [ ] **Step 3: Build + gate** — build in /tmp. Verify with the `99;`-variant probe first (should print `99` not garbage), then the real repro:
```bash
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3c repro/mi_matrix/catch_block_value_producing/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p3c/*.c && gcc -m32 /tmp/p3c/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p3c/prog && /tmp/p3c/prog
```
Expected: dump rc=0, gcc-clean, prints `99` on the error path. 4 MD5s byte-identical. NOTE: the repro's FAIL→OK classification gate requires BOTH this fix AND the P3-7 inline-error-set feature (helper.zig uses `error{Bad}!i32` which fails to parse / ICEs today) — joint gate verified after P3-7.

- [ ] **Step 4: Commit**

```bash
git add sf/src/parser.zig sf/src/lower.zig
git commit -m "fix(P3): value-producing blocks lower last-expression value (catch_block_value_producing)"
```

---

### Task P3-5: Fix switch-on-error exhaustiveness (upstream defect) [AMENDMENT P3-1]

**Files:** `sf/src/lower.zig` (switch-case collection, ~:2919-2934), repro dirs + EXPECTED_FAIL.md

**Root cause (P3-3 investigation, .superpowers/sdd/P3-anonerr-report.md):** switch-case collection in `lower.zig:2919-2934` handles only `int_literal` and `enum_literal` case nodes; an `error_literal` case node (`switch (err) { error.Bad => ..., else => ... }`) falls to `continue` → zero SwitchCase entries → `switch (err) { default: ... }` — always takes `default`. Affects named AND anonymous error sets. The oracle emits proper `case ERROR_Bad:`. Genuine upstream defect; clean small fix; no corpus repro or MD5 gate exercises it today.

- [ ] **Step 1: Add repro(s)** — create `repro/mi_matrix/switch_on_error_named/` + `switch_on_error_anon/` (RED = wrong-today, GREEN = expected) with NOTES.md. Pattern: switch over a caught error value with `error.Bad => ..., error.Other => ..., else => ...`. Named variant uses `const E = error{ Bad, Other }`; anon variant uses bare-`!` fn. Expected today: both dump rc=0/gcc-clean but print the else/default branch (RED); expected post-fix: print the matching branch. Confirm the current wrong behavior first.
- [ ] **Step 2: Fix** — add an `error_literal` branch to the switch-case collection in `lower.zig:2919-2934` mirroring the `enum_literal` branch: resolve the case value via `enum_value_table` (ordinal) when present, else fall back to the raw name_id (anonymous-set case — matching how error literals emit in the anon regime). Keep the `continue` as the final else. Verify the emitted C contains real `case <value>:` entries.
- [ ] **Step 3: Build + gate** — build in /tmp; both repros dump rc=0, gcc-clean, run the correct branch; 4 MD5s byte-identical (mud `4644ad13...`, gol `d0d3051d...`, lisp `f84c8748...`, json `3492a935...`); corpus FAIL count must not increase (switch_on_error_* should be OK post-fix, or OK-per-gate with runtime-gap annotation per the comptime_neg_int/xmod precedent if they classify OK-but-wrong today).
- [ ] **Step 4: Commit** — `fix(P3): switch-on-error case collection drops error_literal nodes (switch_on_error)` (only lower.zig + repro dirs + EXPECTED_FAIL.md).

---

### Task I3-5: Investigate error-code representation unification [AMENDMENT P3-1]

**Files:** investigation → `.superpowers/sdd/I3-5-errorcodes-report.md`; no source changes.

**Scope (P3-3 adjacent defect #1, operator-ruled):** zig1 accepts inferred→named error-set coercions that real Zig also accepts (verified — subset→superset is legal), but then MISCOMPARES: anonymous-set errors carry the raw **name_id** as the C error code, named-set errors carry the **ordinal**. `e1 == e2` across the two regimes compares different encodings → wrong results for programs real Zig accepts.

- [ ] **Step 1: Characterize the current encodings** — confirm anon = raw name_id (lower.zig:1191-1206, semantic_analyzer.zig:1182) and named = ordinal (semantic_analyzer.zig:1184-1186, typeRegistryErrorSetMemberIndex). Map every error-literal/error-code emission site in lower.zig + semantic_analyzer.zig + c89_emit.zig.
- [ ] **Step 2: Design the unification** — per-program error-code registry assigning a unique small int per distinct error NAME (keyed by name_id, zig0-style `#define ERROR_Name` program-global codes). Determine: registry placement (comptime/sema? type_registry?), assignment timing (which pass), how named-set ordinals and anon name_ids both route through it, and how `@errorFromInt`/`@intFromError`/switch case values stay consistent. Provide A/B/C options with file:line + blast radius (which repros/examples emit anon codes vs named ordinals; MD5-gate impact — the 4 baselines).
- [ ] **Step 3: Report + STOP** — write `.superpowers/sdd/I3-5-errorcodes-report.md`, recommend an option with blast radius analysis. STOP for operator ruling before implementation.

---

### Task P3-6: Implement error-code representation unification [AMENDMENT P3-1]

**Files:** per I3-5 ruling; repro(s) for cross-set `==` + EXPECTED_FAIL.md.

**Pre-requisites:** I3-5 investigation + operator ruling.

- [ ] **Step 1: Implement the approved option** per the I3-5 ruling.
- [ ] **Step 2: Add cross-set comparison repro** — `repro/mi_matrix/errset_cross_set_compare/` (RED/GREEN): a program real Zig accepts (inferred→named subset coercion) that compares an anon error against a named-set error; must print the semantically-correct result post-fix.
- [ ] **Step 3: Build + gate** — build in /tmp; repro dumps rc=0, gcc-clean, runs correct result; 4 MD5s byte-identical OR re-baselined per operator ruling (I3-5 will predict MD5 impact); corpus FAIL count must not increase.
- [ ] **Step 4: Commit** — `fix(P3): unify anonymous/named error-code representation (errset_cross_set_compare)`.

---

### Task P3-7: Support inline error-set types in type positions (feature task) [AMENDMENT P3-2]

**Files:** `sf/src/parser.zig` + `sf/src/type_resolver.zig` + downstream (per investigation); repro + EXPECTED_FAIL.md.

**Origin:** P3-4 investigation gap #2 (operator ruling 5b, 2026-08-05). `helper.zig:1` — `pub fn try_compute() error{Bad}!i32` — fails two ways today: (a) parser.zig:909 `kw_error` branch never checks for a trailing postfix `!` (the `!payload` error-union suffix only exists after `parserParseTypeName` at :914-921), so `error{Bad}!i32` hits `expected '{' but found token` (error[2000]); (b) `error{Bad}` alone (no `!`) parses but ICEs `error[3043]: internal: invalid temp index 0` because `resolveTypeExprFull` (type_resolver.zig:609-904) has NO `error_set_decl` case (falls through to TYPE_UNDEFINED at :901-903). Corpus convention avoids this spelling (`const E = error{Bad}; fn h() E!i32`), but it is valid Zig.

- [ ] **Step 1: Parser fix** — parser.zig:909: after `parserParseErrorSetDecl`, check for a trailing `!` and parse the payload type (mirror the base+`!` path at :914-921). Verify `error{Bad}!i32` now parses.
- [ ] **Step 2: Type-resolver fix** — add an `error_set_decl` case to `resolveTypeExprFull` (type_resolver.zig, around :901-903) so inline `error{...}` in type position resolves to a real error-set type (register the members like a named set / anonymous set). Verify the ICE is gone for `error{Bad}` without `!`.
- [ ] **Step 3: Downstream check** — run the P3-4 joint gate: catch_block_value_producing should now dump rc=0, 2 `.c`, gcc-clean, print `99`. Fix any downstream gaps (sema/lowerer handling of inline-set fn types) that surface.
- [ ] **Step 4: Build + gate** — build in /tmp; P3-4 repro FAIL→OK; 4 MD5s byte-identical (the 4 baselines use no inline error sets — json uses named sets, verified zero `error{...}!` uses in repro/ or examples/); corpus FAIL count must not increase.
- [ ] **Step 5: Commit** — `fix(P3): inline error-set types in type positions (catch_block_value_producing)` (parser.zig + type_resolver.zig + EXPECTED_FAIL.md).

---

## Amendments Record

- **AMENDMENT P3-0 (2026-08-05, operator ruling):** Global Constraints corpus baseline updated from the stale pre-Plans-1-2 `184/8/0/0 @192` (with a nonexistent "3 emission-defect FAIL" term) to the post-Plan-2 **raw `189/8/0/0 @197` / effective `OK=189/FAIL=6/green-guards=2`**. The 8 raw FAILs = 5 frontend gaps + `self_embed_optional_cycle` residual + 2 green-guards (`var_declared_void`, `euvoid_val_catch`). P3-1 Step 2 accounting rewritten: post-P3-1 effective `OK=189/FAIL=4/green-guards=4` (raw FAIL stays 8; green-guards are a sub-bucket). MD5 baselines unchanged and current.
- **AMENDMENT P3-1 (2026-08-05, operator ruling on P3-3 adjacent defects):** P3-3 resolved as Option A (pure-anonymous `==` semantically correct; Step 5 closeout = docs-only reclassify anon_errset_comparison OK + record adjacent defects). Two new tasks added from the P3-3 investigation findings: **P3-5** (upstream switch-on-error defect at lower.zig:2919-2934 — error_literal case nodes dropped → empty switch; repros + fix) and **I3-5 + P3-6** (error-code representation unification — anon name_id vs named ordinal miscompare in accepted real-Zig programs; investigate then implement per ruling). Real-Zig semantics verified from the official Zig language reference: inferred→named subset coercion is legal (zig0/z98 is stricter), so zig1's acceptance is correct; the miscompare is the genuine defect. Execution order appended after P3-4.
- **AMENDMENT P3-2 (2026-08-05, operator ruling on P3-4 investigation):** P3-4 rewritten from the investigation (P3-catch-report.md). Root cause = TWO gaps: (1) parser.zig:1258 unconditional `;` (grammar — real-Zig `BlockExpr: { Statement* Expression? }`), and (2) `lowerExprOrBlock` (lower.zig:3223-3238) + `lowerExpr` block case (lower.zig:3214-3217) drop block values (empirically proven: `99;` variant prints garbage). Operator ruling: Option A WIDE (both lowerer sites) — verified upstream gap-filling, NOT a fallback chain (parser=grammar, lowerer=completing its own single-caller contract, zero emitter/sema change). Second gap (inline `error{Bad}!i32`) → operator ruling **5b**: new feature task **P3-7** (parser.zig:909 postfix `!` + type_resolver error_set_decl case) instead of re-spelling the repro. The repro's FAIL→OK gate is JOINT (P3-4 + P3-7). Sema needs no change for the value-block fix.
