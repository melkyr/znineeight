# tco_return_try — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**MD5 (`--dump-c89`):** re-captured [updated: 2026-08-08]

## Build Recipes

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_return_try/main.zig > /tmp/tr.c
```

### GCC compile + link + run
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/tr.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/tr
/tmp/tr
```

## Expected Output
```
count(10) = 10
count(100000) = 100000
```

## Notes
TCO gate: emitted C has `goto z_bb_0;` back-edge in `count()` (try-CFG eliminated).
[F4 2026-08-08: `std_debug.zig` migrated from `__bootstrap_print*` externs to `std.io` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
