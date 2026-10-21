# HPA\* — `std_hpa`

| | |
|---|---|
| **Modules** | `std_hpa` |
| **Layers** | `L5` — pure algorithm layer: hierarchical grid search over arena-owned maps |
| **Import (by path)** | `const std_hpa = @import("std_hpa.zig");` |
| **Consumes** | `std_pathfind` (grid, `jpsFind`), `std_heap` (A\* open set), `std_arena` (map and query scratch) |

`std_hpa` is not re-exported through `std`; import it by path.

## Module overview

`std_hpa` implements **HPA\*** (Hierarchical Pathfinding A\*, Botea, Müller, and
Schaeffer, "Near Optimal Hierarchical Path-Finding", *Journal of Game
Development* 1(1), 2004) on the same uniform-cost 8-connected grid as
`std_pathfind`. The grid is partitioned into clipped `cluster_w × cluster_h`
clusters. A caller builds an arena-owned **abstract map** once for a static
grid, then answers many start/goal queries by searching the much smaller
abstract graph and refining the result with cluster-local
`std_pathfind.jpsFind` calls.

The v1 abstraction is **exact**, not a heuristic approximation: every abstract
edge carries the true cluster-restricted shortest-path cost, so the refined
tile path has the same cost as a full-grid `jpsFind` path whenever a path
exists. Classic Botea **entrance-segment compression** (collapsing a whole
cluster-boundary segment into one node) is deferred; this version creates one
node per transition tile. The abstraction is therefore larger than the
textbook one, but simpler and still exact.

The movement model is inherited from `std_pathfind`: cardinal cost **10**,
diagonal cost **14**, strict **no-corner-cut** diagonals (both adjacent
cardinal cells must be walkable), and the octile heuristic
`10*max(dx,dy) + 4*min(dx,dy)`.

## Clipped-cluster model

Cluster ids are **row-major** over `cluster_cols = ceil(width/cluster_w)` and
`cluster_rows = ceil(height/cluster_h)`:

```
cluster_id = (y / cluster_h) * cluster_cols + (x / cluster_w)
```

The final row and column are **clipped** to the grid, so a cluster may be
smaller than `cluster_w × cluster_h`. `Cluster` records the concrete rectangle:

```zig
pub const Cluster = struct { x0: u32, y0: u32, w: u32, h: u32 };
```

`cluster_w == 0` or `cluster_h == 0` is a caller bug: `hpaBuild` panics. A
zero-sized grid builds an **empty** map (`clusters`, `nodes`, and `edges` are
empty; the `*_start` arrays still hold their single zero sentinel).

## Transition tiles and the exact edge set

A **transition tile** is a walkable tile with at least one legal 8-neighbour
move to a walkable tile in a **different** cluster. Diagonal moves obey the
strict no-corner-cut rule. One `AbstractNode` is created per transition tile:

```zig
pub const AbstractNode = struct { x: u32, y: u32, cluster: u32 };
```

Node ids are **cluster-major, then row-major** inside each cluster.
`node_start[c]..node_start[c+1]` is cluster `c`'s node range. A fully blocked
cluster contributes no nodes.

The edge set has two parts:

- **Cross-cluster adjacency.** Every legal move from a transition tile to a
  walkable tile in another cluster becomes a directed `AbstractEdge` with cost
  `10` (cardinal) or `14` (diagonal). Because the reverse move is also legal
  and the target is itself a transition tile, the opposite directed edge is
  present too.
- **Intra-cluster paths.** For every pair of transition nodes in the same
  cluster, `hpaBuild` runs `jpsFind` on a **compact cluster-local `Grid`** and
  records the exact cluster-restricted shortest-path cost as directed edges
  **both ways** when reachable. Unreachable pairs get no edge.

```zig
pub const AbstractEdge = struct { to: u32, cost: u32 };
```

