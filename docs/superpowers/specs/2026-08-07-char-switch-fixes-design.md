# char_literal Switch-Case + opt_slice Null Payload — Fix Design Spec

**Date:** 2026-08-07
**Status:** Draft
**Predecessor:** `2026-08-07-char-switch-repros-design.md` (complete at HEAD 65d82657, READY TO MERGE — 15 defensive repros created)

## Goal

Fix the two out-of-scope follow-up compiler defects that the repro battery (HEAD 65d82657) now gates. Each defect gets an I-task (investigation + tech-doc update), a combined operator ruling, then an F-task (fix, runtime-gated). A third F-task applies the 4 Minor doc fixes from the repro battery's final review. A final F-task runs the gate sweep.

## Background

The repro battery plan (commits 95b3c828..65d82657) created 15 defensive repros:

- **12 Battery A** (`switch_char_*`): gate the char_literal switch-case-label bug. Both switch case-collection loops in `sf/src/lower.zig` handle `int_literal`, `enum_literal`, `error_literal` only; `char_literal` (AstKind 13) falls through to `else { continue; }` → case silently dropped → emitted C has `switch(c){default:...}` with no char case labels → char prongs unreachable. Sites: `lower.zig:3183` (expr-switch) and `:3920` (stmt-switch). Pre-fix outputs `000`/`0000`/`99`/`020`/`000`/`0`/`0`/`999`/`000`/`000`/`0`/`99`; post-fix expected `120`/`1120`/`19`/`120`/`120`/`1`/`1`/`109`/`120`/`120`/`1`/`19` (all verified against the zig0 oracle).
- **3 Battery B** (`opt_slice_null*`): gate the opt_slice null-payload temp-type bug. `catch return null` in a `?[]T` function emits the null payload temp as scalar `int` (`zT_N = NULL; zT_M.has_value = 0;`) instead of the slice-struct type. Valid for `?*T` (payload IS a pointer), wrong for `?[]T` (payload is a slice struct). gcc `-Wint-conversion` warning only (rc=0) → OK-by-gate/latent. Warning counts: `opt_slice_null`=2, `opt_slice_null_xmod`=2 (in lib module `lib_F46EFE00.c:28/:36`), `opt_slice_null_multi`=3.

The repro battery final review left 4 Minor findings (none blocking): stale defect-site refs in historical rows, Battery A NOTES "FAIL" vs manifest "runtime-gap-tracked" terminology, prior-row evidence compression, and one dismissed finding.

## The 2 defects

| # | Defect | Root cause | Symptom |
|---|--------|-----------|---------|
| 1 | char_literal switch-case labels dropped | case-collection loops at `lower.zig:3183`/`:3920` have no `AstKind.char_literal` branch → `else { continue; }` drops the case | emitted `switch(c){default:...}`, char prongs unreachable at runtime |
| 2 | optional-of-slice null payload temp typed `int` | null-construction lower emits scalar `int` temp for the payload regardless of real type; valid for `?*T`, wrong for `?[]T` | gcc `-Wint-conversion` warning, type-incorrect C (latent) |

## Architecture

Two independent I-tasks (batched — both dispatched at once), then ONE combined STOP for operator ruling, then three F-tasks + a gate sweep.

```
I1 (char_literal switch-case) ─┐
I2 (opt_slice null payload)   ─┤ COMBINED STOP → F1 (char fix) → F2 (opt_slice fix) → F3 (Minor docs) → F4 (sweep)
                               └── (each F-task: runtime-gated on its battery)
```

### I-task requirement: read AND update tech docs

**Each I-task MUST read the relevant `sf/docs/tech_docs/*.md` file(s) and update them with its findings before reporting.** Per AGENTS.md §1.1.1 (technical documentation maintenance): when modifying pipeline code, update the corresponding tech doc with function signatures, descriptions, data flow, markers, and add `[updated: 2026-08-07]` annotation at the top of the changed section. Since the I-task investigates the defect that will later be fixed, it documents the CURRENT (buggy) behavior with correct line references and notes the gap — the F-task then re-verifies the doc after the code fix.

