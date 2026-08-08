# json_parser_workaround — Z98 Example

**Status:** BROKEN

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** N/A (dump fails)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/json_parser_workaround/main.zig -o build/json_parser_workaround
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/json_parser_workaround/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
N/A — does not build
```

## Notes
Multi-file: `main.zig` imports `file.zig` and `json.zig`. Uses hand-rolled tagged unions (struct+tag+union) with field-store through @ptrCast pointer. Hand-rolled tagged union incompatible with zig1.

**[updated 2026-08-04 — P1-3 battery re-measure, HEAD 60337a84]** The `error[3043]: unsupported field-store base` ICE is GONE (F-3 fixed the field-store ICE). Dump now rc=0 and emits 3 `.c` files. However gcc rejects the emitted C: 6 errors in `main_A50966CE.c` (`zT_10`, `zT_16`, `zT_28`, `zT_34`, `zT_46`, `zT_91` undeclared). Classification changed from **ICE → emission defect** (dump ok, gcc fails).

## Deferred to std-lib [added 2026-08-08 — F2, per operator ruling]
Like `json_parser`, this example calls `arena_alloc_default` (extern at `json.zig:253`,
`file.zig:22`, `arena.zig:1`), declared in `sf/src/include/zig_runtime.h:21-22` but defined
ONLY in the legacy `src/runtime/zig_runtime.c` — a **class-(b) runtime-library gap**, NOT a
compiler defect (I2 report `.superpowers/sdd/I-orphan-module-report.md`; the compiler never
emits extern definitions). The API is documented (`docs/reference/runtime_api.md:38-48`).
**Operator ruling: deferred to the std-zig1 library — NOT fixed here.** The standard recipe
(sf runtime) fails on 5 `undefined reference to arena_alloc_default` (4 in json + 1 in
file); linking the legacy `src/runtime/zig_runtime.c` object makes it link. NOTE: unlike
json_parser this example remains **BLOCKED by the I3 6× zT_xx forward-decl COMPILE gap**
(`main_A50966CE.c` undeclared `zT_10/16/28/34/46/91`) even after the runtime fix — the
arena symbol is only one of two blockers. The `repro/mi_matrix/extern_runtime_symbol_xmod`
repro is the std-lib plan's spec for the arena extern-link gap.
