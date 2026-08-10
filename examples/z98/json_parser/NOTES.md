# json_parser — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** (F3) `std.arena` migration

**MD5 (`--dump-c89`):** `f50ce1e6800d9e1365c019e46ac61292` [updated: 2026-08-08]
(Re-baselined 2026-08-08 F3: `arena_alloc_default` extern replaced by the `std_arena.zig`
module — emitted C changes, runtime output byte-identical to pre-fix, verified by run diff.
Previous `c403f079…` stale. Re-baselined again 2026-08-08 F4: `__bootstrap_print*`/`__bootstrap_write`
externs → `std.io.print/printInt/write` + arena import re-pointed `std_arena.zig` → `std.zig`/
`std.arena`; runtime output byte-identical to pre-F4 (md5 `d90e7828…`), per F-5 AMENDMENT B.)

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
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
(Parses test.json, prints tree)
```
Object fields missing comma separator (e.g. `"status": "alpha"\n    "bugs": null` — no comma between fields).

## Notes
Multi-file: `main.zig` imports `file.zig` and `json.zig`. Links + runs with the STANDARD
recipe (sf runtime). Needs `test.json` in CWD to run. Quirk: missing commas between object
fields in output.

## F3 fixed [updated 2026-08-08 — std.arena migration]
The D2/F2 std-lib-deferred `arena_alloc_default` link gap is CLOSED. `arena.zig`/`file.zig`/
`json.zig` no longer call the extern `arena_alloc_default` (declared
`sf/src/include/zig_runtime.h:21-22`, defined ONLY in the legacy
`src/runtime/zig_runtime.c:31/:154-156`, absent from `sf/src/include/zig_runtime.c` — a
class-(b) runtime-library gap per I2 report `.superpowers/sdd/I-orphan-module-report.md`).
They now import the new **`std_arena.zig`** module (`sf/src/std_arena.zig`, a pure Z98 bump
allocator: `Arena{data,capacity,used}` + `create/alloc/reset` over a 1MB static buffer;
copied into this dir so `@import("std_arena.zig")` resolves locally) and call
`std.create/alloc` instead. Verified (F3, `sf/build/out_release/zig1`): multi-module
dump rc=0 (main/json/file/std_arena), per-file gcc `-c` rc=0, **standard-recipe link rc=0
(no legacy runtime object)**, run rc=0 parses test.json. Runtime output byte-identical to
pre-fix (old binary linked against legacy runtime vs new — `diff` empty), per the F-5
AMENDMENT B precedent. `repro/mi_matrix/extern_runtime_symbol_xmod` was migrated to
`std_arena.zig` too and is now a green regression guard (link rc=0, run rc=0).
**[F4 2026-08-08]** The arena import is re-pointed: `arena.zig`/`file.zig`/`json.zig` now
`@import("std.zig")` and call `std.arena.create/alloc` (the F3 `std_arena.zig`-alias form is
replaced by the canonical root-package API). `main.zig` uses `std.io.print/printInt/write`.
Verified: multi-module dump rc=0 (6 `.c`), gcc rc=0, standard-recipe link rc=0, run rc=0,
output byte-identical to pre-F4 (`d90e7828…`).
