# json_parser_workaround — Z98 Example

**Status:** OK (with tagged-union print quirk)

**Entry file:** `main.zig`

**Working commit:** (F3) `std.arena` migration

**MD5 (`--dump-c89`):** N/A (not an MD5-gate entry)

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
Starting main
Parsed JSON successfully
DEBUG: val.tag=<tag>
{}
```
(Prints `{}` — the hand-rolled tagged-union print path only renders the tag value, not the
payload; a known example-source quirk, not a build blocker.)

## Notes
Multi-file: `main.zig` imports `file.zig` and `json.zig`. Uses hand-rolled tagged unions (struct+tag+union) with field-store through @ptrCast pointer. Hand-rolled tagged union incompatible with zig1.

**[updated 2026-08-04 — P1-3 battery re-measure, HEAD 60337a84]** The `error[3043]: unsupported field-store base` ICE is GONE (F-3 fixed the field-store ICE). Dump now rc=0 and emits 3 `.c` files. However gcc rejects the emitted C: 6 errors in `main_A50966CE.c` (`zT_10`, `zT_16`, `zT_28`, `zT_34`, `zT_46`, `zT_91` undeclared). Classification changed from **ICE → emission defect** (dump ok, gcc fails).

**[updated 2026-08-08 — F3 cross-module enum member FIXED]** The 6× zT_xx forward-decl
COMPILE gap is GONE (F3, commit `021ffcfd` — cross-module enum member resolution; see
`zT_missing_fwd_xmod`). Dump rc=0, per-file gcc `-c` rc=0 (was 6× `zT_10/16/28/34/46/91`
undeclared).

**[F4 2026-08-08]** `main.zig` `__bootstrap_print*`/`__bootstrap_write` externs → `std.io.print/
printInt/write`; the arena import is re-pointed: `arena.zig`/`file.zig`/`json.zig` now
`@import("std.zig")` and call `std.arena.create/alloc` (F3 `std_arena.zig`-alias form replaced).
Verified: multi-module dump rc=0 (6 `.c`), gcc rc=0, standard-recipe link rc=0, run rc=0
(`{}` tag-print quirk unchanged).

## F3 fixed [updated 2026-08-08 — std.arena migration]
The D2/F2 std-lib-deferred `arena_alloc_default` link gap is CLOSED. `arena.zig`/`file.zig`/
`json.zig` no longer call the extern `arena_alloc_default` (declared
`sf/src/include/zig_runtime.h:21-22`, defined ONLY in the legacy
`src/runtime/zig_runtime.c:31/:154-156`, absent from `sf/src/include/zig_runtime.c` — a
class-(b) runtime-library gap per I2 report `.superpowers/sdd/I-orphan-module-report.md`).
They now import the new **`std_arena.zig`** module (`sf/src/std_arena.zig`, a pure Z98 bump
allocator: `Arena{data,capacity,used}` + `create/alloc/reset` over a 1MB static buffer;
copied into this dir so `@import("std_arena.zig")` resolves locally) and call
`std.create/alloc` instead. Verified (F3, `sf/build/out_release/zig1`): multi-module dump
rc=0 (main/json/file/std_arena), per-file gcc `-c` rc=0 (both the enum-member fix AND the
std_arena migration), **standard-recipe link rc=0 (no legacy runtime object)**, run rc=0
parses test.json (prints `{}` — the hand-rolled tagged-union print path still only shows
the tag; a known example-source quirk, not a build blocker). `repro/mi_matrix/
extern_runtime_symbol_xmod` was migrated to `std_arena.zig` too and is now a green
regression guard (link rc=0, run rc=0).
