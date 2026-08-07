# char_literal Switch + opt_slice Null Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two out-of-scope follow-up compiler defects gated by the 15-repro battery (char_literal switch-case labels dropped; opt_slice null-payload temp typed `int`), with I-task investigation that reads AND updates the relevant tech docs, operator ruling, then runtime-gated F-tasks plus the 3 actionable Minor doc fixes.

**Architecture:** Batched I1+I2 investigations (each also updates its tech doc), combined STOP for operator ruling, then F1 (char_literal fix), F2 (opt_slice fix), F3 (Minor doc fixes), F4 (gate sweep + docs).

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`sf/build/out_release/zig1`), zig0 oracle (`sf/build/zig0`), gcc -m32 C89, repro battery (15 dirs, committed at 65d82657).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1`. Build with `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: sf/build/out_release/zig1 ===`. Oracle: `sf/build/zig0`.
- **Compile+run recipe:** `sf/build/out_release/zig1 --dump-c89 <FILE.zig> > /tmp/x.c 2>/tmp/x.err ; gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x ; /tmp/x`. MUST link `zig_runtime.c` AND `zig_pal.c` + `-I sf/src/include`. Multi-module: `--dump-c89 --output-dir DIR` (DIR must pre-exist), gcc inside DIR.
- **RUNTIME gate mandatory per F-task** (AGENTS §2.5.3): each fixed repro must run rc=0 AND print the expected POST-FIX output. Compile-only gates are FORBIDDEN.
- **Corpus:** 230 repros, OK=223/FAIL=3/gg=4 (raw 7), 231 dirs. FAIL must not increase. The 3 FAILs: `field_store_drop`, `test_stub_0` (std-lib-deferred), `self_embed_optional_cycle`. 4 green-guards: `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
- **4 MD5 gates** byte-identical: mud `906fa59c8676bb1054d3fcc13704fce5`, gol `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json `b5f56ebd51d2f0fcd379a1e083594462` — UNLESS operator-approved re-baseline (F-5 AMENDMENT B precedent: runtime is the gate). I2 assesses blast radius.
- **The 12 Battery A repros' post-fix outputs** (oracle-verified): `switch_char_single`=`120`, `switch_char_multi`=`1120`, `switch_char_nodefault`=`19`, `switch_char_mixed_kinds`=`120`, `switch_char_expr`=`120`, `switch_char_while`=`1`, `switch_char_labeled`=`1`, `switch_char_nested`=`109`, `switch_char_xmod`=`120`, `switch_char_xmod_expr`=`120`, `switch_char_xmod_while`=`1`, `switch_char_xmod_nodefault`=`19`.
- **The 3 Battery B repros**: `opt_slice_null`, `opt_slice_null_xmod`, `opt_slice_null_multi` — must run rc=0 printing `1` with gcc `-Wint-conversion` warnings GONE post-fix.
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task MUST update the corresponding `sf/docs/tech_docs/*.md` — corrected line refs, descriptions, `[updated: 2026-08-07]` annotation. Check INDEX.md Table A for the covering doc.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present. On any issue, STOP.
- **I-tasks report then STOP for operator ruling** (I1+I2 both, one combined STOP). F-tasks do NOT start until the ruling.

---

### Task I1: char_literal switch-case investigation + tech-doc update

**Files:**
- Investigate: `sf/src/lower.zig:3183` (expr-switch), `sf/src/lower.zig:3920` (stmt-switch)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` (switch case-collection section)
- Report: `.superpowers/sdd/I-char-switch-report.md`

**Interfaces:**
- Consumes: the 12 Battery A repros (committed), the I-char-literal-gaps audit findings (`.superpowers/sdd/I-char-literal-gaps-report.md`).
- Produces: mechanism confirmation, tech-doc update, blast radius assessment, fix recommendation for the operator ruling.

**Context:** Both switch case-collection loops check `int_literal`, `enum_literal`, `error_literal`, then `else { continue; }`. `char_literal` (AstKind 13) hits `continue` → case dropped → emitted C has `switch(c){default:...}`. Prior audit (`I-char-literal-gaps-report.md`) confirmed char_literal is ONLY broken for switch cases, and its value is stored in `store.int_values` at the payload index.

- [ ] **Step 1: Confirm the mechanism**

Read `sf/src/lower.zig` around `:3160-3190` (expr-switch case collection) and `:3898-3925` (stmt-switch case collection). Confirm both chains handle `int_literal`/`enum_literal`/`error_literal` and hit `else { continue; }` at `:3183`/`:3920` for `char_literal`. Confirm the `int_literal` accessor: `case_val = store.int_values.items[@intCast(usize, case_node.payload)];` at `:3170-3171` and `:3907-3908`. Verify `ast.zig:323-327` stores char literal values in `int_values` at the payload index.

- [ ] **Step 2: Verify the emitted-C symptom + oracle post-fix reference**

Pick `repro/mi_matrix/switch_char_single/main.zig`. `zig1 --dump-c89` → grep the emitted C: `switch (c) {` with NO `case 'a':` label (only `default:`). Then zig0 oracle on a copy: `sf/build/zig0 -o /tmp/x.c <copy>` (zig0 writes beside the source — use a /tmp copy) → grep: `case 'a':` labels PRESENT. Record both.

- [ ] **Step 3: Assess blast radius (4 MD5s)**

For each of mud/gol/lisp/json, check whether the program uses a `switch` with `char_literal` case values (grep `examples/z98/<e>/main.zig` for switch cases with char literals; also grep all module files under each example dir). Report which (if any) would change emitted C post-fix → which MD5s would re-baseline. Prior audit says none use char switches — verify.

- [ ] **Step 4: Update the tech doc `sf/docs/tech_docs/07_lir_lowering.md`**

Find the switch-case-collection description (switch lowering section). Update it to: (a) list all 4 literal kinds handled by the case-collection loops (`int_literal`, `enum_literal`, `error_literal`, `char_literal` — noting `char_literal` was previously missing/gap at `lower.zig:3183`/`:3920`); (b) document the `store.int_values` payload access pattern for `int_literal`/`char_literal`; (c) correct any stale line references; (d) add `[updated: 2026-08-07]` at the top of the changed section. Do NOT fix the compiler code — document current behavior + the gap.

- [ ] **Step 5: Write the I-report**

Write `.superpowers/sdd/I-char-switch-report.md` with: mechanism confirmation (file:line evidence), tech-doc update summary (what changed + why), blast radius (which repros flip, which MD5s), recommended fix option (expected: Option A — add char_literal branch to both loops reading `store.int_values`), concerns.

- [ ] **Step 6: Report back**

Return: **Status** (DONE/BLOCKED/NEEDS_CONTEXT), mechanism summary, tech-doc update summary, blast radius, recommended option, report path.

**Gate:** mechanism confirmed with file:line evidence; emitted-C symptom + oracle post-fix reference recorded; tech doc updated with `[updated: 2026-08-07]` + corrected refs; blast radius assessed. No compiler code changes.

---

### Task I2: opt_slice null-payload temp-type investigation + tech-doc update

**Files:**
- Investigate: lowerer null-construction path (locus to locate — likely `sf/src/lower.zig`), possibly `sf/src/c89_emit.zig` optional emission
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` + `sf/docs/tech_docs/08_c89_emission.md`
- Report: `.superpowers/sdd/I-opt-slice-report.md`

**Interfaces:**
- Consumes: the 3 Battery B repros (committed), the existing guard `opt_slice_null_return/NOTES.md`.
- Produces: mechanism confirmation (exact locus of the `int` payload-temp type assignment), tech-doc updates, blast radius, fix options A/B/C for the operator ruling.

**Context:** `catch return null` in a `?[]T` function emits `zT_N = NULL; zT_M.has_value = 0;` where the payload temp is typed `int` but the optional's payload field is a slice struct. Valid for `?*T` (payload IS a pointer), wrong for `?[]T`. gcc `-Wint-conversion` warning only → latent/OK-by-gate.

- [ ] **Step 1: Locate the null-construction lowering**

Trace `catch return null` for a `?[]T` function. Use `repro/mi_matrix/opt_slice_null/main.zig`. `zig1 --dump-c89` → inspect emitted C: find `zT_N = NULL; zT_M.has_value = 0;` and the declaration of `zT_N` (typed `int`). Then locate in `sf/src/lower.zig` where a null optional value is constructed (search for `has_value` field-set, `null` optional construction, `TYPE_NULL` handling in lowerExpr/lowerStmt). Find the exact instruction that declares the payload temp and its type. Determine WHY the type is `int` (hardcoded? scalar fallback? optional payload type lookup missing?). Verify `?*T` works because `int`+`NULL` is pointer-compatible, and identify the optional payload type lookup that SHOULD be used (`typeRegistryGetPointeeType`? optional payload accessor?).

- [ ] **Step 2: Verify all 3 Battery B repros**

`opt_slice_null`, `opt_slice_null_xmod` (multi-module), `opt_slice_null_multi` — dump rc=0, gcc rc=0, run rc=0 printing `1`, warning counts 2/2/3. Record the exact warning text (`assignment to 'int' from 'void *' makes integer from pointer without a cast`).

- [ ] **Step 3: Assess blast radius (4 MD5s)**

For each of mud/gol/lisp/json, check for `?[]T` functions using `catch return null` (or `return null` on an optional-slice) — grep each example dir. Report which would change emitted C post-fix → which MD5s re-baseline. Prior guard NOTES say rogue_mud's pathfinding is the origin; verify none of the 4 gates hit this.

- [ ] **Step 4: Propose fix options (A/B/C) with tradeoffs**

- Option A: type the null-payload temp at the optional's declared payload type (correct type for both `?*T` and `?[]T`).
- Option B: skip the payload temp entirely when has_value=0 (payload is dead — but the emitter may still reference it).
- Option C: narrow fix for slice-type payloads only.

For each: safety (does `?*T` still work?), blast radius (which repros/MD5s change), implementation location (lowerer vs emitter). Recommend one.

- [ ] **Step 5: Update the tech docs**

Update `sf/docs/tech_docs/07_lir_lowering.md` (null-construction / optional value lowering section) and `sf/docs/tech_docs/08_c89_emission.md` (optional type emission, payload temp emission) to: (a) describe the current null-payload temp typing (scalar `int` regardless of payload type — correct for `?*T`, wrong for `?[]T`); (b) correct stale line references; (c) add `[updated: 2026-08-07]`. Do NOT fix compiler code — document current behavior + the gap.

- [ ] **Step 6: Write the I-report**

Write `.superpowers/sdd/I-opt-slice-report.md` with: mechanism confirmation (exact file:line locus of the type assignment), tech-doc update summary, blast radius, recommended option with tradeoff analysis, concerns.

- [ ] **Step 7: Report back**

Return: **Status**, mechanism summary (locus), tech-doc update summary, blast radius, recommended option, report path.

**Gate:** mechanism locus confirmed with file:line evidence; all 3 repros verified; blast radius assessed; fix options A/B/C analyzed; both tech docs updated with `[updated: 2026-08-07]` + corrected refs. No compiler code changes.

---

### Task F1: char_literal switch-case fix (per ruling)

**Files:**
- Modify: `sf/src/lower.zig` — both case-collection loops (expr `:3183`, stmt `:3920`)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` (re-verify refs post-fix)
- Test: 12 Battery A repros

**Interfaces:**
- Consumes: I1 ruling (expected Option A), the 12 Battery A repros + their post-fix outputs.
- Produces: fixed case collection handling `char_literal`.

**Context:** Add `AstKind.char_literal` handling to both loops, mirroring `int_literal`: `case_val = store.int_values.items[@intCast(usize, case_node.payload)];`. Insert as `else if (case_node.kind == AstKind.char_literal) { ... }` before the final `else { continue; }` in EACH loop.

- [ ] **Step 1: Write the failing test (repro pre-fix evidence already exists)**

No new test needed — the 12 Battery A repros ARE the tests. Record their pre-fix outputs (from the repro NOTES.md / I1 report).

- [ ] **Step 2: Implement the fix**

Using `edit` (exact strings), add to the expr-switch case collection (around `lower.zig:3170`):

```zig
                } else if (case_node.kind == AstKind.char_literal) {
                    case_val = store.int_values.items[@intCast(usize, case_node.payload)];
                } else if (case_node.kind == AstKind.enum_literal) {
```

and to the stmt-switch case collection (around `lower.zig:3907`):

```zig
                } else if (case_node.kind == AstKind.char_literal) {
                    case_val = store.int_values.items[@intCast(usize, case_node.payload)];
                } else if (case_node.kind == AstKind.enum_literal) {
```

Read the region before each edit; bottom-to-top. NOTE: the exact `else if` chain text must match the source — verify the current `int_literal`/`enum_literal` ordering by reading before editing.

- [ ] **Step 3: Build + verify all 12 Battery A repros**

`bash sf/scripts/build_release.sh` → gate on `=== [release] Done ===`. Then for each of the 12 `switch_char_*` repros: dump rc=0, gcc rc=0, run rc=0, output MUST equal the post-fix expected value (see Global Constraints). For cross-module repros use the multi-module recipe.

- [ ] **Step 4: Verify emitted C has case labels**

For a representative repro (`switch_char_single`), grep emitted C: `case 'a':` and `case 'b':` labels PRESENT (no longer just `default:`).

- [ ] **Step 5: Verify 4 MD5 gates + corpus**

4 MD5s must be byte-identical (or re-baselined per ruling with runtime proof). Corpus sweep: the 12 Battery A repros now print correct output (fully OK), FAIL=3 + gg=4 unchanged, no regression.

- [ ] **Step 6: Update tech doc `07_lir_lowering.md`**

Re-verify the line references updated in I1 are still correct post-fix (the case-collection loops now include char_literal). Add/confirm `[updated: 2026-08-07]`.

- [ ] **Step 7: Commit**

```bash
git add sf/src/lower.zig sf/docs/tech_docs/07_lir_lowering.md
git commit -m "fix: char_literal switch case labels emitted (12 switch_char repros)"
```

**Gate:** build 0 err; 12/12 Battery A repros run rc=0 printing post-fix outputs; emitted C has `case 'a':` labels; 4 MD5s byte-identical (or re-baselined per ruling); corpus FAIL=3 + gg=4 unchanged; tech doc updated.

---

### Task F2: opt_slice null-payload temp-type fix (per ruling)

**Files:**
- Modify: the lowerer/emitter locus per I2 ruling (identified in I2 Step 1)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` + `sf/docs/tech_docs/08_c89_emission.md` (re-verify refs post-fix)
- Test: 3 Battery B repros

**Interfaces:**
- Consumes: I2 ruling (Option A/B/C), the 3 Battery B repros.
- Produces: null-payload temp typed at the correct payload type (or dead-temp elimination), warnings gone.

**Context:** Implement per I2 ruling. The fix makes the null-payload temp carry the optional's declared payload type (or eliminates it), so gcc `-Wint-conversion` warnings disappear for `?[]T`.

- [ ] **Step 1: Write the failing test (repro pre-fix evidence already exists)**

The 3 Battery B repros ARE the tests. Record their pre-fix warning counts (2/2/3) + outputs (`1`).

- [ ] **Step 2: Implement the fix per I2 ruling**

Follow the ruling exactly. Use `edit`/`fastedit` (read region before each edit; bottom-to-top). If the ruling's approach would break `?*T` repros, STOP and report — do not proceed.

- [ ] **Step 3: Build + verify all 3 Battery B repros**

`bash sf/scripts/build_release.sh` → gate on `=== [release] Done ===`. For each of `opt_slice_null`, `opt_slice_null_xmod` (multi-module), `opt_slice_null_multi`: dump rc=0, gcc rc=0 with 0 `-Wint-conversion` warnings on the payload temp, run rc=0 printing `1`.

- [ ] **Step 4: Verify existing `?*T` optional repros still work**

Confirm no regression in `?*T` null handling — run a few existing optional repros (e.g. `optptr_null_switch`, `mi_opt_null`, `opt_null_decl`) to confirm pointer-optional null still compiles clean.

- [ ] **Step 5: Verify 4 MD5 gates + corpus**

4 MD5s byte-identical OR re-baselined per ruling with runtime proof. Corpus: no regression, FAIL=3 + gg=4 unchanged.

- [ ] **Step 6: Update tech docs**

Re-verify the I2 doc updates are correct post-fix. Add/confirm `[updated: 2026-08-07]`.

- [ ] **Step 7: Commit**

```bash
git add <fixed file(s)> sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "fix: optional-slice null payload temp typed at payload type (opt_slice_null repros)"
```

**Gate:** build 0 err; 3/3 Battery B repros run rc=0 printing `1` with 0 payload-temp warnings; `?*T` optional repros no regression; 4 MD5s byte-identical or re-baselined per ruling; corpus no regression.

---

### Task F3: Minor doc fixes from final review

**Files:**
- Modify: `docs/sf/QUICK_REF.md` (historical F5 row ~:201)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (historical rows ~:38, ~:1220, ~:1250; Prior row build-evidence)
- Modify: 12 Battery A `NOTES.md` files (`repro/mi_matrix/switch_char_*/NOTES.md`)
- Verify: `repro/mi_matrix/opt_slice_null_xmod/NOTES.md` (4th finding dismissed — confirm no change needed)

**Interfaces:**
- Consumes: the final-review Minor list (spec Item 3).
- Produces: doc-only fixes, consistent terminology.

**Context:** 3 actionable Minors: (1) stale refs `lower.zig:3858-3860/:3121-3123` in historical rows — add supersede note to actual `:3183`/`:3920`; (2) Battery A NOTES "FAIL" → add "not counted as a corpus FAIL"; (3) restore the demoted Prior row's build-evidence line.

- [ ] **Step 1: Fix QUICK_REF.md historical F5 row**

At `docs/sf/QUICK_REF.md` the F5 historical paragraph citing `lower.zig:3858-3860/:3121-3123` — append a supersede note: `(refs superseded — actual sites lower.zig:3183 expr / :3920 stmt)`. Verify the actual sites with grep first.

- [ ] **Step 2: Fix EXPECTED_FAIL.md historical rows**

Find every historical row citing `lower.zig:3858-3860/:3121-3123` (~:38, ~:1220, ~:1250) and append the same supersede note. In the demoted F5 Prior row, restore the build-evidence line (e.g. "Verified with `/tmp/zf5/zig1` (fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors)") — note: this is historical record, verify the claim was true per the F5 report (`.superpowers/sdd/task-F5-rogue-report.md`).

- [ ] **Step 3: Fix the 12 Battery A NOTES.md classification lines**

In each `repro/mi_matrix/switch_char_*/NOTES.md`, find `Classification: **FAIL** (runtime gap…` (or similar) and append `, NOT counted as a corpus FAIL (OK-by-compile / runtime-gap-tracked)` — mirroring how `opt_slice_null_return/NOTES.md` states its classification.

- [ ] **Step 4: Verify the dismissed 4th finding**

Confirm `repro/mi_matrix/opt_slice_null_xmod/NOTES.md` has no stale/incorrect classification needing change (the final review dismissed it). If it has the same "not counted as a corpus FAIL" pattern already, leave as-is.

- [ ] **Step 5: Verify all cited line refs grep-match source**

For every doc edit, grep the referenced source lines to confirm the refs are accurate.

- [ ] **Step 6: Commit**

```bash
git add docs/sf/QUICK_REF.md repro/mi_matrix/EXPECTED_FAIL.md repro/mi_matrix/switch_char_*/NOTES.md
git commit -m "docs: fix stale refs + Battery A NOTES classification (final-review minors)"
```

**Gate:** doc-only; all cited refs grep-verified; NOTES terminology consistent with manifest; no compiler changes; 4 MD5s unaffected.

---

### Task F4: Gate sweep + docs reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (Battery A rows cleared, Battery B warning notes updated)
- Modify: `docs/sf/QUICK_REF.md` (baseline row)
- Modify: tech docs 07/08 (final line-ref verification)

**Interfaces:**
- Consumes: F1/F2 fixes, F3 doc fixes, all 15 battery repros.
- Produces: final manifest + QUICK_REF baseline reflecting the fixes.

**Context:** After F1+F2, the 12 Battery A repros print correct output (fully OK, no longer runtime-gap-tracked) and the 3 Battery B repros have no payload-temp warnings. Corpus arithmetic: 230 repros — OK=223→238 (12 A + 3 B become fully OK), FAIL=3 + gg=4 unchanged (verify exact count during the task).

- [ ] **Step 1: Run the full corpus sweep**

Classify all `repro/mi_matrix/*/` by gcc EXIT CODE (QUICK_REF). Record OK/FAIL/ICE/CRASH/gg. Confirm FAIL=3 + gg=4 unchanged.

- [ ] **Step 2: Verify 4 MD5 gates**

`zig1 --dump-c89 examples/z98/<e>/main.zig | md5sum` for mud/gol/lisp/json. Must match the baselines (or re-baselined with runtime proof in F1/F2).

- [ ] **Step 3: Verify test_analyzer_bin PASS**

Run the analyzer test binary (per QUICK_REF).

- [ ] **Step 4: Update EXPECTED_FAIL.md**

Clear the Battery A runtime-gap rows (now fully OK, print correct output). Update the Battery B rows (warnings gone). Add the F1/F2 fix records. Keep FAIL=3 + gg=4.

- [ ] **Step 5: Update QUICK_REF.md**

Add a new corpus-gate baseline row: `[updated: 2026-08-07 — char_literal switch + opt_slice null fixes]: effective OK=… / FAIL=3 / green-guards=4 over 230 repros`. Note the 12+3 battery repros now fully OK.

- [ ] **Step 6: Verify tech docs 07/08 line refs final**

Confirm every line reference cited in 07_lir_lowering.md / 08_c89_emission.md still matches post-fix source.

- [ ] **Step 7: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "docs: gate sweep + manifest + QUICK_REF for char_literal + opt_slice fixes"
```

**Gate:** corpus sweep recorded (OK=238/FAIL=3/gg=4 over 230, reconcile exact), 4 MD5s byte-identical or re-baselined, test_analyzer_bin PASS, manifest + QUICK_REF + tech docs consistent.

---

## Post-Plan (NOT this plan)

- **rogue_mud end-to-end re-attempt** after the char_literal fix — the input switch (main.zig:236-256) becomes runtime-reachable; any remaining parser-incompatible source becomes new repros.
- **0-FAIL corpus goal** remains blocked by the 2 std-lib-deferred FAILs + 1 C89 fundamental.
