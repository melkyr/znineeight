# Phase 3.5 — Defect Repro Inventory (Task 0)

**Status:** Task 0 complete (test-only; no fix, no compiler-source change).
**Base:** `2a8944305e001bdc265b9eb676d86e0817aa1267` on `zig1_improvements`.
**Compiler under test:** `/workspace/znineeight/zig1/zig1_5_clean`
(md5 `cd8d283b917749009961f4445043666b`, sibling `lib/` = 59 std files).
**Plan/spec:** `docs/superpowers/plans/2026-10-29-phase35-defects-plan.md` and
`docs/superpowers/specs/2026-10-29-phase35-defects-design.md`.

Every fixture below is committed by Task 0. Later tasks consume these fixtures
and must not recreate them. `expected.txt` / `expected.rc` encode the
**post-fix** contract; where the pre-fix build passes, the fixture is a
**regression oracle** (explained per row).

## 1. Repro table

| Defect | Fixture path | Expected post-fix contract | Current RED / baseline evidence | Owner |
|---|---|---|---|---|
| **D12** module-scope untyped array literal | `repro/mi_matrix/module_untyped_array_init_ok_xmod/` | dump rc=0, gcc clean, run rc=0, stdout `1 42 3\n` | dump rc=0; emitted module init has `zG_296F1018_arr = zT_0;` with `Tup_554 zT_0`; gcc rc=1 `error: assignment to expression with array type` | Task 1 |
| **D7.3** nested aggregate write targets a temp | `repro/mi_matrix/known_excluded/nested_agg_write_ok/` | lost-write shape lands in storage: stdout `77 88 77 88\n`, rc=0 (pointer control `7 8`; nested chain `5 6`) | compiles/links/runs rc=0 but prints `0 0 0 0` (pre-write values) under `-ffast` and `-fsafe`; nested chain prints `0 0` | Task 2 |
| **D8** mixed stdout stacks | `repro/mi_matrix/known_excluded/stdout_order_ok/` | program order on CRT **and** no-CRT: `A\nB\nC\nDZ\n`, rc=0 (stdin `Z\n`) | **pre-fix pass by luck**: CRT `-ffast`/`-fsafe` and Wine no-CRT both print the expected order (buffered data flushes at normal exit after the unbuffered PAL write). Regression oracle; ordering is only *proved* post-fix on both paths. | Task 3 |
| **D3** lazy `@import` (evaluator fold) | `repro/mi_matrix/known_excluded/lazy_import_fold_ok/` | dead arm never opened: stdout `exists ping\nlazy import fold ok\n`, rc=0 | `if (1 == 1) … else @import("missing.zig")` dump rc=2, `error[3048]: could not resolve imported file 'missing.zig'` | Task 4 |
| **D3** lazy `@import` (unparsable dead arm) | `repro/mi_matrix/known_excluded/lazy_import_unparsable_dead_ok/` | dead arm never opened; stdout `exists ping\nunparsable dead ok\n`, rc=0 | dump rc=2; `unparsable.zig:2:15 error[2000]: expected identifier but found '{'` (+ `unexpected token`) — the dead file is opened and parsed | Task 4 |
| **D5/D10** `extern "stdcall"` definition | `repro/mi_matrix/known_excluded/stdcall_def_ok/` | definition emitted with `Z98_STDCALL`; dump rc=0, gcc clean, stdout `42\n` | dump rc=0, zero Z98 diagnostics; emitted only `((FS_int_unsigned_int)cb)(…)`, no definition; gcc rc=1 `'cb' undeclared` | Task 5 |
| **D5** bare/`"c"` extern definition | `repro/mi_matrix/known_excluded/cdecl_def_ok/` | cdecl definition emitted; dump rc=0, gcc clean, stdout `44\n` | dump rc=0, zero Z98 diagnostics; emitted `cd(…)`, no definition; link rc=1 `undefined reference to 'cd'` | Task 5 |
| **D13** full `enum(u64)` range | `repro/mi_matrix/enum_u64_max_ok_xmod/` | max discriminant accepted and read: dump rc=0, run rc=0, stdout `7\n` | dump rc=2, **two** `error[3000]: enum member value exceeds the supported enum value range (values above 9223372036854775807 require u64 enum storage, not supported yet)` | Task 6 |
| **D14** suspending EU-payload wrapper | `repro/mi_matrix/async_wrapper_eu_payload_ok_xmod/` | non-tail success/error: stdout `32 0\n0 1\n`, rc=0 under `-ffast`/`-fsafe`; tail-return sibling also compiles/runs `55 0\n0 1\n` | **non-tail shape already passes pre-fix** (`32 0\n0 1\n`, `-ffast`/`-fsafe`) — regression oracle. The reproducible RED is the tail-return sibling: gcc rc=1 `stray '@'`, `zF_B6CE39A7_@asyncSuspend`, wrong step result type. See §4 ADJ-17. | Task 7 |
| **D4** analyzer contracts | `tests/analyzers/d4_contract_probe.zig` (+ `--check` evidence) | Task 8 audit defines the must-work set; Task 9 makes the four analyzers honor it | **probe not runnable through `testFixture` without editing `sf/src/tests/test_analyzer_bin.zig`** (each fixture needs a hard-coded call in `main()`). Supplementary real-pipeline run: `--check` rc=2 with 2× `warning[3037]`, `warning[3039]` freeing untracked `q`, `error[3035]` double free `p`, `error[3030]` returning local `x`. See §4 ADJ-20/21/22. | Task 8 (audit) / Task 9 (upgrade) |

