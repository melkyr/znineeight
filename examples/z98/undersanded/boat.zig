// boat.zig — UNDERSANDED boat paint + cosmetic selection (spec §30, §38 P31).
//
// Pure data helpers: the runtime paint LUT is derived here from the pinned
// shade maps, and the owned-cosmetic bits choose the highest index per slot.
// No file I/O, no RNG, no phase change. render_art only consumes the LUTs and
// sprite pointers built by assets.zig.

const def = @import("def.zig");

// Cosmetic item order (data.z98): 0 Foam White, 1 Abyss Teal, 2 Leviathan Black.
pub const PAINT_COUNT: i32 = 3;
pub const PAINT_FOAM: i32 = 0;
pub const PAINT_TEAL: i32 = 1;
pub const PAINT_BLACK: i32 = 2;

pub const PAINT_NONE: i32 = -1;

pub const SLOT_FIGUREHEAD: i32 = 0;
pub const SLOT_FLAG: i32 = 1;
pub const SLOT_DECAL: i32 = 2;
pub const SLOT_COUNT: i32 = 3;

pub const FIGUREHEAD_FIRST: i32 = 3;
pub const FIGUREHEAD_LAST: i32 = 5;
pub const FLAG_FIRST: i32 = 6;
pub const FLAG_LAST: i32 = 8;
pub const DECAL_FIRST: i32 = 9;
pub const DECAL_LAST: i32 = 11;
pub const COSMETIC_OVERLAY_FIRST: i32 = FIGUREHEAD_FIRST;
pub const COSMETIC_OVERLAY_LAST: i32 = DECAL_LAST;

// The deck decal sits inside the hull bbox, so it must be drawn after paint.
pub const OVERLAY_DRAW_ORDER = [3]i32{
    SLOT_DECAL, SLOT_FIGUREHEAD, SLOT_FLAG,
};

pub const BOAT_W: i32 = 200;
pub const BOAT_H: i32 = 150;

// Authored hull paint clip. Pixel coordinates are half-open: x in [30,183),
// y in [42,109). Only ramp-0 shades 5/10/15 change; the outline (shade 0) and
// the ramp-1 portholes are outside the LUT map.
pub const HULL_X: i32 = 30;
pub const HULL_Y: i32 = 42;
pub const HULL_W: i32 = 153;
pub const HULL_H: i32 = 67;

const HULL_SHADES = [3]i32{ 5, 10, 15 };
// Foam White: 5/10/15 -> 10/15/15.
// Abyss Teal: ramp 0 -> ramp 1 at the same shades (21/26/31).
// Leviathan Black: 5/10/15 -> 0/5/10.
const PAINT_TARGETS = [3][3]i32{
    [3]i32{ 10, 15, 15 },
    [3]i32{ 21, 26, 31 },
    [3]i32{ 0, 5, 10 },
};

pub fn slotFirst(slot: i32) i32 {
    switch (slot) {
        SLOT_FIGUREHEAD => return FIGUREHEAD_FIRST,
        SLOT_FLAG => return FLAG_FIRST,
        SLOT_DECAL => return DECAL_FIRST,
        else => return 0,
    }
}

pub fn slotLast(slot: i32) i32 {
    switch (slot) {
        SLOT_FIGUREHEAD => return FIGUREHEAD_LAST,
        SLOT_FLAG => return FLAG_LAST,
        SLOT_DECAL => return DECAL_LAST,
        else => return -1,
    }
}

pub fn anchorX(slot: i32) i32 {
    switch (slot) {
        SLOT_FIGUREHEAD => return 24,
        SLOT_FLAG => return 150,
        SLOT_DECAL => return 96,
        else => return 0,
    }
}

pub fn anchorY(slot: i32) i32 {
    switch (slot) {
        SLOT_FIGUREHEAD => return 40,
        SLOT_FLAG => return 18,
        SLOT_DECAL => return 96,
        else => return 0,
    }
}

fn owned(w: *const def.World, index: i32) bool {
    if (index < 0 or index >= 32) return false;
    const bit = @intCast(u32, 1) << @intCast(u32, index);
    return (w.cosmetics_owned & bit) != 0;
}

fn highestOwned(w: *const def.World, first: i32, last: i32) i32 {
    var i = last;
    while (i >= first) : (i -= 1) {
        if (owned(w, i)) return i;
    }
    return -1;
}

pub fn paintName(paint: i32) []const u8 {
    switch (paint) {
        PAINT_FOAM => return "Foam White",
        PAINT_TEAL => return "Abyss Teal",
        PAINT_BLACK => return "Leviathan Black",
        else => return "none",
    }
}

pub fn paintIndex(w: *const def.World) i32 {
    return highestOwned(w, 0, PAINT_COUNT - 1);
}

pub fn selectedCosmetic(w: *const def.World, slot: i32) i32 {
    return highestOwned(w, slotFirst(slot), slotLast(slot));
}

pub fn figureheadIndex(w: *const def.World) i32 {
    return selectedCosmetic(w, SLOT_FIGUREHEAD);
}

pub fn flagIndex(w: *const def.World) i32 {
    return selectedCosmetic(w, SLOT_FLAG);
}

pub fn decalIndex(w: *const def.World) i32 {
    return selectedCosmetic(w, SLOT_DECAL);
}

pub fn paintLut(out: *[256]u16, base: *const [256]u16, paint: i32) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) out[i] = base[i];
    if (paint < 0 or paint >= PAINT_COUNT) return;

    const p: usize = @intCast(usize, paint);
    var s: usize = 0;
    while (s < HULL_SHADES.len) : (s += 1) {
        const src: usize = @intCast(usize, HULL_SHADES[s]);
        const dst: usize = @intCast(usize, PAINT_TARGETS[p][s]);
        out[src] = base[dst];
    }
}
