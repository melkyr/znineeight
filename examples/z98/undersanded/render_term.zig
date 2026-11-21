// render_term.zig — UNDERSANDED minimal terminal fight frame (spec §26/§28).
//
// Pure rendering: reads a *GameState + the immutable creature row and writes
// an 80x30 ASCII cell buffer. It never mutates game state, never draws from a
// msg string stored in the log, and never calls into fight.zig beyond reading
// public constants. Console output is plain ASCII (no ANSI), CRLF-safe.
//
// The terminal/console shell can blit `Screen.cells` row by row (std_gfx
// gfxDrawText per row, or std_io text output); native tests inspect `dump()`.

const def = @import("def.zig");
const fight = @import("fight.zig");
const world = @import("world.zig");
const creatures = @import("creatures_t1.zig");
const tables = @import("tables_t1.zig");
const items = @import("items.zig");
const render_text = @import("render_text.zig");
const score = @import("score.zig");
const boat = @import("boat.zig");

pub const COLS: usize = render_text.COLS;
pub const ROWS: usize = render_text.ROWS;
pub const CELLS: usize = render_text.CELLS;

pub const BAR_WIDTH: i32 = 20;
pub const LOG_LINES: i32 = 8;

pub const Screen = render_text.Screen;

// Domain-derived values needed by the dock/sub-menu/journal/node screens.
// nav.zig builds this from dock/economy/journal/data so the renderers below
// stay free of domain imports; the raw GameState pointer is read-only and only
// supplies values the renderers already sourced from def/world/tables/items.
pub const View = struct {
    screen: i32,
    g: *const def.GameState,
    journal_has_new: bool,
    save_ok: bool,
    save_block: []const u8,
    refine_parts: [def.MAX_PARTS]i32,
    refine_per_part: [def.MAX_PARTS]i32,
    upgrade_cost: [15]def.CostSlot,
    upgrade_cost_is_material: [15]bool,
    cosmetic_status: [def.MAX_COSMETICS]i32,
    journal_sel: i32,
    journal_unlocked: [def.MAX_CREATURES]bool,
    journal_viewed: [def.MAX_CREATURES]bool,
    journal_text: []const u8,
    journal_text_found: bool,
    zone_flavour: []const u8,
    zone_flavour_found: bool,
    zone_cost: [def.MAX_ZONES]i32,
    heavy_active: bool,
    node_pool: i32,
};

pub const COSMETIC_LOCKED: i32 = 0;
pub const COSMETIC_AVAILABLE: i32 = 1;
pub const COSMETIC_OWNED: i32 = 2;

const ZERO: u8 = ' ';
const FILL: u8 = '#';
const EMPTY: u8 = '.';

pub fn clear(sc: *Screen) void {
    render_text.clear(sc);
}

fn putChar(sc: *Screen, x: i32, y: i32, c: u8) void {
    render_text.putChar(sc, x, y, c);
}

fn put(sc: *Screen, x: i32, y: i32, s: []const u8) i32 {
    return render_text.put(sc, x, y, s);
}

fn putInt(sc: *Screen, x: i32, y: i32, v: i32) i32 {
    return render_text.putInt(sc, x, y, v);
}

fn intInto(out: []u8, start: usize, value: i32) usize {
    return render_text.intInto(out, start, value);
}

fn copyInto(out: []u8, start: usize, s: []const u8) usize {
    return render_text.copyInto(out, start, s);
}

pub fn speedRevealed(s: *const def.GameState) bool {
    return render_text.speedRevealed(s);
}

pub fn conditionName(cond: i32) []const u8 {
    return render_text.conditionName(cond);
}

fn phaseDayNight(phase: i32) []const u8 {
    if (phase == world.PHASE_NIGHT) return "Night";
    return "Day";
}

fn putCycleLine(sc: *Screen, s: *const def.GameState, y: i32) void {
    var x = put(sc, 0, y, "Cycle ");
    x = putInt(sc, x, y, s.world.cycle);
    x = put(sc, x, y, " - ");
    _ = put(sc, x, y, phaseDayNight(s.world.phase));
}


fn barFill(value: i32, max: i32, width: i32) i32 {
    if (max <= 0 or width <= 0) return 0;
    if (value <= 0) return 0;
    if (value >= max) return width;
    var f: i32 = value * width / max;
    if (f < 0) f = 0;
    if (f > width) f = width;
    return f;
}

fn putBar(sc: *Screen, y: i32, label: []const u8, value: i32, max: i32,
    red_at: i32) void {
    var x = put(sc, 0, y, label);
    x = put(sc, x, y, " [");
    const bar_x = x;
    const fill = barFill(value, max, BAR_WIDTH);
    var i: i32 = 0;
    while (i < BAR_WIDTH) : (i += 1) {
        if (i < fill) {
            putChar(sc, x + i, y, FILL);
        } else {
            putChar(sc, x + i, y, EMPTY);
        }
    }
    if (red_at >= 0) {
        const mark = barFill(red_at, max, BAR_WIDTH);
        if (mark < BAR_WIDTH) putChar(sc, bar_x + mark, y, '|');
    }
    x += BAR_WIDTH;
    x = put(sc, x, y, "] ");
    x = putInt(sc, x, y, value);
    x = put(sc, x, y, "/");
    _ = putInt(sc, x, y, max);
}

pub fn creatureName(d: *const def.CreatureDef) []const u8 {
    return render_text.creatureName(d);
}