Raw commands use the canonical recipe (`OUT` pre-created):

```sh
Z=/workspace/znineeight/zig1/zig1_5_clean
$Z -ffast -o "$OUT" <fixture>/main.zig      # dump
( cd "$OUT" && sh build_target.sh linux prog )   # gcc/link
```

## 2. D12 evidence (module-scope untyped array literal)

Fixture: `repro/mi_matrix/module_untyped_array_init_ok_xmod/main.zig`.

```c
/* out/main_EF6A22B9.c */
zT_127FDF6B_Tup_554 zT_0;
...
zT_0._0 = zT_1;
zT_0._1 = zT_2;
zT_0._2 = zT_3;
zG_296F1018_arr = zT_0;          /* illegal array-to-array assignment */
```

`sh build_target.sh linux prog` → rc=1,
`error: assignment to expression with array type` at the whole-global store.
The typed control `multiarray_literal_init_xmod` already emits the element-wise
path and is unchanged.

Sibling probes (same directory, run individually):

| Probe | Current result |
|---|---|
| `sibling_struct_array_untyped.zig` (1-D struct array, typed elements) | Same D12 class: dump rc=0, emitted `zG_ABF64FF9_sarr = zT_0;`, gcc `assignment to expression with array type`. **Same defect → in-scope under D12** (extend Task 1 fixture set if needed). |
| `sibling_2d_untyped.zig` (2-D untyped literal) | Same D12 class: dump rc=0, emitted `zG_E20C2606_g = zT_0;`, gcc `assignment to expression with array type`. **Same defect → in-scope under D12.** |

## 3. D7.3 evidence (nested aggregate write)

Fixture: `repro/mi_matrix/known_excluded/nested_agg_write_ok/main.zig`
(`fill(peers[i].field[0..])` — the wireguard demo shape). The callee writes
through the slice into a by-value temporary of `peers[i]`; the program runs and
prints the pre-write values:

```text
$ ./prog
0 0 0 0          # expected post-fix: 77 88 77 88
$ echo $?
0
```

Both `-ffast` and `-fsafe` produce `0 0 0 0`. `sibling_pointer_aggregate.zig`
(the explicit-pointer workaround) prints `7 8` and is the control.

Sibling probes:

