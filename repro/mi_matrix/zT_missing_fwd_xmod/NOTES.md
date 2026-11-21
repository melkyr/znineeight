# zT_missing_fwd_xmod — FAIL (multi-module emission gap, undeclared zT_XX cross-module enum literal)  [R1c, 2026-08-08]

## What it tests
A cross-module enum literal comparison: `types.zig` declares `pub const
Tag = enum { Null, Boolean, Number };`, and `main.zig` (importing `types.zig`)
compares a parameter `tag == t.Tag.Null` in a branch. The emitted C for
`main_*.c` reads `zT_3 = tag == zT_2;` where `zT_2` is the enum-literal temp
that is never declared in the module → gcc compile fails with
`error: 'zT_2' undeclared`. Minimal version of `json_parser_workaround`
(gcc compile FAIL: `'zT_10' undeclared`, `'zT_16' undeclared`, … at
`main_A50966CE.c:212` etc. — cross-module `val.tag == json.JsonValueTag.Null`
enum comparisons, MEM4).

## The compiler gap
zig1's multi-module type emission declares enum-literal temporaries for
cross-module enum values inconsistently: the temp symbol `zT_XX` is
referenced in the emitted function body but its declaration is missing from
the emitted module. (The brief's original R1c form — a struct `Point`
passed by value as a function param — does NOT trigger this: the emitted
`main_*.h` correctly `#include "types_*.h"` and forward-declares
`zT_EAA8EF31_Point`, and gcc compiles it clean. The struct-forward-decl
path works for simple structs; the actual corpus failure
(`json_parser_workaround`) is the cross-module ENUM-LITERAL comparison, so
this repro uses that faithful trigger.)

## Measured result (2026-08-08, sf/build/out_release/zig1)
- dump rc=0, `.c`/`.h` emitted for both modules.
- gcc `-c` of `main_*.c`: rc=1 — `error: 'zT_2' undeclared` (the enum
  literal temp is used but never declared).
- gcc `-c` of `types_*.c`: rc=0.
- Expected pre-fix behavior confirmed: emission defect (compile-time, not
  link-time).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy compiles clean (rc=0) and emits the enum
literal as a named constant (`zS_..._Tag_Null`) — a cross-module enum
literal comparison is valid Z98, genuine compiler gap.

## Expected classification
FAIL (multi-module emission gap) until cross-module enum-literal temps are
declared in the emitting module (then gcc compile rc=0).
