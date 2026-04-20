# Rogue MUD Week-by-Week Plan

## Week 0: Foundation
- [x] Integrate `sand.zig` (Arena allocator).
- [x] Implement type-specific `ArrayList` patterns for `Room_t` and `BspNode`.
- [x] Set up basic module structure (`util`, `dungeon`, `net`).

## Week 1: BSP Dungeon Generation
- [x] Implement LCG Random Number Generator.
- [x] Implement Tile and Room data structures.
- [x] Implement Iterative BSP subdivision using an explicit stack.
- [x] Implement room carving and L-shaped corridor connection.
- [x] Verify generation with `dungeon_test.zig`.

## Week 2: Pathfinding (Future)
- [ ] Implement a Priority Queue (Min-Heap).
- [ ] Implement A* pathfinding algorithm for mobile entities.

## Week 3: Entities and Combat (Future)
- [ ] Implement Player and Monster entities.
- [ ] Implement turn-based combat and state persistence.

## Week 4: Polish (Future)
- [ ] Add ANSI color support.
- [ ] Implement "Look" command with procedural descriptions based on nearby tiles.