// Effective Speed for display: delegate to the fight math so field-driven
// bonuses, Last Surge, and rule ADD_SPEED rows agree exactly (Sonar reveal).
pub fn effectiveSpeed(s: *const def.GameState, d: *const def.CreatureDef) i32 {
    return fight.effectiveSpeed(s, d, creatures.rules());
}

pub fn roleName(role: i32) []const u8 {
    switch (role) {
        1 => return "common",
        2 => return "named",
        3 => return "rare",
        4 => return "boss",
        else => return "unknown",
    }
}

pub fn msgLine(e: def.LogEntry, d: *const def.CreatureDef, out: []u8) []const u8 {
    return render_text.msgLine(e, d, out);
}



fn renderLog(sc: *Screen, s: *const def.GameState, d: *const def.CreatureDef, y0: i32) void {
    var first: i32 = 0;
    if (s.log_n > LOG_LINES) first = s.log_n - LOG_LINES;
    var i: i32 = first;
    var y = y0;
    while (i < s.log_n and y < ROWS) : (i += 1) {
        var buf: [96]u8 = undefined;
        const e = s.log[@intCast(usize, i)];
        const line = msgLine(e, d, buf[0..]);
        _ = put(sc, 0, y, line);
        y += 1;
    }
}

pub fn renderModal(sc: *Screen, s: *const def.GameState, d: *const def.CreatureDef) void {
    render_text.renderModal(sc, s, d);
}

pub fn renderToolStatus(sc: *Screen, s: *const def.GameState, y: i32) void {
    render_text.renderToolStatus(sc, s, y);
}



pub fn renderFrame(s: *const def.GameState, d: *const def.CreatureDef, sc: *Screen) void {
    clear(sc);

    if (s.screen == def.SCREEN_SUBDUE or s.screen == def.SCREEN_SUBDUE_POST) {
        renderModal(sc, s, d);
        return;
    }

    _ = put(sc, 0, 0, "UNDERSANDED  FIGHT");

    var x = put(sc, 0, 1, creatureName(d));
    x = put(sc, x, 1, "  ");
    x = put(sc, x, 1, roleName(d.role));
    x = put(sc, x, 1, "  SPD ");
    if (speedRevealed(s)) {
        x = putInt(sc, x, 1, effectiveSpeed(s, d));
    } else {
        x = put(sc, x, 1, "??");
    }
    if ((d.flags & def.F_PHASING) != 0) {
        x = put(sc, x, 1, "  ");
        if (fight.phaseState(s) == fight.PHASE_PHASED) {
            _ = put(sc, x, 1, "PHASE");
        } else {
            _ = put(sc, x, 1, "SOLID");
        }
    }

    x = put(sc, 0, 2, "COND ");
    _ = put(sc, x, 2, conditionName(s.fight.cond));

    putBar(sc, 3, "HP     ", s.fight.hp, s.fight.max_hp, fight.dangerHp(s));
    putBar(sc, 4, "RESOLVE", s.fight.res, s.fight.max_res, -1);
    putBar(sc, 5, "HULL   ", s.fight.hull, s.fight.max_hull, -1);

    renderToolStatus(sc, s, 6);

    renderLog(sc, s, d, 7);

    _ = put(sc, 0, 15, "[S]trike [R]estrain [E] Use tool [F]lee  [?] Help");
}

// ---- Dock / map / node screens (§12, §16, §26) ---------------------------

const BOSS_ZONE: i32 = 8;

pub fn zoneName(zone: i32) []const u8 {
    switch (zone) {
        0 => return "The Shallows",
        1 => return "The Reef",
        2 => return "Trench-Edge",
        3 => return "Kelp Basin",
        4 => return "The Shelf",
        5 => return "Wreck Line",
        6 => return "The Hollow",
        7 => return "The Trench",
        8 => return "The Derelict",
        else => return "Unknown Zone",
    }
}

fn zoneTag(zone: i32) []const u8 {
    switch (zone) {
        0 => return "Z1",
        1 => return "Z2",
        2 => return "Z3",
        3 => return "Z4",
        4 => return "Z5",
        5 => return "Z6",
        6 => return "Z7",
        7 => return "Z8",
        8 => return "D",
        else => return "--",
    }
}

// Distinct non-boss creatures seen. The domain helper owns the count so
// expedition can enforce the gate without importing a renderer.
pub fn seenNonBossCount(s: *const def.GameState) i32 {
    return world.seenNonBossCount(&s.world);
}

pub fn bossGateOpen(s: *const def.GameState) bool {
    return world.bossGateOpen(&s.world);
}

pub fn fightsLeft(s: *const def.GameState) i32 {
    var left = world.maxFights(&s.world, s.exp.zone) - s.exp.fight_index;
    if (left < 0) left = 0;
    return left;
}

fn padTo(sc: *Screen, x: i32, y: i32, target: i32) i32 {
    var p = x;
    while (p < target) : (p += 1) {
        putChar(sc, p, y, ZERO);
    }
    return p;
}

pub fn materialName(m: i32) []const u8 {
    switch (m) {
        1 => return "Chitin",
        2 => return "Steel Plate",
        3 => return "Gland",
        4 => return "Brine",
        5 => return "Coral",
        6 => return "Luminescence",
        7 => return "Glass",
        else => return "Unknown",
    }
}

fn toolName(id: i32) []const u8 {
    return render_text.toolName(id);
}

fn toolKindName(kind: i32) []const u8 {
    return render_text.toolKindName(kind);
}


