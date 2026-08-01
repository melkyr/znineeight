# game_of_life — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `f855c9f93c73422f56378f3f73231727`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/game_of_life/main.zig -o build/game_of_life
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/game_of_life/main.zig
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
(Glider pattern ASCII art across generations)
```

## Notes
Multi-file: `main.zig` imports `std.zig` and `std_debug.zig`. Uses `system("cls")` — ignore `cls: not found` on stderr. Warnings ok.
