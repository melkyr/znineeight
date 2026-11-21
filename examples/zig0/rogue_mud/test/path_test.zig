const sand_mod = @import("../lib/sand.zig");
const point_mod = @import("../lib/point.zig");
const pathfinding = @import("../lib/pathfinding.zig");
const scenario = @import("../lib/scenario.zig");
const tile_mod = @import("../lib/tile.zig");
const room_mod = @import("../lib/room.zig");
const entity_mod = @import("../lib/entity.zig");
const std = @import("../../mud_server/std.zig");

pub fn main() !void {
    var buffer: [65536]u8 = undefined;
    var arena = sand_mod.sand_init(buffer[0..], true);

    const width = @intCast(u8, 10);
    const height = @intCast(u8, 10);
    const tile_count = @intCast(usize, width) * @intCast(usize, height);
    const tile_mem = try sand_mod.sand_alloc(&arena, tile_count * @sizeOf(tile_mod.Tile), @alignOf(tile_mod.Tile));
    const tiles = @ptrCast([*]tile_mod.Tile, tile_mem)[0..tile_count];

    var i: usize = 0;
    while (i < tile_count) : (i += 1) {
        tiles[i] = .Floor;
    }

    var empty_rooms: []room_mod.Room_t = undefined;
    var empty_entities: []entity_mod.Entity = undefined;

    const dungeon = scenario.Dungeon_t{
        .width = width,
        .height = height,
        .tiles = tiles,
        .rooms = empty_rooms,
        .room_count = @intCast(u8, 0),
        .entities = empty_entities,
        .entity_count = @intCast(usize, 0),
    };

    const start = point_mod.Point{ .x = @intCast(u8, 0), .y = @intCast(u8, 0) };
    const goal = point_mod.Point{ .x = @intCast(u8, 2), .y = @intCast(u8, 2) };

    std.debug.print("Finding path...\n", .{});
    const path_opt = pathfinding.findPath(&arena, dungeon, start, goal);

    if (path_opt) |path| {
        std.debug.print("Path found! Length: {}\n", .{path.len});
        if (path.len == 0) {
            std.debug.print("Error: path length is 0\n", .{});
            return;
        }
    } else {
        std.debug.print("No path found!\n", .{});
        return;
    }

    std.debug.print("Pathfinding test passed!\n", .{});
}