pub fn axisName(axis: i32) []const u8 {
    switch (axis) {
        0 => return "Hull",
        1 => return "Speed",
        2 => return "Cargo",
        3 => return "Oxygen",
        4 => return "Precision",
        else => return "Unknown",
    }
}

// One-line cumulative effect for the next (or current max) tier (spec §11).
fn axisEffect(axis: i32, tier: i32) []const u8 {
    switch (axis) {
        0 => {
            if (tier <= 1) return "max Hull 125";
            if (tier == 2) return "max Hull 150";
            return "max Hull 200; Heavy +1 on cost 3+";
        },
        1 => {
            if (tier <= 1) return "player Speed 12";
            if (tier == 2) return "player Speed 15";
            return "player Speed 19";
        },
        2 => {
            if (tier <= 1) return "Cargo +1 part per drop";
            if (tier == 2) return "Cargo +2 parts per drop";
            return "Cargo +3 parts per drop; Heavy +1 on cost 3+";
        },
        3 => {
            if (tier <= 1) return "4 fights per expedition";
            if (tier == 2) return "5 fights per expedition";
            return "6 fights per expedition";
        },
        4 => {
            if (tier <= 1) return "overkill margin 15%; fragile tools from T2";
            if (tier == 2) return "overkill margin 20%; fragile tools active";
            return "overkill margin 25%; fragile tools active";
        },
        else => return "unknown effect",
    }
}

pub fn cosmeticUnlockName(unlock: i32) []const u8 {
    switch (unlock) {
        1 => return "Reach Z1",
        2 => return "Reach Z2",
        3 => return "Reach Z3",
        4 => return "Kill the Derelict",
        else => return "Unknown",
    }
}

fn ownedToolCount(w: *const def.World) i32 {
    var n: i32 = 0;
    var id: i32 = 1;
    while (id <= 7) : (id += 1) {
        if (items.toolOwned(w, id)) n += 1;
    }
    return n;
}

fn putCost(sc: *Screen, x: i32, y: i32, cost: [3]def.CostSlot) i32 {
    var p = x;
    var any = false;
    var i: usize = 0;
    while (i < cost.len) : (i += 1) {
        if (cost[i].kind <= 0 or cost[i].amt <= 0) continue;
        if (any) p = put(sc, p, y, ", ");
        any = true;
        p = put(sc, p, y, partName(cost[i].kind));
        p = put(sc, p, y, " x");
        p = putInt(sc, p, y, cost[i].amt);
    }
    if (!any) p = put(sc, p, y, "free");
    return p;
}

fn putUpgradeCost(sc: *Screen, x: i32, y: i32, v: *const View, base: usize) i32 {
    var p = x;
    var any = false;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const slot = v.upgrade_cost[base + i];
        if (slot.kind <= 0 or slot.amt <= 0) continue;
        if (any) p = put(sc, p, y, ", ");
        any = true;
        if (v.upgrade_cost_is_material[base + i]) {
            p = put(sc, p, y, materialName(slot.kind));
        } else {
            p = put(sc, p, y, partName(slot.kind));
        }
        p = put(sc, p, y, " x");
        p = putInt(sc, p, y, slot.amt);
    }
    if (!any) p = put(sc, p, y, "free");
    return p;
}

fn putMaterialStat(sc: *Screen, x: i32, y: i32, m: i32, w: *const def.World) i32 {
    var p = put(sc, x, y, materialName(m));
    p = put(sc, p, y, " ");
    p = putInt(sc, p, y, w.materials[@intCast(usize, m)]);
    p = put(sc, p, y, "(E");
    p = putInt(sc, p, y, w.expertise[@intCast(usize, m)]);
    p = put(sc, p, y, ")");
    return p;
}

pub fn renderDock(v: *const View, sc: *Screen) void {
    const s = v.g;
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK");
    putCycleLine(sc, s, 1);

    var x = put(sc, 0, 2, "Hull ");
    x = putInt(sc, x, 2, s.world.hull);
    x = put(sc, x, 2, "/");
    _ = putInt(sc, x, 2, world.hullMax(&s.world));

    x = put(sc, 0, 3, "Coins ");
    _ = putInt(sc, x, 3, s.world.money);

    x = put(sc, 0, 4, "Boat: Hull T");
    x = putInt(sc, x, 4, s.world.boat[world.BOAT_HULL]);
    x = put(sc, x, 4, " Speed T");
    x = putInt(sc, x, 4, s.world.boat[world.BOAT_SPEED]);
    x = put(sc, x, 4, " Cargo T");
    x = putInt(sc, x, 4, s.world.boat[world.BOAT_CARGO]);
    x = put(sc, x, 4, " Oxygen T");
    x = putInt(sc, x, 4, s.world.boat[world.BOAT_OXYGEN]);
    x = put(sc, x, 4, " Precision T");
    _ = putInt(sc, x, 4, s.world.boat[world.BOAT_PRECISION]);

    x = put(sc, 0, 6, "Materials: ");
    x = putMaterialStat(sc, x, 6, 1, &s.world);
    x = put(sc, x, 6, " ");
    x = putMaterialStat(sc, x, 6, 2, &s.world);
    x = put(sc, x, 6, " ");
    x = putMaterialStat(sc, x, 6, 3, &s.world);
    x = put(sc, x, 6, " ");
    _ = putMaterialStat(sc, x, 6, 4, &s.world);

    x = put(sc, 0, 7, "           ");
    x = putMaterialStat(sc, x, 7, 5, &s.world);
    x = put(sc, x, 7, " ");
    x = putMaterialStat(sc, x, 7, 6, &s.world);
    x = put(sc, x, 7, " ");
    _ = putMaterialStat(sc, x, 7, 7, &s.world);

    x = put(sc, 0, 8, "Tools owned: ");
    x = putInt(sc, x, 8, ownedToolCount(&s.world));
    x = put(sc, x, 8, "  Selected: ");
    _ = put(sc, x, 8, toolName(s.world.tool_selected));

    _ = put(sc, 0, 10, "[R]efine [U]pgrade [C]raft [B]uy [E]quip [T] Rest [D]epart [Q]uit");
    if (v.journal_has_new) {
        _ = put(sc, 0, 11, "New journal entry - [J]ournal");
    }
    _ = put(sc, 0, 12, "Hint: Hull persists between trips; dock Rest is safe.");
    if (v.save_ok) {
        _ = put(sc, 0, 13, "[Esc] Save");
    } else {
        var sx = put(sc, 0, 13, "[Esc] Save - ");
        _ = put(sc, sx, 13, v.save_block);
    }
    _ = put(sc, 0, 14, "[?] Help  [J]ournal");
}

