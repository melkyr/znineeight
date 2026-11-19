// tables_t1.zig — T1 encounter weights (spec §13).
//
// Rows are `{ dense DEFS index, weight }`; the dense indices map to the
// roster in creatures_t1.zig (M2 rows 0..4 keep their positions, then the 13
// M4 rows at 5..17). Z1-Z3 carry the §13 tables; Z4..Z11 are empty stubs
// until M13. Base weights sum to 100 per zone/phase (commons + rares).

const def = @import("def.zig");
const world = @import("world.zig");

pub const EncounterRow = def.EncounterRow;

pub const PHASE_DAY: i32 = 0;
pub const PHASE_NIGHT: i32 = 1;

// ---- §12 travel-cost ladder ----------------------------------------------
//
// Travel phases each way per zone. Z1..Z8 then the boss route D at index 8;
// unused slots are 0. Boss detection is a flag column so callers never spell
// the dense index.
pub const ZONE_COST: [def.MAX_ZONES]i32 = .{ 1, 2, 3, 3, 4, 4, 5, 5, 5, 0, 0, 0 };
pub const ZONE_IS_BOSS: [def.MAX_ZONES]i32 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0 };

pub const EMPTY = [0]EncounterRow{};

// ---- Z1 — The Shallows (rare chance 0%) ----------------------------------

pub const Z1_DAY = [_]EncounterRow{
    EncounterRow{ .def_index = 0, .weight = 30 }, // Mystic Eel
    EncounterRow{ .def_index = 2, .weight = 30 }, // Steel Tuna
    EncounterRow{ .def_index = 5, .weight = 20 }, // Rust Tuna
    EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    EncounterRow{ .def_index = 9, .weight = 10 }, // Spark Anemone
};

pub const Z1_NIGHT = [_]EncounterRow{
    EncounterRow{ .def_index = 1, .weight = 40 }, // Mystic Electric Eel
    EncounterRow{ .def_index = 0, .weight = 30 }, // Mystic Eel
    EncounterRow{ .def_index = 5, .weight = 15 }, // Rust Tuna
    EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    EncounterRow{ .def_index = 9, .weight = 5 }, // Spark Anemone
};

// ---- Z2 — The Reef --------------------------------------------------------

pub const Z2_DAY = [_]EncounterRow{
    EncounterRow{ .def_index = 11, .weight = 15 }, // Tunisteel (named)
    EncounterRow{ .def_index = 0, .weight = 15 }, // Mystic Eel
    EncounterRow{ .def_index = 2, .weight = 10 }, // Steel Tuna
    EncounterRow{ .def_index = 5, .weight = 10 }, // Rust Tuna
    EncounterRow{ .def_index = 10, .weight = 10 }, // Mileel (named)
    EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    EncounterRow{ .def_index = 8, .weight = 10 }, // Chitin Barnacle
    EncounterRow{ .def_index = 9, .weight = 5 }, // Spark Anemone
    EncounterRow{ .def_index = 12, .weight = 5 }, // Coral Crab (rare)
    EncounterRow{ .def_index = 3, .weight = 10 }, // Anemoniacus (rare)
};

pub const Z2_NIGHT = [_]EncounterRow{
    EncounterRow{ .def_index = 1, .weight = 20 }, // Mystic Electric Eel
    EncounterRow{ .def_index = 7, .weight = 15 }, // Brine Jelly
    EncounterRow{ .def_index = 0, .weight = 15 }, // Mystic Eel
    EncounterRow{ .def_index = 5, .weight = 10 }, // Rust Tuna
    EncounterRow{ .def_index = 6, .weight = 10 }, // Kelp Crab
    EncounterRow{ .def_index = 8, .weight = 10 }, // Chitin Barnacle
    EncounterRow{ .def_index = 12, .weight = 10 }, // Coral Crab (rare)
    EncounterRow{ .def_index = 3, .weight = 10 }, // Anemoniacus (rare)
};

// ---- Z3 — Trench-Edge -----------------------------------------------------

