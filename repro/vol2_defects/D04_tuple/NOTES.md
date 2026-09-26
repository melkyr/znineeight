# D4 — tuple type/access unusable (RED, chapter-blocking)

## Claim
- The tuple type `struct { T1, T2 }` from Language Spec §1.3 is a parse error
  (`error[2000]: expected ':' but found ','`).
- `t.0` and `t._0` are rejected `error[3060]: no field or member function named
  ...`.
- `t[0]` passes sema (compile rc 0) then gcc rejects the emitted C
  (`subscripted value is neither array nor pointer nor vector`).

## Chapter impact
Chapter 8 (tuples, sample `pair.z98`) — chapter-blocking; the operator ruling
(fix compiler vs re-scope ch8) is still open (Task 0 OQ 1).

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D04_tuple
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D04_tuple \
    repro/vol2_defects/D04_tuple/main.zig                 # rc 2, parse error
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D04_tuple \
    repro/vol2_defects/D04_tuple/red_index.zig            # rc 0
cd /tmp/vol2_defects_out/D04_tuple && timeout 120 sh build_target.sh linux red_index
```

## OBSERVED
- `main.zig`: compile rc 2:
  ```
  main.zig:5:25: error[2000]: expected ':' but found ','
  const Pair = struct { i32, i32 };
  ```
- `red_return_type.zig`: rc 2, same `error[2000]` on the return type
  `struct { i32, i32 }`.
- `red_dot0.zig`: rc 2, `error[3060]: no field or member function named ''`
  at `anon.0`.
- `red_underscore.zig`: rc 2, `error[3060]: ... named '_0'` at `anon._0`.
- `red_index.zig`: compile rc 0; gcc build rc 1:
  ```
  red_index_4E0B4AD9.c:29:16: error: subscripted value is neither array nor pointer nor vector
  red_index_4E0B4AD9.c:33:16: error: subscripted value is neither array nor pointer nor vector
  ```
  Emitted C (the tuple is a struct with `_0`/`_1` fields, then indexed):
  ```c
  zT_1._1 = zT_3;
  anon = zT_1;
  std_print("t[0]=");
  zT_4 = 0;
  zT_5 = anon[zT_4];
  ```
- Passing today:
  - `control_literal_print.zig` -> `anon=.{ 10, 20 }` and
    `nested=.{ 1, .{ 2, 3 } }`.
  - `control_grouped_return.zig` (positional `.{ a / b, a % b }` into a named
    struct return type) -> `q=3 r=2`.
  - `xmod_main.zig` + `helper.zig` (module-scope tuple const + named-struct
    grouped return) -> `pair=.{ 10, 20 }`, `q=3 r=2`.

## EXPECTED
Language Spec §1.3: "**Tuples**: `struct { T1, T2, ... }` for types and
`.{ val1, val2, ... }` for positional anonymous literals. **Member Access**:
Accessed via numeric indices (e.g., `t.0`, `t.1`). ... **Usage**: Primarily
used for `print` arguments and grouped return values." The tuple type and
`.0` access must compile. Zig 0.15.2 oracle (comparison only): the equivalent
program compiles and prints `p=3 4` for tuple type + `p[0]` access.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Tuple type declaration | `main.zig` | RED | `error[2000]` |
| Tuple return type | `red_return_type.zig` | RED | `error[2000]` |
| `t.0` access | `red_dot0.zig` | RED | `error[3060]` |
| `t._0` access | `red_underscore.zig` | RED | `error[3060]` |
| `t[0]` indexing | `red_index.zig` | RED | gcc `subscripted value ...` |
| Literal + `{}` print | `control_literal_print.zig` | control | prints `.{ ... }` |
| Grouped return via named struct | `control_grouped_return.zig` | control | `q=3 r=2` |
| Cross-module tuple const + grouped return | `xmod_main.zig` + `helper.zig` | control | `pair=.{ 10, 20 }`, `q=3 r=2` |
| Cross-module tuple-type return/param | (not representable) | boundary | the tuple type cannot be spelled in either module |

## Boundary
"Grouped returns work today" only through a NAMED struct whose fields are
filled positionally from a `.{...}` literal; the spec's tuple-type spelling
and element access are unusable in-module and cross-module. A cross-module
tuple return/param shape cannot even be written (no tuple type name), so the
closest representable shapes are the module-scope tuple const and the
named-struct grouped return above.
