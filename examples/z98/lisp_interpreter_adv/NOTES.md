# lisp_interpreter_adv — Z98 Example

**Status:** OK-WITH-BUG

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `5783ee16976852cecaffdaf355edb698`

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
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c /tmp/out/*.c
gcc -m32 /tmp/out/*.o sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/out/prog
/tmp/out/prog
```

## Expected Output
```
>  (REPL prompt)
```
Basic expressions work but `define` + call silently fails.

## Notes
Multi-file: 10 modules. Runtime bug — variable is in scope after closure returns but value is nil. `define` followed by call produces nil instead of defined value.
