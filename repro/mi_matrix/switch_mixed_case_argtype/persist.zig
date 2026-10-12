pub const Sand = struct { pos: usize, end: usize };
pub const Dungeon_t = struct { width: u8, height: u8 };

pub fn saveDungeon(arena: *Sand, dungeon: Dungeon_t, filename: []const u8) !void {
    _ = arena;
    _ = dungeon;
    _ = filename;
    return;
}
