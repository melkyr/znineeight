// std_hpa.zig — Z98 std lib L5: HPA* hierarchical pathfinding.
//
// Contract (spec §6.9): build allocates map from the caller arena; hpaFind
// uses its arena as query scratch. Imports L5 `std_pathfind` (M5), L4
// `std_heap`, and L1 `std_arena` only.
//
//   Cluster      { x0, y0, w, h }
//   AbstractNode { x, y, cluster }
//   AbstractEdge { to, cost }
//   AbstractMap  { width, height, cluster_w, cluster_h, cluster_cols,
//                  cluster_rows, clusters, node_start, nodes, edge_start,
//                  edges }
//
// The v1 abstraction is exact. A transition tile is a walkable tile with at
// least one legal cross-cluster 8-neighbour (diagonal strict no-corner-cut).
// One node exists per transition tile, cluster-major then row-major. Cross-
// cluster adjacencies become directed edges cost 10/14. Every reachable
// same-cluster node pair gets exact cluster-restricted `jpsFind` costs in both
// directions. Edges are sorted by `to`.
//
// Build uses temporary scratch and restores the arena's used bytes before
// returning, so only the map remains. hpaFind's arena is query scratch.
// A* uses the octile heuristic and the M5 composite key `(f<<32)|(~g)`.
// The abstract path is refined with cluster-local `jpsFind` paths; duplicate
// boundary tiles are dropped. `out` follows M5: at most out.len/2 pairs, odd
// trailing slot untouched, full tile count returned.

const arena_mod = @import("std_arena.zig");
const heap_mod = @import("std_heap.zig");
const pf = @import("std_pathfind.zig");

pub const Cluster = struct {
    x0: u32,
    y0: u32,
    w: u32,
    h: u32,
};

pub const AbstractNode = struct {
    x: u32,
    y: u32,
    cluster: u32,
};

pub const AbstractEdge = struct {
    to: u32,
    cost: u32,
};

pub const AbstractMap = struct {
    width: u32,
    height: u32,
    cluster_w: u32,
    cluster_h: u32,
    cluster_cols: u32,
    cluster_rows: u32,
    clusters: []Cluster,
    node_start: []u32,
    nodes: []AbstractNode,
    edge_start: []u32,
    edges: []AbstractEdge,
};

const INF: u32 = 4294967295;
const NONE: u32 = 4294967295;

const DIR_DX = [_]i32{ 0, 1, 1, 1, 0, -1, -1, -1 };
const DIR_DY = [_]i32{ -1, -1, 0, 1, 1, 1, 0, -1 };

fn absI32(v: i32) i32 {
    if (v < 0) return -v;
    return v;
}

fn divCeil(a: u32, b: u32) u32 {
    var au: u64 = @intCast(u64, a);
    var bu: u64 = @intCast(u64, b);
    var q: u64 = (au + bu - 1) / bu;
    return @intCast(u32, q);
}

fn allocU32(ar: *arena_mod.Arena, count: usize) ![]u32 {
    var raw = try arena_mod.alloc(ar, count * @sizeOf(u32));
    return @ptrCast([*]u32, raw)[0..count];
}

fn allocU8(ar: *arena_mod.Arena, count: usize) ![]u8 {
    var raw = try arena_mod.alloc(ar, count);
    return @ptrCast([*]u8, raw)[0..count];
}

fn allocClusters(ar: *arena_mod.Arena, count: usize) ![]Cluster {
    var raw = try arena_mod.alloc(ar, count * @sizeOf(Cluster));
    return @ptrCast([*]Cluster, raw)[0..count];
}

fn allocNodes(ar: *arena_mod.Arena, count: usize) ![]AbstractNode {
    var raw = try arena_mod.alloc(ar, count * @sizeOf(AbstractNode));
    return @ptrCast([*]AbstractNode, raw)[0..count];
}

fn allocEdges(ar: *arena_mod.Arena, count: usize) ![]AbstractEdge {
    var raw = try arena_mod.alloc(ar, count * @sizeOf(AbstractEdge));
    return @ptrCast([*]AbstractEdge, raw)[0..count];
}

fn zeroU32(s: []u32) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) s[i] = 0;
}

fn fillU32(s: []u32, v: u32) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) s[i] = v;
}

fn idxOf(grid: *const pf.Grid, x: u32, y: u32) usize {
    return @intCast(usize, y) * @intCast(usize, grid.width) + @intCast(usize, x);
}