pub fn renderRefine(v: *const View, sc: *Screen) void {
    const s = v.g;
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - REFINE");
    _ = put(sc, 0, 1, "Convert all parts of one type. Rare batches need a second press.");

    var m: i32 = 1;
    while (m <= 7) : (m += 1) {
        const y = 3 + m - 1;
        const mi: usize = @intCast(usize, m);
        const parts = v.refine_parts[mi];
        const per = v.refine_per_part[mi];
        var x = putInt(sc, 0, y, m);
        x = put(sc, x, y, " ");
        x = put(sc, x, y, partName(m));
        x = put(sc, x, y, " x");
        x = putInt(sc, x, y, parts);
        x = put(sc, x, y, " -> ");
        x = putInt(sc, x, y, parts * per);
        x = put(sc, x, y, " ");
        x = put(sc, x, y, materialName(m));
        x = put(sc, x, y, " (E");
        x = putInt(sc, x, y, s.world.expertise[mi]);
        x = put(sc, x, y, ", ");
        x = putInt(sc, x, y, per);
        _ = put(sc, x, y, "/part)");
    }

    _ = put(sc, 0, 12, "[1-7] Refine material  [Esc] Back  [?] Help");
}

pub fn renderUpgrade(v: *const View, sc: *Screen) void {
    const s = v.g;
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - UPGRADE");
    _ = put(sc, 0, 1, "Buy the next tier of one axis (T2 needs E2, T3 needs E4).");

    var axis: i32 = 0;
    while (axis < 5) : (axis += 1) {
        const y = 3 + axis * 2;
        const tier = s.world.boat[@intCast(usize, axis)];
        var x = putInt(sc, 0, y, axis + 1);
        x = put(sc, x, y, " ");
        x = put(sc, x, y, axisName(axis));
        x = put(sc, x, y, " T");
        x = putInt(sc, x, y, tier);
        if (tier >= 3) {
            _ = put(sc, x, y, " (max)");
        } else {
            x = put(sc, x, y, " -> T");
            x = putInt(sc, x, y, tier + 1);
            x = put(sc, x, y, ": ");
            _ = putUpgradeCost(sc, x, y, v, @intCast(usize, axis) * 3);
        }
        var effect_tier = tier + 1;
        if (effect_tier > 3) effect_tier = 3;
        var ex = put(sc, 2, y + 1, "Effect: ");
        _ = put(sc, ex, y + 1, axisEffect(axis, effect_tier));
    }

    _ = put(sc, 0, 14, "[1-5] Upgrade axis  [Esc] Back  [?] Help");
}

pub fn renderCraft(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - CRAFT");
    _ = put(sc, 0, 1, "Build one tool from parts; owned forever.");

    const rows = tables.tools();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const row = rows[i];
        const y = 3 + @intCast(i32, i) * 2;
        var x = putInt(sc, 0, y, row.id);
        x = put(sc, x, y, " ");
        x = put(sc, x, y, toolName(row.id));
        x = put(sc, x, y, " [");
        x = put(sc, x, y, toolKindName(row.kind));
        x = put(sc, x, y, "] ");
        x = putCost(sc, x, y, row.cost);
        if (items.toolOwned(&s.world, row.id)) _ = put(sc, x, y, " (owned)");
        var ex = put(sc, 2, y + 1, "Effect: ");
        _ = put(sc, ex, y + 1, render_text.toolEffect(row.id));
    }

    _ = put(sc, 0, 18, "[1-7] Craft tool  [Esc] Back  [?] Help");
}

fn cosmeticKey(index: i32) u8 {
    if (index < 9) return @intCast(u8, '1' + index);
    return @intCast(u8, 'a' + (index - 9));
}

pub fn renderBuy(v: *const View, sc: *Screen) void {
    const s = v.g;
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - BUY");
    var x = put(sc, 0, 1, "Coins: ");
    _ = putInt(sc, x, 1, s.world.money);

    const rows = tables.cosmetics();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const idx: i32 = @intCast(i32, i);
        const row = rows[i];
        const y = 3 + idx;
        putChar(sc, 0, y, cosmeticKey(idx));
        var p = put(sc, 2, y, row.name);
        p = put(sc, p, y, " ");
        p = putInt(sc, p, y, row.price);
        const status = v.cosmetic_status[@intCast(usize, idx)];
        if (status == COSMETIC_OWNED) {
            _ = put(sc, p, y, " (owned)");
        } else if (status == COSMETIC_LOCKED) {
            p = put(sc, p, y, " (locked) ");
            _ = put(sc, p, y, cosmeticUnlockName(row.unlock));
        } else {
            _ = put(sc, p, y, " (available)");
        }
    }

    _ = put(sc, 0, 16, "[1-9,a-c] Buy cosmetic  [Esc] Back  [?] Help");
}

