# days_in_month — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `96d49e025fdf638b5b9b5b8b5cc37fc4`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/days_in_month/main.zig -o build/days_in_month
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/days_in_month/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
(Calendar output, month names show null bytes — display corruption)
```

## Notes
Cosmetic: month name null bytes cause display corruption in calendar output.