fn walkable(grid: *const pf.Grid, x: i32, y: i32) bool {
    if (x < 0 or y < 0) return false;
    if (x >= @intCast(i32, grid.width) or y >= @intCast(i32, grid.height)) return false;
    return grid.tiles[idxOf(grid, @intCast(u32, x), @intCast(u32, y))] == 1;
}

fn stepLegal(grid: *const pf.Grid, x: i32, y: i32, nx: i32, ny: i32) bool {
    if (!walkable(grid, nx, ny)) return false;
    var dx: i32 = nx - x;
    var dy: i32 = ny - y;
    if (dx < -1 or dx > 1 or dy < -1 or dy > 1) return false;
    if (dx == 0 and dy == 0) return false;
    if (dx != 0 and dy != 0) {
        if (!walkable(grid, nx, y) or !walkable(grid, x, ny)) return false;
    }
    return true;
}

fn clusterIndex(cols: u32, cw: u32, ch: u32, x: u32, y: u32) u32 {
    return (y / ch) * cols + x / cw;
}

fn isTransition(grid: *const pf.Grid, cols: u32, cw: u32, ch: u32, x: u32, y: u32) bool {
    var ci: usize = idxOf(grid, x, y);
    if (grid.tiles[ci] != 1) return false;
    var cid: u32 = clusterIndex(cols, cw, ch, x, y);
    var d: usize = 0;
    while (d < 8) : (d += 1) {
        var nx: i32 = @intCast(i32, x) + DIR_DX[d];
        var ny: i32 = @intCast(i32, y) + DIR_DY[d];
        if (!stepLegal(grid, @intCast(i32, x), @intCast(i32, y), nx, ny)) continue;
        var ncid: u32 = clusterIndex(cols, cw, ch, @intCast(u32, nx), @intCast(u32, ny));
        if (ncid != cid) return true;
    }
    return false;
}

fn clusterGeom(cols: u32, cw: u32, ch: u32, width: u32, height: u32, cid: u32) Cluster {
    var cx: u32 = cid % cols;
    var cy: u32 = cid / cols;
    var x0: u32 = cx * cw;
    var y0: u32 = cy * ch;
    var w: u32 = width - x0;
    if (w > cw) w = cw;
    var h: u32 = height - y0;
    if (h > ch) h = ch;
    return Cluster{ .x0 = x0, .y0 = y0, .w = w, .h = h };
}

fn fillClusters(clusters: []Cluster, cols: u32, cw: u32, ch: u32, width: u32, height: u32) void {
    var c: usize = 0;
    while (c < clusters.len) : (c += 1) {
        clusters[c] = clusterGeom(cols, cw, ch, width, height, @intCast(u32, c));
    }
}

fn makeLocalGrid(ar: *arena_mod.Arena, grid: *const pf.Grid, c: Cluster) !pf.Grid {
    var n: usize = @intCast(usize, c.w) * @intCast(usize, c.h);
    var tiles = try allocU8(ar, n);
    var y: u32 = 0;
    while (y < c.h) : (y += 1) {
        var x: u32 = 0;
        while (x < c.w) : (x += 1) {
            var si: usize = idxOf(grid, c.x0 + x, c.y0 + y);
            var di: usize = @intCast(usize, y) * @intCast(usize, c.w) + @intCast(usize, x);
            tiles[di] = grid.tiles[si];
        }
    }
    return pf.Grid{ .tiles = tiles, .width = c.w, .height = c.h };
}

const FindResult = struct {
    ok: bool,
    count: u32,
    cost: u32,
};

fn pathCost(out: []const u32, count: u32) u32 {
    var total: u32 = 0;
    var i: u32 = 1;
    while (i < count) : (i += 1) {
        var px: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2]);
        var py: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2 + 1]);
        var cx: i32 = @intCast(i32, out[@intCast(usize, i) * 2]);
        var cy: i32 = @intCast(i32, out[@intCast(usize, i) * 2 + 1]);
        if (absI32(cx - px) + absI32(cy - py) == 2) {
            total += 14;
        } else {
            total += 10;
        }
    }
    return total;
}

fn localFind(ar: *arena_mod.Arena, lg: *const pf.Grid, fx: u32, fy: u32, gx: u32, gy: u32, out: []u32) !FindResult {
    var n = pf.jpsFind(ar, lg, pf.Point{ .x = fx, .y = fy }, pf.Point{ .x = gx, .y = gy }, out) catch |e| {
        if (e == error.NoPath) return FindResult{ .ok = false, .count = 0, .cost = 0 };
        return error.OutOfMemory;
    };
    if (@intCast(usize, n) * 2 > out.len) {
        return FindResult{ .ok = false, .count = 0, .cost = 0 };
    }
    return FindResult{ .ok = true, .count = n, .cost = pathCost(out, n) };
}

