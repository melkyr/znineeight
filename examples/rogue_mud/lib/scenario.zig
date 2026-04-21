// src/dungeon/scenario.zig (Module name renamed to avoid conflict with Dungeon struct name)
const sand_mod = @import("sand.zig");
const array_list = @import("array_list.zig");
const rng_mod = @import("rng.zig");
const tile_mod = @import("tile.zig");
const room_mod = @import("room.zig");
const bsp_mod = @import("bsp.zig");

pub const Dungeon_t = struct {
    width: u8,
    height: u8,
    tiles: []tile_mod.Tile,
    rooms: []room_mod.Room_t,
    room_count: u8,
};

pub fn generateDungeon(
    arena: *sand_mod.Sand,
    random: *rng_mod.Random,
    width: u8,
    height: u8
) !Dungeon_t {
    // 1. Allocate tile buffer (1D)
    const tile_count = @intCast(usize, width) * @intCast(usize, height);
    const tile_mem = try sand_mod.sand_alloc(arena,
        tile_count * @sizeOf(tile_mod.Tile),
        @alignOf(tile_mod.Tile));
    const tiles_ptr = @ptrCast([*]tile_mod.Tile, tile_mem);
    const tiles = tiles_ptr[0..tile_count];

    // 2. Initialize to walls
    var i: usize = 0;
    while (i < tile_count) : (i += 1) {
        tiles[i] = .Wall;
    }

    // 3. Prepare room list
    var rooms_list = try room_mod.ArrayListRoom_init(arena, 32);

    // 4. BSP stack
    var stack = try bsp_mod.ArrayListBspNodePtr_init(arena, 64);

    // 5. Create root node on arena
    const root_mem = try sand_mod.sand_alloc(arena,
        @sizeOf(bsp_mod.BspNode),
        @alignOf(bsp_mod.BspNode));
    const root = @ptrCast(*bsp_mod.BspNode, root_mem);
    root.* = bsp_mod.BspNode{
        .x = @intCast(u8, 0), .y = @intCast(u8, 0), .w = width, .h = height,
        .left = null, .right = null, .room = null,
    };

    try bsp_mod.ArrayListBspNodePtr_append(&stack, root);

    // 6. Main BSP loop
    while (stack.len > 0) {
        const node_opt = bsp_mod.ArrayListBspNodePtr_pop(&stack);
        if (node_opt == null) break;
        var node: *bsp_mod.BspNode = undefined;
        if (node_opt) |n| { node = n; }

        const too_small = node.w < 8 or node.h < 8;
        const random_carve = rng_mod.Random_range(random, 0, 100) < 30;

        if (too_small or random_carve) {
            try carveRoom(node, tiles, width, height, random, &rooms_list);
        } else {
            try splitNode(node, arena, random, &stack);
        }
    }

    var rooms_slice: []room_mod.Room_t = undefined;
    room_mod.ArrayListRoom_toSlice(&rooms_list, &rooms_slice);

    // 7. Connect rooms
    try connectRooms(tiles, width, height, rooms_slice, random);

    return Dungeon_t{
        .width = width,
        .height = height,
        .tiles = tiles,
        .rooms = rooms_slice,
        .room_count = @intCast(u8, rooms_slice.len),
    };
}

fn carveRoom(
    node: *bsp_mod.BspNode,
    tiles: []tile_mod.Tile,
    dungeon_width: u8,
    dungeon_height: u8,
    random: *rng_mod.Random,
    rooms_list: *room_mod.ArrayListRoom
) !void {
    if (node.w < 5 or node.h < 5) return;

    const max_w = node.w - 2;
    const max_h = node.h - 2;

    const room_w = rng_mod.Random_range(random, 4, max_w);
    const room_h = rng_mod.Random_range(random, 4, max_h);
    const room_x = node.x + rng_mod.Random_range(random, 1, node.w - room_w - 1);
    const room_y = node.y + rng_mod.Random_range(random, 1, node.h - room_h - 1);

    var dy: u8 = 0;
    while (dy < room_h) : (dy += 1) {
        var dx: u8 = 0;
        while (dx < room_w) : (dx += 1) {
            const tx = room_x + dx;
            const ty = room_y + dy;
            const idx = @intCast(usize, ty) * @intCast(usize, dungeon_width) + @intCast(usize, tx);
            tiles[idx] = .Floor;
        }
    }

    const room = room_mod.Room_t{
        .x = room_x, .y = room_y, .w = room_w, .h = room_h,
    };
    try room_mod.ArrayListRoom_append(rooms_list, room);
    const rooms_slice = rooms_list.items[0..rooms_list.len];
    node.room = &rooms_slice[rooms_list.len - 1];
}

