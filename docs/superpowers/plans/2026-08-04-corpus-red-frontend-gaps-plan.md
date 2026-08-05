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

---

### Task P3-4: Investigate + Fix catch_block_value_producing (standalone I-task)

**Files:** investigation → `.superpowers/sdd/P3-catch-report.md`; fix in `sf/src/parser.zig` + verification in sema/lowerer.

**Pre-requisites:** None. Tech docs do NOT cover this gap (confirmed — parser/design docs imply blocks-as-catch-fallback works but never implement value-producing trailing expressions).

**Scope:** `catch |err| { _ = err; 99 }` fails error[2000] because `parserParseBlock` (parser.zig:1746) loops `parserParseStatement`, and `parserParseExprStmt` (:1256-1259) always requires a trailing `;`. The value-producing final expression `99` (no `;` before `}`) fails.

- [ ] **Step 1: Confirm root cause**

Read `sf/src/parser.zig:1746-1770` (parserParseBlock), `:1256-1260` (parserParseExprStmt), `:432-436` (parserParseCatchRHS). Confirm the exact failure: `99` parsed as expr-stmt then `parserExpect(semicolon)` fails on `}`.

- [ ] **Step 2: Design the value-producing block extension**

Determine how to allow a block's final statement to be a bare expression (no trailing `;`) that becomes the block's value. Investigate:
- How does `if`/`switch` handle value-producing blocks already (if any)?
- Does the AST/lowerer have a concept of "block with trailing value" (like `lowerExprOrBlock`)?
- What does the repro's expected semantics require (the block value `99` becomes the catch fallback)?

Provide A/B/C options:
- **A:** Parser-only — when the block is a catch-fallback (or any value context), allow the final expr-stmt to omit `;` and record it as the block value. Requires threading "value block" context.
- **B:** Parser + AST — add a `block_value` field/flag to block nodes; sema reads it as the block's type.
- **C:** Require explicit `return 99` (document as unsupported bare-value form) — matches the spec's divergent-only example.

Recommend an option. STOP for operator ruling.

- [ ] **Step 3: Implement the approved option**

Implement per the ruling. Include exact old→new parser code.

- [ ] **Step 4: Build + gate**

```bash
# Build /tmp compiler, then:
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3c repro/mi_matrix/catch_block_value_producing/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p3c/*.c && gcc -m32 /tmp/p3c/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p3c/prog && /tmp/p3c/prog
```
Expected: dump rc=0, gcc-clean, prints `99` on the error path (or correct per the repro's expected output). 4 MD5s byte-identical. Corpus: catch_block_value_producing FAIL→OK (or correct-rejection if the form is documented unsupported).

- [ ] **Step 5: Commit**

```bash
git add sf/src/parser.zig [sf/src/semantic_analyzer.zig] [sf/src/lower.zig] repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix(P3): value-producing catch block fallback (catch_block_value_producing)"
```

---

## Amendments Record

- **AMENDMENT P3-0 (2026-08-05, operator ruling):** Global Constraints corpus baseline updated from the stale pre-Plans-1-2 `184/8/0/0 @192` (with a nonexistent "3 emission-defect FAIL" term) to the post-Plan-2 **raw `189/8/0/0 @197` / effective `OK=189/FAIL=6/green-guards=2`**. The 8 raw FAILs = 5 frontend gaps + `self_embed_optional_cycle` residual + 2 green-guards (`var_declared_void`, `euvoid_val_catch`). P3-1 Step 2 accounting rewritten: post-P3-1 effective `OK=189/FAIL=4/green-guards=4` (raw FAIL stays 8; green-guards are a sub-bucket). MD5 baselines unchanged and current.