const BuildInfo = struct {
    cols: u32,
    rows: u32,
    cluster_count: u32,
    node_count: u32,
    edge_count: u32,
};

fn countBuild(ar: *arena_mod.Arena, grid: *const pf.Grid, cw: u32, ch: u32) !BuildInfo {
    var cols: u32 = divCeil(grid.width, cw);
    var rows: u32 = divCeil(grid.height, ch);
    var cc64: u64 = @intCast(u64, cols) * @intCast(u64, rows);
    var cc: u32 = @intCast(u32, cc64);
    var n: usize = @intCast(usize, grid.width) * @intCast(usize, grid.height);

    var counts = try allocU32(ar, @intCast(usize, cc));
    zeroU32(counts);
    var y: u32 = 0;
    while (y < grid.height) : (y += 1) {
        var x: u32 = 0;
        while (x < grid.width) : (x += 1) {
            if (isTransition(grid, cols, cw, ch, x, y)) {
                var cid: u32 = clusterIndex(cols, cw, ch, x, y);
                counts[@intCast(usize, cid)] += 1;
            }
        }
    }

    var ns = try allocU32(ar, @intCast(usize, cc) + 1);
    ns[0] = 0;
    var c: u32 = 0;
    while (c < cc) : (c += 1) {
        ns[@intCast(usize, c) + 1] = ns[@intCast(usize, c)] + counts[@intCast(usize, c)];
    }
    var node_count: u32 = ns[@intCast(usize, cc)];

    var tile_node = try allocU32(ar, n);
    fillU32(tile_node, NONE);
    var node_pos = try allocU32(ar, @intCast(usize, node_count));
    zeroU32(counts);
    y = 0;
    while (y < grid.height) : (y += 1) {
        var x2: u32 = 0;
        while (x2 < grid.width) : (x2 += 1) {
            if (!isTransition(grid, cols, cw, ch, x2, y)) continue;
            var cid: u32 = clusterIndex(cols, cw, ch, x2, y);
            var id: u32 = ns[@intCast(usize, cid)] + counts[@intCast(usize, cid)];
            counts[@intCast(usize, cid)] += 1;
            var ii: usize = idxOf(grid, x2, y);
            tile_node[ii] = id;
            node_pos[@intCast(usize, id)] = @intCast(u32, ii);
        }
    }

    var cross: u32 = 0;
    y = 0;
    while (y < grid.height) : (y += 1) {
        var x3: u32 = 0;
        while (x3 < grid.width) : (x3 += 1) {
            var ii: usize = idxOf(grid, x3, y);
            if (tile_node[ii] == NONE) continue;
            var cid: u32 = clusterIndex(cols, cw, ch, x3, y);
            var d: usize = 0;
            while (d < 8) : (d += 1) {
                var nx: i32 = @intCast(i32, x3) + DIR_DX[d];
                var ny: i32 = @intCast(i32, y) + DIR_DY[d];
                if (!stepLegal(grid, @intCast(i32, x3), @intCast(i32, y), nx, ny)) continue;
                var ncid: u32 = clusterIndex(cols, cw, ch, @intCast(u32, nx), @intCast(u32, ny));
                if (ncid != cid) cross += 1;
            }
        }
    }

    var intra: u32 = 0;
    c = 0;
    while (c < cc) : (c += 1) {
        var start: u32 = ns[@intCast(usize, c)];
        var end: u32 = ns[@intCast(usize, c) + 1];
        if (end - start < 2) continue;
        var geom: Cluster = clusterGeom(cols, cw, ch, grid.width, grid.height, c);
        var lg = try makeLocalGrid(ar, grid, geom);
        var area: usize = @intCast(usize, geom.w) * @intCast(usize, geom.h);
        var out = try allocU32(ar, area * 2);
        var i: u32 = start;
        while (i < end) : (i += 1) {
            var j: u32 = i + 1;
            while (j < end) : (j += 1) {
                var ip: u32 = node_pos[@intCast(usize, i)];
                var jp: u32 = node_pos[@intCast(usize, j)];
                var ifx: u32 = ip % grid.width - geom.x0;
                var ify: u32 = ip / grid.width - geom.y0;
                var jgx: u32 = jp % grid.width - geom.x0;
                var jgy: u32 = jp / grid.width - geom.y0;
                var r = try localFind(ar, &lg, ifx, ify, jgx, jgy, out);
                if (r.ok) intra += 2;
            }
        }
    }

    return BuildInfo{
        .cols = cols,
        .rows = rows,
        .cluster_count = cc,
        .node_count = node_count,
        .edge_count = cross + intra,
    };
}