pub fn renderTools(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - EQUIP");
    var x = put(sc, 0, 1, "Selected: ");
    _ = put(sc, x, 1, toolName(s.world.tool_selected));

    var id: i32 = 1;
    while (id <= 7) : (id += 1) {
        const y = 3 + (id - 1) * 2;
        var p = putInt(sc, 0, y, id);
        p = put(sc, p, y, " ");
        p = put(sc, p, y, toolName(id));
        if (s.world.tool_selected == id) {
            p = put(sc, p, y, " *selected*");
        }
        if (!items.toolOwned(&s.world, id)) {
            _ = put(sc, p, y, " (not owned)");
        }
        var ex = put(sc, 2, y + 1, "Effect: ");
        _ = put(sc, ex, y + 1, render_text.toolEffect(id));
    }

    _ = put(sc, 0, 18, "[1-7] Select tool  [0] None  [Esc] Back  [?] Help");
}


fn renderMapRow(v: *const View, sc: *Screen, zone: i32, y: i32) void {
    const s = v.g;
    var x = put(sc, 0, y, zoneTag(zone));
    x = padTo(sc, x, y, 4);
    x = put(sc, x, y, zoneName(zone));
    x = padTo(sc, x, y, 24);
    x = putInt(sc, x, y, v.zone_cost[@intCast(usize, zone)]);
    x = padTo(sc, x, y, 28);

    var open = true;
    if (tables.zoneIsBoss(zone) != 0) open = bossGateOpen(s);
    if (open) {
        x = put(sc, x, y, "open");
    } else {
        x = put(sc, x, y, "locked");
    }
    if (tables.zoneIsBoss(zone) != 0) {
        _ = put(sc, x, y, "  Hull 150+ recommended.");
    }
}

pub fn renderMap(v: *const View, sc: *Screen) void {
    const s = v.g;
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  MAP");
    putCycleLine(sc, s, 1);
    _ = put(sc, 0, 2, "Zone ladder (travel phases each way):");

    var zone: i32 = 0;
    var y: i32 = 3;
    while (zone <= BOSS_ZONE) : (zone += 1) {
        renderMapRow(v, sc, zone, y);
        y += 1;
    }

    var x = put(sc, 0, 13, "Seen non-boss: ");
    x = putInt(sc, x, 13, seenNonBossCount(s));
    x = put(sc, x, 13, "/");
    _ = putInt(sc, x, 13, world.BOSS_SEEN_GATE);
    if (v.heavy_active) {
        _ = put(sc, 0, 14, "Heavy +1 (Hull/Cargo T3) on cost 3+ zones.");
    }

    _ = put(sc, 0, 15, "[1-8] Z1-Z8  [9] Boss  [Esc] Back  [?] Help  [J]ournal");
}

// ---- Secured line (§7) ----------------------------------------------------

pub fn partName(part: i32) []const u8 {
    switch (part) {
        1 => return "Shell Chip",
        2 => return "Plate Scrap",
        3 => return "Gland Sac",
        4 => return "Brine Vial",
        5 => return "Coral Bud",
        6 => return "Glow Polyp",
        7 => return "Glass Pane",
        8 => return "Hooked Barbel",
        9 => return "Steel Fins",
        else => return "Unknown Part",
    }
}

// Same primary-line Cargo rule as expedition.addLoot (§7): only the first
// non-empty, non-keystone line receives the Cargo total.
fn addSecuredLines(h: *[def.MAX_PARTS]i32, lines: []const def.DropLine, cargo: i32) void {
    var primary: i32 = -1;
    var p: usize = 0;
    while (p < def.MAX_DROP_LINES and p < lines.len) : (p += 1) {
        if (lines[p].part <= 0 or lines[p].count <= 0) continue;
        if (items.isKeystone(lines[p].part)) continue;
        primary = @intCast(i32, p);
        break;
    }

    var i: usize = 0;
    while (i < def.MAX_DROP_LINES and i < lines.len) : (i += 1) {
        const part = lines[i].part;
        var count = lines[i].count;
        if (part <= 0 or count <= 0) continue;
        if (@intCast(usize, part) >= def.MAX_PARTS) continue;
        if (@intCast(i32, i) == primary) count += cargo;
        h[@intCast(usize, part)] += count;
    }
}