pub const Z3_DAY = [_]EncounterRow{
    EncounterRow{ .def_index = 17, .weight = 20 }, // Ironclad Wrasse (rare)
    EncounterRow{ .def_index = 12, .weight = 15 }, // Coral Crab (rare)
    EncounterRow{ .def_index = 5, .weight = 20 }, // Rust Tuna
    EncounterRow{ .def_index = 6, .weight = 20 }, // Kelp Crab
    EncounterRow{ .def_index = 8, .weight = 15 }, // Chitin Barnacle
    EncounterRow{ .def_index = 4, .weight = 10 }, // Freezing Perch (rare)
};

pub const Z3_NIGHT = [_]EncounterRow{
    EncounterRow{ .def_index = 12, .weight = 10 }, // Coral Crab (rare)
    EncounterRow{ .def_index = 13, .weight = 15 }, // Abyssal Lantern-Jelly (rare)
    EncounterRow{ .def_index = 14, .weight = 15 }, // Neon Ghost-Ray (rare)
    EncounterRow{ .def_index = 15, .weight = 10 }, // Glass Squid (rare)
    EncounterRow{ .def_index = 16, .weight = 15 }, // Brine Angler (rare)
    EncounterRow{ .def_index = 7, .weight = 15 }, // Brine Jelly
    EncounterRow{ .def_index = 8, .weight = 10 }, // Chitin Barnacle
    EncounterRow{ .def_index = 4, .weight = 10 }, // Freezing Perch (rare)
};

