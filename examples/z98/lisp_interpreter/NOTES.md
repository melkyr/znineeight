# lisp_interpreter — Z98 Example

**Status:** BROKEN

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** N/A (dump fails)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/z98/lisp_interpreter/main.zig -o build/lisp_interpreter
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
N/A — does not build
```

## Notes
Multi-file: 9 modules. Dump rc=2, stderr errors. Uses hand-rolled tagged unions (struct+tag+union) instead of `union(enum)`. Uses bare `!` (inferred error sets) instead of explicit `LispError`. Key error: `error[3011] error literal not found in error set` in `eval.zig` at `@ptrCast(fn(...) !*Value, builtin_ptr)` — inferred error set can't be populated through ptrCast. Incompatible with zig1, needs upgrade to tagged-union syntax.