- I1 reads + updates: `sf/docs/tech_docs/07_lir_lowering.md` (switch case-collection section, `lower.zig` lowering)
- I2 reads + updates: `sf/docs/tech_docs/07_lir_lowering.md` (null-construction lower) + `sf/docs/tech_docs/08_c89_emission.md` (optional type emission, payload temp emission)

## Gates (global, per F-task)

- Build: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: sf/build/out_release/zig1 ===`, 0 gcc errors (QUICK_REF recipe).
- **RUNTIME gate mandatory per F-task**: each fixed repro must run rc=0 AND print the EXPECTED POST-FIX output (the 12 Battery A post-fix outputs + the 3 Battery B `1` with warnings GONE). Compile-only gates are FORBIDDEN (AGENTS §2.5.3).
- Corpus: 230 repros, OK=223/FAIL=3/gg=4 (raw 7), 231 dirs. FAIL count must not increase. Only the battery repros flip (Battery A runtime-gap-tracked → fully OK).
- 4 MD5 gates byte-identical to the 2026-08-07 baselines (mud `906fa59c…`, gol `0d8f0092…`, lisp `605b597e…`, json `b5f56ebd…`) UNLESS operator-approved re-baseline (F-5 AMENDMENT B precedent — runtime behavior is the gate, not byte-identity; I2 assesses the blast radius).
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- QUICK_REF.md reference mandatory for all gates.
- The plan is the ONLY authority. Plan says A → do A; if you think X/Y is better, STOP and present.

---

# Item 1: char_literal Switch-Case Labels

## Investigation (I1)

**Files:** `sf/src/lower.zig:3183`, `sf/src/lower.zig:3920`
**Read tech doc:** `sf/docs/tech_docs/07_lir_lowering.md`
**Update tech doc:** document the switch case-collection, the 4 literal kinds, corrected line refs, `[updated: 2026-08-07]`.

Confirm both case-collection loops check `int_literal` (`store.int_values.items[payload]`), `enum_literal` (enum_value_table), `error_literal` (error_code_registry), then `else { continue; }`. Confirm `char_literal` (kind 13) falls to `else { continue; }`. Verify the `char_literal` value is stored in `store.int_values` at the payload index (same accessor as `int_literal`). Verify the emitted-C symptom on a Battery A repro (no `case 'a':` label). Verify the zig0 oracle emits `case 'a':` correctly (post-fix reference). Assess blast radius: which of the 4 MD5 programs use char switches (mud/gol/lisp/json).

Options (A/B/C) — expected: Option A is the only viable fix (simple branch addition). Investigate and confirm no Option B/C exists.

## Fix (F1)

Per I1 ruling (expected Option A): add a `char_literal` branch to BOTH case-collection loops (`lower.zig:3183`/`:3920`), reading `case_val = store.int_values.items[@intCast(usize, case_node.payload)];` — mirroring the `int_literal` branch. Verify all 12 Battery A repros print their post-fix outputs.

**Gate:** build 0 err; all 12 Battery A repros dump rc=0, gcc rc=0, run rc=0 printing post-fix outputs; emitted C has `case 'a':`-style labels; 4 MD5s byte-identical (or re-baseline per ruling); corpus: 12 runtime-gap-tracked → fully OK, FAIL 3 stays.

---

# Item 2: opt_slice Null-Payload Temp Type

## Investigation (I2)

**Files:** lowerer null-construction path (locus to be located — likely `sf/src/lower.zig`), possibly `sf/src/c89_emit.zig` optional emission.
**Read tech docs:** `sf/docs/tech_docs/07_lir_lowering.md` + `sf/docs/tech_docs/08_c89_emission.md`
**Update tech docs:** correct the null-payload temp-type description in both, `[updated: 2026-08-07]`.

Trace `catch return null` in a `?[]T` function. Find where the null optional is constructed and where the payload temp type is assigned as `int` (or where the optional type's payload field type is ignored). Determine the correct payload type (the optional's payload type: pointer for `?*T`, slice struct for `?[]T`). Assess why `?*T` works today (payload temp `int` + `NULL` is compatible with a pointer field) and what breaks for `?[]T`. Assess blast radius: does any 4-MD5 program have `?[]T` with `catch return null`? Which MD5s would re-baseline?

Options (A/B/C): (a) type the null-payload temp at the optional's declared payload type; (b) skip the payload temp entirely when has_value=0 (payload dead); (c) narrow fix for slice-type payloads only. Investigate each's safety + blast radius.

## Fix (F2)

Per I2 ruling. Verify all 3 Battery B repros run rc=0 printing `1` with gcc `-Wint-conversion` warnings GONE.

**Gate:** build 0 err; all 3 Battery B repros dump rc=0, gcc rc=0 (0 warnings on the payload temp), run rc=0 printing `1`; 4 MD5s byte-identical or re-baseline per ruling; corpus: Battery B unchanged (already OK-by-gate), no regression.

---

# Item 3: Minor Doc Fixes from Final Review (F3)

**Files:**
- Modify: `docs/sf/QUICK_REF.md:201` (historical F5 row — superseded refs)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (historical rows at ~:38, :1220, :1250 — superseded refs; and the demoted Prior row build-evidence)
- Modify: 12 Battery A `NOTES.md` files (`repro/mi_matrix/switch_char_*/NOTES.md` — "FAIL" → "FAIL (runtime gap, NOT counted as corpus FAIL)")
- Modify: `repro/mi_matrix/opt_slice_null_xmod/NOTES.md` — (the 4th finding was dismissed; verify none needed)

From the repro battery final review, 3 actionable Minors:
1. **Stale refs:** QUICK_REF.md:201 + EXPECTED_FAIL.md historical rows cite `lower.zig:3858-3860/:3121-3123` (wrong — unrelated code). Actual sites: `:3183` expr / `:3920` stmt. Add a one-line supersede note in each historical row (e.g. "refs superseded — actual sites `:3183` expr / `:3920` stmt").
2. **Battery A NOTES terminology:** 12 NOTES.md say "Classification: **FAIL** (runtime gap…)" while the manifest/QUICK_REF say "OK-by-compile / runtime-gap-tracked, NOT added to FAIL". Add "not counted as a corpus FAIL" to each Battery A NOTES classification line (mirroring how `opt_slice_null_return` states it).
3. **Prior-row evidence:** the demoted EXPECTED_FAIL Prior row lost the "Verified with `/tmp/zf5/zig1` (fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors)" build-evidence sentence. Restore a one-line note.

**Gate:** doc-only; all cited line refs grep-verified against source; NOTES terminology consistent with manifest; 4 MD5s unaffected.

---

# Item 4: Gate Sweep + Docs (F4)

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, tech docs (07/08 as changed)

- Run full corpus sweep. Expected final: 230 repros — the 12 Battery A repros move from runtime-gap-tracked to fully OK (OK=223→235), the 3 Battery B repros stay OK-by-gate (warnings removed by F2 → fully OK, OK=235→238), FAIL=3 + green-guards=4 unchanged. Reconcile exact arithmetic during the task.
- 4 MD5s verified (or re-baselined with runtime proof).
- Update EXPECTED_FAIL.md (Battery A rows cleared from runtime-gap-tracked; Battery B warning notes updated), QUICK_REF baseline, tech docs for the changed files.
- Re-verify tech-doc line refs from I1/I2/F1/F2 remain correct post-fix.

**Gate:** corpus numbers recorded, FAIL=3 + green-guards=4 unchanged, 4 MD5s byte-identical (or re-baselined with runtime proof), docs consistent.

---

## Follow-ups (NOT this plan)

- **rogue_mud end-to-end re-attempt** after the char_literal fix — expect the input switch (main.zig:236-256) to become runtime-reachable; any remaining parser-incompatible source becomes new repros.
- The 0-FAIL corpus goal remains blocked by the 2 std-lib-deferred FAILs + 1 C89 fundamental.
