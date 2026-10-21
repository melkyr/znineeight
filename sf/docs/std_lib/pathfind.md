# Pathfinding — `std_pathfind`

| | |
|---|---|
| **Modules** | `std_pathfind` |
| **Layers** | `L5` — pure algorithm layer: 8-connected grid search over arena scratch |
| **Import (by path)** | `const std_pathfind = @import("std_pathfind.zig");` |
| **Consumes** | `std_heap` (open set), `std_arena` (scratch) |

`std_pathfind` is not re-exported through `std`; import it by path.

## Module overview

`std_pathfind` answers one question on a uniform-cost grid: what is the
shortest 8-connected tile path from `start` to `goal`? It provides two search
entry points over the same movement model:

- **`jpsFind`** — Jump Point Search for dynamic grids. It needs no
  preprocessing and reads the current `Grid.tiles` on every call.
- **`jpsPlusFind`** — preprocessed JPS+ for static grids. Build a `JpsPlus`
  once with `jpsPlusBuild`, then reuse it for many queries while the tiles do
  not change.

The movement model is fixed and shared by both paths. The grid is row-major
(`idx = y*width + x`) with `0` blocked and `1` walkable. Moves are 8-connected:
cardinal cost **10**, diagonal cost **14** (integer octile). A diagonal move is
legal only when **both** adjacent cardinal cells are walkable — strict
**no-corner-cut**, the movement model of Harabor & Grastien, "The JPS
Pathfinding System", SoCS 2012. The heuristic is
`10*max(dx,dy) + 4*min(dx,dy)`, consistent with those costs.

Both entry points use the existing `std_heap` min-heap with the composite
`i64` key `(f << 32) | (~g & 0xffffffff)`, so equal `f` prefers the larger `g`
(the node closer to the goal). The open set, `g`, parent, closed, and path
scratch are arena allocations; the module never frees individually and keeps
no hidden heap. The jump functions are iterative loops, not recursion, so the
stack depth is bounded.

### `out` capacity and truncation

`out` is a **capacity in `u32` slots**, not a length. Both functions write at
most `out.len/2` complete `(x, y)` pairs in forward order (start and goal
included) and ignore an odd trailing slot. They never write past `out.len`.
The return value is always the **full path tile count**, so the caller detects
truncation with `2*return > out.len`. If the capacity is smaller than the
path, the written prefix is the beginning of the path and the remaining tiles
are omitted.

### Errors and edge cases

Both functions return `error.NoPath` for a zero-sized grid, a start or goal
outside the grid, a blocked start or goal, or an unreachable goal. A walkable
`start == goal` returns `1` (and writes the single pair when `out.len >= 2`).
Arena allocation failure returns `error.OutOfMemory`. `jpsPlusBuild` can only
fail with `error.OutOfMemory`.

### JPS+ table, lifetime, and memory

`JpsPlus.dist` holds eight signed `i32` distances for every cell in direction
order **N, NE, E, SE, S, SW, W, NW**:

- **positive** — distance to the next static jump point in that direction;
- **negative** — distance to the wall (no jump point before the wall);
- **`0`** — blocked, or no legal move in that direction.

The table is a static snapshot of the grid. Rebuild the map whenever
`Grid.tiles` changes; `jpsPlusFind` does not detect tile mutation. It does
validate `map.width`/`map.height` and `map.dist.len == width*height*8` against
the grid and returns `error.NoPath` on a mismatch. The persistent table is
exactly **32 bytes per cell** (`8 * 4`); `jpsPlusBuild` additionally uses one
transient `N`-byte jump-point bitmap, so peak build memory is **33 bytes per
cell**, all from the caller's arena. The bitmap is not retained after build.

`jpsFind` remains the right choice when the grid changes between queries or
when a single query does not justify preprocessing. `jpsPlusFind` pays the
build once and then jumps in O(1) per direction using the table.

## Quick start

Search an all-walkable 8×8 grid with plain JPS, then build a JPS+ map and run
the same query.

