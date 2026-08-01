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
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c /tmp/out/*.c
gcc -m32 /tmp/out/*.o sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/out/prog
/tmp/out/prog
```

## Expected Output
```
N/A — does not build
```

## Notes
Multi-file: 9 modules. Dump rc=2, stderr errors. Uses hand-rolled tagged unions (struct+tag+union) instead of `union(enum)`. Uses bare `!` (inferred error sets) instead of explicit `LispError`. Key error: `error[3011] error literal not found in error set` in `eval.zig` at `@ptrCast(fn(...) !*Value, builtin_ptr)` — inferred error set can't be populated through ptrCast. Incompatible with zig1, needs upgrade to tagged-union syntax.
