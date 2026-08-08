# json_parser — Z98 Example

**Status:** OK-WITH-QUIRKS

**Entry file:** `main.zig`

**Working commit:** `bf5d3636`

**MD5 (`--dump-c89`):** `900cb401779aab11bcf22ce35100323c` [updated: 2026-08-06]
(Re-baselined 2026-08-03/2026-08-05 per AMENDMENT 9-11 / P3-6 error-code registry; previous
`11a5db1d…` stale.)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/json_parser/main.zig -o build/json_parser
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/json_parser/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/src/include -c /workspace/znineeight/src/runtime/zig_runtime.c -o /tmp/rt.o
gcc -m32 *.o /tmp/rt.o /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
(Parses test.json, prints tree)
```
Object fields missing comma separator (e.g. `"status": "alpha"\n    "bugs": null` — no comma between fields).

## Notes
Multi-file: `main.zig` imports `file.zig` and `json.zig`. **STANDARD RECIPE DOES NOT LINK** — `arena_alloc_default` is in legacy `src/runtime/zig_runtime.c`, not `sf/src/include/zig_runtime.c`. Must compile legacy runtime separately as shown above. Needs `test.json` in CWD to run. Quirk: missing commas between object fields in output.

## Deferred to std-lib [added 2026-08-08 — F2, per operator ruling]
`arena_alloc_default` is an `extern` (`json.zig:253`, `file.zig:25`) declared in
`sf/src/include/zig_runtime.h:21-22` but defined ONLY in the legacy
`src/runtime/zig_runtime.c:31/:154-156` — the sf runtime (`sf/src/include/zig_runtime.c`)
provides no arena symbols. This is a **class-(b) runtime-library gap**, NOT a compiler
defect (I2 report `.superpowers/sdd/I-orphan-module-report.md`; `mod_silent_drop_xmod`
proves all modules emit; the compiler never emits extern definitions). It is a
**documented runtime API** (`docs/reference/runtime_api.md:38-48`, "provided primarily for
backward compatibility with earlier bootstrap milestones"). **Operator ruling: deferred to
the std-zig1 library — NOT fixed here.** The standard recipe (sf runtime) fails on **5
`undefined reference to arena_alloc_default`** (4 in json + 1 in file); the recipe above
(compiling the legacy `src/runtime/zig_runtime.c` to `/tmp/rt.o`) makes it link+run.
The `repro/mi_matrix/extern_runtime_symbol_xmod` repro is the std-lib plan's spec for this
gap (flips to PASS when the std-lib runtime provides the symbol). The workaround note
above (legacy-runtime link) becomes obsolete once the sf runtime gains the definition —
the two runtimes must not both be linked (duplicate-symbol risk).