// Recompute the last fight's secured parts from the most recent CLS_SECURED
// settlement entry: `a` is the def index and `b` the outcome. No entry means no
// secured line; a CREATURE_FLED entry renders the explicit empty line.
pub fn securedLine(g: *const def.GameState, out: []u8) []const u8 {
    var last: i32 = -1;
    var i: i32 = 0;
    while (i < g.log_n) : (i += 1) {
        if (g.log[@intCast(usize, i)].class == def.CLS_SECURED) last = i;
    }
    if (last < 0) return "";

    var h: [def.MAX_PARTS]i32 = undefined;
    var k: usize = 0;
    while (k < def.MAX_PARTS) : (k += 1) {
        h[k] = 0;
    }

    const e = g.log[@intCast(usize, last)];
    const idx = e.a;
    const outcome = e.b;
    if (idx >= 0 and idx < creatures.defCount()) {
        const cargo = world.cargoMax(&g.world);
        var cdef = creatures.defAt(idx);
        if (outcome == def.OUT_SUBDUE) {
            addSecuredLines(&h, cdef.sub[0..], cargo);
        } else if (outcome == def.OUT_KILL) {
            addSecuredLines(&h, cdef.kill[0..], cargo);
        } else if (outcome == def.OUT_OVERKILL) {
            addSecuredLines(&h, cdef.over[0..], cargo);
        }
    }

    var p: usize = 0;
    p = copyInto(out, p, "Secured: ");
    var any = false;
    k = 0;
    while (k < def.MAX_PARTS) : (k += 1) {
        if (h[k] <= 0) continue;
        if (any) p = copyInto(out, p, ", ");
        any = true;
        p = copyInto(out, p, partName(@intCast(i32, k)));
        p = copyInto(out, p, " x");
        p = intInto(out, p, h[k]);
    }
    if (!any) {
        p = copyInto(out, p, "nothing");
    }
    return out[0..p];
}

// Plain text block: '\n' is one line break, '\n\n' one blank row. Long lines
// clip at the frame edge; authored prose wraps well below 80 columns.
fn putTextBlock(sc: *Screen, y0: i32, s: []const u8, y_limit: i32) void {
    render_text.putTextBlock(sc, y0, s, y_limit);
}


// Journal list: entry i uses key i+1 (digit 1-9, then a-j). Locked entries
// stay unnamed; unlocked-but-unviewed entries carry a '*'.
pub fn renderJournal(v: *const View, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  JOURNAL");

    if (v.journal_sel > 0) {
        const d = v.journal_sel - 1;
        var x = put(sc, 0, 1, "Entry ");
        x = putInt(sc, x, 1, v.journal_sel);
        x = put(sc, x, 1, ": ");
        if (d >= 0 and d < creatures.defCount()) {
            var cdef = creatures.defAt(d);
            _ = put(sc, x, 1, creatureName(&cdef));
        }
        if (v.journal_text_found) {
            putTextBlock(sc, 3, v.journal_text, ROWS - 2);
        } else {
            _ = put(sc, 0, 3, "(entry text unavailable)");
        }
        _ = put(sc, 0, ROWS - 1, "[Esc] Back to journal  [?] Help");
        return;
    }

    var d: i32 = 0;
    while (d < creatures.defCount() and d < 19) : (d += 1) {
        const y = 2 + d;
        var x: i32 = 0;
        if (d < 9) {
            putChar(sc, 0, y, @intCast(u8, '1' + d));
        } else {
            putChar(sc, 0, y, @intCast(u8, 'a' + (d - 9)));
        }
        x = put(sc, 2, y, " ");
        const di: usize = @intCast(usize, d);
        if (v.journal_unlocked[di]) {
            var cdef = creatures.defAt(d);
            x = put(sc, x, y, creatureName(&cdef));
            if (!v.journal_viewed[di]) {
                _ = put(sc, x, y, "  *NEW*");
            }
        } else {
            _ = put(sc, x, y, "- unrecorded -");
        }
    }

    _ = put(sc, 0, ROWS - 1, "[1-9,a-j] Read  [Esc] Back  [?] Help");
}

pub fn renderHelp(text: []const u8, sc: *Screen) void {
    render_text.renderHelp(text, sc);
}



pub fn renderNode(v: *const View, sc: *Screen) void {
    const s = v.g;
    clear(sc);

    var sbuf: [128]u8 = undefined;
    const secured = securedLine(s, sbuf[0..]);

    // A pending Subdue owns the screen: the intro is Continue-only and the
    // settle screen is the irreversible 1/2 choice (spec §7.1/§9.7).
    if (s.fight.outcome == def.OUT_SUBDUE and s.fight.def_index != def.NO_FIGHT) {
        var cdef = creatures.defAt(s.fight.def_index);
        const name = creatureName(&cdef);
        var x: i32 = 0;
        if (s.screen == def.NAV_SUBDUE_INTRO) {
            x = put(sc, 0, 0, "SUBDUED ");
            _ = put(sc, x, 0, name);
            if (secured.len > 0) {
                _ = put(sc, 0, 2, secured);
            } else {
                _ = put(sc, 0, 2, "Secured: nothing");
            }
            _ = put(sc, 0, 4, "[C]ontinue");
            _ = put(sc, 0, 6, "[?] Help");
            return;
        }

        _ = put(sc, 0, 0, "UNDERSANDED  SETTLE");
        x = put(sc, 0, 2, "Subdued ");
        _ = put(sc, x, 2, name);
        if (secured.len > 0) {
            _ = put(sc, 0, 4, secured);
        } else {
            _ = put(sc, 0, 4, "Secured: nothing");
        }
        _ = put(sc, 0, 6, "[1] Release - parts kept; rare chance +8 where rares exist (cap +40);");
        _ = put(sc, 0, 7, "returns +15 Resolve");
        x = put(sc, 0, 8, "[2] Sell - parts kept; +");
        x = putInt(sc, x, 8, cdef.sale);
        _ = put(sc, x, 8, " coins");
        _ = put(sc, 0, 10, "[?] Help");
        return;
    }

    _ = put(sc, 0, 0, "UNDERSANDED  NODE");
    putCycleLine(sc, s, 1);
    _ = put(sc, 0, 2, zoneName(s.exp.zone));

    const locked = world.lockoutRemaining(&s.world, s.exp.zone);
    var x: i32 = 0;
    if (locked > 0) {
        x = put(sc, 0, 3, "Rare chance 0% (locked ");
        x = putInt(sc, x, 3, locked);
        _ = put(sc, x, 3, " cycles)");
    } else {
        x = put(sc, 0, 3, "Rare chance: ");
        x = putInt(sc, x, 3, world.rareChance(&s.world, s.exp.zone));
        _ = put(sc, x, 3, "%");
    }

    x = put(sc, 0, 4, "Pool: ");
    x = putInt(sc, x, 4, v.node_pool);
    x = put(sc, x, 4, "  Fights left ");
    _ = putInt(sc, x, 4, fightsLeft(s));

    x = put(sc, 0, 5, "Hull ");
    x = putInt(sc, x, 5, s.world.hull);
    x = put(sc, x, 5, "/");
    _ = putInt(sc, x, 5, world.hullMax(&s.world));

    if (tables.zoneIsBoss(s.exp.zone) != 0) {
        _ = put(sc, 0, 10, "Hull 150+ recommended.");
    }

    if (secured.len > 0) {
        _ = put(sc, 0, 6, secured);
    }

    _ = put(sc, 0, 7, "[H]unt [R]est [S]urface");
    _ = put(sc, 0, 8, "[?] Help  [J]ournal");
    _ = put(sc, 0, 9, "Hint: Rest at a node risks rough sleep unless the pool is empty.");

    if (v.zone_flavour_found) {
        putTextBlock(sc, 11, v.zone_flavour, ROWS - 1);
    }
}

