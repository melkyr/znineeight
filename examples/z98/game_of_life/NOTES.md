# game_of_life — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `bf5d3636`

**MD5 (`--dump-c89`):** `b246a2fecc0b5ff4402912c49970cdae` [updated: 2026-08-08]
(Re-baselined 2026-08-08 — F4 `std.io` migration replaces `__bootstrap_sleep_ms`/`__bootstrap_print*`
with `std.io.sleepMs`/`std.io.print*`; runtime output byte-identical to pre-F4 (glider, 100
generations, md5 `fcbf7e7c…`), per F-5 AMENDMENT B. Previous `e2f4c625…` stale. NOTE: `sleepMs`
now uses a real `usleep` (was a busy loop) — a 100-gen run takes ~10s.)

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
[F4 2026-08-08: `__bootstrap_sleep_ms` extern → `std.io.sleepMs`; `std_debug.zig` → `std.io` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
