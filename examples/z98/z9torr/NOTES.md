# z9torr — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `01dd8843`

**MD5 (`--dump-c89`):** `TBD` (not captured in Task 0; recorded by a later task/closeout)

## Build Recipes

### seed zig1_5_clean (build + run) — binding
```bash
mkdir -p /tmp/z9_m1_out
timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9_m1_out examples/z98/z9torr/main.zig
sh /tmp/z9_m1_out/build_target.sh linux /tmp/z9_m1_out/prog
/tmp/z9_m1_out/prog
```

### zig1 (dump C89) — for the MD5 above
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/z9torr/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

## Expected Output
```
z9torr
```

## Notes
Single-file skeleton. Task 0 of M1. `main.zig` imports the canonical `std` root package
and writes the literal `z9torr\n` to stdout via `std.io.write`. No sub-modules yet.
MD5 not baselined in Task 0 (TBD).