fn prefixNodeStart(counts: []u32, ns: []u32) void {
    ns[0] = 0;
    var c: usize = 0;
    while (c < counts.len) : (c += 1) {
        ns[c + 1] = ns[c] + counts[c];
    }
}

fn assignNodeIds(ar: *arena_mod.Arena, grid: *const pf.Grid, cols: u32, cw: u32, ch: u32, cc: u32, ns: []u32, nodes: []AbstractNode) ![]u32 {
    var n: usize = @intCast(usize, grid.width) * @intCast(usize, grid.height);
    var tile_node = try allocU32(ar, n);
    fillU32(tile_node, NONE);
    var cursor = try allocU32(ar, @intCast(usize, cc));
    zeroU32(cursor);
    var y: u32 = 0;
    while (y < grid.height) : (y += 1) {
        var x: u32 = 0;
        while (x < grid.width) : (x += 1) {
            if (!isTransition(grid, cols, cw, ch, x, y)) continue;
            var cid: u32 = clusterIndex(cols, cw, ch, x, y);
            var id: u32 = ns[@intCast(usize, cid)] + cursor[@intCast(usize, cid)];
            cursor[@intCast(usize, cid)] += 1;
            tile_node[idxOf(grid, x, y)] = id;
            nodes[@intCast(usize, id)] = AbstractNode{ .x = x, .y = y, .cluster = cid };
        }
    }
    return tile_node;
}

fn addTempEdge(edges: []AbstractEdge, from: []u32, at: *u32, src: u32, to: u32, cost: u32) void {
    var k: usize = @intCast(usize, at.*);
    if (k >= edges.len) return;
    edges[k] = AbstractEdge{ .to = to, .cost = cost };
    from[k] = src;
    at.* += 1;
}

fn sortNodeEdges(edges: []AbstractEdge, start: u32, end: u32) void {
    var i: u32 = start + 1;
    while (i < end) : (i += 1) {
        var j: u32 = i;
        while (j > start) : (j -= 1) {
            var a: usize = @intCast(usize, j - 1);
            var b: usize = @intCast(usize, j);
            if (edges[a].to <= edges[b].to) break;
            var t = edges[a];
            edges[a] = edges[b];
            edges[b] = t;
        }
    }
}

