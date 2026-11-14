# Phase 3.5 D15 parity investigation — expected-type vs peer-type

**Task:** 9j (investigation/test-only; no `sf/src` change, no Task 9k).
**Status:** COMPLETE — STOP for operator review before Task 9k.
**Date:** 2026-11-09.
**Repo:** `/workspace/znineeight`, branch `zig1_improvements`, HEAD
`cf4cc032d9bdcb2d54e58a232a388f126e52abb6`.

**Binding rule (operator spec, D15):**

> Switch expressions use expected-type-first coercion when the result type is
> known (optional/error-union/null/noreturn prongs valid), and peer-type
> resolution only when it is not; unannotated mixed prongs remain invalid.
> — `docs/superpowers/specs/2026-10-29-phase35-defects-design.md:25`

§5.8 lists the known-result positions explicitly: return, typed var/const, call
argument, field/array initializer, nested result position. Rule 2 (no expected
type) peer-resolves and rejects incompatible prongs once at level 0 with 0 `.c`.
The interim `280a3b12` fix implemented only rule 2 and is over-broad; the 12
annotated corpus cases are false-rejected. This investigation establishes real
Zig 0.17.1 parity and an insertion-point contract for Task 9k.

---

## 1. Oracle and compilers

### Oracle (Zig 0.17.1)

No `zig` was on `PATH`; `/home/node/.cache/zig` contained only cache/probe
artifacts and no Zig installation. The official archive was downloaded and
verified:

| Item | Observed value |
|---|---|
| URL | `https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz` |
| SHA-256 | `3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a` |
| Archive | `/tmp/phase35-d15-i/zig-0.17.1.tar.xz` |
| Binary | `/tmp/phase35-d15-i/zig-0.17.1/zig` |
| `zig version` | `0.17.1` |

The oracle was used from `/tmp`; it was not installed on `PATH`. No substitute
version was used.

### Z98 pre-D15 base

| Item | Observed value |
|---|---|
| Commit | `32473a034317c626e38608599eb74a35e314fb7a` (`280a3b12^`) |
| Source | `git archive 32473a03` → `/tmp/phase35-d15-i/pre-d15-src` |
| Build | `bash scripts/self_compile/build_next_gen.sh /workspace/znineeight/zig1/zig1_5_clean /tmp/phase35-d15-i/pre-d15-build` |
| Binary | `/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean` |
| md5 | `1bdedb7419952ed10be80f1cca7b5476` |
| sha256 | `bb4ce380c84d2cc0495ba072ed31e07091aa08ad17b0485642ba70549fedfd02` |

### Z98 current

| Item | Observed value |
|---|---|
| HEAD | `cf4cc032d9bdcb2d54e58a232a388f126e52abb6` |
| `HEAD:sf/src/semantic_analyzer.zig` | `1fb55af6117dfe8372cf87cc587e5a8053b80977` (last changed by `280a3b12`; `e178063d` only restores test binaries) |
| `HEAD:sf/src/type_registry.zig` | `72fa25dd0b2ea676f603369e78e16da616ab2474` |
| `git status --porcelain -- sf/src` | empty (source clean) |
| In-tree seed `zig1/zig1_5_clean` md5 | `cd8d283b917749009961f4445043666b` |
| Current-source rebuild | `/tmp/phase35-d15-i/current-build/zig1_5_clean` |
| Current rebuild md5 | `5011d08cd6419d2f8b2cab2af0977055` |
| Current rebuild sha256 | `23befcded9c2adbf02741cdd22d9126e5603a219994fc3a49d7a8db2af8d6467` |

The in-tree seed md5 does **not** match a rebuild of current source, so the
three-way run uses the rebuilt current binary, not `zig1/zig1_5_clean`.

Exact provenance and build commands are recorded in
`repro/mi_matrix/known_excluded/d15_parity/results/compilers.txt`.

---

## 2. Method and probe set

All probes and observed outputs are committed under
`repro/mi_matrix/known_excluded/d15_parity/`. Run:

```sh
cd repro/mi_matrix/known_excluded/d15_parity
ZIG=/tmp/phase35-d15-i/zig-0.17.1/zig \
PRE=/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean \
CUR=/tmp/phase35-d15-i/current-build/zig1_5_clean \
./run_d15_parity.sh
```

