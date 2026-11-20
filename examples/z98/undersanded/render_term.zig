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
const dock = @import("dock.zig");
const items = @import("items.zig");
const economy = @import("economy.zig");
const save_ux = @import("save_ux.zig");
const journal = @import("journal.zig");
const data = @import("data.zig");
const render_text = @import("render_text.zig");

pub const COLS: usize = render_text.COLS;
pub const ROWS: usize = render_text.ROWS;
pub const CELLS: usize = render_text.CELLS;

pub const BAR_WIDTH: i32 = 20;
pub const LOG_LINES: i32 = 8;

pub const Screen = render_text.Screen;

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

fn keyIntInto(prefix: []const u8, n: i32, out: []u8) []const u8 {
    return render_text.keyIntInto(prefix, n, out);
}

pub fn speedRevealed(s: *const def.GameState) bool {
    return render_text.speedRevealed(s);
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

fn putBar(sc: *Screen, y: i32, label: []const u8, value: i32, max: i32) void {
    var x = put(sc, 0, y, label);
    x = put(sc, x, y, " [");
    const fill = barFill(value, max, BAR_WIDTH);
    var i: i32 = 0;
    while (i < BAR_WIDTH) : (i += 1) {
        if (i < fill) {
            putChar(sc, x + i, y, FILL);
        } else {
            putChar(sc, x + i, y, EMPTY);
        }
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
        _ = putInt(sc, x, 1, effectiveSpeed(s, d));
    } else {
        _ = put(sc, x, 1, "??");
    }

    putBar(sc, 3, "HP     ", s.fight.hp, s.fight.max_hp);
    putBar(sc, 4, "RESOLVE", s.fight.res, s.fight.max_res);
    putBar(sc, 5, "HULL   ", s.fight.hull, s.fight.max_hull);

    renderToolStatus(sc, s, 6);

    renderLog(sc, s, d, 7);

    _ = put(sc, 0, 15, "[S]trike [R]estrain [E]quipment [F]lee");
}

// ---- Dock / map / node screens (§12, §16, §26) ---------------------------

const BOSS_ZONE: i32 = 8;
const BOSS_SEEN_GATE: i32 = 6;
const ROLE_BOSS: i32 = 4;

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

fn seenMaskHas(s: *const def.GameState, d: i32) bool {
    if (d < 0) return false;
    const word: usize = @intCast(usize, d / 32);
    if (word >= 2) return false;
    const bit: u32 = @intCast(u32, d % 32);
    const m: u32 = @intCast(u32, 1) << bit;
    return (s.world.seen_mask[word] & m) != 0;
}

// Distinct non-boss creatures seen: count set bits in seen_mask over DEFS rows
// whose role is not boss. Boss rows have no role constant in T1; §9.1 fixes the
// boss role value at 4 (T1 DEFS only carry roles 1..3).
pub fn seenNonBossCount(s: *const def.GameState) i32 {
    var n: i32 = 0;
    var i: i32 = 0;
    while (i < creatures.defCount()) : (i += 1) {
        const d = creatures.defAt(i);
        if (d.role == ROLE_BOSS) continue;
        if (seenMaskHas(s, i)) n += 1;
    }
    return n;
}

pub fn bossGateOpen(s: *const def.GameState) bool {
    return seenNonBossCount(s) >= BOSS_SEEN_GATE;
}

pub fn fightsLeft(s: *const def.GameState) i32 {
    var left = world.maxFights(&s.world) - s.exp.fight_index;
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

fn materialName(m: i32) []const u8 {
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


fn axisName(axis: i32) []const u8 {
    switch (axis) {
        0 => return "Hull",
        1 => return "Speed",
        2 => return "Cargo",
        3 => return "Oxygen",
        4 => return "Precision",
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

fn putUpgradeCost(sc: *Screen, x: i32, y: i32, cost: [3]def.CostSlot) i32 {
    var p = x;
    var any = false;
    var i: usize = 0;
    while (i < cost.len) : (i += 1) {
        if (cost[i].kind <= 0 or cost[i].amt <= 0) continue;
        if (any) p = put(sc, p, y, ", ");
        any = true;
        if (cost[i].kind >= economy.MAT_CHITIN and cost[i].kind <= economy.MAT_GLASS) {
            p = put(sc, p, y, materialName(cost[i].kind));
        } else {
            p = put(sc, p, y, partName(cost[i].kind));
        }
        p = put(sc, p, y, " x");
        p = putInt(sc, p, y, cost[i].amt);
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

pub fn renderDock(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK");

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
    if (journal.journalHasNew(&s.world)) {
        _ = put(sc, 0, 11, "New journal entry - [J]ournal");
    }
    _ = put(sc, 0, 12, "Hint: Hull persists between trips; dock Rest is safe.");
    if (save_ux.canSave(s)) |reason| {
        var sx = put(sc, 0, 13, "[Esc] Save - ");
        _ = put(sc, sx, 13, reason);
    } else {
        _ = put(sc, 0, 13, "[Esc] Save");
    }
}

pub fn renderRefine(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - REFINE");
    _ = put(sc, 0, 1, "Convert all parts of one type. Rare batches need a second press.");

    var m: i32 = 1;
    while (m <= 7) : (m += 1) {
        const y = 3 + m - 1;
        var x = putInt(sc, 0, y, m);
        x = put(sc, x, y, " ");
        x = put(sc, x, y, partName(m));
        x = put(sc, x, y, " x");
        x = putInt(sc, x, y, dock.refineParts(s, m));
        x = put(sc, x, y, " -> ");
        x = putInt(sc, x, y, dock.refineParts(s, m) * dock.refinePerPart(s, m));
        x = put(sc, x, y, " ");
        x = put(sc, x, y, materialName(m));
        x = put(sc, x, y, " (E");
        x = putInt(sc, x, y, s.world.expertise[@intCast(usize, m)]);
        x = put(sc, x, y, ", ");
        x = putInt(sc, x, y, dock.refinePerPart(s, m));
        _ = put(sc, x, y, "/part)");
    }

    _ = put(sc, 0, 12, "[1-7] Refine material  [Esc] Back");
}

pub fn renderUpgrade(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - UPGRADE");
    _ = put(sc, 0, 1, "Buy the next tier of one axis (T2 needs E2, T3 needs E4).");

    var axis: i32 = 0;
    while (axis < 5) : (axis += 1) {
        const y = 3 + axis;
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
            var cost: [3]economy.MaterialAmt = [3]economy.MaterialAmt{
                .{ .kind = 0, .amt = 0 },
                .{ .kind = 0, .amt = 0 },
                .{ .kind = 0, .amt = 0 },
            };
            economy.upgradeCost(axis, tier + 1, &cost);
            var slots: [3]def.CostSlot = [3]def.CostSlot{
                .{ .kind = 0, .amt = 0 },
                .{ .kind = 0, .amt = 0 },
                .{ .kind = 0, .amt = 0 },
            };
            var i: usize = 0;
            while (i < 3) : (i += 1) {
                slots[i] = def.CostSlot{ .kind = cost[i].kind, .amt = cost[i].amt };
            }
            _ = putUpgradeCost(sc, x, y, slots);
        }
    }

    _ = put(sc, 0, 10, "[1-5] Upgrade axis  [Esc] Back");
}

pub fn renderCraft(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - CRAFT");
    _ = put(sc, 0, 1, "Build one tool from parts; owned forever.");

    const rows = tables.tools();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const row = rows[i];
        const y = 3 + @intCast(i32, i);
        var x = putInt(sc, 0, y, row.id);
        x = put(sc, x, y, " ");
        x = put(sc, x, y, toolName(row.id));
        x = put(sc, x, y, " [");
        x = put(sc, x, y, toolKindName(row.kind));
        x = put(sc, x, y, "] ");
        x = putCost(sc, x, y, row.cost);
        if (items.toolOwned(&s.world, row.id)) _ = put(sc, x, y, " (owned)");
    }

    _ = put(sc, 0, 12, "[1-7] Craft tool  [Esc] Back");
}

fn cosmeticKey(index: i32) u8 {
    if (index < 9) return @intCast(u8, '1' + index);
    return @intCast(u8, 'a' + (index - 9));
}

pub fn renderBuy(s: *const def.GameState, sc: *Screen) void {
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
        if (dock.cosmeticOwned(&s.world, idx)) {
            _ = put(sc, p, y, " (owned)");
        } else if (!dock.cosmeticUnlocked(&s.world, idx)) {
            _ = put(sc, p, y, " (locked)");
        } else {
            _ = put(sc, p, y, " (available)");
        }
    }

    _ = put(sc, 0, 16, "[1-9,a-c] Buy cosmetic  [Esc] Back");
}

pub fn renderTools(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  DOCK - EQUIP");
    var x = put(sc, 0, 1, "Selected: ");
    _ = put(sc, x, 1, toolName(s.world.tool_selected));

    var id: i32 = 1;
    while (id <= 7) : (id += 1) {
        const y = 3 + id - 1;
        var p = putInt(sc, 0, y, id);
        p = put(sc, p, y, " ");
        p = put(sc, p, y, toolName(id));
        if (s.world.tool_selected == id) {
            p = put(sc, p, y, " *selected*");
        }
        if (!items.toolOwned(&s.world, id)) {
            _ = put(sc, p, y, " (not owned)");
        }
    }

    _ = put(sc, 0, 12, "[1-7] Select tool  [0] None  [Esc] Back");
}


fn renderMapRow(s: *const def.GameState, sc: *Screen, zone: i32, y: i32) void {
    var x = put(sc, 0, y, zoneTag(zone));
    x = padTo(sc, x, y, 4);
    x = put(sc, x, y, zoneName(zone));
    x = padTo(sc, x, y, 24);
    x = putInt(sc, x, y, tables.zoneCost(zone));
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

pub fn renderMap(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  MAP");
    _ = put(sc, 0, 1, "Zone ladder (travel phases each way):");

    var zone: i32 = 0;
    var y: i32 = 3;
    while (zone <= BOSS_ZONE) : (zone += 1) {
        renderMapRow(s, sc, zone, y);
        y += 1;
    }

    var x = put(sc, 0, 13, "Seen non-boss: ");
    x = putInt(sc, x, 13, seenNonBossCount(s));
    x = put(sc, x, 13, "/");
    _ = putInt(sc, x, 13, BOSS_SEEN_GATE);

    _ = put(sc, 0, 15, "[1-8] Z1-Z8  [9] Boss  [Esc] Back");
}

// ---- Secured line (§7) ----------------------------------------------------

fn isKeystonePart(part: i32) bool {
    return part == creatures.PART_HOOKED_BARBEL or part == creatures.PART_STEEL_FINS;
}

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
        if (isKeystonePart(lines[p].part)) continue;
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
pub fn renderJournal(s: *const def.GameState, sel: i32, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  JOURNAL");

    if (sel > 0) {
        const d = sel - 1;
        var x = put(sc, 0, 1, "Entry ");
        x = putInt(sc, x, 1, sel);
        x = put(sc, x, 1, ": ");
        if (d >= 0 and d < creatures.defCount()) {
            var cdef = creatures.defAt(d);
            _ = put(sc, x, 1, creatureName(&cdef));
        }
        var key_buf: [24]u8 = undefined;
        const key = journal.journalKey(d, key_buf[0..]);
        if (data.textFind(key)) |text| {
            putTextBlock(sc, 3, text, ROWS - 2);
        } else {
            _ = put(sc, 0, 3, "(entry text unavailable)");
        }
        _ = put(sc, 0, ROWS - 1, "[Esc] Back to journal");
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
        if (journal.journalUnlocked(&s.world, d)) {
            var cdef = creatures.defAt(d);
            x = put(sc, x, y, creatureName(&cdef));
            if (!journal.journalViewed(&s.world, d)) {
                _ = put(sc, x, y, "  *NEW*");
            }
        } else {
            _ = put(sc, x, y, "- unrecorded -");
        }
    }

    _ = put(sc, 0, ROWS - 1, "[1-9,a-j] Read  [Esc] Back");
}

pub fn renderHelp(text: []const u8, sc: *Screen) void {
    render_text.renderHelp(text, sc);
}



pub fn renderNode(s: *const def.GameState, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  NODE");
    _ = put(sc, 0, 2, zoneName(s.exp.zone));

    var x = put(sc, 0, 4, "Fights left ");
    _ = putInt(sc, x, 4, fightsLeft(s));

    x = put(sc, 0, 5, "Hull ");
    x = putInt(sc, x, 5, s.world.hull);
    x = put(sc, x, 5, "/");
    _ = putInt(sc, x, 5, world.hullMax(&s.world));

    var sbuf: [128]u8 = undefined;
    const secured = securedLine(s, sbuf[0..]);
    if (secured.len > 0) {
        _ = put(sc, 0, 6, secured);
    }

    if (s.fight.outcome == def.OUT_SUBDUE and s.fight.def_index != def.NO_FIGHT) {
        _ = put(sc, 0, 7, "[R]elease  [S]ell");
    } else {
        _ = put(sc, 0, 7, "[H]unt [R]est [S]urface");
    }
    _ = put(sc, 0, 9, "Hint: Rest at a node risks rough sleep unless the pool is empty.");

    var zkey: [24]u8 = undefined;
    const ztext = keyIntInto("zone.", s.exp.zone + 1, zkey[0..]);
    if (data.textFind(ztext)) |flavour| {
        putTextBlock(sc, 11, flavour, ROWS - 1);
    }
}

// ---- First run / menu / save error (§20, §32, §33) ------------------------

// manual.1 is literal text: '\n' is one line break, '\n\n' is a paragraph
// break (one blank row). Never re-wrap; a long line clips at the 80-column
// frame edge.
pub fn renderLore(text: []const u8, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  LORE");

    var i: usize = 0;
    var x: i32 = 0;
    var y: i32 = 2;
    while (i < text.len and y < ROWS - 2) {
        const c = text[i];
        if (c == '\r') {
            i += 1;
            continue;
        }
        if (c == '\n') {
            if (i + 1 < text.len and text[i + 1] == '\n') {
                y += 2;
                i += 2;
            } else {
                y += 1;
                i += 1;
            }
            x = 0;
            continue;
        }
        if (x < COLS) putChar(sc, x, y, c);
        x += 1;
        i += 1;
    }

    _ = put(sc, 0, ROWS - 1, "[Enter] Begin");
}

pub fn renderMenu(sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  MAIN MENU");
    _ = put(sc, 2, 3, "[C]ontinue");
    _ = put(sc, 2, 4, "[N]ew Game");
    _ = put(sc, 2, 5, "[O]ptions (unavailable until M12)");
    _ = put(sc, 2, 6, "[Q]uit");
}

pub fn renderSaveError(reason: []const u8, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  SAVE ERROR");
    _ = put(sc, 2, 3, reason);
    _ = put(sc, 2, 6, "[F]resh  [B]ackup slot  [Q]uit");
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
