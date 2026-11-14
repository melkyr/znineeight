const scenario = @import("scenario.zig");
const sand_mod = @import("sand.zig");
const tile_mod = @import("tile.zig");
const room_mod = @import("room.zig");
const entity_mod = @import("entity.zig");

// C89 File I/O
extern "c" fn fopen(path: [*]const u8, mode: [*]const u8) ?*void;
extern "c" fn fwrite(ptr: *const void, size: usize, count: usize, stream: *void) usize;
extern "c" fn fread(ptr: *void, size: usize, count: usize, stream: *void) usize;
extern "c" fn fclose(stream: *void) i32;

pub const FileError = error {
    OpenFailed,
    WriteFailed,
    ReadFailed,
};

pub fn saveDungeon(arena: *sand_mod.Sand, dungeon: scenario.Dungeon_t, filename: []const u8) !void {
    const c_path = try sand_mod.sand_dupe_z(arena, filename);
    const file = fopen(c_path, "wb") orelse return error.OpenFailed;
    defer _ = fclose(file);

    var header = [2]u8{ dungeon.width, dungeon.height };
    if (fwrite(@ptrCast(*const void, &header), 1, 2, file) != 2) return error.WriteFailed;

    const tile_count = @intCast(usize, dungeon.width) * @intCast(usize, dungeon.height);
    if (fwrite(@ptrCast(*const void, dungeon.tiles.ptr), @sizeOf(tile_mod.Tile), tile_count, file) != tile_count) return error.WriteFailed;

    var counts = [2]usize{ @intCast(usize, dungeon.room_count), dungeon.entity_count };
    if (fwrite(@ptrCast(*const void, &counts), @sizeOf(usize), 2, file) != 2) return error.WriteFailed;

    if (fwrite(@ptrCast(*const void, dungeon.rooms.ptr), @sizeOf(room_mod.Room_t), @intCast(usize, dungeon.room_count), file) != @intCast(usize, dungeon.room_count)) return error.WriteFailed;
    if (fwrite(@ptrCast(*const void, dungeon.entities.ptr), @sizeOf(entity_mod.Entity), dungeon.entity_count, file) != dungeon.entity_count) return error.WriteFailed;
}

pub fn loadDungeon(arena: *sand_mod.Sand, out: *scenario.Dungeon_t, filename: []const u8) !void {
    const c_path = try sand_mod.sand_dupe_z(arena, filename);
    const file = fopen(c_path, "rb") orelse return error.OpenFailed;
    defer _ = fclose(file);

    var header = [2]u8{ @intCast(u8, 0), @intCast(u8, 0) };
    if (fread(@ptrCast(*void, &header), 1, 2, file) != 2) return error.ReadFailed;

    const width = header[0];
    const height = header[1];
    const tile_count = @intCast(usize, width) * @intCast(usize, height);

    const tiles_mem = try sand_mod.sand_alloc(arena, tile_count * @sizeOf(tile_mod.Tile), @alignOf(tile_mod.Tile));
    const tiles = @ptrCast([*]tile_mod.Tile, tiles_mem)[0..tile_count];
    if (fread(@ptrCast(*void, tiles.ptr), @sizeOf(tile_mod.Tile), tile_count, file) != tile_count) return error.ReadFailed;

    var counts = [2]usize{ @intCast(usize, 0), @intCast(usize, 0) };
    if (fread(@ptrCast(*void, &counts), @sizeOf(usize), 2, file) != 2) return error.ReadFailed;

    const room_count = counts[0];
    const entity_count = counts[1];

    const rooms_mem = try sand_mod.sand_alloc(arena, room_count * @sizeOf(room_mod.Room_t), @alignOf(room_mod.Room_t));
    const rooms = @ptrCast([*]room_mod.Room_t, rooms_mem)[0..room_count];
    if (fread(@ptrCast(*void, rooms.ptr), @sizeOf(room_mod.Room_t), room_count, file) != room_count) return error.ReadFailed;

    // Load entities into a reasonably sized buffer
    const max_entities = if (entity_count > @intCast(usize, 100)) entity_count else @intCast(usize, 100);
    const entities_mem = try sand_mod.sand_alloc(arena, max_entities * @sizeOf(entity_mod.Entity), @alignOf(entity_mod.Entity));
    const entities = @ptrCast([*]entity_mod.Entity, entities_mem)[0..max_entities];
    if (fread(@ptrCast(*void, entities.ptr), @sizeOf(entity_mod.Entity), entity_count, file) != entity_count) return error.ReadFailed;

    out.* = scenario.Dungeon_t{
        .width = width,
        .height = height,
        .tiles = tiles,
        .rooms = rooms,
        .room_count = @intCast(u8, room_count),
        .entities = entities,
        .entity_count = entity_count,
    };
}