Per probe:

```sh
# Zig 0.17.1 (no C emission: Zig builds an ELF object/executable)
zig build-exe <probe>.zig \
  --cache-dir /tmp/.../zig-cache --global-cache-dir /tmp/.../zig-global \
  -femit-bin /tmp/.../out

# Z98 pre-D15 and current
<Z> --check -ffast <probe>.zig
<Z> --dump-c89 -ffast --output-dir <tmp> <probe>.zig
```

`results/results.tsv` records the observed rc, unique diagnostic codes and the
number of `.c` files. `results/run.log` records the full observed diagnostic
text. `results/safe_spotcheck.tsv` repeats `--check -fsafe` for the corpus,
negative and selector sets; it matches `-ffast` throughout.

Observed C presence on Z98 accept is **5 `.c` files** (the program translation
unit plus `c_exit.c`, `zig_nocrt.c`, `zig_pal.c`, `zig_runtime.c`); on a sema
reject it is **0**. Zig does not emit C, so C presence is N/A for the oracle.

Probe groups:

- `matrix/`: expected type × position cross product.
  Expected types: `i32`, `?i32`, `error{E}!i32`, `error{E}!?i32`, `??i32`,
  `?*i32`, `[]const u8`, `f32`, plus `anyerror!i32` in return position.
  Positions: return, typed const, typed var, untyped const, untyped var, call
  argument, field initializer, array initializer, nested switch.
- `corpus_adapted/`: the 12 re-opened corpus cases, with only Zig-0.17.1
  hygiene changes (`var` never-mutated → self-assignment; `@intToPtr` → `&g`).
  The switch shape and typed var position are preserved.
- `corpus_raw/`: verbatim copies of the 12 corpus `main.zig` files. They are
  **not valid Zig 0.17.1** (old `var`/`@intToPtr` syntax), so Zig rejects them
  for unrelated reasons; the adapted twins are the parity oracle.
- `neg/`: the D15 mixed int/bool negatives with runtime selectors.
- `selectors/`: statement vs value switch, runtime vs comptime selector,
  tagged-union capture, noreturn and undefined.

---

## 3. Three-way matrix

Legend: `A` = accept (Z98 rc 0, C emitted; Zig rc 0); `R` = reject. Cell format
is `Zig / pre-D15 / current`. All values are observed in
`results/results.tsv`.

### 3.1 Expected type × position (value result position)

| Position | `i32` | `?i32` | `E!i32` | `E!?i32` | `??i32` | `?*i32` | `[]const u8` | `f32` | `anyerror!i32` |
|---|---|---|---|---|---|---|---|---|---|
| return | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | A/R/R |
| typed const | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | — |
| typed var | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | — |
| untyped const | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | — |
| untyped var | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | A/A/A | — |
| call argument | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | — |
| field initializer | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | — |
| array initializer | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | — |
| nested switch | A/A/A | A/A/R | A/A/R | A/A/R | A/A/R | A/A/R | A/A/A | A/A/A | — |

`—` = not probed: Z98 has no `anyerror` keyword (see §5.4). The `anyerror!i32`
return probe is Zig-accepted but Z98 rejects with `error[20]` in both pre-D15
and current, independent of D15.

The complete cross product (73 matrix probes) is in `matrix/`; the table above
is the full observed truth for every probed cell. Two facts stand out:

1. **Every expected-type-sensitive value position is Zig-accepted and
   pre-D15-accepted but current-rejected** for `?i32`, `E!i32`, `E!?i32`,
   `??i32` and `?*i32`. That is 35 matrix cells (seven value positions × five
   types) plus the 12 corpus cases.
2. **Untyped positions agree in all three compilers** (peer resolution), as do
   `i32`, slice and `f32` controls. The defect is specifically the missing
   expected-type rule, not a generic rejection problem.

### 3.2 The 12 re-opened corpus cases (`corpus_adapted/`)

All 12 are Zig-accepted, pre-D15-accepted, and current-rejected. Current emits
exactly one level-0 `error[3000]` and 0 `.c`; pre-D15 and Zig emit none.

