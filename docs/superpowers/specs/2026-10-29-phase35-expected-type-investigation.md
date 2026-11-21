# Phase 3.5 Task 12.2-I — expected-type sentinel contract investigation

**Task:** 12.2-I (investigation/report only; no `sf/src` change, no fix).
**Status:** COMPLETE — STOP for operator review before Task 12.2-F.
**Date:** 2026-11-09.
**Repo:** `/workspace/znineeight`, branch `zig1_improvements`, HEAD
`36e39cf3` (v146 seed rotation).
**Binding inputs:** `task-12.2-I-brief.md`, the final whole-branch review finding
in `progress.md`, the expected-type stack in `sf/src/semantic_analyzer.zig`,
and `docs/superpowers/specs/2026-10-29-phase35-d15-parity-investigation.md`.

**No `sf/src` file was changed.** Probes and observed outputs are committed
under `repro/mi_matrix/known_excluded/expected_type_contract/`.

---

## 1. Executive summary

The final-review finding reproduces exactly:

| compiler | `--check -ffast` | `--dump-c89 -ffast` |
|---|---|---|
| v145 (`cd8d283b…`) | rc 0 | rc 0, 5 `.c` |
| v146 (`de5e99b6…`) | rc 2, `error[3000]`, `target: type` | rc 2, 0 `.c` |

The root cause is a split "no expected type" convention:

- the function-local declaration producer normalizes an unannotated decl to
  `0` (`sf/src/semantic_analyzer.zig:6713`) before
  `pushExpectedType` (`:6714`);
- the module declaration producer pushes `decl_type` directly
  (`:7576`), and `decl_type` is `TYPE_UNDEFINED` for an unannotated binding;
- the D15 expected-type-first switch branch (`:5049-5050`) normalizes only
  `TYPE_VOID`, not `TYPE_UNDEFINED`, so it treats `TYPE_UNDEFINED` as a real
  expected type. No value type is assignable to it, and the diagnostic
  fallback prints it as `type`.

`TYPE_UNDEFINED` is an undetermined/poison marker, not a type: the type
resolver already states this (`sf/src/type_resolver.zig:411-418`). The contract
should be: **a pushed expected type is either a real type or `0` (no expected
type); `TYPE_UNDEFINED` must never be used as an assignability target.**

**Recommendation:** option (a), normalize the module declaration producer to
`0` at `sf/src/semantic_analyzer.zig:7576`, mirroring the local rule at
`:6713`. One producer site, no consumer change, no parser/lowering/emitter
change. The v146 seed contains the false reject; after the fix the seed must be
rotated (v147) or the operator must waive the invalid v146 artifact.

---

## 2. Sentinels and the intended contract

| value | id | meaning in this codebase | may it be a pushed expected type? |
|---|---|---|---|
| `0` | n/a | "no type id / absent" | yes — this is the no-expected marker |
| `TYPE_VOID` | 1 | real `void` type; historically also "no value expected" | as a real type only; consumers normalize it as no-expected |
| `TYPE_UNDEFINED` | 18 | undetermined / failed resolution / poison | **no** — never a real assignability target |
| `TYPE_TYPE` | 20 | the `type` value | only when a `type` value is genuinely expected |

`sf/src/type_resolver.zig:411-418` says `0` and `TYPE_UNDEFINED` "are never
types". `diagnostics.zig:934-992` has no `undefined_type` branch in
`typeKindTgtStr`, so it falls through to `return s_type;` (`:992`) and prints
the sentinel as `target: type`. That is the observed v146 diagnostic, not a
real `type` expectation.

The codebase already uses three different no-expected spellings:

- `0` — local unannotated decl (`:6713`), extra call arguments
  (`:3581`, `:3589`), non-callable-callee arguments (`:3639`);
- `TYPE_VOID` — a real `void` expectation; if/switch/`@ptrFromInt`
  consumers special-case it;
- `TYPE_UNDEFINED` — call-argument parameter type when unresolved
  (`:3584-3585`, `:3679`) and the module unannotated decl (`:7576`).

