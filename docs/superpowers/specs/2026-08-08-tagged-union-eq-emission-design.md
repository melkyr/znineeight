# Tagged-Union `==` Binary Emission Fix Design Spec

**Date:** 2026-08-08
**Status:** Approved by operator (m0471 ruling: Option A — supersede zig0, valid Zig behavior). Ready for plan.

## 1. Goal

Make tagged-union comparison (`s == Shape.Circle`, `s != Shape.Circle`) emit valid C that compiles and runs correctly. This supersedes the zig0 oracle, which rejects `==` on unions (type-mismatch error). The operator ruled (m0471): "we can supersede zig0 and use valid zig so option A, filling out all gaps required either in LIR or lower and emission if needed or sema if so."

## 2. Problem Statement

Post-F6 (commit efbf4807, the tagged-union member-access SEGV fix), the repro `repro/mi_matrix/tagged_union_cmp_xmod/` dumps rc=0 (no SEGV) but the emitted C for the `==` comparison is **gcc-invalid**: `binary ==` on the union struct.

The C89 emitter's `.binary` handler (`sf/src/c89_emit.zig:3708-3744`) is type-unaware — it emits `result = lhs op rhs;` for ALL binary operators. For tagged-union operands (C struct: `.tag` + `union{}` payload), both LHS and RHS are full structs → gcc `error: invalid operands to binary ==`.

The lowerer is already correct: `cmp_eq` (lower.zig:1462) lowers `s == Shape.Circle` to a `BIN_EQ` LIR instruction with the LHS temp (union-typed) and RHS temp (union-typed, `.tag` set to the variant ordinal via `emitTaggedUnionInit`). Only the emitter's C output is wrong.

## 3. Architecture

**Single fix in the emitter's `.binary` handler.** When the op is `BIN_EQ` (10) or `BIN_NE` (11), check each operand's temp type; if `tagged_union_type`, append `.tag` to the emitted C operand name.

Valid Zig semantics: `s == Shape.Circle` compares the active tag (`s.tag`) against the variant ordinal (`Shape.Circle` → tag value 0). Both operands' `.tag` fields are compared as integers.

**Precedent in the same file:** the `.tag` access pattern is already used at `c89_emit.zig:3441-3443` (load_field accesses `.tag` when `field_id == TU_FIELD_TAG`) and `:3762-3784` (int_const with tagged-union type emits `.tag = X`). The temp-type lookup pattern (iterate `hoisted_temps`, match `temp_id`, check `registry.types_items[tid].kind`) is used at `:3768-3779`.

## 4. Tasks

### 4.1 F — Fix tagged-union `==`/`!=` binary emission (Option A, emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (`.binary` handler at `:3708-3744`)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Test: `repro/mi_matrix/tagged_union_cmp_xmod/`

**Change:** After `lhs = resolveTempName(...)` (:3717) and `rhs = resolveTempName(...)` (:3723), for `BIN_EQ`/`BIN_NE` ops, iterate `hoisted_temps` to resolve each operand's type; for any operand whose type is `tagged_union_type`, set a `.tag` suffix. Emit the suffix after the operand name in the emission block (:3736-3743).

Resulting C: `zT_result = zT_s.tag == zT_rhs.tag;` — valid `unsigned int == unsigned int`.

**Gate:**
- Repro `tagged_union_cmp_xmod/`: dump rc=0, gcc compile rc=0, run rc=0 printing `1`
- Same-module union `==` variant: gcc-clean (currently also gcc-invalid — same gap, now fixed)
- No regression: F3 repros (`zT_missing_fwd_xmod/`, `json_parser_workaround/`) still gcc-clean
- 4 MD5 gates byte-identical: mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `a12f2fcebc30f2d8c2a148facb9d1174` (post-F1), json `c403f0799dbc5c56d548eee07bb9eebd`
- test_analyzer_bin PASS
- Tech doc `08_c89_emission.md` updated to FIXED (`[updated: 2026-08-08]`)

## 5. Blast Radius

- **Repro:** `tagged_union_cmp_xmod/` goes from gcc-FAIL → OK (dump/gcc/run green).
- **Same-module union `==`:** any same-module `s == Shape.Circle` (currently gcc-invalid, same gap) also fixed.
- **Other binary ops on tagged unions:** untouched (only `==`/`!=` get the `.tag` treatment; `<`, `>`, arithmetic on unions remain type-unaware but sema rejects those as invalid before lowering).
- **MD5 gates:** none use union `==` — byte-identical.
- **zig0 oracle:** superseded for this construct (operator ruling m0471). zig0 rejects; zig1 now emits valid C. This is the intended divergence.

## 6. Out of Scope

- **Tagged-union payload-read lowering** (`s.Circle` reads the payload value) — separate latent issue (currently lowers to the tag value), documented as a follow-up.
- **`==` on non-tagged `union_type`** — only `tagged_union_type` is in scope.
- **Option B (sema reject)** — rejected by the operator (m0471).
