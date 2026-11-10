# z9gb

A Game Boy emulator shell for Z98. This example is at **P1: platform
abstraction + deterministic headless backend**. It provides the `Platform`
callback table, a pure-Z98 headless backend, and an `Emu` facade with fixed
storage, but it does **not** emulate the CPU, PPU, or APU yet — P1 frames are a
deterministic self-test pattern.

P1 has no window, no Win32/DirectX dependency, no heap allocation, and no save
backend. Header parsing, memory-bank controllers, and actual emulation arrive in
P2.

## Building with zig1

The compiler is self-hosted. A seed build
(`scripts/seed/build_from_seed.sh`) puts `lib/` next to the `zig1` binary, and
the compiler searches `<exe-dir>/lib` automatically. `-o <dir>` selects the
output directory (create it first) and emits a complete self-contained C89 tree
with a companion `build_target.sh`.

### Linux

```sh
mkdir -p /tmp/z9gb_p1
/path/to/zig1_5_clean -ffast -o /tmp/z9gb_p1 main.zig
sh /tmp/z9gb_p1/build_target.sh linux /tmp/z9gb_p1/z9gb
/tmp/z9gb_p1/z9gb --headless --frames 1 --fb-out /tmp/z9gb_p1.fb
```

The emitted framebuffer file is 92,160 bytes: 160×144 little-endian RGB32
pixels, written identically on every run.

## Usage

```sh
z9gb [--headless] [--frames <n>] [--fb-out <path>] [--rom <path>]
```

- `--headless` selects the headless platform (the only P1 backend). It never
  opens a window and imports no Win32 or DirectX header.
- `--frames <n>` runs `n` frames before presenting the framebuffer (default
  `1`).
- `--fb-out <path>` writes the final framebuffer as 160×144 little-endian
  `u32` RGB32 pixels (92,160 bytes).
- `--rom <path>` copies a ROM into the fixed **8 MiB** buffer after a
  size-checked load. Files larger than 8 MiB are rejected with
  `ROM too large` and exit code 2. This is a byte copy only: no header parsing
  and no emulation happen until P2. The size check compares the full 64-bit
  file size before narrowing, so a file at or above 4 GiB cannot truncate into
  the cap.

Unknown flags and missing operands exit with code 1; a bad ROM or an
unopenable headless platform exits with code 2.

## RAM model

- The **1 MiB stack** is a hard limit and is separate from the **1 MiB code
  cache** (the code cache is not part of P1).
- The **8 MiB ROM buffer** is a static module-scope buffer inside the single
  `Emu` instance; it is never a stack local and never copied by value.
- The 92,160-byte framebuffer and the platform snapshots are static too.
- P1 performs no heap allocation.

## P1 gate

```sh
bash examples/z98/z9gb/tests/tier_smoke.sh /path/to/zig1_5_clean
bash examples/z98/z9gb/tests/measure_rss.sh /path/to/zig1_5_clean /tmp/z9gb_p1_rss
```

The smoke tier checks that the platform modules dump cleanly with no
Win32/DirectX header, builds the headless CLI, verifies the deterministic
framebuffer (size plus full-image MD5 `54c0af1aa8cee3642b6f1c4a24831e89` and
three spot pixels), and exercises the 8 MiB ROM cap. The RSS tier measures peak
RSS with a synthetic 8 MiB ROM resident and asserts three runs produce a
byte-identical framebuffer. If `/usr/bin/time` is unavailable, the RSS tier
prints `SKIP` and exits 77.
