# Volume II defect repro set (task D0)

Read-only, committed defect reproduction set for the twelve verified
compiler-defect candidates from the Volume II capability inventory (Task 0 +
independent review). **These repros pin current seed-compiler behavior; they do
not fix anything.** The D1-D12 investigation tasks and any later
operator-authorized F tasks consume this set.

> **FA-a status (2026-09-26):** D2 (enum range prongs) and D3 (mandatory
> `else`) are **FIXED** on the current compiler (fixed point
> `93b884b5f3ab2aebf500782dca76c3c3`). D2 now prints the values in its
> `expected.txt` (`run_all.sh`: `D02_enum_switch_ranges: rc=0 ok`); D3 now
> rejects with exactly one `error[3068]` per no-`else` switch (`run_all.sh`:
> `D03_missing_else: rc=2 ok`). The per-case `OBSERVED` sections below remain
> the historical seed-v88 evidence.
>
> **FG status (2026-09-26):** D1 (defer-queue corruption) is **FIXED** on the
> current compiler (fixed point
> `c4f10f9e2d33a0833b9882c5dad2539b`). All four D1 RED programs compile/build/
> run rc 0 and print their documented expected output; the D01 case ships
> `expected.txt` and `run_all.sh` now also goldens that program's stdout/rc
> (`D01_defer_segfault: rc=0 ok`). `--no-leak-check` is no longer needed
> anywhere. The D01 `OBSERVED` section below remains the historical seed-v88
> evidence.
>
> **FD1 status (2026-09-26):** D7 and the S01 print-container cluster are
> **FIXED as clean rejects** on the current compiler (fixed point
> `7bf2da194d7385dea638a9126191c173`; code 3065, `run_all.sh` kind
> `fixedreject`). Every non-tuple `print` container now rejects rc 2 / 0 `.c`
> with level-0 `error[3065]` (`print arguments must be a tuple literal`) at the
> container node; a `print` call with more than two arguments rejects with the
> existing `error[3061]` at the call span; no shape SIGSEGVs. The spec-legal
> tuple **variable** is still **interim-rejected** (3065) until FD2 implements
> its element reads; tuple literals (including the empty `.{ }`) are unchanged
> and byte-identical. The per-case `OBSERVED` sections below remain the
> historical seed-v88 evidence.
>
> **FE status (2026-09-26):** D8 and D11 are **FIXED** on the current compiler
> (fixed point `536ed4943ecf8bacbbf93343d732c3e0`). D8: the `catch |e|` capture
> temp is typed as the sema error set, so `print("{}", .{e})` prints
> `error.Bar` (the annotated copy, typed values and the `{d}`/`{x}` 3013 reject
> are unchanged; `run_all.sh`: `D08_errset_capture: rc=0 ok`). D11: qualified
> prongs bind exactly like the shorthand (`Shape.circle => |r|`,
> `Color.red => |v|`, cross-module `helper.Box.num`), enum-operand captures
> bind the operand value Zig-style, and an unused enum capture no longer
> SIGSEGVs the compiler (bundled guard; `run_all.sh`:
> `D11_qualified_capture: rc=0 ok`). The D11 f32 shapes (`main.zig`,
> `xmod_main.zig`, `red_multiple_qualified.zig`) compile rc 0 but their gcc
> step stayed blocked by the unrelated D6 float-union defect until FF; the FF
> fix unblocks them. The per-case `OBSERVED` sections remain the historical
> seed-v88 evidence.
>
> **FF status (2026-09-26):** D6 and D9 are **FIXED** on the current compiler
> (fixed point `cadf3c241abd1baf4d31da52b0ccd649`). D6: an f64 float-literal
> payload temp is narrowed to the selected variant's f32 type before the store,
> so `ShapeF{ .circle = 2.0 }` emits a real `zT.payload.circle._0 = (float)…`
> store (previously gcc-invalid whole-union C, or a silent f64-sibling write);
> `run_all.sh` now goldens it as `wrong` kind (`D06_float_union: rc=0 ok`,
> `f=2`). D9: union `@offsetOf`/`@bitOffsetOf` is a **clean Zig-parity reject**
> (`error[3072]` `expected struct type, found 'X'`, rc 2 / 0 `.c`); unknown
> field / non-literal name reject `error[3073]`, unresolved type / arity reject
> `error[3074]`; the `error[3043]` ICE net is gone (`D09_bare_union_offsetof:
> rc=2 ok` with `expected_error.txt` `3072 1`). Union `@sizeOf`/`@alignOf`/
> `@bitSizeOf` values are unchanged. The f32 param literal stays the FX3
> residual; the typed-f64-variable payload stays the documented FX3 residual.
>
> **FC status (2026-09-26):** D5 and D12 are **FIXED** on the current compiler
> (fixed point `effa5a6aae9f11266597196561186f1b`). D5: the slice -> `[*]T`
> coercion now lowers to a real `.ptr` field extraction, so `[]i32` ->
> `[*]i32` / `[]const i32` -> `[*]const i32` compile/build/run spec-correctly
> (`run_all.sh` kind `runok` with `expected.txt` `mp[1]=20`, rc 0). D12: every
> const-discarding coercion (`[]const T` -> `[]T`, `[]const T` -> `[*]T`,
> `*const T` -> `*T`, `[*]const T` -> `[*]T`) rejects level-0
> `error[3000]: cannot implicitly discard 'const' qualifier` at all six sites
> (local decl, assignment, module var, return, call arg, field init) plus
> cross-module, rc 2 / 0 `.c` (`run_all.sh` kind `fixedreject`,
> `expected_error.txt` `3000 1`). The legal const-adding directions are
> unchanged. The per-case `OBSERVED` sections below remain the historical
> seed-v88 evidence.
>
> **FB status (2026-09-26):** D4 is **FIXED** on the current compiler (fixed
> point `d1ae438960d85b9f1df02ebcd2defe73`). The tuple type
> `struct { T1, T2 }` parses and registers, `.0`/`._0`/`t[0]` all read, write
> and address the positional C fields `_0`/`_1`, tuple literals coerce to
> named tuple types (var decl/assignment/return/argument), and cross-module
> tuple types/params/returns/globals work. The `.N` name-id silent alias is
> closed (`.73` is `error[3060] named '73'`, never `len`); new level-0 codes
> `error[3069]` (non-comptime `t[i]`) and `error[3070]` (out-of-range
> `.N`/`._N`/`t[N]`) reject the invalid forms with Zig 0.15.2 wording. D04
> `run_all.sh` uses kind `runok` (golden `expected.txt` `p=.{ 3, 4 }`); the
> five RED entries (`main`, `red_return_type`, `red_dot0`, `red_underscore`,
> `red_index`) compile/build/run rc 0, and the three controls print
> byte-identically. `print(fmt, tupleVariable)` stays the interim
> `error[3065]` until FD2. The per-case `OBSERVED` sections below remain the
> historical seed-v88 evidence.
>
> **FH status (2026-09-27):** D10 is **FIXED as a clean reject** on the current
> compiler (fixed point `99ef01ad63ba37f98f327317608f577f`). Indexing a
> single-item pointer to a non-array pointee (`p[0]`, `p[1]`, a runtime `p[i]`,
> `p[0] = v`, `*Point`, `*const`/`*volatile`/multi-level) and the `type` base
> `(*p)[i]` reject level-0 `error[3066]` with Zig 0.15.2 wording (`type '*T'
> does not support indexing` / `unable to resolve comptime value`); a `*T`
> slice accepts only the comptime bounds `[0..0]`/`[0..1]`/`[1..1]` and now
> yields Zig's `*[0]T`/`*[1]T` (const/volatile carried), while every other form
> (`p[0..2]`, `p[1..0]`, `p[-1..1]`, runtime `p[0..n]`, open `p[0..]`) rejects
> level-0 `error[3067]` — the open form no longer ICEs `[3043]`. `*[N]T`
> auto-deref indexing/slicing, `p.*` and `[*]T` indexing are unchanged. D10
> `run_all.sh` uses kind `fixedreject` with a multi-code census
> (`3066 6` + `3067 5` + `3000 10`); the sibling slice/`(*p)` rejects and the
> accepted `control_slice_legal.zig` are exercised outside the runner. The
> per-case `OBSERVED` sections below remain the historical seed-v88 evidence.
>
> **FI status (2026-09-27):** the FH follow-up over-rejection is fixed — `for`
> iterates a pointer-to-array (operator ruling A; fixed point
> `b44a85111b1f89921ab1d46a752c61a5`). `for (p[0..1]) |v|` runs again with the
> pre-FH `sum=42` shape, `for (p[0..0])`/`for (p[1..1])` iterate zero times, and
> direct `for (pa) |v|`, `*const [N]T`, explicit `for (pa, 0..3)`/`(pa, 1..)`
> and the row-by-value `*[2][3]i32` item match Zig 0.15.2;
> `control_slice_legal.zig` now covers the former probe (tail
> `fsum=42 fz=0 fpa=60`). Non-array pointer pointees still reject `error[20]`.
>
> **FX2 status (2026-09-27):** the D1 *traversal* extras are **FIXED** on the
> current compiler (fixed point `325f741f0326ebaf177a0503e000312a`).
> `visitStatement` now walks switch-prong and bare-block statements, so defers
> inside them reach the null/lifetime/double-free passes (runtime unchanged).
> New sibling `D01_defer_segfault/red_switch_block.zig` (plain + switch-prong +
> bare-block defers) compiles/builds/runs rc 0 with stdout
> `plain-body / plain-defer / switch 2 / switch-defer / block-body /
> block-defer`; all three FX2 shapes SIGSEGV rc 139 on an FX2-only (no-FG)
> compiler and rc 0 on FG+FX2. Positive fixture
> `repro/mi_matrix/stdlib_defer_switch_block_xmod` + standalone
> `repro/defer_traversal.z98`. `run_all.sh` stays `D01_defer_segfault: rc=0 ok`.
>
> **FX4 status (2026-09-27):** the D11 *validation* extras are **FIXED** as
> clean level-0 `error[3071]` rejects on the current compiler. A qualified
> prong whose qualifier denotes a different enum/tagged-union type
> (`B.x` on an `A` switch) and a qualified/shorthand prong naming a
> non-existent member (`Shape.bogus`, `.bogus`) reject rc 2 / 0 `.c`; the
> captured variants keep the pre-existing unbound-capture `error[20]` cascade
> visible (no suppression; no `error[3060]` co-fires — the member check is the
> direct condition walk, not the generic field-access reporter). Valid
> same-type/alias/module-qualified prongs and the FE captures are unchanged.
> New siblings `D11_qualified_capture/red_bogus_member.zig` (4 x 3071 + 1 x 20)
> and `red_foreign_qualifier.zig` (4 x 3071 + 1 x 20), both exercised outside
> `run_all.sh`; the reject census is pinned in
> `repro/mi_matrix/switch_case_qualifier_reject_xmod` (12 x 3071 + 2 x 20) and
> standalone `repro/switch_case_qualifier_reject.z98` (4 x 3071), with the
> positive control `repro/switch_case_qualified.z98`. `run_all.sh` stays
> `D11_qualified_capture: rc=0 ok`.

