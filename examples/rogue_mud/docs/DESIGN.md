# Rogue MUD Design Document

## Overview
Rogue MUD is an enhanced version of the original `mud_server` example, designed to stress-test the `zig0` bootstrap compiler (Milestone 11). It introduces procedural dungeon generation using Binary Space Partitioning (BSP).

## Architecture
The project is organized into several modules to test cross-module visibility and compilation:

- **Scenario (Dungeon):** Handles the generation of the tile map and rooms.
- **RNG:** A simple LCG random number generator.
- **Sand (Arena):** Memory management using a chunked arena allocator.
- **Net (Server):** Platform-independent socket server.

## Data Structures

### Tile
A tagged union representing different map features:
- `Wall`
- `Floor`
- `Door`

### Dungeon_t
The main world structure containing:
- `width`, `height`
- `tiles`: A 1D slice of `Tile`s.
- `rooms`: A slice of `Room_t` structures.

### BspNode
A recursive tree structure used for dungeon subdivision.

## Memory Strategy
Rogue MUD uses a dual-arena system:
1. **Permanent Arena:** Used for the long-lived world state (dungeon, rooms).
2. **Transient Arena:** (Planned) Used for per-tick calculations like pathfinding or command processing.

Currently, it uses a single large arena for the initialization phase.