The split is the defect. The target contract is: producers translate "I do not
know an expected type" to `0`; `TYPE_UNDEFINED` is reserved for
undetermined/poison results and consumers must not use it as a type.

---

## 3. Step 0 — reproduction

Primary probe (`probes/module_const_switch_unannotated.zig`):

```zig
const X = switch (1) { 0 => 1, else => 7 };

pub fn main() void {
    _ = X;
}
```

Observed with the v145 and v146 seed binaries:

```sh
# v145
$ /tmp/expected-type-i/v145/zig1-seed/zig1 --check -ffast probes/module_const_switch_unannotated.zig
Z98 Compiler 2026 (map: off)
rc=0

$ /tmp/expected-type-i/v145/zig1-seed/zig1 --dump-c89 -ffast \
    --output-dir /tmp/.../v145 probes/module_const_switch_unannotated.zig
rc=0; 5 .c files

# v146
$ /tmp/expected-type-i/v146/zig1-seed/zig1 --check -ffast probes/module_const_switch_unannotated.zig
.../module_const_switch_unannotated.zig:1:28: error[3000]: type mismatch in switch expression -- prong type may not be compatible with the switch expression type
const X = switch (1) { 0 => 1, else => 7 };
                            ^
note: source: comptime_int
note: target: type
rc=2

$ /tmp/expected-type-i/v146/zig1-seed/zig1 --dump-c89 -ffast \
    --output-dir /tmp/.../v146 probes/module_const_switch_unannotated.zig
rc=2; 0 .c files
```

Equivalent module-scope unannotated `if` controls (`module_const_if_unannotated`,
`module_var_if_unannotated`, `module_if_strings_unannotated`) accept on **both**
v145 and v146. Annotated module/local `if` and `switch` controls also accept on
both. The regression is switch-specific, but the sentinel reaches nested
switches under a module `if` arm and an untyped tuple literal (see §6).

**Compiler provenance is load-bearing:** the working-tree
`zig1/zig1_5_clean` is md5 `cd8d283b…` (v145), not v146. The v146 column uses
the compiler extracted from `release/seed/zig1-seed.tgz` (md5 `de5e99b6…`).
See `results/compilers.md`.

---

## 4. Step 1 — producer inventory (`pushExpectedType`)

Current `sf/src/semantic_analyzer.zig` line numbers.

| line | producer context | pushed value | class | intentional? |
|---|---|---|---|---|
| 2619 | comparison: contextual error/enum literal on RHS | peer operand type `lhs` | known type | yes — selected only when peer kind is error-set/enum/tagged-union; guards `0`/void/undefined |
| 2626 | comparison: contextual error/enum literal on LHS | peer operand type `rhs` | known type | yes — same guard |
| 3326 | `return expr` | `self.current_fn_return` | known type (could be `void` for a void function) | yes |
| 3588 | direct call argument | `0` when no known parameter; parameter type when known; `TYPE_UNDEFINED` is only an initialization placeholder at `:3584` and is overwritten by map/xt | known type or `0`; `TYPE_UNDEFINED` only if an unresolved parameter type is stored | mostly yes — the `0` cases are deliberate no-expected; unresolved-parameter `TYPE_UNDEFINED` is an unknown/undetermined value that downstream checks already skip |
| 3639 | non-callable callee arguments | `0` | no expected | yes |
| 3679 | fn-value call argument | `param_type` from `xt_items`; can be `TYPE_UNDEFINED` for an unresolved parameter | known type, or unknown/undetermined | yes for known; unresolved `TYPE_UNDEFINED` is not a real type and downstream checks (`:3682`, `:3699`) already treat it as no/unknown expected |
| 3709 | variadic extra call argument | `0` | no expected | yes |
| 3829 | `orelse` fallback | optional payload type | known type | yes |
| 4500 | struct/union/tagged-union field initializer | `field_type` | known type | yes |
| 4692 | assignment RHS | `lhs` type | known type in valid code; `TYPE_UNDEFINED` only if the LHS is already poisoned | yes for valid code; poison case is invalid code and not demonstrated |
| 5155 | switch error-case item | `cond_es` error set | known type | yes |
| 5701 | `catch` handler error literal | `catch_es` error set | known type | yes |
| 6713-6714 | **local** variable declaration initializer | `decl_type` when annotated, **`0` when `TYPE_UNDEFINED`** (`vd_exp`) | known type or no expected | **yes — this is the reference rule** |
| 7483 | array literal element | `elem_expected`, pushed only when `!= TYPE_UNDEFINED` | known type | yes |
| 7576 | **module** variable declaration initializer | `decl_type` directly; **`TYPE_UNDEFINED` when unannotated/unresolved** | known type **or unknown/undetermined misused as no-expected** | **no for the unannotated case — defect** |