pub fn fallbackRows(zone: i32, phase: i32) []const EncounterRow {
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

pub fn rows(zone: i32, phase: i32) []const EncounterRow {
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

// ---- §10 tools -----------------------------------------------------------
//
// Tool ids match `creatures_t1.TOOL_*` counter-tool ids. Costs are keystone
// parts as-is; material ids are the §14.1 source part ids (R7).

pub const TOOL_KIND_ACTIVATED: i32 = 0;
pub const TOOL_KIND_RIGGED: i32 = 1;

// Two-field cost slot local to the dock/M6 tables. `kind` 0 = unused slot;
// otherwise a part id (1..9). Task 1's `MaterialAmt` is a separate type.
pub const CostSlot = def.CostSlot;

pub const ToolRow = def.ToolRow;

fn slot(kind: i32, amt: i32) CostSlot {
    return CostSlot{ .kind = kind, .amt = amt };
}

const NONE_SLOT = CostSlot{ .kind = 0, .amt = 0 };

pub const TOOLS = [_]ToolRow{
    // Steel Plate Tool | Rigged | Plate Scrap ×3
    .{ .id = 1, .kind = TOOL_KIND_RIGGED, .cost = [3]CostSlot{ slot(2, 3), NONE_SLOT, NONE_SLOT } },
    // Brine Net | Rigged | Brine Vial ×2, Shell Chip ×1
    .{ .id = 2, .kind = TOOL_KIND_RIGGED, .cost = [3]CostSlot{ slot(4, 2), slot(1, 1), NONE_SLOT } },
    // Electric Gland | Activated | Gland Sac ×3
    .{ .id = 3, .kind = TOOL_KIND_ACTIVATED, .cost = [3]CostSlot{ slot(3, 3), NONE_SLOT, NONE_SLOT } },
    // Bioluminescent Lure | Activated | Glow Polyp ×2, Glass Pane ×1
    .{ .id = 4, .kind = TOOL_KIND_ACTIVATED, .cost = [3]CostSlot{ slot(6, 2), slot(7, 1), NONE_SLOT } },
    // Pressure Hook | Rigged | Hooked Barbel ×1, Shell Chip ×2, Coral Bud ×1
    .{ .id = 5, .kind = TOOL_KIND_RIGGED, .cost = [3]CostSlot{ slot(8, 1), slot(1, 2), slot(5, 1) } },
    // Sonar Ping | Activated | Glass Pane ×2, Gland Sac ×1
    .{ .id = 6, .kind = TOOL_KIND_ACTIVATED, .cost = [3]CostSlot{ slot(7, 2), slot(3, 1), NONE_SLOT } },
    // Coral Shield | Rigged | Coral Bud ×2, Plate Scrap ×1
    .{ .id = 7, .kind = TOOL_KIND_RIGGED, .cost = [3]CostSlot{ slot(5, 2), slot(2, 1), NONE_SLOT } },
};

// ---- §11 upgrade costs ---------------------------------------------------
//
// One row per axis/tier; `axis` uses the `World.boat` indexes (the same
// indexes dock Upgrade applies). Material ids follow R7: 1 Chitin, 2 Steel
// Plate, 3 Gland, 4 Brine, 5 Coral, 6 Luminescence, 7 Glass; 8/9 are the
// Hooked Barbel / Steel Fins keystone parts.

pub const UpgradeRow = def.UpgradeRow;

pub const UPGRADES = [_]UpgradeRow{
    // Hull
    .{ .axis = world.BOAT_HULL, .tier = 1, .cost = [3]CostSlot{ slot(1, 3), NONE_SLOT, NONE_SLOT } },
    .{ .axis = world.BOAT_HULL, .tier = 2, .cost = [3]CostSlot{ slot(1, 6), slot(2, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_HULL, .tier = 3, .cost = [3]CostSlot{ slot(1, 10), slot(2, 4), NONE_SLOT } },
    // Precision
    .{ .axis = world.BOAT_PRECISION, .tier = 1, .cost = [3]CostSlot{ slot(3, 2), slot(6, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_PRECISION, .tier = 2, .cost = [3]CostSlot{ slot(3, 4), slot(6, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_PRECISION, .tier = 3, .cost = [3]CostSlot{ slot(3, 8), slot(6, 2), NONE_SLOT } },
    // Cargo
    .{ .axis = world.BOAT_CARGO, .tier = 1, .cost = [3]CostSlot{ slot(4, 3), slot(5, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_CARGO, .tier = 2, .cost = [3]CostSlot{ slot(4, 6), slot(5, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_CARGO, .tier = 3, .cost = [3]CostSlot{ slot(4, 10), slot(5, 4), NONE_SLOT } },
    // Oxygen
    .{ .axis = world.BOAT_OXYGEN, .tier = 1, .cost = [3]CostSlot{ slot(5, 3), slot(4, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 2, .cost = [3]CostSlot{ slot(5, 6), slot(4, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_OXYGEN, .tier = 3, .cost = [3]CostSlot{ slot(5, 10), slot(4, 4), NONE_SLOT } },
    // Speed
    .{ .axis = world.BOAT_SPEED, .tier = 1, .cost = [3]CostSlot{ slot(7, 2), slot(3, 1), NONE_SLOT } },
    .{ .axis = world.BOAT_SPEED, .tier = 2, .cost = [3]CostSlot{ slot(7, 2), slot(3, 2), NONE_SLOT } },
    .{ .axis = world.BOAT_SPEED, .tier = 3, .cost = [3]CostSlot{ slot(7, 4), slot(3, 4), slot(9, 2) } },
};

// ---- §11 cosmetics -------------------------------------------------------
//
// Twelve fixed items in §11 order (bit 0..11). Prices total 2,100 coins.
// Unlock milestones: zone-first-arrival bits (set by M5) or Derelict kill.

pub const UNLOCK_Z1: i32 = 1;
pub const UNLOCK_Z2: i32 = 2;
pub const UNLOCK_Z3: i32 = 3;
pub const UNLOCK_DERELICT: i32 = 4;

pub const CosmeticRow = def.CosmeticRow;

pub const COSMETICS = [_]CosmeticRow{
    .{ .name = "Foam White", .price = 150, .unlock = UNLOCK_Z1 },
    .{ .name = "Abyss Teal", .price = 175, .unlock = UNLOCK_Z2 },
    .{ .name = "Leviathan Black", .price = 200, .unlock = UNLOCK_Z3 },
    .{ .name = "Gull Skull", .price = 150, .unlock = UNLOCK_Z1 },
    .{ .name = "Lantern Jaw", .price = 175, .unlock = UNLOCK_Z2 },
    .{ .name = "Derelict Cog", .price = 200, .unlock = UNLOCK_DERELICT },
    .{ .name = "Patched Pennant", .price = 150, .unlock = UNLOCK_Z1 },
    .{ .name = "Reef Signal", .price = 175, .unlock = UNLOCK_Z3 },
    .{ .name = "Trench Mark", .price = 200, .unlock = UNLOCK_DERELICT },
    .{ .name = "Barnacle Stamp", .price = 150, .unlock = UNLOCK_Z2 },
    .{ .name = "Glass Squid", .price = 175, .unlock = UNLOCK_Z3 },
    .{ .name = "Boss Sigil", .price = 200, .unlock = UNLOCK_DERELICT },
};
