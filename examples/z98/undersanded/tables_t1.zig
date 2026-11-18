// tables_t1.zig — T1 encounter weights (spec §13).
//
// Rows are `{ dense DEFS index, weight }`; the dense indices map to the
// roster in creatures_t1.zig (M2 rows 0..4 keep their positions, then the 13
// M4 rows at 5..17). Z1-Z3 carry the §13 tables; Z4..Z11 are empty stubs
// until M13. Base weights sum to 100 per zone/phase (commons + rares).

const def = @import("def.zig");

pub const EncounterRow = struct { def_index: i32, weight: i32 };

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

pub fn rows(zone: i32, phase: i32) []const EncounterRow {
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
