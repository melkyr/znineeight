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
Task 1 of M1 adds `cli.zig` (argv parsing, `usage`, `exitCodeFor`) and wires `main.zig`
to it. `main` now has `pub fn main(argc: i32, argv: [*][*]u8) void` so the emitted C
wrapper forwards `argc`/`argv`; the return type stays `void`. `parseArgs` takes the Z98
slice form `[][*]u8` (the generated main cast for a slice param is invalid C, so `main`
converts from the many-pointer with `argv[0..n]`).

Exit codes per spec §8: 0 success, 1 usage, 2 torrent/file, 3 tracker/net, 4 peer,
5 disk. The seed compiler has no `anyerror`, so `exitCodeFor` uses the brief-authorized
fixed-mapping alternative: it takes a concrete `FailureClass` enum (usage=1..disk=5).

The seed `lib/std.zig` does not re-export `file`, so `std_file` is imported by path
(`@import("std_file.zig")`). Tests: `tests/tier1_cli.sh` (CLI shapes).

**Win9x argv caveat:** on Windows 9x the CRT builds `argv` from `GetCommandLineA`, which
is subject to the 16-bit command-line length limit and Win9x quoting rules. The parser
consumes the `argv` the runtime supplies and never re-tokenizes the raw command line, so
Win9x argument handling matches the CRT's, not a custom splitter.

MD5 not baselined in Task 0 (TBD).