| Probe | Current result |
|---|---|
| `sibling_pointer_aggregate.zig` | pass `7 8` (regression oracle; workaround must stay valid) |
| `sibling_nested_chain.zig` (`outers[i].mids[j].inner.bytes[0..]`) | lost store: prints `0 0`. **Same defect → in-scope D7.3.** |
| `sibling_field_array_assign.zig` (`arr[i].field = srcArray`) | dump rc=0 + `warning[3000]` type mismatch; emitted `zT->field = src`; gcc `assignment to expression with array type` (D12 emission class on a nested lvalue). **In-scope D7.3 (cross-ref D12).** |
| `sibling_slice_of_array.zig` (`arr[i].field[0..] = src[0..]`) | dump rc=3, `error[3043]: internal: unsupported assignment l-value (node 38)`. **In-scope D7.3**; Task 2 must decide whether this direct form is covered by the same storage fix. |

## 4. Adjacent / sibling findings (`ADJ-<n>`)

| ID | Finding | Evidence | Disposition |
|---|---|---|---|
| ADJ-1 | 1-D struct-array module untyped literal is the same whole-array-assignment class as D12 | `sibling_struct_array_untyped.zig` gcc error | **in-scope under D12** |
| ADJ-2 | 2-D untyped module literal is the same class as D12 | `sibling_2d_untyped.zig` gcc error | **in-scope under D12** |
| ADJ-3 | `arr[i].field[0..] = src[0..]` hard-fails as an unsupported l-value | dump rc=3 `error[3043]` | **in-scope under D7.3** (lvalue composition) |
| ADJ-4 | `arr[i].field = srcArray` emits an illegal C array assignment | dump rc=0 + gcc array-assignment error | **in-scope under D7.3**, cross-ref D12 |
| ADJ-5 | Pointer-to-aggregate hidden workaround works | `sibling_pointer_aggregate.zig` prints `7 8` | **in-scope control** (must stay working) |
| ADJ-6 | Deeper nested index/field chain loses the write like the base shape | `sibling_nested_chain.zig` prints `0 0` | **in-scope under D7.3** |
| ADJ-7 | D8 mixed ordering passes pre-fix on CRT and no-CRT | CRT `-ffast`/`-fsafe`; `cross_nocrt.sh` + Wine both print `A\nB\nC\nDZ\n` | **regression oracle**; D8 value is the post-fix proof on both paths |
| ADJ-8 | Unparsable dead arm fails as parser errors (`error[2000]`), not `error[3048]` | `lazy_import_unparsable_dead_ok` dump rc=2 | **in-scope under D3** (lazy load must avoid parse too) |
| ADJ-9 | `switch`, `and`/`or`, nested and live-arm forms all eagerly open a missing dead-arm file | `sibling_switch.zig`, `sibling_and_or.zig`, `sibling_nested.zig`, `sibling_live_arm.zig` all rc=2 `error[3048]` | **in-scope under D3** |
| ADJ-10 | Variadic `stdcall` declaration rejects `error[3012]` | `sibling_variadic.zig` dump rc=2 | **in-scope under D5/D10** (preserve this reject) |
| ADJ-11 | Prototype/definition convention mismatch is silently treated as a declaration | `sibling_mismatch.zig` dump rc=0, no Z98 diagnostic, gcc `'mm' undeclared` | **in-scope under D5/D10** (sema agreement) |
| ADJ-12 | Fn-pointer call to the stdcall definition also references an undefined symbol | `sibling_fnptr.zig` dump rc=0, gcc `'cb' undeclared` | **in-scope under D5/D10** |
| ADJ-13 | Signed `enum(i64)` with a negative member works | `sibling_signed.zig` rc=0, prints `1` | **in-scope under D13** (must stay) |
| ADJ-14 | Implicit successor at `u64_max - 1` is rejected pre-fix as a range error | `sibling_implicit_ok.zig` dump rc=2 `error[3000]` ×2 | **in-scope under D13** |
| ADJ-15 | Duplicate tags at `u64` max already reject as `error[3055]` (not range) | `sibling_duplicate.zig` dump rc=2 `error[3055]` | **in-scope under D13** (preserve duplicate behavior) |
| ADJ-16 | Module-const enum value at `u64` max rejects like the base | `sibling_const_switch.zig` dump rc=2 `error[3000]` ×2 | **in-scope under D13** |
| ADJ-17 | **Spec contradiction:** the non-tail `try wait(c); return 32;` EU-payload wrapper compiles and runs correctly at BASE; the real `http2Wait` and `http2Get` wrapper shapes also compile. Only the tail-return form reproduces the step-ABI defect. | `async_wrapper_eu_payload_ok_xmod/main.zig` prints `32 0\n0 1\n`; scratch wrappers around `std_http2.http2Wait`/`http2Get` compile rc=0. | **in-scope D14, but spec §5.7 says this shape errors `error[3043]` — STOP-reported concern.** Task 7 should re-scope the RED to the tail-return ABI (or find the narrower trigger). |
| ADJ-18 | Tail-return EU wrapper emits a GCC-incompatible step ABI | `sibling_tail.zig` build rc=1: `stray '@'`, `zF_B6CE39A7_@asyncSuspend`, `incompatible types when returning type ... EU ... but Opt ... expected` | **in-scope under D14** (the reproducible RED) |
| ADJ-19 | Non-tail void/optional/aggregate wrappers pass pre-fix | `sibling_void.zig` `1 0/0 1`, `sibling_optional.zig` `32 0/0 1`, `sibling_aggregate.zig` `34 0/0 1` | **regression oracles**; must stay green post-fix |
| ADJ-20 | **D4 harness blocker:** `testFixture` has no generic/CLI entry; every fixture needs a hard-coded `testFixture(...)` call in `main()` of `sf/src/tests/test_analyzer_bin.zig` | `sf/src/tests/test_analyzer_bin.zig:1794-1859` | **deferred to Task 9**; Task 0 did not edit the harness |
| ADJ-21 | Simple `std.io` programs emit 3× `warning[3037] potential null pointer dereference` (unseeded params) | every fixture dump above | **in-scope under D4** (defect (b) false positives) |
| ADJ-22 | Real-pipeline probe run shows the contract holes | `zig1 -ffast --check tests/analyzers/d4_contract_probe.zig` rc=2: 2× `warning[3037]`, `warning[3039] freeing untracked pointer 'q'`, `error[3035] double free of pointer 'p'` (dead arm), `error[3030] returning address of local variable 'x'` | **in-scope under D4**; the dead-arm double free and null warnings are false positives, the alias-chain miss is a false negative, and the local-address error is the true positive that must stay |