Each node's adjacency range `edges[edge_start[n]..edge_start[n+1]]` is sorted
by `to` ascending. The compact local grid is a scratch copy; the cost is the
true path cost inside that cluster only, not a straight-line estimate.

The public map keeps only these persistent arrays:

```zig
pub const AbstractMap = struct {
    width: u32, height: u32, cluster_w: u32, cluster_h: u32,
    cluster_cols: u32, cluster_rows: u32,
    clusters: []Cluster, node_start: []u32,
    nodes: []AbstractNode, edge_start: []u32, edges: []AbstractEdge,
};
```

## Queries: temporary `S` / `G` nodes

`hpaFind` does not store the start and goal in the map. It adds two temporary
abstract nodes at query time:

- **`S`** connects to every transition node reachable from `start` inside
  `start`'s cluster (exact cluster-local `jpsFind` cost).
- Every transition node reachable **to** `goal` inside `goal`'s cluster
  connects to **`G`** with the exact cluster-local cost.
- When `start` and `goal` are in the same cluster, a direct `S -> G` edge is
  also added when that cluster-local path is reachable.

A\* then runs with the octile heuristic and the same M5 composite heap key
`(f << 32) | (~g)`, so equal `f` prefers the larger `g`. The chosen abstract
path is refined segment by segment: same-cluster segments are expanded with
cluster-local `jpsFind`, while a cross-cluster edge contributes its single
legal step. Duplicate boundary tiles are dropped. The returned tile path is
the full path, including both `start` and `goal`.

`hpaFind` errors are exactly `error.NoPath` and `error.OutOfMemory`.
Blocked/out-of-bounds endpoints, `start == goal` on a walkable tile, map/grid
mismatch, a zero-sized grid, and an unreachable goal follow `jpsFind`
semantics; a walkable `start == goal` returns `1`. `hpaBuild` errors are
exactly `error.OutOfMemory` (plus the zero-cluster-size panic above).

### `out` capacity and truncation

`out` is a **capacity in `u32` slots**, not a length, exactly as in
`std_pathfind`. `hpaFind` writes at most `out.len/2` complete `(x, y)` pairs in
forward order and ignores an odd trailing slot. It never writes past
`out.len`. The return value is always the **full path tile count**, so the
caller detects truncation with `2*return > out.len`; the written prefix is the
beginning of the path.

## Ownership, lifetime, and scratch

- `hpaBuild` allocates the map from the caller's arena. It uses temporary
  counting/scatter and cluster-local search scratch, then restores the arena's
  used bytes before returning, so **only the map allocations remain**. An
  allocation failure may consume build-arena scratch.
- The map is a **static snapshot** of the grid. Rebuild it after any
  `Grid.tiles` change; `hpaFind` does not detect tile mutation. It does
  validate `width`/`height`, the cluster geometry/counts implied by
  `cluster_w`/`cluster_h`, and the `node_start`/`edge_start` lengths, returning
  `error.NoPath` on a mismatch.
- `hpaFind`'s `arena` is **query scratch** and may be reset by the caller after
  each call. It must **not** be the arena that owns `m` if the caller resets it
  after a query.
- The grid must hold at least `width*height` tiles; that length is a caller
  precondition, as in `std_pathfind`.

## Determinism and exact cost

Build and query order are fixed: clusters row-major, nodes cluster-major then
row-major, adjacency ranges sorted by `to`, stable heap insertion, and
cluster-local `jpsFind`. Identical grids, cluster sizes, and queries therefore
produce identical maps and identical paths.

The exact-cost guarantee follows from the edge construction: cross-cluster
edges are single legal steps with their true cost, same-cluster edges are exact
restricted shortest paths, and refinement re-runs the same `jpsFind` searches
on the same clusters. The refined path is consequently a legal tile path whose
cost equals the abstract cost and equals the unrestricted `jpsFind` cost when
a path exists.

## Cluster-size tradeoff

Cluster size trades build time and memory against abstract-graph size:

- **Larger clusters** mean fewer clusters and fewer boundary crossings, but
  more transition nodes per cluster and a pairwise intra-cluster precompute
  whose worst case is `O(sum_c k_c^2 * A_c)` for `k_c` transition tiles and
  cluster area `A_c`. Memory grows with clusters, nodes, and edges.
- **Smaller clusters** make that precompute cheaper per cluster and reduce
  `k_c`, but create more clusters and a denser abstract graph, so queries see
  more boundary nodes and edges.

There is no universal best size; `8×8` to `16×16` is a reasonable starting
point for large maps. The abstraction remains exact at any size.

## When to prefer HPA\* over JPS

Use `std_hpa` when the grid is **static** and many queries will amortize the
build. HPA\* pays off on large maps where the abstract search is much smaller
than the full grid search.

Use plain `jpsFind` for a grid that changes between queries, for a single
query, or for small maps where the hierarchy adds more bookkeeping than it
saves. `jpsPlusFind` is another static-grid option when repeated queries want
O(1) directional jumps without building an abstract graph; HPA\* adds
hierarchical decomposition instead. Classic entrance-segment compression is a
future optimization and is **not** part of this exact-cost v1.

## Quick start

Build a `16×16` map with `8×8` clusters, then query it with a separate query
arena.

```zig
const std = @import("std");
const std_hpa = @import("std_hpa.zig");
const std_pathfind = @import("std_pathfind.zig");

pub fn main() !void {
    var tiles: [256]u8 = undefined;
    var i: usize = 0;
    while (i < tiles.len) : (i += 1) tiles[i] = 1;
    var y: u32 = 4;
    while (y < 12) : (y += 1) tiles[@intCast(usize, y) * 16 + 8] = 0;

    var grid = std_pathfind.Grid{ .tiles = tiles[0..], .width = 16, .height = 16 };

    var map_backing: [16384]u8 = undefined;
    var map_arena = std.arena.init(map_backing[0..]);
    const map = try std_hpa.hpaBuild(&map_arena, &grid, 8, 8);

    var query_backing: [16384]u8 = undefined;
    var query_arena = std.arena.init(query_backing[0..]);
    var out: [512]u32 = undefined;
    const count = try std_hpa.hpaFind(
        &query_arena, &map, &grid,
        std_pathfind.Point{ .x = 0, .y = 0 },
        std_pathfind.Point{ .x = 15, .y = 15 },
        out[0..],
    );
    std.io.printInt(@intCast(i32, count));
    std.arena.reset(&query_arena);
}
```

## API

### std_hpa.Cluster

**Purpose** — the concrete clipped rectangle of one cluster.

**Signature** — `pub const Cluster = struct { x0: u32, y0: u32, w: u32, h: u32 };`

**Parameters** (fields)
- `x0`, `y0` — grid coordinates of the cluster's upper-left tile.
- `w`, `h` — actual width and height after clipping to the grid.

**Returns** — a plain value type.

**Errors** — none.

**Gotchas** — the last row and column of clusters can be smaller than
`cluster_w`/`cluster_h`.

### std_hpa.AbstractNode

**Purpose** — one transition tile in the abstract graph.

**Signature** — `pub const AbstractNode = struct { x: u32, y: u32, cluster: u32 };`

**Parameters** (fields)
- `x`, `y` — grid tile coordinates.
- `cluster` — cluster id owning the node.

**Returns** — a plain value type.

**Errors** — none.

**Gotchas** — ids are positional in `AbstractMap.nodes`; do not reorder them.

### std_hpa.AbstractEdge

**Purpose** — one directed weighted adjacency.

**Signature** — `pub const AbstractEdge = struct { to: u32, cost: u32 };`

**Parameters** (fields)
- `to` — destination node id.
- `cost` — exact cost (`10` cardinal, `14` diagonal, or a longer same-cluster
  path cost).

**Returns** — a plain value type.

**Errors** — none.

**Gotchas** — ranges are sorted by `to`; do not assume they are unique across
different source nodes.

