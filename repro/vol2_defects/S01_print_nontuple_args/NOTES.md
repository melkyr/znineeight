# S1 — print-argument container family (new sibling found during D0; RED)

## Claim
`lowerPrintFmt` treats the last call argument as if it were the print-args
tuple container (`extraChildCount(arg)`). When the argument is not a tuple
literal, the container is empty or wrong. New sibling cluster found while
authoring D7; it is **not** the D7 literal no-op. Representative shapes:

- **Tuple variable** (spec-allowed): rejected `error[3013]`.
- **Two non-tuple literal calls** in one module: reject `error[3013]`
  **attributed to the first call** (wrong span, not the offending one).
- **Non-tuple variable call then tuple call**: reject `error[3013]` on the
  tuple call.
- **Tuple call then non-tuple variable call**: compiler SIGSEGV (rc 139).
- **Two non-tuple variable calls**: compile+run, but both placeholders print
  the FIRST variable's value (silent wrong output).
- **Expression argument** (`v + 1`): placeholder silently dropped, like D7.

## Chapter impact
Chapter 18 (print, sample `print.z98`) — a chapter sample that mixes print
shapes can crash the compiler; the spec's tuple-variable argument is unusable.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/S01_print_nontuple_args
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/S01_print_nontuple_args \
    repro/vol2_defects/S01_print_nontuple_args/main.zig        # rc 139
```

## OBSERVED
- `main.zig` (tuple call + non-tuple variable call): compile rc **139**,
  `Segmentation fault`; no C emitted.
- `red_tuple_var.zig` (`const t = .{7, 8}; print("...", t)`): compile rc 2:
  ```
  red_tuple_var.zig:8:17: error[3013]: invalid print format specifier for the argument type
      std.io.print("tuple-var={} {}\n", t);
  ```
  (Zig 0.15.2 oracle, comparison only: `std.debug.print("tuple-var={} {}\n", t)`
  compiles and prints `tuple-var=7 8`.)
- `red_two_literals.zig` (`print("one={}\n", 1); print("two={}\n", 2);`):
  compile rc 2, the diagnostic points at the FIRST call:
  ```
  red_two_literals.zig:7:17: error[3013]: invalid print format specifier for the argument type
      std.io.print("one={}\n", 1);
  ```
- `red_var_then_tuple.zig`: compile rc 2, diagnostic points at the TUPLE call
  (`tuple={}`, line 8).
- `red_two_vars.zig`: compile/build/run rc 0, stdout `one=1` / `two=1`
  (should be `one=1` / `two=2`) — silently wrong.
- `red_expr.zig` (`print("expr={}\n", v + 1)`): rc 0, stdout `expr=` — value
  dropped like D7.

## EXPECTED
Language Spec §4: "The arguments **must** be a tuple literal (e.g.,
`.{arg1, arg2}`) or a tuple variable." So:
- `red_tuple_var.zig` should compile and print `tuple-var=7 8`;
- the mixed/non-tuple shapes should reject at the OFFENDING call, with a
  correct span and no crash;
- `red_two_vars.zig` must never print wrong values (it should reject, since
  bare values are not accepted).

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Tuple call + non-tuple var call | `main.zig` | RED | compile rc 139 (SIGSEGV) |
| Tuple variable argument | `red_tuple_var.zig` | RED | `error[3013]` (spec allows it) |
| Two non-tuple literal calls | `red_two_literals.zig` | RED | `error[3013]` on first call |
| Var call then tuple call | `red_var_then_tuple.zig` | RED | `error[3013]` on tuple call |
| Two non-tuple var calls | `red_two_vars.zig` | RED | `one=1 two=1`, wrong values |
| Expression argument | `red_expr.zig` | RED | `expr=`, value dropped |

## Boundary (unsettled)
This cluster was found during D0 authoring, not in Task 0. The D0 tree pins
representative shapes only; the exact interaction trigger (why a second
non-tuple print call corrupts an earlier call's validation, and why the
tuple-then-var order SIGSEGVs) is left to the investigations. The report
lists this as an unsettled boundary and a candidate split into separate
investigations (spec-legal tuple-variable rejection vs wrong-span reject vs
crash vs silent wrong value).
