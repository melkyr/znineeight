# lisp_interpreter_adv — Z98 Example

**Status:** OK-WITH-BUG

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `5783ee16976852cecaffdaf355edb698` [verified: 2026-08-08]

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/lisp_interpreter_adv/main.zig -o build/lisp_interpreter_adv
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/lisp_interpreter_adv/main.zig
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
>  (REPL prompt)
```
Basic expressions work but `define` + call silently fails.

## Notes
Multi-file: 10 modules. Runtime bug — variable is in scope after closure returns but value is nil. `define` followed by call produces nil instead of defined value.
[F4 2026-08-08: `__bootstrap_print*` externs → `std.io.print`/`std.io.printInt` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies). Builds + runs rc=0; known define-after-closure runtime bug unchanged.]