- Plan: `.superpowers/sdd/2026-09-25-z98-manual-volume-II-plan/`
- Report: `.superpowers/sdd/2026-09-25-z98-manual-volume-II-plan/task-D0-report.md`
- Fixture style follows `repro/mi_matrix/`: `main.zig` plus relative helper
  modules, per-case `NOTES.md`, cross-module variants as extra entry files.

## Seed compiler

Every observation in this tree is against the v88 fixed-point seed:

```sh
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
md5sum /tmp/manual_seed/zig1_5_clean
# must print a3928c11f9852db9646dff39006ef654
```

Compile + run a single case (`-o` needs an existing directory):

```sh
mkdir -p /tmp/vol2_defects_out/D05_slice_to_manyptr
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D05_slice_to_manyptr \
    repro/vol2_defects/D05_slice_to_manyptr/main.zig
cd /tmp/vol2_defects_out/D05_slice_to_manyptr && timeout 120 sh build_target.sh linux main
timeout 120 ./main
```

Run the whole set (POSIX `sh`, never hangs -- every stage is `timeout 120`):

```sh
sh repro/vol2_defects/run_all.sh
```

Outputs and logs: `/tmp/vol2_defects_out/<case>/`. Each case prints exactly one
line, `<case>: rc=<n> <RED|ok>`, where `RED` means the expected defect
reproduced (the expected failure kind per case is in that case's `kind.txt`;
`compile.log` / `build.log` / `diff.txt` capture it). Oracle comparison only:
`/tmp/zig-x86_64-linux-0.15.2/zig` (Zig 0.15.2); the oracle never defines
expected behavior here -- `docs/reference/Language_Spec_Z98.md` does.

