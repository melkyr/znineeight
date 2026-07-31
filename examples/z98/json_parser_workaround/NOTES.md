# json_parser_workaround — Z98 Example

**Status:** BROKEN

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** N/A (dump fails)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/json_parser_workaround/main.zig -o build/json_parser_workaround
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser_workaround/main.zig
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
Multi-file: `main.zig` imports `file.zig` and `json.zig`. Dump rc=3 (ICE/PANIC). Uses hand-rolled tagged unions (struct+tag+union) with field-store through @ptrCast pointer: `val_ptr.data = val.data` triggers `error[3043]: unsupported field-store base`. ICE, hand-rolled tagged union incompatible with zig1.