### std_hpa.AbstractMap

**Purpose** — the arena-owned, static abstract graph for one grid.

**Signature** — `pub const AbstractMap = struct { width: u32, height: u32, cluster_w: u32, cluster_h: u32, cluster_cols: u32, cluster_rows: u32, clusters: []Cluster, node_start: []u32, nodes: []AbstractNode, edge_start: []u32, edges: []AbstractEdge };`

**Parameters** (fields)
- `width`, `height` — grid dimensions the map was built for.
- `cluster_w`, `cluster_h` — requested cluster size.
- `cluster_cols`, `cluster_rows` — derived clipped cluster grid.
- `clusters` — one rectangle per cluster, row-major.
- `node_start` — `clusters.len + 1` prefix offsets.
- `nodes` — all transition nodes, cluster-major then row-major.
- `edge_start` — `nodes.len + 1` prefix offsets.
- `edges` — all directed edges.

**Returns** — a value type borrowing arena-owned slices.

**Errors** — none.

**Gotchas** — the map is static: rebuild it after any `Grid.tiles` change.
Keep the owning arena alive; reset only the separate query arena.

### std_hpa.hpaBuild

**Purpose** — partitions a grid and builds the exact abstract map.

**When to use** — once per static grid and cluster size, before repeated
queries. Use `std_pathfind` directly for one-off or changing grids.

**Signature** — `pub fn hpaBuild(arena: *std_arena.Arena, grid: *const std_pathfind.Grid, cluster_w: u32, cluster_h: u32) !AbstractMap`

**Parameters**
- `arena` — the map's owning arena. Scratch is released before return.
- `grid` — the static tile map; `tiles.len >= width*height` is a precondition.
- `cluster_w`, `cluster_h` — cluster dimensions; both must be non-zero.

**Returns** — the arena-owned `AbstractMap`. A zero-sized grid yields an empty
map.

**Errors**
- `error.OutOfMemory` — an arena allocation failed.
- Panics if `cluster_w == 0` or `cluster_h == 0`.

**Example**
```zig
const map = try std_hpa.hpaBuild(&map_arena, &grid, 8, 8);
```

**Gotchas** — the map never observes later tile changes. Do not reset the map
arena while the map is in use.

### std_hpa.hpaFind

**Purpose** — finds a full tile path from `start` to `goal` through the
abstract map, refining it with cluster-local JPS.

**When to use** — repeated queries on a static grid that already has a map.
For a single query or a changing grid use `std_pathfind.jpsFind`.

**Signature** — `pub fn hpaFind(arena: *std_arena.Arena, m: *const AbstractMap, grid: *const std_pathfind.Grid, start: std_pathfind.Point, goal: std_pathfind.Point, out: []u32) !u32`

**Parameters**
- `arena` — query scratch; may be reset by the caller after each call, and
  must not own `m` if reset.
- `m` — a map built for this grid and cluster configuration.
- `grid` — the current grid; it must still match the map's dimensions.
- `start`, `goal` — walkable endpoints.
- `out` — capacity for forward `(x, y)` pairs; an odd trailing slot is
  ignored.

**Returns** — the **full** path tile count, including start and goal. At most
`out.len/2` leading pairs are written; compare `2*return > out.len` to detect
truncation. A walkable `start == goal` returns `1`.

**Errors**
- `error.NoPath` — zero-sized grid, out-of-bounds or blocked endpoint,
  map/grid mismatch, or no route.
- `error.OutOfMemory` — query scratch allocation failed.

**Example**
```zig
const count = try std_hpa.hpaFind(
    &query_arena, &map, &grid, start, goal, out[0..],
);
```

**Gotchas** — duplicate boundary tiles are dropped from the output, but the
returned count is always the full tile count. The result is deterministic and
exact-cost, not an approximation.

## See also

- [`pathfind.md`](pathfind.md) — `std_pathfind`: the underlying JPS/JPS+ search.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
