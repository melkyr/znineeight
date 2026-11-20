// tables_t1.zig — T1 encounter weights (spec §13).
//
// Rows are `{ dense DEFS index, weight }`; the dense indices map to the
// roster in creatures_t1.zig (M2 rows 0..4 keep their positions, then the 13
// M4 rows at 5..17). Z1-Z3 carry the §13 tables; Z4..Z11 are empty stubs
// until M13. Base weights sum to 100 per zone/phase (commons + rares).

const def = @import("def.zig");
const world = @import("world.zig");

pub const PHASE_DAY: i32 = 0;
pub const PHASE_NIGHT: i32 = 1;

// ---- §12 travel-cost ladder ----------------------------------------------
//
// Travel phases each way per zone. Z1..Z8 then the boss route D at index 8;
// unused slots are 0. Boss detection is a flag column so callers never spell
// the dense index.
pub const ZONE_COST: [def.MAX_ZONES]i32 = .{ 1, 2, 3, 3, 4, 4, 5, 5, 5, 0, 0, 0 };
pub const ZONE_IS_BOSS: [def.MAX_ZONES]i32 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0 };

pub const EMPTY = [0]def.EncounterRow{};

// ---- Z1 — The Shallows (rare chance 0%) ----------------------------------

pub const Z1_DAY = [_]def.EncounterRow{
    def.EncounterRow{ .def_index = 0, .weight = 30 }, // Mystic Eel
    def.EncounterRow{ .def_index = 2, .weight = 30 }, // Steel Tuna
    def.EncounterRow{ .def_index = 5, .weight = 20 }, // Rust Tuna
    def.EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    def.EncounterRow{ .def_index = 9, .weight = 10 }, // Spark Anemone
};

pub const Z1_NIGHT = [_]def.EncounterRow{
    def.EncounterRow{ .def_index = 1, .weight = 40 }, // Mystic Electric Eel
    def.EncounterRow{ .def_index = 0, .weight = 30 }, // Mystic Eel
    def.EncounterRow{ .def_index = 5, .weight = 15 }, // Rust Tuna
    def.EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    def.EncounterRow{ .def_index = 9, .weight = 5 }, // Spark Anemone
};

// ---- Z2 — The Reef --------------------------------------------------------

pub const Z2_DAY = [_]def.EncounterRow{
    def.EncounterRow{ .def_index = 11, .weight = 15 }, // Tunisteel (named)
    def.EncounterRow{ .def_index = 0, .weight = 15 }, // Mystic Eel
    def.EncounterRow{ .def_index = 2, .weight = 10 }, // Steel Tuna
    def.EncounterRow{ .def_index = 5, .weight = 10 }, // Rust Tuna
    def.EncounterRow{ .def_index = 10, .weight = 10 }, // Mileel (named)
    def.EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    def.EncounterRow{ .def_index = 8, .weight = 10 }, // Chitin Barnacle
    def.EncounterRow{ .def_index = 9, .weight = 5 }, // Spark Anemone
    def.EncounterRow{ .def_index = 12, .weight = 5 }, // Coral Crab (rare)
    def.EncounterRow{ .def_index = 3, .weight = 10 }, // Anemoniacus (rare)
};

pub const Z2_NIGHT = [_]def.EncounterRow{
    def.EncounterRow{ .def_index = 1, .weight = 20 }, // Mystic Electric Eel
    def.EncounterRow{ .def_index = 7, .weight = 15 }, // Brine Jelly
    def.EncounterRow{ .def_index = 0, .weight = 15 }, // Mystic Eel
    def.EncounterRow{ .def_index = 5, .weight = 10 }, // Rust Tuna
    def.EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    def.EncounterRow{ .def_index = 8, .weight = 10 }, // Chitin Barnacle
    def.EncounterRow{ .def_index = 12, .weight = 10 }, // Coral Crab (rare)
    def.EncounterRow{ .def_index = 3, .weight = 10 }, // Anemoniacus (rare)
};

// ---- Z3 — Trench-Edge -----------------------------------------------------

pub const Z3_DAY = [_]def.EncounterRow{
    def.EncounterRow{ .def_index = 17, .weight = 20 }, // Ironclad Wrasse (rare)
    def.EncounterRow{ .def_index = 12, .weight = 15 }, // Coral Crab (rare)
    def.EncounterRow{ .def_index = 5, .weight = 20 }, // Rust Tuna
    def.EncounterRow{ .def_index = 6, .weight = 20 }, // Kelp Crab
    def.EncounterRow{ .def_index = 8, .weight = 15 }, // Chitin Barnacle
    def.EncounterRow{ .def_index = 4, .weight = 10 }, // Freezing Perch (rare)
};

