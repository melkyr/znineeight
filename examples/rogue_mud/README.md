# Rogue MUD (Z98 Stress Test)

An enhanced roguelike MUD server implemented in the Z98 subset of Zig. This project serves as a stress test for the `zig0` bootstrap compiler Milestone 11.

## Progress
- **Week 0 & 1 Complete:** ArrayList patterns, LCG RNG, and BSP Dungeon Generation are implemented and verified via smoke test.
- **Current State:** The project has successfully hit several compiler limits, which are documented in `missing_features_rmud.md`.

## Building and Testing

### Build the smoke test
```bash
./zig0 examples/rogue_mud/test/dungeon_test.zig -o examples/rogue_mud/test/dungeon_test.c
```

### Run the smoke test (requires GCC)
```bash
gcc -m32 examples/rogue_mud/test/dungeon_test.c src/runtime/zig_runtime.c -Isrc/runtime -o dungeon_test
./dungeon_test
```

## Documentation
- [Design Document](../../docs/ROGUE_MUD/DESIGN.md)
- [Week-by-Week Plan](../../docs/ROGUE_MUD/WEEK_BY_WEEK.md)
- [Z98 Workarounds](../../docs/ROGUE_MUD/Z98_WORKAROUNDS.md)
- [Missing Features & Quirks](missing_features_rmud.md)