| Case | Type | Zig | pre-D15 | current | current `error[3000]` notes |
|---|---|---|---|---|---|
| `eu_err_switch` | `E!i32` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `error-set` |
| `eunum_err_switch` | `E!u64` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `error-set` |
| `euopt_err_switch` | `E!?i32` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `error-set` |
| `euopt_val_switch` | `E!?i32` | A | A, 5 `.c` | R, 0 `.c` | `null` → `comptime_int` |
| `euoptptr_err_switch` | `E!?*i32` | A | A, 5 `.c` | R, 0 `.c` | `pointer` → `error-set` |
| `opt_null_switch` | `?i32` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `null` |
| `opteu_err_switch` | `?E!i32` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `error-set` |
| `opteu_null_switch` | `?E!i32` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `null` |
| `optnum_null_switch` | `?u64` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `null` |
| `optopt_null_switch` | `??i32` | A | A, 5 `.c` | R, 0 `.c` | `comptime_int` → `null` |
| `optopt_val_switch` | `??i32` | A | A, 5 `.c` | R, 0 `.c` | `null` → `comptime_int` |
| `optptr_null_switch` | `?*i32` | A | A, 5 `.c` | R, 0 `.c` | `pointer` → `null` |

Representative exact current output (`corpus_adapted/eu_err_switch.zig`):

```text
$ /tmp/phase35-d15-i/current-build/zig1_5_clean --check -ffast \
    repro/mi_matrix/known_excluded/d15_parity/corpus_adapted/eu_err_switch.zig
rc=2
.../eu_err_switch.zig:5:13: error[3000]: type mismatch in switch expression -- prong type may not be compatible with the switch expression type
        1 => 0,
             ^
note: source: comptime_int
note: target: error-set
```

The current diagnostic reports the peer type (`error-set` / `null` / first-prong
`comptime_int`) as the target, not the expected type. That is the signature of
the bug: the switch resolver never consults `topExpectedType` for general result
typing, so the first non-coercible peer pair is rejected even when the annotated
expected type accepts every prong.

### 3.3 `corpus_raw/` (verbatim old-syntax corpus)

Zig 0.17.1 rejects all 12 raw files for syntax/hygiene reasons unrelated to the
switch: 10 × `local variable is never mutated` and 2 × `invalid builtin
function: '@intToPtr'`. Pre-D15 accepts all 12 (Z98 syntax), current rejects all
12 with `error[3000]`. The adapted twins in §3.2 are the valid oracle comparison;
the raw results are recorded so the original corpus is not silently substituted.

### 3.4 Statement/value, selector, capture, noreturn and undefined

| Probe | Zig | pre-D15 | current | Classification |
|---|---|---|---|---|
| `selectors/stmt_void.zig` | A | A | A | Valid control (all prongs void) |
| `selectors/stmt_mixed_int_bool.zig` | R | A | A | **Current divergence** (mixed statement accepted) |
| `selectors/stmt_mixed_int_void.zig` | R | A | A | **Current divergence** (mixed statement accepted) |
| `selectors/sel_runtime_opt_i32.zig` | A | A | R | Current expected-type over-reject |
| `selectors/sel_comptime_opt_i32.zig` | A | A | R | Current expected-type over-reject (valid prongs) |
| `selectors/sel_comptime_mixed_i32.zig` | A | A | R | **Comptime-selector divergence** (Zig prunes untaken prong; spec rule 1 would reject it) |
| `selectors/sel_comptime_mixed_opt_i32.zig` | A | A | R | Same comptime-selector divergence |
| `selectors/sel_capture_tu.zig` | A | A | A | Capture unaffected |
| `selectors/sel_noreturn_i32.zig` | A | A | A | Noreturn prong unaffected |
| `selectors/sel_undefined_i32.zig` | A | A | A | Undefined prong unaffected |
| `selectors/sel_undefined_opt_i32.zig` | A | A | A | Undefined + optional unaffected |

D15 mixed negatives with runtime selectors (`neg/`):