pub fn hpaBuild(arena: *arena_mod.Arena, grid: *const pf.Grid, cluster_w: u32, cluster_h: u32) !AbstractMap {
    if (cluster_w == 0 or cluster_h == 0) @panic("hpaBuild: zero cluster size");
    var base: usize = arena.used;
    var info = try countBuild(arena, grid, cluster_w, cluster_h);
    arena.used = base;

    var cluster_slice = try allocClusters(arena, @intCast(usize, info.cluster_count));
    var node_start = try allocU32(arena, @intCast(usize, info.cluster_count) + 1);
    var nodes = try allocNodes(arena, @intCast(usize, info.node_count));
    var edge_start = try allocU32(arena, @intCast(usize, info.node_count) + 1);
    var edges = try allocEdges(arena, @intCast(usize, info.edge_count));
    var perm_end: usize = arena.used;

    fillClusters(cluster_slice, info.cols, cluster_w, cluster_h, grid.width, grid.height);

    var node_counts = try allocU32(arena, @intCast(usize, info.cluster_count));
    zeroU32(node_counts);
    var y: u32 = 0;
    while (y < grid.height) : (y += 1) {
        var x: u32 = 0;
        while (x < grid.width) : (x += 1) {
            if (isTransition(grid, info.cols, cluster_w, cluster_h, x, y)) {
                var cid: u32 = clusterIndex(info.cols, cluster_w, cluster_h, x, y);
                node_counts[@intCast(usize, cid)] += 1;
            }
        }
    }
    prefixNodeStart(node_counts, node_start);

    var tile_node = try assignNodeIds(arena, grid, info.cols, cluster_w, cluster_h, info.cluster_count, node_start, nodes);

    var temp_edges = try allocEdges(arena, @intCast(usize, info.edge_count));
    var temp_from = try allocU32(arena, @intCast(usize, info.edge_count));
    var written: u32 = 0;

    y = 0;
    while (y < grid.height) : (y += 1) {
        var x2: u32 = 0;
        while (x2 < grid.width) : (x2 += 1) {
            var ii: usize = idxOf(grid, x2, y);
            var src: u32 = tile_node[ii];
            if (src == NONE) continue;
            var cid: u32 = clusterIndex(info.cols, cluster_w, cluster_h, x2, y);
            var d: usize = 0;
            while (d < 8) : (d += 1) {
                var nx: i32 = @intCast(i32, x2) + DIR_DX[d];
                var ny: i32 = @intCast(i32, y) + DIR_DY[d];
                if (!stepLegal(grid, @intCast(i32, x2), @intCast(i32, y), nx, ny)) continue;
                var ncid: u32 = clusterIndex(info.cols, cluster_w, cluster_h, @intCast(u32, nx), @intCast(u32, ny));
                if (ncid == cid) continue;
                var to: u32 = tile_node[idxOf(grid, @intCast(u32, nx), @intCast(u32, ny))];
                var cost: u32 = 10;
                if (DIR_DX[d] != 0 and DIR_DY[d] != 0) cost = 14;
                addTempEdge(temp_edges, temp_from, &written, src, to, cost);
            }
        }
    }

    var c: u32 = 0;
    while (c < info.cluster_count) : (c += 1) {
        var start: u32 = node_start[@intCast(usize, c)];
        var end: u32 = node_start[@intCast(usize, c) + 1];
        if (end - start < 2) continue;
        var geom: Cluster = clusterGeom(info.cols, cluster_w, cluster_h, grid.width, grid.height, c);
        var lg = try makeLocalGrid(arena, grid, geom);
        var area: usize = @intCast(usize, geom.w) * @intCast(usize, geom.h);
        var out = try allocU32(arena, area * 2);
        var i: u32 = start;
        while (i < end) : (i += 1) {
            var j: u32 = i + 1;
            while (j < end) : (j += 1) {
                var ni = nodes[@intCast(usize, i)];
                var nj = nodes[@intCast(usize, j)];
                var r = try localFind(arena, &lg, ni.x - geom.x0, ni.y - geom.y0, nj.x - geom.x0, nj.y - geom.y0, out);
                if (!r.ok) continue;
                addTempEdge(temp_edges, temp_from, &written, i, j, r.cost);
                addTempEdge(temp_edges, temp_from, &written, j, i, r.cost);
            }
        }
    }

    var ecounts = try allocU32(arena, @intCast(usize, info.node_count));
    zeroU32(ecounts);
    var k: u32 = 0;
    while (k < written) : (k += 1) {
        var src: u32 = temp_from[@intCast(usize, k)];
        ecounts[@intCast(usize, src)] += 1;
    }
    prefixNodeStart(ecounts, edge_start);

    var cursor = try allocU32(arena, @intCast(usize, info.node_count));
    var nidx: u32 = 0;
    while (nidx < info.node_count) : (nidx += 1) {
        cursor[@intCast(usize, nidx)] = edge_start[@intCast(usize, nidx)];
    }
    k = 0;
    while (k < written) : (k += 1) {
        var src: u32 = temp_from[@intCast(usize, k)];
        var at: u32 = cursor[@intCast(usize, src)];
        edges[@intCast(usize, at)] = temp_edges[@intCast(usize, k)];
        cursor[@intCast(usize, src)] = at + 1;
    }
    nidx = 0;
    while (nidx < info.node_count) : (nidx += 1) {
        sortNodeEdges(edges, edge_start[@intCast(usize, nidx)], edge_start[@intCast(usize, nidx) + 1]);
    }

    arena.used = perm_end;
    return AbstractMap{
        .width = grid.width,
        .height = grid.height,
        .cluster_w = cluster_w,
        .cluster_h = cluster_h,
        .cluster_cols = info.cols,
        .cluster_rows = info.rows,
        .clusters = cluster_slice,
        .node_start = node_start,
        .nodes = nodes,
        .edge_start = edge_start,
        .edges = edges,
    };
}

const Sink = struct {
    out: []u32,
    cap: usize,
    count: u32,
    has_last: bool,
    last_x: u32,
    last_y: u32,
};

fn sinkPush(p: *Sink, x: u32, y: u32) void {
    if (p.has_last and p.last_x == x and p.last_y == y) return;
    if (@intCast(usize, p.count) < p.cap) {
        p.out[@intCast(usize, p.count) * 2] = x;
        p.out[@intCast(usize, p.count) * 2 + 1] = y;
    }
    p.count += 1;
    p.has_last = true;
    p.last_x = x;
    p.last_y = y;
}

