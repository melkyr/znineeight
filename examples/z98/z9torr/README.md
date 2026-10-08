# z9torr

z9torr — a BitTorrent client example for the Z98 bootstrap compiler.

This is the Task 0 skeleton: a minimal, buildable entry point that prints `z9torr`.

## Files
- `main.zig`: Entry point. Writes `z9torr` to stdout.
- `NOTES.md`: Build recipes, expected output, and status.
- `README.md`: This file.

## Build and Run

```bash
mkdir -p /tmp/z9_m1_out
timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9_m1_out examples/z98/z9torr/main.zig
sh /tmp/z9_m1_out/build_target.sh linux /tmp/z9_m1_out/prog
/tmp/z9_m1_out/prog
```

**Expected output:**
```
z9torr
```

## Status
Skeleton only. Full BitTorrent functionality lands in later M1 tasks.