| Probe | Zig | pre-D15 | current |
|---|---|---|---|
| `neg_mixed_direct.zig` | R | A | R (`error[3000]`, 0 `.c`) |
| `neg_mixed_infer.zig` | R | A | R (`error[3000]`, 0 `.c`) |
| `neg_mixed_use.zig` | R | A | R (`error[3000]`, 0 `.c`) |
| `neg_mixed_reverse.zig` | R | A | R (`error[3000]`, 0 `.c`) |
| `neg_mixed_bool_ret.zig` | R | A | R (`error[3000]`, 0 `.c`) |

Zig rejects the negatives because the prong types (`comptime_int`/`bool`) do
not unify; pre-D15 silently accepted and first-prong-typed them; current rejects
them correctly. Expected-type-first must preserve this rejection.

---

## 4. Classification

The correct rule is not uniform: it depends on whether a result type is known.

1. **Expected type known** (`return`, typed var/const, call argument,
   field/array initializer, nested result position): **expected-type-first**.
   Each prong must be assignable to the expected type. `typeRegistryIsAssignable`
   already covers null → optional, error set → error union, integer-literal →
   numeric, slice qualifiers, and optional/error-union unwrapping. The existing
   `semanticAnalyzerResolveIfExpr` path (`sf/src/semantic_analyzer.zig:4311-4328`)
   proves this machinery accepts every sensitive type in this matrix. Current
   Z98 is wrong here: it peer-resolves first and rejects 35 matrix cells + 12
   corpus cases.
2. **No expected type** (untyped var/const, statement switch): **peer
   resolution**. Current agrees for untyped bindings (all accept) but disagrees
   for mixed statement switches, which current accepts via `sw_is_stmt_expr`.
   The spec's rule 2 and Zig both reject them.
3. **Comptime-known selector**: Zig 0.17.1 analyzes only the taken prong, so a
   mixed switch with a literal selector is accepted. The spec's rule 1 says each
   prong must be assignable, which would reject the untaken mismatching prong.
   Current rejects. This is a real Zig/spec divergence; the D15 type rule does
   not settle Zig's lazy-prong analysis order. See §5.1.
4. **`anyerror!i32`**: Zig accepts; Z98 does not parse `anyerror` as a type in
   either pre-D15 or current (`error[20] identifier 'anyerror' is not declared`).
   This is a pre-existing keyword/type limitation, not a D15 typing rule.
5. **`f32`**: current FX10 value-aware behavior already matches Zig on this
   matrix; keep it out of the new generic path.

---

## 5. Divergences and residual issues

### 5.1 Zig vs spec on comptime-known selectors (operator ruling requested)

Zig 0.17.1 accepts `return switch (0) { 0 => 1, else => true };` in an `i32`
return and `switch (0) { 0 => null, else => true }` in `?i32`: the untaken prong
is never analyzed. Current Z98 rejects both with `error[3000]`; pre-D15 accepts
both. The spec's rule 1 ("each prong must be assignable to the expected type")
would reject the mismatching untaken prong, so **the spec and Zig do not agree
here**.

Recommendation: do **not** expand Task 9k to add switch-prong comptime pruning.
It is an analysis-order feature (the analyzer already has DED-2 fold gating, but
the sema switch resolver deliberately does not use selector comptime-ness for
typing). Implement the D15 rule as written and record this as an adjacent parity
gap for an operator decision. If Zig parity is required, the correct shape is
the if-expression's T3 gating: evaluate the selector, stamp untaken prongs
`TYPE_NORETURN`, and analyze only the taken prong. That is a larger blast radius
than D15 and should be its own task.

### 5.2 Statement mixed switches

Current Z98 accepts `switch (v) { 0 => 1, else => true }` as a statement because
the interim fix added `sw_is_stmt_expr` (`sf/src/semantic_analyzer.zig:5039-5044`,
used at `:5212`). Zig 0.17.1 rejects it (`incompatible types: 'comptime_int' and
'bool'`). The spec's rule 2 also rejects it. Task 9k must remove the statement
exemption; `stmt_void.zig` (all prongs void) still accepts because the prongs
unify before the MIX branch.

Residual risk: any existing in-tree source relying on heterogeneous statement
switches would become a reject. That is Zig/spec-correct, but 9k must run the
corpus/gates and migrate any such source.