Conclusion: the module declaration producer is the only producer that maps the
valid state "no declared type" to `TYPE_UNDEFINED` instead of `0`. Every other
no-expected producer uses `0`. The local declaration producer is the intended
reference implementation.

---

## 5. Step 1 — consumer inventory (`topExpectedType` + raw stack reads)

### 5.1 Via `topExpectedType`

| line | consumer | recognizes as no-expected | `TYPE_UNDEFINED` behavior | assessment |
|---|---|---|---|---|
| 4311 | `if` expression result typing (`semanticAnalyzerResolveIfExpr`) | `0`, `TYPE_VOID` | enters expected branch; mismatch falls through to peer resolution; no diagnostic from this branch | benign for the observed module `if` controls, but not normalized |
| 4541 | untyped struct literal target | `0` | `TYPE_UNDEFINED` is non-zero; lookup by that id is not a struct/tagged-union/union and falls through to `TYPE_VOID` | benign; should be no-expected |
| 5038 | switch f32-site detection | n/a (exact `TYPE_F32` test) | not f32 | benign |
| 5049-5050 | **D15 expected-type-first switch** | `0`, `TYPE_VOID` | **treated as a real expected type → false reject** | **defect** |
| 5204 | switch no-unified peer/string fallback | `0`, `TYPE_VOID` | `TYPE_UNDEFINED` disables the string-literal-slice heuristic (`:5206-5210`) | latent; option (d) must address this second read, not only `:5049` |
| 5526 | `@ptrFromInt` result-type inference | `0`, `TYPE_UNDEFINED` (explicitly excludes both) | treated as no expected | correct; proves the intended normalization |

### 5.2 Direct stack reads (not via `topExpectedType`)

| line | consumer | recognizes as no-expected | `TYPE_UNDEFINED` behavior | assessment |
|---|---|---|---|---|
| 3803-3805 | `orelse` on a bare `null` | `0` only | non-zero, so it builds an optional from the sentinel id | latent contract violation; pre-existing, not a valid-code regression observed here |
| 4428-4430 | enum-literal contextual typing | `0` only | non-enum kind → falls through as unresolved | benign |
| 5381-5383 | error-literal contextual typing | `0` only | non-error-set kind → falls through | benign |

The only consumer that turns `TYPE_UNDEFINED` into a **valid-code false
rejection** is the D15 switch branch at `:5049`. The module `if` path is
protected by its fall-through; `@ptrFromInt` already excludes the sentinel;
struct/enum/error-literal paths fall through harmlessly. The raw `orelse`
read is the other place where the sentinel is treated as a type, but no valid
module probe exposed it; it remains a contract inconsistency.

---

## 6. Step 2 — probe matrix and observed results

Committed probes: `repro/mi_matrix/known_excluded/expected_type_contract/probes/`.
Raw results: `results/results.tsv`; raw compiler text: `results/run.log`.

Legend: `A` = accept (v145/v146 `--check` rc 0 and `--dump-c89` 5 `.c`);
`R` = reject (rc 2, `error[3000]`, 0 `.c`). Zig 0.17.1 is the oracle where
available; all probes use shared Z98/Zig syntax except the `@ptrFromInt`
inference control.

### 6.1 Declaration binding: module vs local, unannotated vs annotated