## Index

| Id | Directory | One-line claim | Chapter impact | Module-scope note |
|----|-----------|----------------|----------------|-------------------|
| D1 | `D01_defer_segfault/` | A module with one plain-`defer` fn and one `for`/`while`-body-`defer` fn made the compiler SIGSEGV (rc 139); **FIXED by FG** (rc 0 with documented output) | ch11 (defer) -- unblocked | Boundary matters: the pre-fix crash needed both shapes in the SAME module; `xmod_main.zig` (both in helper) crashed, `split_*` controls passed |
| D2 | `D02_enum_switch_ranges/` | Enum `switch` range prongs (`a...b`, `a..b`) emit no `case` labels; every value takes `else` (silent wrong code) | ch6 (enums), ch10 (switch) | Does not matter: `xmod_main.zig` (enum from `colors.zig`) also all-`else` |
| D3 | `D03_missing_else/` | `switch` without `else` is accepted; an unmatched value reads an uninitialized result temp | ch10 (control flow) | Does not matter: `xmod_main.zig` (switch in `picker.zig`) also silent garbage |
| D4 | `D04_tuple/` | Tuple type `struct { T1, T2 }` is a parse error; `.0`/`._0` are `error[3060]`; `t[0]` emits gcc-invalid C; **FIXED by FB** (tuple model end-to-end; `run_all.sh` kind `runok`, `p=.{ 3, 4 }` rc 0) | ch8 (tuples) -- unblocked | Does not matter: the tuple type/access works in-module and cross-module now (`helper.Pair` param/return/global in `stdlib_tuple_model_ok_xmod`); spelling+`.N`-alias+OOB reject fixtures added; `print(fmt, tupleVariable)` stays interim 3065 until FD2 |
| D5 | `D05_slice_to_manyptr/` | Implicit `[]T` -> `[*]T` coercion compiles rc 0 then gcc-rejects the C; **FIXED by FC** (`.ptr` extraction; `run_all.sh` kind `runok`, `mp[1]=20` rc 0) | ch3 (pointers), ch9 (arrays/slices) -- unblocked | Does not matter: `xmod_main.zig` (imported `[*]i32` param) now builds+runs `first-ish=20`; const slice -> `[*]const` and all controls byte-identical |
| D6 | `D06_float_union/` | An f32 tagged-union payload init emits gcc-invalid C (`payload = double`); **FIXED by FF** (literal f64→f32 payload narrowing; the f64-sibling silent wrong-variant write is closed too; `run_all.sh`: `rc=0 ok`, `f=2`) and **completed by FX3** (value-aware narrowing: `green_param.zig` is the former f32-param residual turned positive `x=1.5/x=2/x=2.5/x=2`; runtime f64/i32 and inexact values now clean-reject `error[3000]` at parameters/returns/fields/declarations/assignments/payloads; matrix pinned by `stdlib_f32_narrow_ok_xmod` + `f32_narrow_reject_xmod`) | ch7 (unions) -- unblocked | Does not matter: `xmod_main.zig` (union from `shapes.zig`) now builds+runs (`f=2`); f64/int/bool/struct payloads unchanged; the extreme-literal `parseF64` precision residual (spec §7.2) stays documented |
| D7 | `D07_nontuple_print/` | `print(fmt, <non-tuple literal>)` is silently accepted and prints no value; **FIXED by FD1** (rc 2 / 0 `.c` / 1 × `error[3065]` at the argument, tuple control GREEN + byte-identical) | ch18 (print) -- unblocked | Does not matter: `xmod_main.zig` (call in `logger.zig`) rejects 3065 in the helper file too |
| D8 | `D08_errset_capture/` | `catch \|e\|` capture of an error set prints numeric where a typed value prints `error.Name`; **FIXED by FE** (capture temp retyped to the sema error set; `run_all.sh`: `rc=0 ok` with `capture=error.Bar`) | ch12 (errors), ch18 (print) | Does not matter: `xmod_main.zig` (`errors.zig`) now prints `capture=error.Bar`; the annotated copy and the typed controls are unchanged |
| D9 | `D09_bare_union_offsetof/` | `@offsetOf` on a bare union was an internal error (`error[3043]`); tagged unions ICEd too; **FIXED by FF** (Zig-parity clean reject `error[3072]`, rc 2 / 0 `.c`; `run_all.sh`: `rc=2 ok`) | ch7 (unions), ch15 (builtins) -- unblocked | Does not matter: `xmod_main.zig` (union from `raw.zig`) rejects 3072 in the same clean class; union `@sizeOf`/`@alignOf` controls unchanged |
| D10 | `D10_single_ptr_index/` | `p[0]` on a single-item pointer is accepted and runs though spec 1.2 says it is rejected | ch3 (pointers) | Does not matter: `xmod_main.zig` (indexing in `helper.zig`) also accepted. Defect-vs-spec-correction is for the investigation; this pins current behavior |
| D11 | `D11_qualified_capture/` | `Shape.circle => \|r\|` (qualified prong) leaves the capture unbound (`error[20]`); **FIXED by FE** (qualified prongs populate `enum_value_table`; enum captures bind Zig-style; the unused-capture SIGSEGV is guarded; `run_all.sh`: `rc=0 ok`); the D11 validation extras (`Shape.bogus`, foreign `B.x`) are **FIXED by FX4** as `error[3071]` rejects (`red_bogus_member.zig` / `red_foreign_qualifier.zig`) | ch7 (unions) | Does not matter: `xmod_main.zig` (type from `shapes.zig`) binds; `.circle =>` shorthand unchanged; the f32 shapes stay gcc-blocked by D6 (FF) |
| D12 | `D12_const_discard_slice/` | `[]const T` -> `[]T` is accepted warning-only (in the var-decl shape) and mutates; **FIXED by FC** (every const-discarding family rejects `error[3000]`, rc 2 / 0 `.c`; `run_all.sh` kind `fixedreject`, `3000 1`) | ch9 (arrays/slices), ch3 (const) -- unblocked | Does not matter: `xmod_main.zig` now rejects with the same diagnostic; added `red_assign.zig` / `red_modvar.zig` cover the two silent sites; legal const-adding control unchanged (`c0=1`) |
| S1 | `S01_print_nontuple_args/` | New sibling cluster: non-tuple `print` args are container-misinterpreted -- tuple-variable rejects, mixed calls misattribute `error[3013]` or SIGSEGV, two var calls print wrong values; **FIXED by FD1** (every shape rc 2 / 0 `.c` / `error[3065]` at its own container, no SIGSEGV; tuple variable interim) | ch18 (print) -- unblocked | Cross-module variant in the D07 tree; shapes here same-module only |