```zig
const std = @import("std");
const std_pathfind = @import("std_pathfind.zig");

pub fn main() !void {
    var tiles: [64]u8 = undefined;
    var i: usize = 0;
    while (i < tiles.len) : (i += 1) tiles[i] = 1;

    var grid = std_pathfind.Grid{
        .tiles = tiles[0..],
        .width = 8,
        .height = 8,
    };
    var out: [64]u32 = undefined;
    var backing: [8192]u8 = undefined;
    var arena = std.arena.init(backing[0..]);

    const start = std_pathfind.Point{ .x = 0, .y = 0 };
    const goal = std_pathfind.Point{ .x = 7, .y = 7 };

    const tiles_found = try std_pathfind.jpsFind(
        &arena, &grid, start, goal, out[0..],
    );
    std.io.printInt(@intCast(i32, tiles_found));

    var map = try std_pathfind.jpsPlusBuild(&arena, &grid);
    const plus_tiles = try std_pathfind.jpsPlusFind(
        &arena, &map, &grid, start, goal, out[0..],
    );
    std.io.printInt(@intCast(i32, plus_tiles));
}
```

Both calls return `8` on this open grid: 7 diagonal moves plus the start tile,
and the tile count includes both endpoints.

## API

### `std_pathfind`

#### `Point`

**Purpose** — a grid coordinate.

**Signature** — `pub const Point = struct { x: u32, y: u32 };`

**Parameters** (fields)
- `x` — column, `0` at the left edge.
- `y` — row, `0` at the top edge.

**Returns** — a plain value type.

**Errors** — none.

**Gotchas** — coordinates are unsigned; out-of-grid values are rejected by the
search functions with `error.NoPath`, not wrapped.

#### `Grid`

**Purpose** — a caller-owned row-major tile map.

**Signature** — `pub const Grid = struct { tiles: []u8, width: u32, height: u32 };`

**Parameters** (fields)
- `tiles` — row-major tile slice, `0` blocked and `1` walkable. It must hold
  `width*height` entries; this length is a caller precondition and is not
  validated.
- `width` — number of columns.
- `height` — number of rows.

**Returns** — a value type borrowing `tiles`; it does not copy or own them.

**Errors** — none.

**Gotchas** — keep `tiles` alive for the whole call. For `jpsPlusFind`, the
`Grid` must still describe the same tiles used to build the map.

#### `JpsPlus`

**Purpose** — a preprocessed JPS+ distance table for one static grid.

**Signature** — `pub const JpsPlus = struct { dist: []i32, width: u32, height: u32 };`

**Parameters** (fields)
- `dist` — `width*height*8` signed distances in direction order
  `N, NE, E, SE, S, SW, W, NW`; positive = next jump point, negative = wall,
  `0` = blocked/no move.
- `width` — grid width the table was built for.
- `height` — grid height the table was built for.

**Returns** — a value type borrowing an arena-owned slice.

**Errors** — none.

**Gotchas** — the map is static: rebuild it after any `Grid.tiles` change.
Passing a map built for different dimensions or with a `dist.len` that is not
`width*height*8` makes `jpsPlusFind` return `error.NoPath`.

#### `jpsFind`

**Purpose** — runs Jump Point Search on the current grid and returns the full
tile count of the shortest path.

**When to use** — the default pathfinder for a grid that changes between
queries. Use `jpsPlusBuild`/`jpsPlusFind` when the same static grid answers
many queries.

**Signature** — `pub fn jpsFind(arena: *std_arena.Arena, grid: *const Grid, start: Point, goal: Point, out: []u32) !u32`

**Parameters**
- `arena` — caller arena; scratch is allocated from it and never freed.
- `grid` — the current tile map.
- `start` — walkable start coordinate.
- `goal` — walkable goal coordinate.
- `out` — capacity for forward `(x, y)` pairs; an odd trailing slot is
  ignored.

**Returns** — the **full** path tile count, including start and goal. At most
`out.len/2` leading pairs are written; compare `2*return > out.len` to detect
truncation. `start == goal` returns `1`.

**Errors**
- `error.NoPath` — zero-sized grid, out-of-bounds or blocked start/goal, or
  no route.
- `error.OutOfMemory` — arena allocation failed.

**Example**
```zig
var out: [64]u32 = undefined;
const count = try std_pathfind.jpsFind(
    &arena, &grid, start, goal, out[0..],
);
// truncation: the full count is 2*count slots; compare with out.len
```

**Gotchas** — the path is materialized tile-by-tile in one extra arena buffer
of `count*8` bytes, on top of the search arrays. A large reachable path can
therefore return `error.OutOfMemory`; size the arena for grid plus path
scratch. `out` is not a length check: a too-small buffer truncates rather than
failing.

#### `jpsPlusBuild`

**Purpose** — preprocesses a static grid into the eight-direction JPS+
distance table.

