# lisp_interpreter_curr — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `0ad0204088f91c1eae7c040da8f99a1c`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/lisp_interpreter_curr/main.zig -o build/lisp_interpreter_curr
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
>  (REPL prompt, reads stdin until EOF)
```
Stress test: all arithmetic, closures, recursion work.

## Notes
Multi-file: 10 modules — sand, value, token, parser, env, eval, builtins, util, deep_copy. REPL functions correctly.
