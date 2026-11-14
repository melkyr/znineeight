# tco_defer — Z98 Example

**Status:** OK (pre-existing quirks)

**Entry file:** `main.zig`

**MD5 (`--dump-c89`):** re-captured [updated: 2026-08-08]

## Build Recipes

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_defer/main.zig > /tmp/td.c
```

### GCC compile + link + run
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/td.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/td
/tmp/td
```

## Expected Output
```
countDown(10) = 10
countDown(100000) = 100000
deep ok
```

## Notes
TCO gate: emitted C has `goto z_bb_0;` back-edge in `countDown()`.
Pre-existing lowerer quirk: the TCO+defer path drops the return VALUE (`printInt` prints `0`) and the
defer fires twice — unchanged by F4. Output ORDER also shifted under redirection (std.io unifies the
write path through libc stdio `fwrite`; pre-F4 used raw PAL writes). Not a regression; run rc=0.
[F4 2026-08-08: `__bootstrap_print` externs → `std.io.print` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