### 5.3 Raw corpus is not a Zig-0.17.1 oracle

The original 12 cases use `var` bindings that Zig now rejects as never-mutated
and `@intToPtr`, which Zig 0.17.1 removed. The adapted twins preserve the switch
shape and typed var position, and all 12 are Zig-accepted. The report does not
claim Zig accepted the raw files.

### 5.4 `anyerror` and switch selectors

- Z98 does not resolve the `anyerror` keyword; the `anyerror!i32` oracle row is
  Zig-only. This is outside D15.
- Zig 0.17.1 rejects `switch` on optional and error-union *selectors*
  (`switch on optional type` / `switch on error union type`), while Z98 supports
  them. The D15 corpus switches on `u32` and uses optional/error-union *result*
  types, so this existing feature divergence is outside this task.

---

## 6. Recommended fix shape

### 6.1 Shape (a) — expected-type-first before the MIX branch (RECOMMENDED)

This is the minimal shape that mirrors the proven if-expression path and
implements the spec's rule 1 without weakening rule 2.

**Insertion points in `sf/src/semantic_analyzer.zig` (current HEAD line numbers):**

1. **Hoist the expected type before the prong loop**, next to the existing
   `sw_f32_site` setup at `:5037-5038`:
   ```zig
   var sw_exp = topExpectedType(self);
   if (sw_exp == type_mod.TYPE_VOID) sw_exp = 0;
   ```
   Keep `sw_f32_site` and the FX10 tail unchanged. The generic expected-first
   branch should be taken only when `sw_exp != 0` and `sw_f32_site == 0`.
2. **Remove the statement exemption** at `:5039-5044` (`sw_is_stmt_expr`) and the
   `if (sw_is_stmt_expr != 0)` branch at `:5212`. Statement switches then reach
   peer resolution exactly like untyped bindings; mixed prongs reject.
3. **Add one expected-type-first arm in the per-prong unification chain**, after
   `if (bt == TYPE_NORETURN) {}` at `:5174` and before the f32/peer branches
   (`:5175-5206`):
   ```zig
   else if (sw_exp != 0 and sw_f32_site == 0) {
       var sw_arm_str = isStringLiteralSliceCoercion(
           coercion_mod.classifyCoercion(self.registry, bt, sw_exp));
       var sw_arm_ok = bt == sw_exp or bt == type_mod.TYPE_NORETURN or sw_arm_str
           or type_mod.typeRegistryIsAssignable(self.registry, bt, sw_exp);
       if (sw_arm_ok) {
           if (bt != sw_exp) tryRecordCoercion(self, prong.child_0, bt, sw_exp);
           unified = sw_exp;
           unified_node = prong.child_0;
       } else {
           if (diag_mod.diagnosticCollectorMarkNodeOnce(self.diag, node_idx)) {
               var mix_tm_msg: []const u8 =
                   "type mismatch in switch expression -- prong type may not be compatible with the switch expression type";
               semanticAnalyzerTypeMismatchReport(self, prong.child_0, bt, sw_exp, mix_tm_msg, false);
           }
           unified = type_mod.TYPE_NORETURN;
           rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_NORETURN);
       }
   }
   ```
   `undefined` is accepted by `typeRegistryIsAssignable` (`undefined_type`
   returns true); `noreturn` is explicitly accepted. The existing peer path
   below remains for `sw_exp == 0` (untyped/statement). The existing MIX branch
   (`:5208-5212`) remains as the no-expected reject.
4. **Do not change** the f32 FX10 tail (`:5220-5265`), the mandatory-`else`
   reporter, the import idiom, the capture registration, or the zero-prong
   early returns.
5. Keep the existing `semanticAnalyzerTypeMismatchReport` reporter and message;
   only the target type changes from peer `unified` to expected `sw_exp`.

This is not a symptom patch: it restores the documented two-rule model (expected
type first; peer only when absent), reuses the same assignability predicate and
coercion recorder as the if-expression, and keeps the D15 mixed reject for
untyped cases. A special case such as "null/error-set are coercible" would not
fix `??i32`, `?*i32`, slices, nested switches, or statement mixed switches.

**Expected effect:**

