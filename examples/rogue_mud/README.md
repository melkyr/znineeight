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
- **Verified on 32-bit Linux**: Stable build using `zig0` and `gcc`.

## Building and Running

### Build the MUD Server
```bash
./zig0 examples/rogue_mud/main.zig -o examples/rogue_mud/main.c -Iexamples/rogue_mud
```

### Run the MUD Server (requires GCC)
```bash
gcc -m32 examples/rogue_mud/main.c src/runtime/zig_runtime.c src/runtime/net_runtime.c -Isrc/include -Iexamples/rogue_mud -o rogue_mud
./rogue_mud
```
Wait for "Welcome to Rogue MUD!" to appear. You can play locally using WASD.

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

### Lifetime Violation Repro
```bash
./zig0 examples/rogue_mud/test/lifetime_repro.zig -o examples/rogue_mud/test/lifetime_repro.c
```

## Documentation
- [Design Document](docs/DESIGN.md)
- [Week-by-Week Plan](docs/WEEK_BY_WEEK.md)
- [Z98 Workarounds](docs/Z98_WORKAROUNDS.md)
- [Missing Features & Quirks](missing_features_rmud.md)
