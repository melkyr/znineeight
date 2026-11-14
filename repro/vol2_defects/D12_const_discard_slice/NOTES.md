# D12 — `[]const T` -> `[]T` const-discarding coercion is warning-only (RED)

## Claim
The const-discarding slice coercion is accepted warning-only in the variable
declaration shape (`warning[3000]`, then runs and mutates) and is accepted
**silently** in the parameter, struct-field and return shapes. Language Spec
"Type Coercions / Const Correctness" says `[]const T` -> `[]T` is **forbidden**.

## Chapter impact
Chapter 9 (arrays and slices, sample `strings.z98`) and chapter 3 (const) —
the chapter cannot claim const is enforced.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D12_const_discard_slice
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D12_const_discard_slice \
    repro/vol2_defects/D12_const_discard_slice/main.zig
cd /tmp/vol2_defects_out/D12_const_discard_slice && timeout 120 sh build_target.sh linux main
timeout 120 ./main
```

## OBSERVED
- `main.zig`: compile rc 0; `compile.log` has exactly one diagnostic:
  ```
  main.zig:9:4: warning[3000]: type mismatch in variable declaration -- initialization type may not be compatible with declared type
      var m: []i32 = c;
  ```
  build+run rc 0; stdout `m0=9` (the write through the mutable alias landed).
- `red_param.zig`: compile rc 0 with **no warning**; run `m0=9`.
- `red_field.zig`: compile rc 0 with **no warning**; run `m0=9`.
- `red_return.zig`: compile rc 0 with **no warning**; run `m0=9`.
- `xmod_main.zig` + `helper.zig` (const slice passed to an imported `fn
  take(m: []i32)`): compile rc 0 with **no warning**; run `m0=9`.
- `control_mut_to_const.zig` (`[]T` -> `[]const T`): rc 0, no diagnostic,
  `c0=1`.

## EXPECTED
Language Spec, "Type Coercions / Const Correctness": "Coercions are only
allowed if they do not discard const qualifiers. ... `[]const T` -> `[]T`
(Forbidden)". Expected: a compile-time rejection. Zig 0.15.2 oracle
(comparison only): `error: expected type '[]i32', found '[]const i32'`,
`note: cast discards const qualifier`.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Variable declaration | `main.zig` | RED | `warning[3000]` then `m0=9` |
| Function parameter | `red_param.zig` | RED, silent | `m0=9`, no diagnostic |
| Struct field init | `red_field.zig` | RED, silent | `m0=9`, no diagnostic |
| Function return | `red_return.zig` | RED, silent | `m0=9`, no diagnostic |
| Cross-module parameter | `xmod_main.zig` + `helper.zig` | RED, silent | `m0=9`, no diagnostic |
| `[]T` -> `[]const T` | `control_mut_to_const.zig` | control | `c0=1` |

## Boundary
Only the in-module variable-declaration site warns; all other coercion sites
accept silently. The D12 investigation should pin the diagnostic-site matrix
and decide whether the manual documents a warning or a hard error.

## FC conversion (2026-09-26) — FIXED (rejected)

**Fix:** a const-discard predicate next to `semanticAnalyzerMaybeDiagVolatileDrop`
(`semantic_analyzer.zig`) detects "source has `const`, target does not, same
effective element/base" for the frozen family slice->slice, slice->many,
ptr->ptr and many->many, and emits level-0
`error[3000]: cannot implicitly discard 'const' qualifier` (deduped per node).
It is called at the local-decl and assignment sites (before the level-1
mismatch fallback, so the warning is gone), at the module-var site, and inside
`tryRecordCoercion` (return, call args, field init). The legal const-ADDING
directions are untouched.

**POST (FC `effa5a6a…`), all rc 2 / 0 `.c` / 1 x `error[3000]` / 0 x
`warning[3000]` / no other error code:**

| Shape | File | PRE (seed) | POST (FC) |
|---|---|---|---|
| variable declaration `[]const` -> `[]` | `main.zig` | warning[3000], run `m0=9` | **reject** |
| assignment `[]const` -> `[]` | `red_assign.zig` (added) | warning[3000], run `m0=9` | **reject** |
| module var `[]const` -> `[]` / `[*]` | `red_modvar.zig` (added) | silent, run `m0=9` | **reject (2 x)** |
| function parameter `[]const` -> `[]` | `red_param.zig` | silent, run `m0=9` | **reject** |
| struct field init `[]const` -> `[]` | `red_field.zig` | silent, run `m0=9` | **reject** |
| function return `[]const` -> `[]` | `red_return.zig` | silent, run `m0=9` | **reject** |
| cross-module parameter | `xmod_main.zig` | silent, run `m0=9` | **reject** |
| `[]T` -> `[]const T` control | `control_mut_to_const.zig` | silent, run `c0=1` | unchanged `c0=1` |

All six D12 recorded sites plus the two added siblings reject with a real
`file:line:col` span; `run_all.sh` uses the `fixedreject` kind with
`expected_error.txt` `3000 1`. Fixture:
`repro/mi_matrix/const_discard_reject_xmod` (17 sites incl. `*const i32` ->
`*i32`, `[*]const i32` -> `[*]i32` and the cross-module return); standalone:
`repro/const_discard.z98` (8 sites). The `[]const T` -> `[*]T` bullet of the
spec is now enforced, closing the D5 interaction the investigation flagged.