fn heuristicTo(start: pf.Point, goal: pf.Point, x: u32, y: u32) u32 {
    var dx: i32 = absI32(@intCast(i32, goal.x) - @intCast(i32, x));
    var dy: i32 = absI32(@intCast(i32, goal.y) - @intCast(i32, y));
    var mx: i32 = dx;
    if (dy > mx) mx = dy;
    var mn: i32 = dx;
    if (dy < mn) mn = dy;
    return @intCast(u32, 10 * mx + 4 * mn);
}

fn makeKey(f: u32, g: u32) i64 {
    var low: u32 = ~g;
    return (@intCast(i64, f) << 32) | @intCast(i64, low);
}

fn indexPtr(idx: usize) *void {
    return @intToPtr(*void, idx);
}

const SearchCtx = struct {
    m: *const AbstractMap,
    start: pf.Point,
    goal: pf.Point,
    total: u32,
    real_count: u32,
    g: []u32,
    parent: []u32,
    closed: []u8,
    heap: heap_mod.Heap,
    s_edges: []AbstractEdge,
    goal_cost: []u32,
};

fn searchHeuristic(ctx: *SearchCtx, id: u32) u32 {
    if (id == ctx.real_count) return heuristicTo(ctx.start, ctx.goal, ctx.start.x, ctx.start.y);
    if (id == ctx.real_count + 1) return heuristicTo(ctx.start, ctx.goal, ctx.goal.x, ctx.goal.y);
    var n = ctx.m.nodes[@intCast(usize, id)];
    return heuristicTo(ctx.start, ctx.goal, n.x, n.y);
}

fn pushSearch(ctx: *SearchCtx, id: u32, f: u32, g: u32) !void {
    var item = heap_mod.HeapItem{ .key = makeKey(f, g), .value = indexPtr(@intCast(usize, id)) };
    try heap_mod.heapPush(&ctx.heap, item);
}



fn relaxFrom(ctx: *SearchCtx, from: u32, to: u32, cost: u32) !void {
    if (ctx.closed[@intCast(usize, to)] != 0) return;
    var base: u32 = ctx.g[@intCast(usize, from)];
    if (base == INF) return;
    var ng: u32 = base + cost;
    if (ng >= ctx.g[@intCast(usize, to)]) return;
    ctx.g[@intCast(usize, to)] = ng;
    ctx.parent[@intCast(usize, to)] = from;
    var h: u32 = searchHeuristic(ctx, to);
    try pushSearch(ctx, to, ng + h, ng);
}

fn expandSearch(ctx: *SearchCtx, id: u32) !void {
    if (id == ctx.real_count) {
        var i: usize = 0;
        while (i < ctx.s_edges.len) : (i += 1) {
            try relaxFrom(ctx, id, ctx.s_edges[i].to, ctx.s_edges[i].cost);
        }
        return;
    }
    if (id == ctx.real_count + 1) return;
    var e: u32 = ctx.m.edge_start[@intCast(usize, id)];
    var ee: u32 = ctx.m.edge_start[@intCast(usize, id) + 1];
    while (e < ee) : (e += 1) {
        var ed = ctx.m.edges[@intCast(usize, e)];
        try relaxFrom(ctx, id, ed.to, ed.cost);
    }
    var gc: u32 = ctx.goal_cost[@intCast(usize, id)];
    if (gc != INF) try relaxFrom(ctx, id, ctx.real_count + 1, gc);
}

fn reverseU32(s: []u32) void {
    if (s.len < 2) return;
    var i: usize = 0;
    var j: usize = s.len - 1;
    while (i < j) {
        var t = s[i];
        s[i] = s[j];
        s[j] = t;
        i += 1;
        j -= 1;
    }
}

