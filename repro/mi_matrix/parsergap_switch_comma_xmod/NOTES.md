# parsergap_switch_comma_xmod — RED: value-less return in switch prong rejected

## What it tests
A value-less `return` as a switch prong expression (`else => return,`) — the
exact shape that mirrors `lexerSkipWSC` at sf/src/lexer.zig:236. The Z98
self-hosted compiler (`zig1`) rejects it at parse time. Fixture is
self-contained: bare `@import("std")` (canonical lib at `/tmp/fx_subfolder/lib/`)
+ `std.io.printInt(c)` (canonical print, `std_io.zig`).

## (a) Measured baseline — RED (2026-08-18, `/tmp/fx_subfolder/zig1` at HEAD 505177c6)

```
cd repro/mi_matrix/parsergap_switch_comma_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` expected expression / unexpected token** — reported at
  main.zig:6:22, caret under the `1` of the FIRST prong's block body
  (`' ' => { c = 1; }`), i.e. the parser chokes on the value-less prong shape.
  Full diagnostic:

```
main.zig:6:22: error[2000]: expected expression
        ' ' => { c = 1; },
                      ^
main.zig:6:22: error[2000]: unexpected token
        ' ' => { c = 1; },
                      ^
main.zig:9:0: error[2000]: expected expression
    std.io.printInt(c);
^
main.zig:9:0: error[2000]: unexpected token
    std.io.printInt(c);
^
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend parse gap, classified FAIL
  (never "OK").

NOTE: plan predicted the caret at `return`/`,`; observed reality is a caret at
6:22 on the first prong's `1`. This is the known multi-line/source-offset quirk
of the error reporter (also seen in parsergap_wrap_arith_xmod). The value-less
`return` prong is still unambiguously RED: rc=2, error[2000], 0-byte `.c`.

## (b) Control — GREEN (temporary braced variant, /tmp only, NOT committed)
`/tmp/parsergap_switch_comma_xmod_control.zig`: identical fixture except the
second prong is `else => {}` instead of `else => return,`.

- **dump rc=0** (`zig1 --dump-c89`), 10472-byte `.c`
- **gcc rc=0** (`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign
  -I sf/src/include /tmp/x_control.c sf/src/include/zig_runtime.c
  sf/src/include/zig_pal.c -o /tmp/x_control`)
- **run rc=0**, prints **`0`**

## (c) Post-fix expectation
GREEN: the value-less `return` prong compiles (rc=0, non-empty `.c`, gcc rc=0)
and the program prints `0` — identical behavior to the control variant. The
parser must accept a `return` statement (no expression) as a switch prong body.