| probe | Zig | v145 | v146 |
|---|---|---|---|
| `module_const_switch_unannotated` | A | A | **R** |
| `module_var_switch_unannotated` | A | A | **R** |
| `module_const_switch_typed_prongs_unannotated` (`@as(i32, …)` prongs) | A | A | **R** |
| `module_switch_strings_unannotated` | A | A | **R** |
| `module_const_switch_annotated` (`i32`) | A | A | A |
| `module_var_switch_annotated` (`i32`) | A | A | A |
| `local_const_switch_unannotated` | A | A | A |
| `local_var_switch_unannotated` | A | A | A |
| `local_const_switch_annotated` (`i32`) | A | A | A |
| `local_var_switch_annotated` (`i32`) | A | A | A |
| `local_switch_strings_unannotated` | A | A | A |
| `module_const_if_unannotated` | A | A | A |
| `module_var_if_unannotated` | A | A | A |
| `module_const_if_annotated` (`?i32`) | A | A | A |
| `module_var_if_annotated` (`?i32`) | A | A | A |
| `module_if_strings_unannotated` | A | A | A |
| `local_const_if_unannotated` | A | A | A |
| `local_var_if_unannotated` | A | A | A |
| `local_const_if_annotated` (`?i32`) | A | A | A |
| `local_var_if_annotated` (`?i32`) | A | A | A |

The `var` switch probes use `@as(i32, …)` prongs so the Zig oracle does not
reject them for `comptime_int`-typed `var` (a Zig hygiene rule unrelated to the
Z98 defect). The same module unannotated `var` sentinel applies with or without
typed prongs.

### 6.2 Nested / propagated sentinel

| probe | Zig | v145 | v146 | note |
|---|---|---|---|---|
| `module_tuple_switch_unannotated` | A | A | **R** | tuple literal does not push an expected type, so the switch sees the module sentinel |
| `module_if_switch_arm_unannotated` | A | A | **R** | `if` arm resolves under the same module sentinel |
| `module_nested_switch_unannotated` | A | A | **R** | inner and outer both see the sentinel |

### 6.3 Known expected-type positions (inner push overrides the module sentinel)

| probe | Zig | v145 | v146 |
|---|---|---|---|
| `module_callarg_switch` / `local_callarg_switch` | A | A | A |
| `module_struct_field_switch` / `local_struct_field_switch` | A | A | A |
| `module_array_elem_switch` / `local_array_elem_switch` | A | A | A |
| `local_return_switch` | A | A | A |
| `module_ptr_from_int_annotated` | A | A | A |
| `module_ptr_from_int_unannotated` | R (`@ptrFromInt` needs known result type) | R (`error[19]`) | R (`error[19]`) |

These confirm the D15 expected-type push works where an expected type is
genuinely known; the defect is only the module declaration sentinel.

### 6.4 Existing D15 controls re-run on v146

The D15 matrix and negative set under
`repro/mi_matrix/known_excluded/d15_parity/` were re-run:

- `matrix/typed_const_opt_i32`, `untyped_const_opt_i32`, `ret_opt_i32`,
  `callarg_opt_i32`, `field_opt_i32`, `array_opt_i32`, `nested_opt_i32` — all
  rc 0 on v145 and v146 (typed prongs; expected-first remains correct).
- `neg/neg_mixed_{direct,infer,use,reverse,bool_ret}` — all rc 2, one
  `error[3000]`, 0 `.c` on v146 (D15 negative rejection preserved).
- `selectors/stmt_mixed_int_bool` and `selectors/stmt_void` — rc 0 on v146
  (current `sw_is_stmt_expr` statement-switch behavior is still present; this
  task does not re-litigate it).

The full result matrix is `results/results.tsv`.

---

## 7. Root cause

v145 already pushed `TYPE_UNDEFINED` for an unannotated module declaration
(`git show 07144129:sf/src/semantic_analyzer.zig`, module declaration push at
old `:7440`). v145's switch had no expected-type-first branch, so it never
consulted the sentinel; it peer-resolved and accepted.

Task 9k (`ace04574`) added the D15 expected-first branch. It hoists
`topExpectedType` and normalizes only `TYPE_VOID`:

```zig
var sw_exp: u32 = topExpectedType(self);
if (sw_exp == type_mod.TYPE_VOID) sw_exp = @intCast(u32, 0);
```

For an unannotated module declaration the stack top is `TYPE_UNDEFINED` (18);
`sw_exp` stays 18. The branch then asks whether each prong is assignable to 18.
`typeRegistryIsAssignable` has no rule that makes a real value assignable to
`undefined_type`, so every normal prong such as `comptime_int` fails. The
mismatch reporter prints the target through `typeKindTgtStr`, which has no
`undefined_type` case and falls through to `type`.

Why the other constructs are not regressed:

- **module `if`:** `semanticAnalyzerResolveIfExpr` sees `TYPE_UNDEFINED` as a
  non-zero expected type, tries the expected branch, fails, and falls through
  to peer typing without a diagnostic. That happens to match v145 for the
  observed arms.
- **untyped tuple literal:** it does not push an expected type, so a switch
  element still sees the module sentinel and fails.
- **module `if` arm:** the arm is resolved under the same module sentinel; a
  switch inside it fails even though the `if` itself would accept.
- **call argument / struct field / array element / return:** each pushes a known
  type before resolving the switch/if, masking the module sentinel.
- **`@ptrFromInt`:** it explicitly excludes both `0` and `TYPE_UNDEFINED`
  (`:5526-5527`), so it already behaves as no-expected.

The switch also has a **second** raw expected-type read at `:5204` for the
string-literal-slice fallback; a fix that only rewrites `:5049` would leave
that path inconsistent. This is important when rejecting option (d).

---

## 8. Step 3 — option evaluation

### Option (a) — normalize the module declaration producer to `0` (RECOMMENDED)

Change `sf/src/semantic_analyzer.zig:7576` so the module declaration mirrors
the local rule at `:6713`:

```zig
// current
pushExpectedType(self, decl_type);

// proposed semantics (not applied)
var mvd_exp: u32 = decl_type;
if (mvd_exp == @intCast(u32, type_mod.TYPE_UNDEFINED)) mvd_exp = @intCast(u32, 0);
pushExpectedType(self, mvd_exp);
```

- **Touches:** one producer site (`:7576`). No consumer, parser, lowerer,
  emitter, or type-registry change.
- **Fixes:** every valid-code leak of the module sentinel: direct switch,
  switch in an untyped tuple, switch in a module `if` arm, nested switch, and
  string switches. Because the stack top becomes `0`, both switch reads
  (`:5049` and `:5204`) and all other consumers automatically see no-expected,
  restoring v145 behavior.
- **Behavior changes:** module unannotated value switches that v145 accepted
  become accepted again (rc 0, 5 `.c`); annotated declarations and all known
  expected-type positions are unchanged; module unannotated `if` and
  `@ptrFromInt` controls are unchanged. Any exotic module-unannotated
  expression that previously observed `TYPE_UNDEFINED` as an expected value now
  observes `0`; the audit found only the D15 switch branch converts that into a
  valid-code reject.
- **Risk:** low. The only semantic change is "undeclared module type" now
  meaning no expected type, which is exactly the local rule. Annotated-but-
  unresolved module types also push `0`; such code already fails its annotation
  resolution elsewhere.

### Option (b) — enforce a push/top invariant or normalization helper

Two variants:

1. **Normalize inside `pushExpectedType` (`:6217-6225`):** translate
   `TYPE_VOID`/`TYPE_UNDEFINED` (and `0`) to `0` on push.
2. **Normalize inside `topExpectedType` (`:6233-6236`) plus the three raw reads**
   (`:3804`, `:4429`, `:5382`): translate the same sentinels to `0` on read.

- **Touches:** all 14 producer sites (variant 1), or 6 `topExpectedType` reads
  plus 3 raw reads (variant 2); the stack's element contract changes across
  the analyzer.
- **Pros:** central invariant; prevents future producers from repeating the
  split; variant 1 would also protect invalid-code cascade paths (for example
  an unresolved fn-value parameter or a poisoned assignment LHS pushed as
  `TYPE_UNDEFINED`).
