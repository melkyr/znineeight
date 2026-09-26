# D7 — `print` with a non-tuple literal argument silently no-ops (RED)

## Claim
`print(fmt, <non-tuple literal>)` is accepted rc 0 and the argument is never
printed: the placeholder is dropped and only the literal format text around it
(plus newline) survives. Spec §4 says the arguments **must** be a tuple literal
or a tuple variable.

## Chapter impact
Chapter 18 (print, sample `print.z98`) — a wrong-argument sample silently
produces empty output instead of a diagnostic.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D07_nontuple_print
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D07_nontuple_print \
    repro/vol2_defects/D07_nontuple_print/main.zig
cd /tmp/vol2_defects_out/D07_nontuple_print && timeout 120 sh build_target.sh linux main
timeout 120 ./main | od -c
```

## OBSERVED
- `main.zig` (`std.io.print("{}\n", 5);`): compile/build/run rc 0; stdout is
  exactly one byte `\n` (`od -c` -> `\n`). No `5`, no diagnostic.
- `red_prefixed_literal.zig` (`"bare={}\n"`): stdout `bare=\n` — the literal
  text is kept, the placeholder and argument vanish.
- `red_alias.zig` (`const p = std.io.print; p("{}\n", 5);`): rc 0, stdout
  `\n`; emitted C is just `std_print("\n");` — the special case still fires
  through the alias and drops the value.
- `xmod_main.zig` + `logger.zig` (call inside the imported module): stdout
  `helper-bare=\n` — same silent drop across the module boundary.
- `control_tuple.zig`: `tuple=7 8` (tuple-literal form prints correctly).
- Emitted C for `main.zig` (`main_8797A6B3.c`) — the argument is gone:
  ```c
  void zF_EA90E208_main(void) {
      std_print("\n");
      return;
  }
  ```

## EXPECTED
Language Spec §4: "**Arguments**: The arguments **must** be a tuple literal
(e.g., `.{arg1, arg2}`) or a tuple variable." Expected behavior is a compile
diagnostic for the bare value, not a silent drop. Zig 0.15.2 oracle
(comparison only): `error: expected tuple or struct argument, found
comptime_int`.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| In-module bare literal | `main.zig` | RED | stdout `\n` |
| Prefixed format text | `red_prefixed_literal.zig` | RED | stdout `bare=\n` |
| Aliased callee | `red_alias.zig` | RED | stdout `\n`, `std_print("\n")` |
| Cross-module call | `xmod_main.zig` + `logger.zig` | RED | stdout `helper-bare=\n` |
| Tuple literal | `control_tuple.zig` | control | `tuple=7 8` |

## Boundary
Only the literal argument is a *silent no-op*. During authoring, sibling
defects surfaced for non-literal non-tuple arguments and for mixing print-call
shapes in one module; they are pinned in `S01_print_nontuple_args/` rather
than here (tuple-variable rejected `error[3013]`, mixed calls misattribute
`error[3013]` or SIGSEGV, two var-arg calls print wrong values). The D7
investigation should treat D7 = "literal argument silently dropped" and consume
S01 for the surrounding container bugs.