pub const Z3_NIGHT = [_]def.EncounterRow{
    def.EncounterRow{ .def_index = 12, .weight = 10 }, // Coral Crab (rare)
    def.EncounterRow{ .def_index = 13, .weight = 15 }, // Abyssal Lantern-Jelly (rare)
    def.EncounterRow{ .def_index = 14, .weight = 15 }, // Neon Ghost-Ray (rare)
    def.EncounterRow{ .def_index = 15, .weight = 10 }, // Glass Squid (rare)
    def.EncounterRow{ .def_index = 16, .weight = 15 }, // Brine Angler (rare)
    def.EncounterRow{ .def_index = 7, .weight = 15 }, // Brine Jelly
    def.EncounterRow{ .def_index = 8, .weight = 10 }, // Chitin Barnacle
    def.EncounterRow{ .def_index = 4, .weight = 10 }, // Freezing Perch (rare)
};

pub fn fallbackRows(zone: i32, phase: i32) []const def.EncounterRow {
    switch (zone) {
        0 => {
            if (phase == PHASE_NIGHT) return Z1_NIGHT[0..];
            return Z1_DAY[0..];
        },
        1 => {
            if (phase == PHASE_NIGHT) return Z2_NIGHT[0..];
            return Z2_DAY[0..];
        },
        2 => {
            if (phase == PHASE_NIGHT) return Z3_NIGHT[0..];
            return Z3_DAY[0..];
        },
        else => return EMPTY[0..],
    }
}

pub fn rows(zone: i32, phase: i32) []const def.EncounterRow {
    if (def.content_override) |t| {
        if (zone < 0 or zone >= def.MAX_ZONES or phase < 0 or phase > 1) {
            return EMPTY[0..];
        }
        const ci: usize = @intCast(usize, zone) * 2 + @intCast(usize, phase);
        const base: usize = @intCast(usize, zone) * 2 * def.MAX_ENCOUNTER +
            @intCast(usize, phase) * def.MAX_ENCOUNTER;
        const n: usize = @intCast(usize, t.enc_count[ci]);
        return t.encounters[base .. base + n];
    }
    return fallbackRows(zone, phase);
}

pub fn tools() []const def.ToolRow {
    if (def.content_override) |t| {
        const n: usize = @intCast(usize, t.tool_count);
        return t.tools[0..n];
    }
    return TOOLS[0..];
}

pub fn upgrades() []const def.UpgradeRow {
    if (def.content_override) |t| {
        const n: usize = @intCast(usize, t.upgrade_count);
        return t.upgrades[0..n];
    }
    return UPGRADES[0..];
}

pub fn cosmetics() []const def.CosmeticRow {
    if (def.content_override) |t| {
        const n: usize = @intCast(usize, t.cosmetic_count);
        return t.cosmetics[0..n];
    }
    return COSMETICS[0..];
}

pub fn zoneCost(i: i32) i32 {
    if (i < 0 or i >= @intCast(i32, def.MAX_ZONES)) return 0;
    if (def.content_override) |t| return t.zone_cost[@intCast(usize, i)];
    return ZONE_COST[@intCast(usize, i)];
}

pub fn zoneIsBoss(i: i32) i32 {
    if (i < 0 or i >= @intCast(i32, def.MAX_ZONES)) return 0;
    if (def.content_override) |t| return t.zone_boss[@intCast(usize, i)];
    return ZONE_IS_BOSS[@intCast(usize, i)];
}

// ---- §10 tools -----------------------------------------------------------
//
// Tool ids match `def.TOOL_*` counter-tool ids. Costs are keystone
// parts as-is; material ids are the §14.1 source part ids (R7).

// Two-field cost slot for the dock tables. `kind` 0 = unused slot;
// otherwise a part id (1..9).

fn slot(kind: i32, amt: i32) def.CostSlot {
    return def.CostSlot{ .kind = kind, .amt = amt };
}

const NONE_SLOT = def.CostSlot{ .kind = 0, .amt = 0 };

pub const TOOLS = [_]def.ToolRow{
    // Steel Plate Tool | Rigged | Plate Scrap ×3
    .{ .id = 1, .kind = def.TOOL_KIND_RIGGED, .cost = [3]def.CostSlot{ slot(2, 3), NONE_SLOT, NONE_SLOT } },
    // Brine Net | Rigged | Brine Vial ×2, Shell Chip ×1
    .{ .id = 2, .kind = def.TOOL_KIND_RIGGED, .cost = [3]def.CostSlot{ slot(4, 2), slot(1, 1), NONE_SLOT } },
    // Electric Gland | Activated | Gland Sac ×3
    .{ .id = 3, .kind = def.TOOL_KIND_ACTIVATED, .cost = [3]def.CostSlot{ slot(3, 3), NONE_SLOT, NONE_SLOT } },
    // Bioluminescent Lure | Activated | Glow Polyp ×2, Glass Pane ×1
    .{ .id = 4, .kind = def.TOOL_KIND_ACTIVATED, .cost = [3]def.CostSlot{ slot(6, 2), slot(7, 1), NONE_SLOT } },
    // Pressure Hook | Rigged | Hooked Barbel ×1, Shell Chip ×2, Coral Bud ×1
    .{ .id = 5, .kind = def.TOOL_KIND_RIGGED, .cost = [3]def.CostSlot{ slot(8, 1), slot(1, 2), slot(5, 1) } },
    // Sonar Ping | Activated | Glass Pane ×2, Gland Sac ×1
    .{ .id = 6, .kind = def.TOOL_KIND_ACTIVATED, .cost = [3]def.CostSlot{ slot(7, 2), slot(3, 1), NONE_SLOT } },
    // Coral Shield | Rigged | Coral Bud ×2, Plate Scrap ×1
    .{ .id = 7, .kind = def.TOOL_KIND_RIGGED, .cost = [3]def.CostSlot{ slot(5, 2), slot(2, 1), NONE_SLOT } },
};