// ---- Score / credits (§19, §38 P31) --------------------------------------

fn variantSeen(mask: u32, index: i32) bool {
    if (index < 0 or index >= score.VARIANT_COUNT) return false;
    const bit: u32 = @intCast(u32, 1) << @intCast(u32, index);
    return (mask & bit) != 0;
}

fn putVariantLine(sc: *Screen, y: i32, mask: u32, index: i32) void {
    const i: usize = @intCast(usize, index);
    if (variantSeen(mask, index)) {
        _ = put(sc, 38, y, "[x]");
    } else {
        _ = put(sc, 38, y, "[ ]");
    }
    _ = put(sc, 42, y, score.IDENTITIES[i]);
}

pub fn renderScore(p: *const score.ScorePanels, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  SCORE");
    _ = put(sc, 71, 0, "[?] Help");

    _ = put(sc, 0, 2, score.TITLE_FIELD_RECORD);
    _ = put(sc, 38, 2, score.TITLE_VARIANTS_SEEN);

    var x = put(sc, 0, 3, "Cycles: ");
    _ = putInt(sc, x, 3, p.field.cycles);
    x = put(sc, 38, 3, "Variants: ");
    x = putInt(sc, x, 3, p.variants_count);
    _ = put(sc, x, 3, " / 5");

    x = put(sc, 0, 4, "Field time: ");
    x = putInt(sc, x, 4, p.field.field_phases);
    _ = put(sc, x, 4, " phases");
    putVariantLine(sc, 4, p.variants_seen, 0);

    x = put(sc, 0, 5, "Species seen: ");
    x = putInt(sc, x, 5, p.field.creatures_seen);
    x = put(sc, x, 5, "/");
    _ = putInt(sc, x, 5, p.creatures_total);
    putVariantLine(sc, 5, p.variants_seen, 1);

    x = put(sc, 0, 6, "Rares seen: ");
    x = putInt(sc, x, 6, p.field.rares_seen);
    x = put(sc, x, 6, "/");
    _ = putInt(sc, x, 6, p.rares_total);
    putVariantLine(sc, 6, p.variants_seen, 2);

    x = put(sc, 0, 7, "Bosses killed: ");
    x = putInt(sc, x, 7, p.field.bosses_killed);
    _ = put(sc, x, 7, "/1");
    putVariantLine(sc, 7, p.variants_seen, 3);

    x = put(sc, 0, 8, "Final Phase 2: ");
    _ = put(sc, x, 8, score.identityLabel(p.field.final_phase2));
    putVariantLine(sc, 8, p.variants_seen, 4);

    x = put(sc, 0, 9, "Subdued/Killed/Overkilled: ");
    x = putInt(sc, x, 9, p.field.subdued);
    x = put(sc, x, 9, "/");
    x = putInt(sc, x, 9, p.field.killed);
    x = put(sc, x, 9, "/");
    _ = putInt(sc, x, 9, p.field.overkilled);

    x = put(sc, 0, 10, "Expertise:");
    var i: usize = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        x = put(sc, x, 10, " ");
        x = putInt(sc, x, 10, p.field.expertise[i]);
    }

    x = put(sc, 0, 11, "Money earned: ");
    _ = putInt(sc, x, 11, p.field.money_earned);

    x = put(sc, 0, 12, "Cosmetics: ");
    x = putInt(sc, x, 12, p.field.cosmetics);
    _ = put(sc, x, 12, "/12");

    x = put(sc, 0, 13, "Boat: Hull ");
    x = putInt(sc, x, 13, p.field.boat[world.BOAT_HULL]);
    x = put(sc, x, 13, " Speed ");
    x = putInt(sc, x, 13, p.field.boat[world.BOAT_SPEED]);
    x = put(sc, x, 13, " Cargo ");
    x = putInt(sc, x, 13, p.field.boat[world.BOAT_CARGO]);
    x = put(sc, x, 13, " Oxygen ");
    x = putInt(sc, x, 13, p.field.boat[world.BOAT_OXYGEN]);
    x = put(sc, x, 13, " Precision ");
    _ = putInt(sc, x, 13, p.field.boat[world.BOAT_PRECISION]);

    _ = put(sc, 0, 15, score.TITLE_LAST_RUN);

    x = put(sc, 0, 16, "Cycles: ");
    _ = putInt(sc, x, 16, p.last.cycles);

    x = put(sc, 0, 17, "Phase 2: ");
    _ = put(sc, x, 17, score.identityLabel(p.last.phase2));

    x = put(sc, 0, 18, "Outcome: ");
    _ = put(sc, x, 18, score.outcomeLabel(p.last.outcome));

    x = put(sc, 0, 19, "Actions: ");
    _ = putInt(sc, x, 19, p.last.actions);

    x = put(sc, 0, 20, "Hull spent: ");
    _ = putInt(sc, x, 20, p.last.hull_spent);

    x = put(sc, 0, 21, "Boss kills: ");
    _ = putInt(sc, x, 21, p.last.boss_kills);

    _ = put(sc, 0, 23, score.CLOSING);
}