- 12/12 `corpus_adapted/` cases accept (rc 0, C emitted), matching Zig and
  pre-D15.
- All 35 expected-type-sensitive matrix cells accept.
- D15 `neg/` cases keep rejecting (expected `i32` vs `bool`; untyped peer
  resolution).
- Statement mixed switches begin rejecting (Zig/spec parity); `stmt_void` stays
  accepted.
- Noreturn/undefined/captures/f32/enum/tagged-union/import idiom unchanged.
- Comptime-mixed switches remain rejected per spec rule 1 (see §5.1); this is
  the one known Zig divergence left after shape (a).

### 6.2 Shape (b) — full result-location expected-type push (NOT NEEDED)

The expected-type stack is already populated at every result position. Evidence:
the committed controls in `repro/mi_matrix/known_excluded/d15_parity/selectors/if_expected_positions/`
show the existing `semanticAnalyzerResolveIfExpr` expected-type path accepting
`?i32` `if` expressions at typed const, typed var, call argument, field
initializer, array initializer, and nested positions under both pre-D15 and
current Z98 (all Zig/pre/current accept; `results/results.tsv`). The switch
resolver already reads `topExpectedType` at `:5038` and `:5179`. Adding pushes
would be redundant and risks double-push/stack imbalance at sites that already
push. Shape (b) would increase blast radius without changing the outcome.

### 6.3 Shape (c) — shared if/switch type-resolution helper (OPTIONAL, LATER)

A shared helper (`semanticAnalyzerExpectedCoerceArm`, built on
`typeRegistryIsAssignable` + `tryRecordCoercion`) called by both
`semanticAnalyzerResolveIfExpr` and `semanticAnalyzerResolveSwitchExpr` would
prevent future drift. However, it would refactor the working if-expression path
(which is byte-sensitive) in the same task that fixes D15. Not recommended for
Task 9k; consider a post-D15 cleanup.

---

## 7. Blast radius

- **Code touched by shape (a):** `semanticAnalyzerResolveSwitchExpr` only. No
  parser, AST, lowering, emitter or type-registry change. The new path uses
  existing `typeRegistryIsAssignable`, `tryRecordCoercion`,
  `isStringLiteralSliceCoercion` and `semanticAnalyzerTypeMismatchReport`.
- **Behavior widened:** value switches with a known expected type now type to
  that expected type and record prong coercions, instead of peer-typing or
  rejecting. All 35 sensitive matrix cells and the 12 corpus cases are currently
  rejected; they become accepted. Existing already-valid switches whose peer
  type and expected type agree are unchanged. Switches where expected and peer
  differ should now follow the expected type, which is the documented rule; 9k
  must run the existing valid-switch/fixture comparison to prove no emission
  regression.
- **Behavior narrowed:** heterogeneous statement switches now reject (removal of
  `sw_is_stmt_expr`). This is Zig/spec-correct but is the main migration risk.
- **Unaffected:** f32 FX10, enum/tagged-union prongs and captures, import idiom,
  mandatory `else`, zero-prong handling, noreturn/undefined, untyped peer
  resolution, and all emitter/lowering code.
- **Tests required in 9k:** 12 corpus cases accept; five D15 negatives reject
  with one level-0 mismatch and 0 `.c`; matrix sensitive cells accept; statement
  mixed rejects; `stmt_void`, capture, noreturn, undefined and f32 controls stay
  green; existing valid-switch fixtures byte-identical; `test_semantic_bin`
  green; corpus/gates no new false rejects.

---

## 8. STOP — operator review

Task 9k must not start until the operator approves this report. Two items need an
explicit ruling:

1. **Comptime-known selector parity** (§5.1): Zig accepts the untaken mismatching
   prong; the spec's rule 1 rejects it. Recommendation: keep the spec rule and
   defer Zig lazy-prong parity to an adjacent task. If the operator wants Zig
   parity inside D15, 9k's scope and blast radius grow.
2. **Statement mixed switches** (§5.2): remove the interim `sw_is_stmt_expr`
   exemption in 9k (Zig/spec reject). Confirm no accepted in-tree source relies
   on the old behavior; 9k must run the corpus/gates and migrate if needed.

No `sf/src` file was changed by Task 9j.