// ---- §11 upgrade costs ---------------------------------------------------
//
// One row per axis/tier; `axis` uses the `World.boat` indexes (the same
// indexes dock Upgrade applies). Material ids follow R7: 1 Chitin, 2 Steel
// Plate, 3 Gland, 4 Brine, 5 Coral, 6 Luminescence, 7 Glass; 8/9 are the
// Hooked Barbel / Steel Fins keystone parts.

pub const UPGRADES = [_]def.UpgradeRow{
    // Hull
    .{ .axis = world.BOAT_HULL, .tier = 1, .cost = [3]def.CostSlot{ slot(1, 3), NONE_SLOT, NONE_SLOT } },
    .{ .axis = world.BOAT_HULL, .tier = 2, .cost = [3]def.CostSlot{ slot(1, 6), slot(2, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_HULL, .tier = 3, .cost = [3]def.CostSlot{ slot(1, 10), slot(2, 4), NONE_SLOT } },
    // Precision
    .{ .axis = world.BOAT_PRECISION, .tier = 1, .cost = [3]def.CostSlot{ slot(3, 2), slot(6, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_PRECISION, .tier = 2, .cost = [3]def.CostSlot{ slot(3, 4), slot(6, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_PRECISION, .tier = 3, .cost = [3]def.CostSlot{ slot(3, 8), slot(6, 2), NONE_SLOT } },
    // Cargo
    .{ .axis = world.BOAT_CARGO, .tier = 1, .cost = [3]def.CostSlot{ slot(4, 3), slot(5, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_CARGO, .tier = 2, .cost = [3]def.CostSlot{ slot(4, 6), slot(5, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_CARGO, .tier = 3, .cost = [3]def.CostSlot{ slot(4, 10), slot(5, 4), NONE_SLOT } },
    // Oxygen
    .{ .axis = world.BOAT_OXYGEN, .tier = 1, .cost = [3]def.CostSlot{ slot(5, 3), slot(4, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 2, .cost = [3]def.CostSlot{ slot(5, 6), slot(4, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 3, .cost = [3]def.CostSlot{ slot(5, 10), slot(4, 4), NONE_SLOT } },
    // Speed
    .{ .axis = world.BOAT_SPEED, .tier = 1, .cost = [3]def.CostSlot{ slot(7, 2), slot(3, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_SPEED, .tier = 2, .cost = [3]def.CostSlot{ slot(7, 2), slot(3, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_SPEED, .tier = 3, .cost = [3]def.CostSlot{ slot(7, 4), slot(3, 4), slot(9, 2) } },
};

// ---- §11 cosmetics -------------------------------------------------------
//
// Twelve fixed items in §11 order (bit 0..11). Prices total 2,100 coins.
// Unlock milestones: zone-first-arrival bits (set by M5) or Derelict kill.

pub const COSMETICS = [_]def.CosmeticRow{
    .{ .name = "Foam White", .price = 150, .unlock = def.UNLOCK_Z1 },
    .{ .name = "Abyss Teal", .price = 175, .unlock = def.UNLOCK_Z2 },
    .{ .name = "Leviathan Black", .price = 200, .unlock = def.UNLOCK_Z3 },
    .{ .name = "Gull Skull", .price = 150, .unlock = def.UNLOCK_Z1 },
    .{ .name = "Lantern Jaw", .price = 175, .unlock = def.UNLOCK_Z2 },
    .{ .name = "Derelict Cog", .price = 200, .unlock = def.UNLOCK_DERELICT },
    .{ .name = "Patched Pennant", .price = 150, .unlock = def.UNLOCK_Z1 },
    .{ .name = "Reef Signal", .price = 175, .unlock = def.UNLOCK_Z3 },
    .{ .name = "Trench Mark", .price = 200, .unlock = def.UNLOCK_DERELICT },
    .{ .name = "Barnacle Stamp", .price = 150, .unlock = def.UNLOCK_Z2 },
    .{ .name = "Glass Squid", .price = 175, .unlock = def.UNLOCK_Z3 },
    .{ .name = "Boss Sigil", .price = 200, .unlock = def.UNLOCK_DERELICT },
};