- **Cons:** broader blast radius than the one valid-code defect requires.
  Variant 1 changes call-argument `TYPE_UNDEFINED` semantics and any legitimate
  `TYPE_VOID` push used as a real `void` expectation (for example a void-typed
  field initializer); it needs the full corpus, stdlib, self-host, and seed
  battery to prove no emission/acceptance change. Variant 2 does not fix the
  producer contract and must also update the raw reads or it remains
  inconsistent. It is defensible hardening, but not the minimal fix for
  Task 12.2-F.

### Option (c) — explicit expected-type enum/optional contract

Replace the `u32` stack entries with something like
`ExpectedType = union(enum) { none, known: TypeId, undetermined }`, or an
optional `TypeId` with `null` as no-expected.

- **Touches:** the analyzer struct field and initialization (`:59-62`,
  `:285-288`), grow/alloc (`:766`, `:782`), `pushExpectedType`/`popExpectedType`/
  `topExpectedType` (`:6217-6236`), all 14 producers, all 6 `topExpectedType`
  consumers, and the 3 raw stack reads; plus any code that assumes the stack
  holds `u32`.
- **Pros:** makes the contract explicit and type-checked; `undetermined` can be
  distinguished from `none` if a future consumer needs that.
- **Cons:** largest blast radius, touches byte-sensitive analyzer code and the
  analyzer struct, and requires a full battery plus seed rotation. No current
  consumer needs three states; the valid-code defect is one producer using the
  wrong sentinel. Defer as a post-Phase-3.5 cleanup if the operator wants a
  permanent type-level contract.

### Option (d) — switch-only normalization (REJECTED as a patch)

Change only the D15 switch branch, for example:

```zig
if (sw_exp == type_mod.TYPE_VOID or sw_exp == type_mod.TYPE_UNDEFINED) sw_exp = 0;
```

- **Touches:** `:5049-5050`, and necessarily also the second raw read at
  `:5204-5208`; otherwise module unannotated string switches still bypass the
  string-literal-slice heuristic and may diverge from v145.
- **Pros:** smallest textual change; fixes the primary repro quickly.
- **Cons:** leaves the producer contract split (module still pushes
  `TYPE_UNDEFINED`); leaves the raw `orelse` read (`:3803`) and any future
  expected-sensitive consumer with the same trap; treats the symptom in one
  consumer. It is a patch, not a sound contract, and the brief explicitly
  rejects it.

---

## 9. Step 4 — recommended design and test matrix

### 9.1 Recommended change (Task 12.2-F, not implemented here)

**Option (a):** in `sf/src/semantic_analyzer.zig`,
`semanticAnalyzerResolveModuleVarDecl`, normalize `TYPE_UNDEFINED` to `0`
before the push at `:7576`, mirroring `:6713`:

```zig
var mvd_exp: u32 = decl_type;
if (mvd_exp == @intCast(u32, type_mod.TYPE_UNDEFINED)) mvd_exp = @intCast(u32, 0);
pushExpectedType(self, mvd_exp);
```

Do **not** change the switch consumer, the `if` consumer, the f32 branch,
`sw_is_stmt_expr`, or any other producer in 12.2-F.

Optional hardening (separate task, only if the operator wants an enforced
invariant): add a small declaration-expected helper shared by `:6713` and
`:7576`, or adopt option (b) variant 1 with a full battery. Neither is needed
to make valid code match v145.

### 9.2 Test matrix

**A. New probes (must all match v145 and Zig):**

- `module_const_switch_unannotated`, `module_var_switch_unannotated`,
  `module_const_switch_typed_prongs_unannotated`,
  `module_switch_strings_unannotated` — rc 0, 5 `.c`.
- `module_tuple_switch_unannotated`, `module_if_switch_arm_unannotated`,
  `module_nested_switch_unannotated` — rc 0, 5 `.c`.
- `module/local` annotated and local unannotated switch/if controls — unchanged
  rc 0, 5 `.c`.
- `module_callarg_switch`, `module_struct_field_switch`,
  `module_array_elem_switch`, `local_*` position controls, `local_return_switch`
  — unchanged rc 0, 5 `.c`.