## 5. D4 probe run status (blocker recorded, no harness change)

`tests/analyzers/d4_contract_probe.zig` is created as a source fixture with one
contract hole per analyzer plus a clean Signature surface. The existing runner
(`testFixture` in `sf/src/tests/test_analyzer_bin.zig`) only executes the
fixtures named in `main()`; running the new probe would require editing that
harness, which Task 0 is forbidden to do. Per the Task 0 instruction this is
recorded as ADJ-20 and the harness was left unchanged. Supplementary evidence
was captured through the real pipeline (`--check`, ADJ-22); Task 8/9 own the
fixture-driven expansion.

## 6. Corpus classification notes

- New dirs are additive only; no `scripts/stdlib/expected_dirs.txt` change
  (these are compiler repros, not stdlib fixtures).
- `known_excluded/` and `tests/analyzers/` are outside the live corpus.
- Corpus-visible additions: `module_untyped_array_init_ok_xmod` (pre-fix FAIL:
  gcc rejects the emitted C), `enum_u64_max_ok_xmod` (pre-fix GREEN:
  0 `.c` + `error[3000]`), `async_wrapper_eu_payload_ok_xmod` (pre-fix OK:
  the non-tail shape compiles). The live count / class md5 is re-anchored only
  at Task 12.

## 7. Open concerns for the controller

1. **D14 spec contradiction (ADJ-17).** The plan/spec say a non-tail
   `try wait(c); return 32;` wrapper fails with `error[3043]`; at BASE it
   compiles and runs. The tail-return form is the only reproducible RED. Task 7
   must not assume the non-tail RED exists.
2. **D4 probe not runnable via the committed harness (ADJ-20).** The probe
   fixture is committed, but its diagnostics were captured with `--check`, not
   `testFixture`. Task 8/9 should register it when the harness is expanded.
3. The three new corpus-visible dirs change the live corpus's class counts
   before Task 1 (additive only); Task 12 re-anchors.
