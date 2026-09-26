# Volume II defect repro set (task D0)

Read-only, committed defect reproduction set for the twelve verified
compiler-defect candidates from the Volume II capability inventory (Task 0 +
independent review). **These repros pin current seed-compiler behavior; they do
not fix anything.** The D1-D12 investigation tasks and any later
operator-authorized F tasks consume this set.

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
| D1 | `D01_defer_segfault/` | A module with one plain-`defer` fn and one `for`/`while`-body-`defer` fn makes the compiler SIGSEGV (rc 139) | ch11 (defer) -- blocks | Boundary matters: crash needs both shapes in the SAME module; `xmod_main.zig` (both in helper) crashes, `split_*` controls pass |
| D2 | `D02_enum_switch_ranges/` | Enum `switch` range prongs (`a...b`, `a..b`) emit no `case` labels; every value takes `else` (silent wrong code) | ch6 (enums), ch10 (switch) | Does not matter: `xmod_main.zig` (enum from `colors.zig`) also all-`else` |
| D3 | `D03_missing_else/` | `switch` without `else` is accepted; an unmatched value reads an uninitialized result temp | ch10 (control flow) | Does not matter: `xmod_main.zig` (switch in `picker.zig`) also silent garbage |
| D4 | `D04_tuple/` | Tuple type `struct { T1, T2 }` is a parse error; `.0`/`._0` are `error[3060]`; `t[0]` emits gcc-invalid C | ch8 (tuples) -- chapter-blocking | Tuple type/access unusable in-module and cross-module; named-struct grouped returns work both ways |
| D5 | `D05_slice_to_manyptr/` | Implicit `[]T` -> `[*]T` coercion compiles rc 0 then gcc-rejects the C | ch3 (pointers), ch9 (arrays/slices) | Does not matter: `xmod_main.zig` emits `(int*)((int*)sl)` and gcc-rejects at the call |
| D6 | `D06_float_union/` | An f32 tagged-union payload init emits gcc-invalid C (`payload = double`) | ch7 (unions) | Does not matter: `xmod_main.zig` (union from `shapes.zig`) also gcc-rejects; f64/int/bool/struct payloads pass |
| D7 | `D07_nontuple_print/` | `print(fmt, <non-tuple literal>)` is silently accepted and prints no value | ch18 (print) | Does not matter: `xmod_main.zig` (call in `logger.zig`) also silently drops the value |
| D8 | `D08_errset_capture/` | `catch \|e\|` capture of an error set prints numeric where a typed value prints `error.Name` | ch12 (errors), ch18 (print) | Does not matter: `xmod_main.zig` (`errors.zig`) also prints `capture=1`; an annotated copy restores the name |
| D9 | `D09_bare_union_offsetof/` | `@offsetOf` on a bare union is an internal error (`error[3043]`); tagged unions ICE too | ch7 (unions), ch15 (builtins) | Does not matter: `xmod_main.zig` (union from `raw.zig`) also ICEs |
| D10 | `D10_single_ptr_index/` | `p[0]` on a single-item pointer is accepted and runs though spec 1.2 says it is rejected | ch3 (pointers) | Does not matter: `xmod_main.zig` (indexing in `helper.zig`) also accepted. Defect-vs-spec-correction is for the investigation; this pins current behavior |
| D11 | `D11_qualified_capture/` | `Shape.circle => \|r\|` (qualified prong) leaves the capture unbound (`error[20]`) | ch7 (unions) | Does not matter: `xmod_main.zig` (type from `shapes.zig`) also `error[20]`; `.circle =>` shorthand passes |
| D12 | `D12_const_discard_slice/` | `[]const T` -> `[]T` is accepted warning-only (in the var-decl shape) and mutates | ch9 (arrays/slices), ch3 (const) | Does not matter: `xmod_main.zig` accepted silently. Only the in-module var-decl shape warns; param/field/return are silent |
| S1 | `S01_print_nontuple_args/` | New sibling cluster: non-tuple `print` args are container-misinterpreted -- tuple-variable rejects, mixed calls misattribute `error[3013]` or SIGSEGV, two var calls print wrong values | ch18 (print) | Not settled; shapes are same-module only |

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
- `expected.txt` (D2, D8 only) = spec-correct stdout for the `wrong` kind.
