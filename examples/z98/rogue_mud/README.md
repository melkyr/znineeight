# Rogue MUD (Z98 Stress Test)

An enhanced roguelike MUD server implemented in the Z98 subset of Zig. This project serves as a stress test for the `zig0` bootstrap compiler Milestone 11.

## Features
- **Multi-player Networking**: Supports up to 5 remote players via TCP/Telnet on port 4000.
- **Dual-mode UI**: Local player uses ANSI colors; remote players receive plain ASCII with basic Telnet negotiation.
- **BSP Dungeon Generation**: Procedurally generated levels.
- **A* Pathfinding**: NPCs use pathfinding to hunt players.
- **Persistence**: Save and load dungeon state (local-only).
- **Z98 Idiomatic Syntax**: Demonstrates `switch` expressions, labeled loops, payload captures, and anonymous initializers.

## Progress
- **Milestone 11 Stress Test Complete**: Integrated networking, multi-player mechanics, and refactored core logic for Z98 idiomatic constructs.
- **Verified on 32-bit Linux & Windows 98**: Stable build using `zig0` with GCC (Linux) and OpenWatcom/MSVC 6.0 (Windows).
- **Console API Support**: Uses platform-native console functions for flicker-free double-buffered rendering.
- **Stack Safe**: Optimized for limited-stack environments by using static storage for large buffers.

## Building with zig1

The compiler is self-hosted. A seed build (`scripts/seed/build_from_seed.sh`)
puts `lib/` next to the `zig1` binary, and the compiler searches `<exe-dir>/lib`
automatically. When the binary lives elsewhere, pass the library directory with
`-I lib` (relative to the current directory). On Windows never use `-I /lib`:
that is the drive root, and the compiler reports `cannot find std`.

`-o <dir>` selects the output directory and is required; without it the
compiler emits nothing. Create the directory first.

### Linux

```sh
mkdir -p out
/path/to/zig1_5_clean -o out main.zig
sh out/build_target.sh
./out/prog
```

### Windows 9x / NT

Run this from the example directory in a Command Prompt. `-osw` selects the
Windows target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw -o out main.zig
cd out
build_owc_crt.bat
prog.exe
```

`build_owc_crt.bat` (OpenWatcom, static CRT) is the verified path;
`build_target_crt.bat` is the MSVC 6 equivalent (run `VCVARS32.BAT` first);
`build_owc_nocrt.bat` / `build_target_nocrt.bat` are the no-CRT alternates; and
`build_mingw_crt.bat` is the MinGW fallback (needs `msvcrt.dll`). The output is
`out\prog.exe`.

Start the server with `./out/prog` (Linux) or `out\prog.exe` (Windows) and wait
for "Welcome to Rogue MUD!" to appear. You can play locally using WASD.

Sources: `main.zig` (entry) imports `ui.zig`; pass only `main.zig` — the
compiler resolves the rest.

### Configuration and Multiplayer
The game mode is controlled by a compile-time flag in `examples/rogue_mud/main.zig`:

```zig
const MULTIPLAYER_ENABLED: bool = false;
```

- **Single-player Mode (`false`)**: Uses local ASCII UI. Keyboard input is via standard `getchar()`.
- **Multiplayer Mode (`true`)**: Starts a Telnet server on port 4000. Supports up to 5 remote players. Local input remains active but the UI is optimized for ANSI telnet clients.

### Connecting via Telnet
From another terminal:
```bash
telnet localhost 4000
```
or
```bash
nc localhost 4000
```

## Documentation
- [Design Document](docs/DESIGN.md)
- [Z98 Workarounds](docs/Z98_WORKAROUNDS.md)
- [Missing Features & Quirks](missing_features_rmud.md)

## Z98 Milestone 11 Stress Test Report

This project serves as a real-world validation of the `zig0` compiler. Below is a summary of feature stability at this scale.

### Stable & Utilized Features
- **Switch Expressions**: Used extensively for tile rendering, direction mapping, and command processing.
- **Labeled Loops**: Critical for escaping nested loops in BSP generation (`bsp_loop`).
- **Payload Captures**: Successfully utilized in `if` and `while` statements for optional unwrapping (e.g., pathfinding results).
- **Anonymous Initializers**: Used for compact entity and struct creation.
- **Control Flow Lifting**: The `ControlFlowLifter` robustly handles `if`/`switch` as expressions, even in complex nested contexts.
- **Cross-module Symbol Resolution**: Deterministic mangling and stable hashing allow this 10+ module project to link correctly.

### Unstable or Unusable Features
- **Naked Tags in Binary Ops**: Using `.Tag == .Other` can trigger compiler aborts. *Workaround*: Always use `switch`.
- **Mutable Array Sizes**: Using `var` or `pub var` for array sizes (e.g., `[MAX]u8`) is rejected. *Workaround*: Use constant integer literals or `const` (if simple).
- **Struct Methods**: Methods inside structs remain unsupported in `zig0`. *Workaround*: Use prefixed standalone functions.
- **Exhaustive Switch Inference**: The compiler often requires a mandatory `else` prong in `switch` expressions even if all enum tags are covered.
- **Nested Aggregate Coercion**: Complex nested anonymous initializers can occasionally fail type resolution if context is too deep.
- **Lifetime Analyzer (False Positives)**: Returning slices from struct-owned many-item pointers can trigger spurious "dangling pointer" warnings. *Workaround*: Use out-parameters.

### Lifetime Violation Repro
```bash
./zig0 examples/rogue_mud/test/lifetime_repro.zig -o examples/rogue_mud/test/lifetime_repro.c
```

## Documentation
- [Design Document](docs/DESIGN.md)
- [Week-by-Week Plan](docs/WEEK_BY_WEEK.md)
- [Z98 Workarounds](docs/Z98_WORKAROUNDS.md)
- [Missing Features & Quirks](missing_features_rmud.md)
