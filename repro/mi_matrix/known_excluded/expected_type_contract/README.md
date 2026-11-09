# Expected-type sentinel contract probes (Phase 3.5 Task 12.2-I)

Investigation/test-only probes for the module-scope unannotated `switch`
regression. No `sf/src` change is made by this directory.

The finding under test: `pushExpectedType` has no single "no expected type"
value. The function-local declaration producer pushes `0` when unannotated
(`semantic_analyzer.zig:6713`), but the module declaration producer pushes
`TYPE_UNDEFINED` (`:7576`). The D15 expected-type-first switch branch only
normalizes `TYPE_VOID` to `0` (`:5049-5050`), so an unannotated module switch
sees `TYPE_UNDEFINED` as a real target type and rejects valid peer-resolvable
prongs with `error[3000]` / `target: type`.

## Reproduction

```
$ v145 --check -ffast probes/module_const_switch_unannotated.zig
rc=0
$ v146 --check -ffast probes/module_const_switch_unannotated.zig
rc=2
...:1:28: error[3000]: type mismatch in switch expression ...
note: source: comptime_int
note: target: type
```

`--dump-c89 -ffast` emits 5 `.c` files on v145 and 0 on v146.

## Compilers

See `results/compilers.md`. Important: the working-tree `zig1/zig1_5_clean`
is md5 `cd8d283b...` (v145), not the v146 fixed point. The v146 runs here use
the binary extracted from `release/seed/zig1-seed.tgz` (md5 `de5e99b6...`),
and the v145 runs use the binary extracted from the v145 archive in git history
(md5 `cd8d283b...`).

## Run

```sh
Z145=/tmp/expected-type-i/v145/zig1-seed/zig1 \
Z146=/tmp/expected-type-i/v146/zig1-seed/zig1 \
ZIG=/tmp/phase35-d15-i/zig-0.17.1/zig \
./run_expected_type_contract.sh
```

`results/results.tsv` records, per probe, the Zig 0.17.1 rc (when the oracle is
available), v145/v146 `--check` rc and codes, and the `.c` count from a
`--dump-c89` run. `results/run.log` records the raw per-compiler output.

## Observed result (v146 seed)

Rejected (v145 accepted) — all module-scope unannotated value switches whose
prongs are not all `TYPE_UNDEFINED`/`TYPE_NORETURN`:

- `module_const_switch_unannotated`
- `module_var_switch_unannotated`
- `module_const_switch_typed_prongs_unannotated` (even `@as(i32, ...)` prongs)
- `module_switch_strings_unannotated`
- `module_tuple_switch_unannotated` (tuple literal does not push an expected type)
- `module_if_switch_arm_unannotated` (a switch in a module `if` arm still sees the declaration sentinel)
- `module_nested_switch_unannotated`

Accepted on both v145 and v146 (controls):

- module/local annotated `const`/`var` switches
- local unannotated `const`/`var` switches
- module/local unannotated and annotated `if` expressions
- call-argument, struct-field, array-element, and return-position switches
- module unannotated `if` with string arms
- module `@ptrFromInt` annotated/unannotated controls (both reject inference when unannotated)

The `module_ptr_from_int_unannotated` Zig oracle row is a Zig reject
(`@ptrFromInt must have a known result type`); that is the same contract, not a
Z98 regression.
