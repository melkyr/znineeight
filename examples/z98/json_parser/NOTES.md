# json_parser — Z98 Example

**Status:** OK-WITH-QUIRKS

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `11a5db1d3d43acf4880e2d157590abe3`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/json_parser/main.zig -o build/json_parser
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -c -Wno-long-long -Wno-pointer-sign -Isrc/include src/runtime/zig_runtime.c -o /tmp/rt.o
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c /tmp/rt.o sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
(Parses test.json, prints tree)
```
Object fields missing comma separator (e.g. `"status": "alpha"\n    "bugs": null` — no comma between fields).

## Notes
Multi-file: `main.zig` imports `file.zig` and `json.zig`. **STANDARD RECIPE DOES NOT LINK** — `arena_alloc_default` is in legacy `src/runtime/zig_runtime.c`, not `sf/src/include/zig_runtime.c`. Must compile legacy runtime separately as shown above. Needs `test.json` in CWD to run. Quirk: missing commas between object fields in output.