pub fn renderCredits(sc: *Screen) void {
    clear(sc);
    var i: usize = 0;
    while (i < score.CREDITS_LINES.len) : (i += 1) {
        const line = score.CREDITS_LINES[i];
        const width: i32 = @intCast(i32, line.len);
        const cols: i32 = @intCast(i32, COLS);
        const x: i32 = (cols - width) / 2;
        _ = put(sc, x, 10 + @intCast(i32, i), line);
    }
    _ = put(sc, 0, ROWS - 1, "[?] Help");
}

fn putCosmeticName(sc: *Screen, x: i32, y: i32, index: i32) i32 {
    if (index < 0 or index >= def.MAX_COSMETICS) return put(sc, x, y, "none");
    const rows = tables.cosmetics();
    if (@intCast(usize, index) >= rows.len) return put(sc, x, y, "none");
    return put(sc, x, y, rows[@intCast(usize, index)].name);
}

// Boat summary used by `--dump-grid --screen boat`; the decorated pixel boat
// itself is drawn by render_art in art mode (and inside the Field Record).
pub fn renderBoat(w: *const def.World, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  BOAT");
    _ = put(sc, 71, 0, "[?] Help");

    var x = put(sc, 0, 2, "Paint: ");
    _ = put(sc, x, 2, boat.paintName(boat.paintIndex(w)));

    x = put(sc, 0, 3, "Figurehead: ");
    x = putCosmeticName(sc, x, 3, boat.figureheadIndex(w));

    x = put(sc, 0, 4, "Flag: ");
    x = putCosmeticName(sc, x, 4, boat.flagIndex(w));

    x = put(sc, 0, 5, "Decal: ");
    _ = putCosmeticName(sc, x, 5, boat.decalIndex(w));

    x = put(sc, 0, 7, "Boat: Hull ");
    x = putInt(sc, x, 7, w.boat[world.BOAT_HULL]);
    x = put(sc, x, 7, " Speed ");
    x = putInt(sc, x, 7, w.boat[world.BOAT_SPEED]);
    x = put(sc, x, 7, " Cargo ");
    x = putInt(sc, x, 7, w.boat[world.BOAT_CARGO]);
    x = put(sc, x, 7, " Oxygen ");
    x = putInt(sc, x, 7, w.boat[world.BOAT_OXYGEN]);
    x = put(sc, x, 7, " Precision ");
    _ = putInt(sc, x, 7, w.boat[world.BOAT_PRECISION]);

    _ = put(sc, 0, 9, "Highest owned cosmetic per slot is shown in art mode.");
}

// ---- First run / menu / save error (§20, §32, §33) ------------------------

// manual.1 is literal text: '\n' is a line break and '\n\n' a paragraph
// break. Long lines wrap at 80 columns through the shared text-block helper
// so no authored prose is clipped.
pub fn renderLore(text: []const u8, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  LORE");
    render_text.putTextBlockWidth(sc, 2, text, ROWS - 2, COLS);
    _ = put(sc, 0, ROWS - 1, "[Enter] Begin  [?] Help");
}

pub fn renderMenu(sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  MAIN MENU");
    _ = put(sc, 2, 3, "[C]ontinue");
    _ = put(sc, 2, 4, "[N]ew Game");
    _ = put(sc, 2, 5, "[O]ptions (unavailable until M12)");
    _ = put(sc, 2, 6, "[Q]uit");
    _ = put(sc, 0, ROWS - 1, "[?] Help");
}

pub fn renderSaveError(reason: []const u8, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  SAVE ERROR");
    _ = put(sc, 2, 3, reason);
    _ = put(sc, 2, 6, "[F]resh  [B]ackup slot  [Q]uit  [?] Help");
}

// Row-major text dump (trailing spaces trimmed, '\n' after every row) for the
// headless render smoke and future cell-grid goldens.
pub fn dump(sc: *const Screen, out: []u8) []const u8 {
    var p: usize = 0;
    var y: usize = 0;
    while (y < ROWS) : (y += 1) {
        const start = p;
        var x: usize = 0;
        while (x < COLS and p < out.len) : (x += 1) {
            out[p] = sc.cells[y * COLS + x];
            p += 1;
        }
        while (p > start and out[p - 1] == ZERO) p -= 1;
        if (p < out.len) {
            out[p] = 10;
            p += 1;
        }
    }
    return out[0..p];
}
