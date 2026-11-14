// src/dungeon/tile.zig
pub const Tile = union(enum) {
    Wall,
    Floor,
    Door,
};