fn refineSegment(ar: *arena_mod.Arena, grid: *const pf.Grid, m: *const AbstractMap, a: u32, b: u32, start: pf.Point, goal: pf.Point, sink: *Sink) !void {
    var real_count: u32 = @intCast(u32, m.nodes.len);
    var a_real: bool = a < real_count;
    var b_real: bool = b < real_count;
    if (a_real and b_real) {
        var na = m.nodes[@intCast(usize, a)];
        var nb = m.nodes[@intCast(usize, b)];
        if (na.cluster != nb.cluster) {
            sinkPush(sink, nb.x, nb.y);
            return;
        }
    }

    var cid: u32 = 0;
    if (a_real) {
        cid = m.nodes[@intCast(usize, a)].cluster;
    } else if (b_real) {
        cid = m.nodes[@intCast(usize, b)].cluster;
    } else {
        var cid_a: u32 = clusterIndex(m.cluster_cols, m.cluster_w, m.cluster_h, start.x, start.y);
        var cid_b: u32 = clusterIndex(m.cluster_cols, m.cluster_w, m.cluster_h, goal.x, goal.y);
        if (cid_a != cid_b) return error.NoPath;
        cid = cid_a;
    }

    var geom: Cluster = m.clusters[@intCast(usize, cid)];
    var lg = try makeLocalGrid(ar, grid, geom);
    var area: usize = @intCast(usize, geom.w) * @intCast(usize, geom.h);
    var path = try allocU32(ar, area * 2);

    var fx: u32 = 0;
    var fy: u32 = 0;
    if (a_real) {
        var na = m.nodes[@intCast(usize, a)];
        fx = na.x - geom.x0;
        fy = na.y - geom.y0;
    } else if (a == real_count) {
        fx = start.x - geom.x0;
        fy = start.y - geom.y0;
    } else {
        fx = goal.x - geom.x0;
        fy = goal.y - geom.y0;
    }
    var gx: u32 = 0;
    var gy: u32 = 0;
    if (b_real) {
        var nb = m.nodes[@intCast(usize, b)];
        gx = nb.x - geom.x0;
        gy = nb.y - geom.y0;
    } else if (b == real_count) {
        gx = start.x - geom.x0;
        gy = start.y - geom.y0;
    } else {
        gx = goal.x - geom.x0;
        gy = goal.y - geom.y0;
    }

    var r = try localFind(ar, &lg, fx, fy, gx, gy, path);
    if (!r.ok) return error.NoPath;
    var i: u32 = 0;
    while (i < r.count) : (i += 1) {
        var lx: u32 = path[@intCast(usize, i) * 2];
        var ly: u32 = path[@intCast(usize, i) * 2 + 1];
        sinkPush(sink, lx + geom.x0, ly + geom.y0);
    }
}

