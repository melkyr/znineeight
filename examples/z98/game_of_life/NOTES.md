# game_of_life — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `f855c9f93c73422f56378f3f73231727`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/z98/game_of_life/main.zig -o build/game_of_life
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
(Glider pattern ASCII art across generations)
```

## Notes
Multi-file: `main.zig` imports `std.zig` and `std_debug.zig`. Uses `system("cls")` — ignore `cls: not found` on stderr. Warnings ok.
