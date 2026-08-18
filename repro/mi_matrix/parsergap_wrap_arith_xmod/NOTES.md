# parsergap_wrap_arith_xmod — RED: wrapping/saturating operator family rejected

## What it tests
All 15 wrapping/saturating operator forms (Zig `+% -% *% +| -| *| <<|`, prefix
`-%a`, and compound-assign `+%= -%= *%= +|= -|= *|= <<|=`) — a family the Z98
self-hosted compiler (`zig1`) rejects at parse time. Fixture is self-contained:
bare `@import("std")` (canonical lib at `/tmp/fx_subfolder/lib/`) + one function
exercising every form + `std.io.printInt(x)` (canonical print, `std_io.zig`).

## (a) Measured baseline — RED (2026-08-18, `/tmp/fx_subfolder/zig1` at HEAD 14796971)

```
cd repro/mi_matrix/parsergap_wrap_arith_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` expected expression / unexpected token** — reported at the
  FIRST operator `+%` of `x = a +% b;` (main.zig:7:11 in the compiler's line
  accounting; the caret is under the `+`). Full first-error diagnostic:

```
main.zig:7:11: error[2000]: expected expression
    x = a +% b;
           ^
main.zig:7:11: error[2000]: unexpected token
    x = a +% b;
           ^
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend parse gap, classified FAIL
  (never "OK").

NOTE on line numbers: the compiler's error report shows `main.zig:7:11` for the
`+%` operator; `cat -n` confirms `+%` is on physical line 6 of the committed
fixture. This is the known multi-line/source-offset quirk of the error reporter,
not a fixture mismatch — the caret column (11, under `+`) and the operator token
are unambiguous.

## (b) Control — GREEN (temporary `+`-substituted variant, /tmp only, NOT committed)
`/tmp/parsergap_wrap_arith_xmod_control.zig`: every operator replaced by its
plain form (`+%→+`, `-%→-`, `*%→*`, `+|→+`, `-|→-`, `*|→*`, `<<|→<<`,
prefix `-%a→-a`, and `+= -= *= <<=` for the compound forms). Same u8 vars, same
`std.io.printInt(x)`.

- **dump rc=0** (`zig1 --dump-c89`), 11671-byte `.c`
- **gcc rc=0** (`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign
  -I sf/src/include /tmp/x_control.c sf/src/include/zig_runtime.c
  sf/src/include/zig_pal.c -o /tmp/x_control`)
- **run rc=0**, prints **`128`**

Trace of printed value (u8, truncating): a=200,b=2 → +202 → -198 → *144 → +202
→ -198 → *144 → <<32 → -a=56 → +=58 → -=56 → *=112 → +=114 → -=112 → *=224
→ <<=128. **Prints 128.**

## (c) The full 15-form operator table
All 15 forms in the committed fixture, each independently verified RED below.

| # | Form | Kind | Fixture line | Isolated probe rc |
|---|------|------|--------------|-------------------|
| 1 | `a +% b` | binary wrap-add | `x = a +% b;` | 2 |
| 2 | `a -% b` | binary wrap-sub | `x = a -% b;` | 2 |
| 3 | `a *% b` | binary wrap-mul | `x = a *% b;` | 2 |
| 4 | `a +\| b` | binary sat-add | `x = a +\| b;` | 2 |
| 5 | `a -\| b` | binary sat-sub | `x = a -\| b;` | 2 |
| 6 | `a *\| b` | binary sat-mul | `x = a *\| b;` | 2 |
| 7 | `a <<\| b` | binary sat-left-shift | `x = a <<\| b;` | 2 |
| 8 | `-%a` | prefix wrap-neg | `x = -%a;` | 2 |
| 9 | `x +%= b` | compound wrap-add | `x +%= b;` | 2 |
| 10 | `x -%= b` | compound wrap-sub | `x -%= b;` | 2 |
| 11 | `x *%= b` | compound wrap-mul | `x *%= b;` | 2 |
| 12 | `x +\|= b` | compound sat-add | `x +\|= b;` | 2 |
| 13 | `x -\|= b` | compound sat-sub | `x -\|= b;` | 2 |
| 14 | `x *\|= b` | compound sat-mul | `x *\|= b;` | 2 |
| 15 | `x <<\|= b` | compound sat-shift | `x <<\|= b;` | 2 |

The `\|` shown in this table is the Markdown-escaped pipe; actual tokens are
`+|`, `-|`, `*|`, `<<|`, `+|=-|=`, `*|=`, `<<|=`.

## (d) Parse behavior note
Deviation from plan note (d): the plan assumed the parser stops at the first
error so only form #1 (`+%`) is proven RED here. Observed reality: `zig1` does
NOT stop — the single RED run above reports `error[2000]` at **all 15** operator
sites (every fixture line from `+%` through `<<|=`, plus a trailing cascade on
the final `printInt` line). Every one of the 15 forms was additionally verified
**in isolation** (minimal single-operator probe in /tmp): each dumps rc=2 with a
0-byte `.c`. So this fixture + the isolation probes prove all 15 forms RED.
Per the plan, per-form enumeration is also carried in the I-ARITH probe battery
(not this task); the isolated probes here are supplementary evidence only.
