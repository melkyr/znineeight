# lisp_interpreter — Z98 Example

**Status:** BROKEN

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** N/A (dump fails)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/lisp_interpreter/main.zig -o build/lisp_interpreter
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/lisp_interpreter/main.zig
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
Multi-file: 9 modules. Uses hand-rolled tagged unions (struct+tag+union) instead of `union(enum)`. Uses bare `!` (inferred error sets) instead of explicit `LispError`. Incompatible with zig1, needs upgrade to tagged-union syntax.

**[updated 2026-08-04 — P1-3 battery re-measure, HEAD 60337a84]** Dump rc=3, emits 2 `.c` (main, sand), stderr shows `error[3043]: internal: store_field unresolved field (field_id 1)` (plus a `warning[3000]` type-mismatch note). The old key error `error[3011] error literal not found in error set` (inferred error set through `@ptrCast(fn(...) !*Value, builtin_ptr)`) is GONE — the F-1 error[3011] fix removed it — and the current blocker is now the error[3043] store_field ICE instead.
**[updated 2026-08-08 — F4 I/O migration]** Dump now rc=0 and emits 12 `.c`; `__bootstrap_print*`
externs → `std.io.print`/`std.io.printInt` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).
Still **does not compile**: gcc `-c` fails on the pre-existing lowerer `zT_N` defect in
`token.c`/`parser.c`/`builtins.c` (`zT_9/zT_25/…` undeclared, `Opt_` assign from `int`) — the
documented F7 "lisp builtins `zT_N`" follow-up. Not a regression: pre-F4 source fails identically.