fn splitNode(
    node: *bsp_mod.BspNode,
    arena: *sand_mod.Sand,
    random: *rng_mod.Random,
    stack: *bsp_mod.ArrayListBspNodePtr
) !void {
    const split_vert = if (node.w > node.h) true
                      else if (node.h > node.w) false
                      else rng_mod.Random_range(random, 0, 1) == 0;

    if (split_vert) {
        const min_split = @intCast(u8, 4);
        if (node.w <= min_split * 2) {
            // Cannot split vertically, try horizontal or carve
            // For simplicity in this version, just carve if split fails
            return;
        }
        const max_split = node.w - min_split;
        const split_x = node.x + rng_mod.Random_range(random, min_split, max_split);

        const left_mem = try sand_mod.sand_alloc(arena, @sizeOf(bsp_mod.BspNode), @alignOf(bsp_mod.BspNode));
        const right_mem = try sand_mod.sand_alloc(arena, @sizeOf(bsp_mod.BspNode), @alignOf(bsp_mod.BspNode));

        const left = @ptrCast(*bsp_mod.BspNode, left_mem);
        const right = @ptrCast(*bsp_mod.BspNode, right_mem);

        left.* = bsp_mod.BspNode{
            .x = node.x, .y = node.y,
            .w = split_x - node.x, .h = node.h,
            .left = null, .right = null, .room = null,
        };
        right.* = bsp_mod.BspNode{
            .x = split_x, .y = node.y,
            .w = node.x + node.w - split_x, .h = node.h,
            .left = null, .right = null, .room = null,
        };

        node.left = left;
        node.right = right;

        try bsp_mod.ArrayListBspNodePtr_append(stack, right);
        try bsp_mod.ArrayListBspNodePtr_append(stack, left);
    } else {
        const min_split = @intCast(u8, 4);
        if (node.h <= min_split * 2) return;
        const max_split = node.h - min_split;
        const split_y = node.y + rng_mod.Random_range(random, min_split, max_split);

        const left_mem = try sand_mod.sand_alloc(arena, @sizeOf(bsp_mod.BspNode), @alignOf(bsp_mod.BspNode));
        const right_mem = try sand_mod.sand_alloc(arena, @sizeOf(bsp_mod.BspNode), @alignOf(bsp_mod.BspNode));

        const left = @ptrCast(*bsp_mod.BspNode, left_mem);
        const right = @ptrCast(*bsp_mod.BspNode, right_mem);

        left.* = bsp_mod.BspNode{
            .x = node.x, .y = node.y,
            .w = node.w, .h = split_y - node.y,
            .left = null, .right = null, .room = null,
        };
        right.* = bsp_mod.BspNode{
            .x = node.x, .y = split_y,
            .w = node.w, .h = node.y + node.h - split_y,
            .left = null, .right = null, .room = null,
        };

        node.left = left;
        node.right = right;

        try bsp_mod.ArrayListBspNodePtr_append(stack, right);
        try bsp_mod.ArrayListBspNodePtr_append(stack, left);
    }
}

fn connectRooms(
    tiles: []tile_mod.Tile,
    width: u8,
    height: u8,
    rooms: []room_mod.Room_t,
    random: *rng_mod.Random
) !void {
    if (rooms.len < 2) return;

    var i: usize = 1;
    while (i < rooms.len) : (i += 1) {
        const a = rooms[i - 1];
        const b = rooms[i];

        const ax = room_mod.Room_centerX(a);
        const ay = room_mod.Room_centerY(a);
        const bx = room_mod.Room_centerX(b);
        const by = room_mod.Room_centerY(b);

        if (rng_mod.Random_range(random, 0, 1) == 0) {
            carveHCorridor(tiles, width, height, ax, bx, ay);
            carveVCorridor(tiles, width, height, ay, by, bx);
        } else {
            carveVCorridor(tiles, width, height, ay, by, ax);
            carveHCorridor(tiles, width, height, ax, bx, by);
        }
    }
}

fn carveHCorridor(tiles: []tile_mod.Tile, width: u8, height: u8, x1: u8, x2: u8, y: u8) void {
    const start = if (x1 < x2) x1 else x2;
    const end = if (x1 > x2) x1 else x2;
    var x = start;
    while (x <= end) : (x += 1) {
        if (x >= width or y >= height) continue;
        const idx = @intCast(usize, y) * @intCast(usize, width) + @intCast(usize, x);

        // REPRO: if (tiles[idx] == .Wall) tiles[idx] = .Floor;
        // Naked tags in binary ops trigger zig0 abort. Use switch workaround.
        switch (tiles[idx]) {
            .Wall => tiles[idx] = .Floor,
            else => {},
        }
    }
}

fn carveVCorridor(tiles: []tile_mod.Tile, width: u8, height: u8, cy1: u8, cy2: u8, cx: u8) void {
    const start = if (cy1 < cy2) cy1 else cy2;
    const end = if (cy1 > cy2) cy1 else cy2;
    var y = start;
    while (y <= end) : (y += 1) {
        if (cx >= width or y >= height) continue;
        const idx = @intCast(usize, y) * @intCast(usize, width) + @intCast(usize, cx);

        // REPRO: if (tiles[idx] == .Wall) tiles[idx] = .Floor;
        // Naked tags in binary ops trigger zig0 abort. Use switch workaround.
        switch (tiles[idx]) {
            .Wall => tiles[idx] = .Floor,
            else => {},
        }
    }
}
