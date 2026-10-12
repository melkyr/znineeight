const sand_mod = @import("sand.zig");
const point_mod = @import("point.zig");
const priority_queue = @import("priority_queue.zig");
const tile_mod = @import("tile.zig");
const scenario = @import("scenario.zig");

fn heuristic(a: point_mod.Point, b: point_mod.Point) u16 {
    const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
    const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
    return @intCast(u16, dx + dy);
}

pub fn findPath(
    arena: *sand_mod.Sand,
    dungeon: scenario.Dungeon_t,
    start: point_mod.Point,
    goal: point_mod.Point
) ?[]point_mod.Point {
    const width_idx = @intCast(usize, dungeon.width);
    const height_idx = @intCast(usize, dungeon.height);
    const total_tiles = width_idx * height_idx;

    var open_set = PriorityQueue_init(arena, 64) catch return null;

    // came_from: index -> Point
    const came_from_mem = sand_mod.sand_alloc(arena, total_tiles * @sizeOf(point_mod.Point), @alignOf(point_mod.Point)) catch return null;
    const came_from = @ptrCast([*]point_mod.Point, came_from_mem);

    // g_score: index -> u16
    const g_score_mem = sand_mod.sand_alloc(arena, total_tiles * @sizeOf(u16), @alignOf(u16)) catch return null;
    const g_score = @ptrCast([*]u16, g_score_mem);

    // visited: index -> bool
    const visited_mem = sand_mod.sand_alloc(arena, total_tiles * @sizeOf(bool), @alignOf(bool)) catch return null;
    const visited = @ptrCast([*]bool, visited_mem);

    var i: usize = 0;
    while (i < total_tiles) : (i += 1) {
        g_score[i] = 0xFFFF;
        visited[i] = false;
    }

    const start_idx = @intCast(usize, start.y) * width_idx + @intCast(usize, start.x);
    g_score[start_idx] = 0;

    const start_ptr_mem = sand_mod.sand_alloc(arena, @sizeOf(point_mod.Point), @alignOf(point_mod.Point)) catch return null;
    const start_ptr = @ptrCast(*point_mod.Point, start_ptr_mem);
    start_ptr.* = start;
    priority_queue.PriorityQueue_push(&open_set, start_ptr, heuristic(start, goal)) catch return null;

    while (open_set.len > 0) {
        const current_ptr_opt = priority_queue.PriorityQueue_pop(&open_set);
        if (current_ptr_opt) |current_ptr| {
            const current = current_ptr.*;

            if (point_mod.Point_eq(current, goal)) {
            return reconstructPath(arena, came_from, current, start, dungeon.width);
        }

        const current_idx = @intCast(usize, current.y) * width_idx + @intCast(usize, current.x);
        visited[current_idx] = true;

        // Neighbors
        var nb_idx: u8 = 0;
        while (nb_idx < 4) : (nb_idx += 1) {
            var nb: point_mod.Point = undefined;
            if (nb_idx == 0) { // Up
                if (current.y == 0) continue;
                nb = point_mod.Point{ .x = current.x, .y = current.y - 1 };
            } else if (nb_idx == 1) { // Right
                if (current.x >= dungeon.width - 1) continue;
                nb = point_mod.Point{ .x = current.x + 1, .y = current.y };
            } else if (nb_idx == 2) { // Down
                if (current.y >= dungeon.height - 1) continue;
                nb = point_mod.Point{ .x = current.x, .y = current.y + 1 };
            } else { // Left
                if (current.x == 0) continue;
                nb = point_mod.Point{ .x = current.x - 1, .y = current.y };
            }

            const idx = @intCast(usize, nb.y) * width_idx + @intCast(usize, nb.x);

            // Z98 Constraint: Naked tags in binary ops (e.g. dungeon.tiles[idx] == .Wall)
            // trigger zig0 abort. Using switch is the recommended idiomatic workaround
            // for Milestone 11.
            var is_wall = false;
            switch (dungeon.tiles[idx]) {
                .Wall => is_wall = true,
                else => {},
            }
            if (is_wall) continue;

            const tentative_g = g_score[current_idx] + 1;
                if (tentative_g < g_score[idx]) {
                    came_from[idx] = current;
                    g_score[idx] = tentative_g;
                    const f = tentative_g + heuristic(nb, goal);

                    const nb_ptr_mem = sand_mod.sand_alloc(arena, @sizeOf(point_mod.Point), @alignOf(point_mod.Point)) catch return null;
                    const nb_ptr = @ptrCast(*point_mod.Point, nb_ptr_mem);
                    nb_ptr.* = nb;
                    priority_queue.PriorityQueue_push(&open_set, nb_ptr, f) catch return null;
                }
            }
        } else {
            break;
        }
    }

    return null;
}

fn reconstructPath(
    arena: *sand_mod.Sand,
    came_from: [*]point_mod.Point,
    current_in: point_mod.Point,
    start: point_mod.Point,
    width: u8
) ?[]point_mod.Point {
    var count: usize = 0;
    var curr = current_in;
    const width_idx = @intCast(usize, width);

    while (!point_mod.Point_eq(curr, start)) {
        count += 1;
        const idx = @intCast(usize, curr.y) * width_idx + @intCast(usize, curr.x);
        curr = came_from[idx];
    }

    const path_mem = sand_mod.sand_alloc(arena, count * @sizeOf(point_mod.Point), @alignOf(point_mod.Point)) catch return null;
    const path = @ptrCast([*]point_mod.Point, path_mem);

    curr = current_in;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        path[count - 1 - i] = curr;
        const idx = @intCast(usize, curr.y) * width_idx + @intCast(usize, curr.x);
        curr = came_from[idx];
    }

    return path[0..count];
}

fn PriorityQueue_init(arena: *sand_mod.Sand, initial_capacity: usize) !priority_queue.PriorityQueue {
    return priority_queue.PriorityQueue_init(arena, initial_capacity);
}