pub fn hpaFind(arena: *arena_mod.Arena, m: *const AbstractMap, grid: *const pf.Grid, start: pf.Point, goal: pf.Point, out: []u32) !u32 {
    if (m.width != grid.width or m.height != grid.height) return error.NoPath;
    if (m.cluster_w == 0 or m.cluster_h == 0) return error.NoPath;
    var expect_cols: u32 = divCeil(grid.width, m.cluster_w);
    var expect_rows: u32 = divCeil(grid.height, m.cluster_h);
    if (m.cluster_cols != expect_cols or m.cluster_rows != expect_rows) return error.NoPath;
    var expect_cc64: u64 = @intCast(u64, expect_cols) * @intCast(u64, expect_rows);
    if (@intCast(u64, m.clusters.len) != expect_cc64) return error.NoPath;
    if (m.clusters.len + 1 != m.node_start.len) return error.NoPath;
    if (m.nodes.len + 1 != m.edge_start.len) return error.NoPath;
    if (grid.width == 0 or grid.height == 0) return error.NoPath;
    if (start.x >= grid.width or start.y >= grid.height) return error.NoPath;
    if (goal.x >= grid.width or goal.y >= grid.height) return error.NoPath;
    if (grid.tiles[idxOf(grid, start.x, start.y)] != 1) return error.NoPath;
    if (grid.tiles[idxOf(grid, goal.x, goal.y)] != 1) return error.NoPath;
    if (start.x == goal.x and start.y == goal.y) {
        if (out.len >= 2) {
            out[0] = start.x;
            out[1] = start.y;
        }
        return 1;
    }

    var real_count: u32 = @intCast(u32, m.nodes.len);
    var total: u32 = real_count + 2;
    var s_id: u32 = real_count;
    var g_id: u32 = real_count + 1;
    var g = try allocU32(arena, @intCast(usize, total));
    var parent = try allocU32(arena, @intCast(usize, total));
    var closed = try allocU8(arena, @intCast(usize, total));
    fillU32(g, INF);
    fillU32(parent, NONE);
    var z: usize = 0;
    while (z < closed.len) : (z += 1) closed[z] = 0;

    var start_cid: u32 = clusterIndex(m.cluster_cols, m.cluster_w, m.cluster_h, start.x, start.y);
    var goal_cid: u32 = clusterIndex(m.cluster_cols, m.cluster_w, m.cluster_h, goal.x, goal.y);
    var ss: u32 = m.node_start[@intCast(usize, start_cid)];
    var se: u32 = m.node_start[@intCast(usize, start_cid) + 1];
    var gs: u32 = m.node_start[@intCast(usize, goal_cid)];
    var ge: u32 = m.node_start[@intCast(usize, goal_cid) + 1];

    var s_edges = try allocEdges(arena, @intCast(usize, se - ss) + 1);
    var s_len: u32 = 0;
    if (se > ss) {
        var sgeom: Cluster = m.clusters[@intCast(usize, start_cid)];
        var slg = try makeLocalGrid(arena, grid, sgeom);
        var sarea: usize = @intCast(usize, sgeom.w) * @intCast(usize, sgeom.h);
        var sout = try allocU32(arena, sarea * 2);
        var id: u32 = ss;
        while (id < se) : (id += 1) {
            var n = m.nodes[@intCast(usize, id)];
            var r = try localFind(arena, &slg, start.x - sgeom.x0, start.y - sgeom.y0, n.x - sgeom.x0, n.y - sgeom.y0, sout);
            if (r.ok) {
                s_edges[@intCast(usize, s_len)] = AbstractEdge{ .to = id, .cost = r.cost };
                s_len += 1;
            }
        }
    }
    if (start_cid == goal_cid) {
        var sgeom2: Cluster = m.clusters[@intCast(usize, start_cid)];
        var slg2 = try makeLocalGrid(arena, grid, sgeom2);
        var sarea2: usize = @intCast(usize, sgeom2.w) * @intCast(usize, sgeom2.h);
        var sout2 = try allocU32(arena, sarea2 * 2);
        var r2 = try localFind(arena, &slg2, start.x - sgeom2.x0, start.y - sgeom2.y0, goal.x - sgeom2.x0, goal.y - sgeom2.y0, sout2);
        if (r2.ok) {
            s_edges[@intCast(usize, s_len)] = AbstractEdge{ .to = g_id, .cost = r2.cost };
            s_len += 1;
        }
    }

    var goal_cost = try allocU32(arena, @intCast(usize, real_count));
    fillU32(goal_cost, INF);
    if (ge > gs) {
        var ggeom: Cluster = m.clusters[@intCast(usize, goal_cid)];
        var glg = try makeLocalGrid(arena, grid, ggeom);
        var garea: usize = @intCast(usize, ggeom.w) * @intCast(usize, ggeom.h);
        var gout = try allocU32(arena, garea * 2);
        var id2: u32 = gs;
        while (id2 < ge) : (id2 += 1) {
            var n2 = m.nodes[@intCast(usize, id2)];
            var r3 = try localFind(arena, &glg, n2.x - ggeom.x0, n2.y - ggeom.y0, goal.x - ggeom.x0, goal.y - ggeom.y0, gout);
            if (r3.ok) goal_cost[@intCast(usize, id2)] = r3.cost;
        }
    }

    var ctx = SearchCtx{
        .m = m,
        .start = start,
        .goal = goal,
        .total = total,
        .real_count = real_count,
        .g = g,
        .parent = parent,
        .closed = closed,
        .heap = try heap_mod.heapInit(arena, 16),
        .s_edges = s_edges[0..@intCast(usize, s_len)],
        .goal_cost = goal_cost,
    };
    g[@intCast(usize, s_id)] = 0;
    try pushSearch(&ctx, s_id, searchHeuristic(&ctx, s_id), 0);

    var found: bool = false;
    while (true) {
        var item_opt = heap_mod.heapPop(&ctx.heap);
        if (item_opt) |item| {
            var id3: u32 = @intCast(u32, @ptrToInt(item.value));
            if (closed[@intCast(usize, id3)] != 0) continue;
            closed[@intCast(usize, id3)] = 1;
            if (id3 == g_id) {
                found = true;
                break;
            }
            try expandSearch(&ctx, id3);
        } else {
            break;
        }
    }
    if (!found) return error.NoPath;

    var seq = try allocU32(arena, @intCast(usize, total));
    var cur: u32 = g_id;
    var len: u32 = 0;
    while (true) {
        if (len >= total) return error.NoPath;
        seq[@intCast(usize, len)] = cur;
        len += 1;
        if (cur == s_id) break;
        var p: u32 = parent[@intCast(usize, cur)];
        if (p == NONE) return error.NoPath;
        cur = p;
    }
    var seq_slice = seq[0..@intCast(usize, len)];
    reverseU32(seq_slice);

    var sink = Sink{ .out = out, .cap = out.len / 2, .count = 0, .has_last = false, .last_x = 0, .last_y = 0 };
    var si: usize = 0;
    while (si + 1 < seq_slice.len) : (si += 1) {
        try refineSegment(arena, grid, m, seq_slice[si], seq_slice[si + 1], start, goal, &sink);
    }
    return sink.count;
}