- `module_ptr_from_int_annotated` — rc 0; `module_ptr_from_int_unannotated` —
  unchanged rc 2 `error[19]` (proves the normalization does not infer a pointer
  type).

Run the committed harness:

```sh
cd repro/mi_matrix/known_excluded/expected_type_contract
Z145=<v145 seed>/zig1 Z146=<v146 build>/zig1 \
ZIG=/tmp/phase35-d15-i/zig-0.17.1/zig ./run_expected_type_contract.sh
```

**B. D15 regression controls (must not weaken):**

- `d15_parity/matrix/*` expected-type-sensitive cells still accept
  (`typed_const`, `ret`, `callarg`, `field`, `array`, `nested`, `untyped`
  typed-prong controls).
- `d15_parity/neg/neg_mixed_{direct,infer,use,reverse,bool_ret}` still reject
  with exactly one level-0 `error[3000]` and 0 `.c`.
- `d15_parity/selectors/stmt_void` still accepts; statement mixed-switch
  behavior (`sw_is_stmt_expr`) is unchanged by this fix.
- `d15_parity/selectors/sel_noreturn_i32`, `sel_undefined_i32`,
  `sel_undefined_opt_i32`, `sel_capture_tu` unchanged.

**C. Whole-compiler gates (Task 12.2-F acceptance):**

- `test_semantic_bin`, analyzer/integration suites green.
- Corpus and frozen list: no new false rejects, no acceptance/emission delta
  for already-accepted programs; compare emitted C for the five standard inputs.
- `--check` in both `-ffast` and `-fsafe`; 9/9 emit-support gate; goldens;
  markers; examples; stdlib/crosscheck.
- Self-host hop2 == hop3.
- After the fix, rotate the seed (v147) because v146 contains the false reject,
  or record an explicit operator waiver.

**D. Negative/contract tests (recommended, not required):**

- An annotated-but-unresolved module type still reports its existing annotation
  error, not a new switch cascade.
- A module unannotated `orelse`/enum/error-literal initializer still matches
  v145 (the raw `orelse` read at `:3803` is the one place where sentinel
  normalization could change an exotic path).

---

## 10. Concerns / open items

1. **Worktree seed is stale relative to v146.** `zig1/zig1_5_clean` is v145
   (`cd8d283b…`); the v146 fixed point is `de5e99b6…` inside
   `release/seed/zig1-seed.tgz`. Any repro that uses the working-tree binary
   will not reproduce the finding. The committed harness requires explicit
   `Z145`/`Z146` paths.
2. **Statement mixed switches remain accepted** (`sw_is_stmt_expr`, `:5039-5044`,
   `:5181`). This is current operator-chosen behavior after D15; the 12.2-F
   fix must not touch it. It is outside this investigation.
3. **Raw `orelse` sentinel consumer** (`:3803-3805`) treats `TYPE_UNDEFINED` as
   an optional target. No valid-code probe exposed a behavior difference, but
   option (a) changes this path to no-expected while option (d) would not.
   Option (b) variant 1 would cover it centrally.
4. **Unresolved call-argument/assignment producers** (`:3679`, `:4692`) can
   push `TYPE_UNDEFINED` in already-invalid code. They were not observed to
   produce a valid-code false reject; a central push normalization (option b)
   would remove any cascade risk.
5. **No implementation was made.** Task 12.2-F remains gated on operator
   approval of option (a) and on the v146-seed disposition.

---

## 11. Artifacts

- Probes and runner:
  `repro/mi_matrix/known_excluded/expected_type_contract/`
- Results: `results/results.tsv`, `results/run.log`, `results/compilers.md`
- Reproduction and probe README:
  `repro/mi_matrix/known_excluded/expected_type_contract/README.md`
- This report (gitignored ledger copy):
  `.superpowers/sdd/2026-10-29-phase35-defects-plan/task-12.2-I-report.md`
- Tracked report:
  `docs/superpowers/specs/2026-10-29-phase35-expected-type-investigation.md`
