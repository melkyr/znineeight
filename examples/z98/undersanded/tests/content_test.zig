// content_test.zig — T1 content schema and row completeness (spec §14.2,
// §14.4, §25.1, §25.2).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/content_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/content_test"
//   "$OUT/content_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const creatures = @import("../creatures_t1.zig");
const tables = @import("../tables_t1.zig");
const world = @import("../world.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

// Expected rows are transcribed from §14.2 (names, zones, phase) and §14.4
// (drops) in DEFS order, not derived from the table under test.

const EXPECTED_NAMES = [19][]const u8{
    "Mystic Eel",
    "Mystic Electric Eel",
    "Steel Tuna",
    "Anemoniacus",
    "Freezing Perch",
    "Rust Tuna",
    "Kelp Crab",
    "Brine Jelly",
    "Chitin Barnacle",
    "Spark Anemone",
    "Mileel",
    "Tunisteel",
    "Coral Crab",
    "Abyssal Lantern-Jelly",
    "Neon Ghost-Ray",
    "Glass Squid",
    "Brine Angler",
    "Ironclad Wrasse",
    "The Derelict",
};

const EXPECTED_ZONE = [19]u32{
    3, 3, 3, 2, 4,
    7, 7, 6, 6, 3,
    2, 2, 6, 4, 4,
    4, 4, 4, 256,
};

const EXPECTED_PHASE = [19]u32{
    3, 2, 3, 3, 3,
    3, 3, 2, 3, 3,
    1, 1, 3, 2, 2,
    2, 2, 1, 3,
};

const D = def.DropLine;

fn ln(part: i32, count: i32) D {
    return D{ .part = part, .count = count };
}

const Z = D{ .part = 0, .count = 0 };
const L = def.MAX_DROP_LINES;

const SUB = [19][L]D{
    [L]D{ ln(1, 3), ln(3, 1), Z, Z, Z, Z },
    [L]D{ ln(3, 3), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(2, 3), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(6, 2), ln(5, 2), Z, Z, Z, Z },
    [L]D{ ln(4, 3), ln(2, 1), Z, Z, Z, Z },
    [L]D{ ln(2, 2), ln(1, 2), Z, Z, Z, Z },
    [L]D{ ln(5, 2), ln(1, 2), Z, Z, Z, Z },
    [L]D{ ln(4, 3), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(1, 4), ln(5, 1), Z, Z, Z, Z },
    [L]D{ ln(3, 2), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(3, 4), ln(1, 2), ln(8, 1), Z, Z, Z },
    [L]D{ ln(2, 4), ln(1, 2), ln(9, 2), Z, Z, Z },
    [L]D{ ln(5, 3), ln(1, 2), Z, Z, Z, Z },
    [L]D{ ln(6, 2), ln(4, 3), Z, Z, Z, Z },
    [L]D{ ln(6, 4), ln(4, 2), Z, Z, Z, Z },
    [L]D{ ln(7, 4), ln(4, 2), Z, Z, Z, Z },
    [L]D{ ln(6, 2), ln(4, 2), Z, Z, Z, Z },
    [L]D{ ln(2, 3), ln(5, 2), ln(7, 2), Z, Z, Z },
    [L]D{ Z, Z, Z, Z, Z, Z },
};

const KILL = [19][L]D{
    [L]D{ ln(1, 2), Z, Z, Z, Z, Z },
    [L]D{ ln(3, 1), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(2, 2), Z, Z, Z, Z, Z },
    [L]D{ ln(3, 1), ln(5, 1), Z, Z, Z, Z },
    [L]D{ ln(4, 1), ln(2, 1), Z, Z, Z, Z },
    [L]D{ ln(1, 2), Z, Z, Z, Z, Z },
    [L]D{ ln(5, 1), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(4, 1), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(1, 2), Z, Z, Z, Z, Z },
    [L]D{ ln(3, 1), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(3, 2), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(2, 2), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(5, 1), ln(1, 1), Z, Z, Z, Z },
    [L]D{ ln(6, 1), ln(4, 1), Z, Z, Z, Z },
    [L]D{ ln(6, 1), ln(4, 1), Z, Z, Z, Z },
    [L]D{ ln(7, 1), ln(4, 1), Z, Z, Z, Z },
    [L]D{ ln(6, 1), ln(4, 1), Z, Z, Z, Z },
    [L]D{ ln(2, 2), ln(5, 1), Z, Z, Z, Z },
    [L]D{ ln(2, 5), ln(3, 3), ln(6, 3), ln(7, 2), ln(5, 2), Z },
};

const OVER = [19][L]D{
    [L]D{ ln(1, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(3, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(2, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(5, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(3, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(3, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(2, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(2, 1), Z, Z, Z, Z, Z },
    [L]D{ ln(2, 2), ln(3, 1), Z, Z, Z, Z },
};

// §14.2 scalar stats in DEFS order. The boss row is included here as well as
// in tBossRow so the whole roster is checked by one table.
const EXPECTED_FAMILY = [19]i32{
    1, 1, 2, 10, 11,
    2, 3, 4, 5, 10,
    1, 2, 3, 4, 7,
    8, 9, 12, 13,
};
const EXPECTED_ROLE = [19]i32{
    1, 1, 1, 3, 3,
    1, 1, 1, 1, 1,
    2, 2, 3, 3, 3,
    3, 3, 3, 4,
};
const EXPECTED_HP = [19]i32{
    70, 80, 120, 95, 105,
    80, 100, 60, 130, 90,
    80, 140, 160, 90, 100,
    100, 110, 150, 300,
};
const EXPECTED_RES = [19]i32{
    80, 100, 70, 80, 95,
    60, 90, 110, 50, 70,
    140, 100, 120, 130, 110,
    130, 100, 140, 0,
};
const EXPECTED_SPEED = [19]i32{
    10, 16, 6, 7, 13,
    8, 8, 10, 3, 4,
    12, 5, 5, 11, 18,
    14, 9, 7, 7,
};
const EXPECTED_ATTACK = [19]i32{
    6, 7, 8, 9, 10,
    7, 7, 6, 6, 6,
    8, 9, 10, 9, 10,
    9, 10, 11, 10,
};
const EXPECTED_SUBDUE = [19]i32{
    95, 95, 95, 65, 65,
    95, 95, 95, 95, 95,
    80, 80, 60, 60, 60,
    60, 60, 60, -1,
};
const EXPECTED_SALE = [19]i32{
    20, 30, 20, 50, 55,
    15, 20, 20, 15, 20,
    40, 40, 55, 55, 60,
    65, 50, 70, 0,
};
const EXPECTED_RESPAWN_SUB = [19]i32{
    3, 3, 3, 6, 6,
    3, 3, 3, 3, 3,
    4, 4, 6, 6, 6,
    6, 6, 6, 20,
};
const EXPECTED_RESPAWN_KILL = [19]i32{
    9, 9, 9, 18, 18,
    9, 9, 9, 9, 9,
    12, 12, 18, 18, 18,
    18, 18, 18, 20,
};
const EXPECTED_RESPAWN_OVER = [19]i32{
    15, 15, 15, 30, 30,
    15, 15, 15, 15, 15,
    20, 20, 30, 30, 30,
    30, 30, 30, 40,
};

// §10 tool rows, keyed by the landed id order (id 1..7).
fn cs(kind: i32, amt: i32) def.CostSlot {
    return def.CostSlot{ .kind = kind, .amt = amt };
}

const EXPECTED_TOOLS = [_]def.ToolRow{
    .{ .id = 1, .kind = 1, .cost = [3]def.CostSlot{ cs(2, 3), cs(0, 0), cs(0, 0) } },
    .{ .id = 2, .kind = 1, .cost = [3]def.CostSlot{ cs(4, 2), cs(1, 1), cs(0, 0) } },
    .{ .id = 3, .kind = 0, .cost = [3]def.CostSlot{ cs(3, 3), cs(0, 0), cs(0, 0) } },
    .{ .id = 4, .kind = 0, .cost = [3]def.CostSlot{ cs(6, 2), cs(7, 1), cs(0, 0) } },
    .{ .id = 5, .kind = 1, .cost = [3]def.CostSlot{ cs(8, 1), cs(1, 2), cs(5, 1) } },
    .{ .id = 6, .kind = 0, .cost = [3]def.CostSlot{ cs(7, 2), cs(3, 1), cs(0, 0) } },
    .{ .id = 7, .kind = 1, .cost = [3]def.CostSlot{ cs(5, 2), cs(2, 1), cs(0, 0) } },
};

// §11 upgrade rows in the landed table order (Hull, Precision, Cargo,
// Oxygen, Speed; T1..T3 each).
const EXPECTED_UPGRADES = [_]def.UpgradeRow{
    .{ .axis = world.BOAT_HULL, .tier = 1, .cost = [3]def.CostSlot{ cs(1, 3), cs(0, 0), cs(0, 0) } },
    .{ .axis = world.BOAT_HULL, .tier = 2, .cost = [3]def.CostSlot{ cs(1, 6), cs(2, 2), cs(0, 0) } },
    .{ .axis = world.BOAT_HULL, .tier = 3, .cost = [3]def.CostSlot{ cs(1, 10), cs(2, 4), cs(0, 0) } },
    .{ .axis = world.BOAT_PRECISION, .tier = 1, .cost = [3]def.CostSlot{ cs(3, 2), cs(6, 1), cs(0, 0) } },
    .{ .axis = world.BOAT_PRECISION, .tier = 2, .cost = [3]def.CostSlot{ cs(3, 4), cs(6, 2), cs(0, 0) } },
    .{ .axis = world.BOAT_PRECISION, .tier = 3, .cost = [3]def.CostSlot{ cs(3, 8), cs(6, 2), cs(0, 0) } },
    .{ .axis = world.BOAT_CARGO, .tier = 1, .cost = [3]def.CostSlot{ cs(4, 3), cs(5, 1), cs(0, 0) } },
    .{ .axis = world.BOAT_CARGO, .tier = 2, .cost = [3]def.CostSlot{ cs(4, 6), cs(5, 2), cs(0, 0) } },
    .{ .axis = world.BOAT_CARGO, .tier = 3, .cost = [3]def.CostSlot{ cs(4, 10), cs(5, 4), cs(0, 0) } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 1, .cost = [3]def.CostSlot{ cs(5, 3), cs(4, 1), cs(0, 0) } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 2, .cost = [3]def.CostSlot{ cs(5, 6), cs(4, 2), cs(0, 0) } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 3, .cost = [3]def.CostSlot{ cs(5, 10), cs(4, 4), cs(0, 0) } },
    .{ .axis = world.BOAT_SPEED, .tier = 1, .cost = [3]def.CostSlot{ cs(7, 2), cs(3, 1), cs(0, 0) } },
    .{ .axis = world.BOAT_SPEED, .tier = 2, .cost = [3]def.CostSlot{ cs(7, 2), cs(3, 2), cs(0, 0) } },
    .{ .axis = world.BOAT_SPEED, .tier = 3, .cost = [3]def.CostSlot{ cs(7, 4), cs(3, 4), cs(9, 2) } },
};

// §11 cosmetics in item order (bit index 0..11).
const EXPECTED_COSMETIC_NAMES = [12][]const u8{
    "Foam White", "Abyss Teal", "Leviathan Black",
    "Gull Skull", "Lantern Jaw", "Derelict Cog",
    "Patched Pennant", "Reef Signal", "Trench Mark",
    "Barnacle Stamp", "Glass Squid", "Boss Sigil",
};
const EXPECTED_COSMETIC_PRICE = [12]i32{
    150, 175, 200, 150, 175, 200,
    150, 175, 200, 150, 175, 200,
};
const EXPECTED_COSMETIC_UNLOCK = [12]i32{
    1, 2, 3, 1, 2, 4,
    1, 3, 4, 2, 3, 4,
};

// §13 encounter weights in spec row order.
const ER = def.EncounterRow;

fn er(def_index: i32, weight: i32) ER {
    return ER{ .def_index = def_index, .weight = weight };
}

const EXPECTED_Z1_DAY = [5]ER{
    er(0, 30), er(2, 30), er(5, 20), er(6, 10), er(9, 10),
};
const EXPECTED_Z1_NIGHT = [5]ER{
    er(1, 40), er(0, 30), er(5, 15), er(6, 10), er(9, 5),
};
const EXPECTED_Z2_DAY = [10]ER{
    er(11, 15), er(0, 15), er(2, 10), er(5, 10), er(10, 10),
    er(6, 10), er(8, 10), er(9, 5), er(12, 5), er(3, 10),
};
const EXPECTED_Z2_NIGHT = [8]ER{
    er(1, 20), er(7, 15), er(0, 15), er(5, 10),
    er(6, 10), er(8, 10), er(12, 10), er(3, 10),
};
const EXPECTED_Z3_DAY = [6]ER{
    er(17, 20), er(12, 15), er(5, 20), er(6, 20), er(8, 15), er(4, 10),
};
const EXPECTED_Z3_NIGHT = [8]ER{
    er(12, 10), er(13, 15), er(14, 15), er(15, 10),
    er(16, 15), er(7, 15), er(8, 10), er(4, 10),
};

fn nameIs(d: *const def.CreatureDef, want: []const u8) bool {
    if (d.name_len != @intCast(i32, want.len)) return false;
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        if (d.name[i] != want[i]) return false;
    }
    return true;
}

fn namesEqual(a: *const def.CreatureDef, b: *const def.CreatureDef) bool {
    if (a.name_len != b.name_len) return false;
    var i: usize = 0;
    while (i < @intCast(usize, a.name_len)) : (i += 1) {
        if (a.name[i] != b.name[i]) return false;
    }
    return true;
}

fn tableMatches(actual: []const D, expected: []const D) bool {
    if (expected.len > def.MAX_DROP_LINES) return false;
    var i: usize = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        var want_part: i32 = 0;
        var want_count: i32 = 0;
        if (i < expected.len) {
            want_part = expected[i].part;
            want_count = expected[i].count;
        }
        if (actual[i].part != want_part) return false;
        if (actual[i].count != want_count) return false;
    }
    return true;
}

fn tNames() bool {
    if (creatures.DEFS.len != 19) return false;
    if (EXPECTED_NAMES.len != 19) return false;

    var i: usize = 0;
    while (i < 19) : (i += 1) {
        const d = creatures.DEFS[i];
        const want = EXPECTED_NAMES[i];
        if (want.len == 0) return false;
        if (want.len > def.MAX_NAME_LEN) return false;
        if (!nameIs(&d, want)) return false;

        var j: usize = 0;
        while (j < @intCast(usize, d.name_len)) : (j += 1) {
            if (d.name[j] < 0x20) return false;
            if (d.name[j] > 0x7e) return false;
        }

        var k: usize = i + 1;
        while (k < 19) : (k += 1) {
            const other = creatures.DEFS[k];
            if (namesEqual(&d, &other)) return false;
        }
    }
    return true;
}

fn tMasks() bool {
    if (creatures.DEFS.len != 19) return false;

    var i: usize = 0;
    while (i < 19) : (i += 1) {
        const d = creatures.DEFS[i];
        if (d.zone_mask != EXPECTED_ZONE[i]) return false;
        if (d.phase_mask != EXPECTED_PHASE[i]) return false;
        if (d.zone_mask == 0) return false;
        if (d.phase_mask == 0) return false;
        if ((d.phase_mask & 0x3) != d.phase_mask) return false;
    }
    return true;
}

fn tDrops() bool {
    if (creatures.DEFS.len != 19) return false;

    var i: usize = 0;
    while (i < 19) : (i += 1) {
        const d = creatures.DEFS[i];
        if (!tableMatches(d.sub[0..], SUB[i][0..])) return false;
        if (!tableMatches(d.kill[0..], KILL[i][0..])) return false;
        if (!tableMatches(d.over[0..], OVER[i][0..])) return false;
    }
    return true;
}

fn tBossRow() bool {
    if (creatures.DEFS.len != 19) return false;
    const d = creatures.DEFS[18];
    if (d.id != 17) return false;
    if (d.family != creatures.FAMILY_BOSS) return false;
    if (d.role != creatures.ROLE_BOSS) return false;
    if (d.zone_mask != 256) return false;
    if (d.phase_mask != 3) return false;
    if (d.hp != 300) return false;
    if (d.resolve != 0) return false;
    if (d.speed != 7) return false;
    if (d.attack != 10) return false;
    if (d.subdue_chance != -1) return false;
    if (d.flags != def.F_BOSS) return false;
    if (d.sale != 0) return false;
    if (d.respawn[0] != 20) return false;
    if (d.respawn[1] != 20) return false;
    if (d.respawn[2] != 40) return false;
    if (d.counter_tool != def.TOOL_PLATE) return false;
    if (d.rule_count != 0) return false;
    return true;
}

fn tStats() bool {
    if (creatures.DEFS.len != 19) return false;
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        const d = creatures.DEFS[i];
        if (d.family != EXPECTED_FAMILY[i]) return false;
        if (d.role != EXPECTED_ROLE[i]) return false;
        if (d.hp != EXPECTED_HP[i]) return false;
        if (d.resolve != EXPECTED_RES[i]) return false;
        if (d.speed != EXPECTED_SPEED[i]) return false;
        if (d.attack != EXPECTED_ATTACK[i]) return false;
        if (d.subdue_chance != EXPECTED_SUBDUE[i]) return false;
        if (d.sale != EXPECTED_SALE[i]) return false;
        if (d.respawn[0] != EXPECTED_RESPAWN_SUB[i]) return false;
        if (d.respawn[1] != EXPECTED_RESPAWN_KILL[i]) return false;
        if (d.respawn[2] != EXPECTED_RESPAWN_OVER[i]) return false;
    }
    return true;
}

fn toolEq(a: def.ToolRow, b: def.ToolRow) bool {
    if (a.id != b.id or a.kind != b.kind) return false;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (a.cost[i].kind != b.cost[i].kind) return false;
        if (a.cost[i].amt != b.cost[i].amt) return false;
    }
    return true;
}

fn tTools() bool {
    if (tables.TOOLS.len != EXPECTED_TOOLS.len) return false;
    var i: usize = 0;
    while (i < tables.TOOLS.len) : (i += 1) {
        if (!toolEq(tables.TOOLS[i], EXPECTED_TOOLS[i])) return false;
    }
    return true;
}

fn upgradeEq(a: def.UpgradeRow, b: def.UpgradeRow) bool {
    if (a.axis != b.axis or a.tier != b.tier) return false;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (a.cost[i].kind != b.cost[i].kind) return false;
        if (a.cost[i].amt != b.cost[i].amt) return false;
    }
    return true;
}

fn tUpgrades() bool {
    if (tables.UPGRADES.len != EXPECTED_UPGRADES.len) return false;
    var i: usize = 0;
    while (i < tables.UPGRADES.len) : (i += 1) {
        if (!upgradeEq(tables.UPGRADES[i], EXPECTED_UPGRADES[i])) return false;
    }
    return true;
}

fn bytesEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn tCosmetics() bool {
    if (tables.COSMETICS.len != EXPECTED_COSMETIC_NAMES.len) return false;
    var i: usize = 0;
    while (i < tables.COSMETICS.len) : (i += 1) {
        const c = tables.COSMETICS[i];
        if (!bytesEq(c.name, EXPECTED_COSMETIC_NAMES[i])) return false;
        if (c.price != EXPECTED_COSMETIC_PRICE[i]) return false;
        if (c.unlock != EXPECTED_COSMETIC_UNLOCK[i]) return false;
    }
    return true;
}

fn encRowsMatch(zone: i32, phase: i32, expected: []const def.EncounterRow) bool {
    const rows = tables.rows(zone, phase);
    if (rows.len != expected.len) return false;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (rows[i].def_index != expected[i].def_index) return false;
        if (rows[i].weight != expected[i].weight) return false;
    }
    return true;
}

fn tEncounters() bool {
    if (!encRowsMatch(0, 0, EXPECTED_Z1_DAY[0..])) return false;
    if (!encRowsMatch(0, 1, EXPECTED_Z1_NIGHT[0..])) return false;
    if (!encRowsMatch(1, 0, EXPECTED_Z2_DAY[0..])) return false;
    if (!encRowsMatch(1, 1, EXPECTED_Z2_NIGHT[0..])) return false;
    if (!encRowsMatch(2, 0, EXPECTED_Z3_DAY[0..])) return false;
    if (!encRowsMatch(2, 1, EXPECTED_Z3_NIGHT[0..])) return false;
    return true;
}

fn tZonesAndD() bool {
    const want_cost = [12]i32{ 1, 2, 3, 3, 4, 4, 5, 5, 5, 0, 0, 0 };
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        if (tables.zoneCost(@intCast(i32, i)) != want_cost[i]) return false;
        const want_boss: i32 = if (i == 8) 1 else 0;
        if (tables.zoneIsBoss(@intCast(i32, i)) != want_boss) return false;
    }
    // Zone D is boss-only: no encounter rows in either phase.
    if (tables.rows(8, 0).len != 0) return false;
    if (tables.rows(8, 1).len != 0) return false;
    return true;
}

fn tTablesBudget() bool {
    // P26/C1 raises MAX_DROP_LINES 4 -> 6 (three 6-slot tables per row), so
    // the fixed 56-row Tables image grows from ≈32 KB to ≈34 KB.
    if (@sizeOf(def.Tables) > 36 * 1024) return false;
    if (@sizeOf(def.CreatureDef) > 332) return false;
    return true;
}

pub fn main() void {
    report("creature_names_nonempty_unique_24", tNames());
    report("creature_masks_match_s14_2", tMasks());
    report("creature_drops_match_s14_4", tDrops());
    report("boss_row_pins_s14_2_fields", tBossRow());
    report("creature_scalars_match_s14_2", tStats());
    report("tools_match_s10", tTools());
    report("upgrades_match_s11", tUpgrades());
    report("cosmetics_match_s11", tCosmetics());
    report("encounters_match_s13", tEncounters());
    report("zones_and_zone_d_match_s12", tZonesAndD());
    report("tables_size_within_budget", tTablesBudget());

    if (fails != 0) os.exit(1);
    io.write("content_test PASS\n");
}