## Case layout

Each `D*/` and `S*/` directory carries:

- `main.zig` -- the flagship in-module RED shape; `run_all.sh` compiles this.
- `NOTES.md` -- defect claim, chapter impact, exact commands, seed md5,
  OBSERVED (rc/stdout/stderr + emitted-C excerpt or gcc error for
  wrong-code/gcc-fail), EXPECTED (spec citation; Zig 0.15.2 oracle only as a
  comparison), and a variants table (in-module | cross-module | sibling/control).
- extra `*.zig` entry files: `xmod_main.zig` + helper = cross-module variant;
  `red_*.zig` = additional failing shapes; `control_*.zig` = passing controls.
  Compile them like `main.zig` (the binary and `build_target.sh` target take
  the file's basename, e.g. `sh build_target.sh linux red_anon`).
- `expected.txt` (D1, D2, D4, D5, D8) = spec-correct stdout: for D1 (FG-converted
  `crash` kind) the runner additionally builds + runs `main.zig` and goldens
  stdout/rc before printing `ok`; for D2/D8 it is the `wrong` kind's reference;
  for D4/D5 (FB/FC-converted `runok` kind) the runner compiles, builds, runs
  `main.zig` rc 0 and diffs stdout against this file.
- `expected_error.txt` (D07, D09, D12, S01) = the `fixedreject` kind's expected
  diagnostic census (`<code> <count>`): the runner requires exactly that many
  occurrences of that code, rc != 0, no `.c` emitted, and no signal.
