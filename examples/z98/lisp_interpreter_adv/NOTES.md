# lisp_interpreter_adv — Z98 Example

**Status:** OK-WITH-BUG

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `5783ee16976852cecaffdaf355edb698`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/z98/lisp_interpreter_adv/main.zig -o build/lisp_interpreter_adv
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_adv/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
>  (REPL prompt)
```
Basic expressions work but `define` + call silently fails.

## Notes
Multi-file: 10 modules. Runtime bug — variable is in scope after closure returns but value is nil. `define` followed by call produces nil instead of defined value.