**When to use** — before reusing one grid for many queries. Do not use it for
a grid that changes per query; call `jpsFind` instead.

**Signature** — `pub fn jpsPlusBuild(arena: *std_arena.Arena, grid: *const Grid) !JpsPlus`

**Parameters**
- `arena` — caller arena; the table and the transient build bitmap are
  allocated from it and never freed.
- `grid` — the static tile map to preprocess.

**Returns** — a `JpsPlus` with `dist.len == width*height*8` and the grid
dimensions. An empty grid returns an empty table with the given dimensions.

**Errors**
- `error.OutOfMemory` — arena allocation failed.

**Example**
```zig
var map = try std_pathfind.jpsPlusBuild(&arena, &grid);
// reuse `map` for many queries while grid.tiles is unchanged
```

**Gotchas** — preprocessing is O(8N). Persistent memory is 32 bytes per cell
plus one transient N-byte bitmap (33 bytes per cell peak). The map never
observes later tile edits.

#### `jpsPlusFind`

**Purpose** — runs the preprocessed JPS+ search and returns the full tile
count of the shortest path.

**When to use** — repeated queries on an unchanged grid. For a one-off query
or a changing grid, `jpsFind` avoids the build cost.

**Signature** — `pub fn jpsPlusFind(arena: *std_arena.Arena, map: *const JpsPlus, grid: *const Grid, start: Point, goal: Point, out: []u32) !u32`

**Parameters**
- `arena` — caller arena for the search scratch; never freed.
- `map` — table built from this grid by `jpsPlusBuild`.
- `grid` — current tile map; it must still match the map.
- `start` — walkable start coordinate.
- `goal` — walkable goal coordinate.
- `out` — capacity for forward `(x, y)` pairs; an odd trailing slot is
  ignored.

**Returns** — same contract as `jpsFind`: the full path tile count, at most
`out.len/2` leading pairs written, `start == goal` returns `1`.

**Errors**
- `error.NoPath` — zero-sized grid, map/grid dimension mismatch,
  `map.dist.len != width*height*8`, out-of-bounds or blocked start/goal, or no
  route.
- `error.OutOfMemory` — arena allocation failed.

**Example**
```zig
const count = try std_pathfind.jpsPlusFind(
    &arena, &map, &grid, start, goal, out[0..],
);
```

**Gotchas** — the map is a static snapshot; tile edits without a rebuild
produce stale results. `jpsPlusFind` validates dimensions and `dist.len` only;
it does not compare tiles against the build-time grid.

## Performance

Measurements are report-only (no timing gate). Two 256×256 maps, start
`(0,0)` → goal `(255,255)`, built with `gcc -m32 -std=c89 -O0`; Z98 timings
use `std_time.highRes`, the C89 A* baseline uses `gettimeofday`.

Plain JPS per query versus a C89 A* reference:

| map | Z98 JPS | C89 A* |
| --- | ---: | ---: |
| 22% obstacles | 1.84 s | 0.55 s |
| fully open | 0.69 s | 0.01 s |

JPS+ build once, then 200 queries (per query):

| map | JPS+ | `jpsFind` |
| --- | ---: | ---: |
| 22% obstacles | 6.06 ms | 8.87 ms |
| fully open | 0.127 ms | 3.37 ms |

JPS+ is faster than plain JPS on both measured maps (about 1.46× on the 22%
map and 26× open), but **A* remains faster than both** in this O0
microbenchmark. Do not expect the blueprint's claimed 5× speedup on these
maps: on an open grid the octile heuristic is exact and A* expands essentially
the optimal corridor, while JPS pays for cardinal component scans (plain) or
table lookups (plus). Use the numbers to choose a search, not as a guarantee.

## Gates and pins

| gate | command | pin |
|---|---|---|
| basic fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_pathfind_basic_xmod` | byte-exact stdout, exit 0 |
| plus fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_pathfind_plus_xmod` | JPS+ cost equals `jpsFind` on 61 grids plus query/truncation/sign checks |
| crosscheck | `scripts/stdlib/run_crosscheck.sh <zig1> std_pathfind` | Z98 == C89 A* reference on `hand.in` and `random64.in` |
| full std gate | `scripts/stdlib/verify_stdlib.sh <zig1>` | `STDLIB GATE OK` (fixtures + all crosscheck modules) |

## See also

- [`collections.md`](collections.md) — `std_heap`, the open set used by both
  searches.
- [`memory.md`](memory.md) — `std.arena`, the ownership model for all scratch.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
