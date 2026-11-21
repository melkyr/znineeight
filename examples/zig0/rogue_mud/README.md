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

## Building and Running

### Build the MUD Server
```bash
./zig0 examples/rogue_mud/main.zig -o examples/rogue_mud/main.c -Iexamples/rogue_mud
```

### Run the MUD Server (requires GCC)
```bash
# Standard build
gcc -m32 examples/rogue_mud/*.c -Isrc/include -Iexamples/rogue_mud -o rogue_mud

# Strict C89 compliance check
gcc -m32 examples/rogue_mud/*.c -Isrc/include -Iexamples/rogue_mud -std=c89 -pedantic -Werror -Wno-pointer-sign -Wno-format -Wno-long-long -o rogue_mud

./rogue_mud
```
Wait for "Welcome to Rogue MUD!" to appear. You can play locally using WASD.

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
