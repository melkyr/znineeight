// creatures_t1.zig — T1 creature rows (spec §14.2–§14.4).
//
// The rows are generated from data.z98 into fallback_rows.zig by
// `undtool --emit-fallback`; this module keeps the dense-index access API the
// fight resolver and tests depend on. Indices 0..4 are the M2 rows, indices
// 5..17 the M4 roster, and index 18 the Derelict.

const def = @import("def.zig");
const behavior = @import("behavior.zig");
const fallback = @import("fallback_rows.zig");

// Role vocabulary used by this table.
pub const ROLE_COMMON = fallback.ROLE_COMMON;
pub const ROLE_NAMED = fallback.ROLE_NAMED;
pub const ROLE_RARE = fallback.ROLE_RARE;
pub const ROLE_BOSS = fallback.ROLE_BOSS;

// `speed_below_stat` / `discharge_stat` vocabulary (fight.zig consumes these).
pub const STAT_HP = fallback.STAT_HP;
pub const STAT_RES = fallback.STAT_RES;

// Family ids. Eel/Tuna are shared with the named grudges (§10); the remaining
// ids group the T1 families (Anemone/Perch keep their M2 ids 10/11).
pub const FAMILY_EEL = fallback.FAMILY_EEL;
pub const FAMILY_TUNA = fallback.FAMILY_TUNA;
pub const FAMILY_CRAB = fallback.FAMILY_CRAB;
pub const FAMILY_JELLY = fallback.FAMILY_JELLY;
pub const FAMILY_BARNACLE = fallback.FAMILY_BARNACLE;
pub const FAMILY_RAY = fallback.FAMILY_RAY;
pub const FAMILY_SQUID = fallback.FAMILY_SQUID;
pub const FAMILY_ANGLER = fallback.FAMILY_ANGLER;
pub const FAMILY_ANEMONE = fallback.FAMILY_ANEMONE;
pub const FAMILY_PERCH = fallback.FAMILY_PERCH;
pub const FAMILY_WRASSE = fallback.FAMILY_WRASSE;
pub const FAMILY_BOSS = fallback.FAMILY_BOSS;

// Grudge vocabulary (§10; applied from M5).
pub const GRUDGE_RES = fallback.GRUDGE_RES;
pub const GRUDGE_ARMOR = fallback.GRUDGE_ARMOR;

// Part ids in spec §14.1 order (M5 refines these).
pub const PART_SHELL_CHIP = fallback.PART_SHELL_CHIP;
pub const PART_PLATE_SCRAP = fallback.PART_PLATE_SCRAP;
pub const PART_GLAND_SAC = fallback.PART_GLAND_SAC;
pub const PART_BRINE_VIAL = fallback.PART_BRINE_VIAL;
pub const PART_CORAL_BUD = fallback.PART_CORAL_BUD;
pub const PART_GLOW_POLYP = fallback.PART_GLOW_POLYP;
pub const PART_GLASS_PANE = fallback.PART_GLASS_PANE;
pub const PART_HOOKED_BARBEL = fallback.PART_HOOKED_BARBEL;
pub const PART_STEEL_FINS = fallback.PART_STEEL_FINS;

// Counter-tool ids (§14.5) live in def.TOOL_*.

// Single source of truth for the T1 rows. Indices 0..4 are the M2/M3 sim
// creatures and must not move (the token table and their tests depend on it);
// indices 5..17 are the 13 M4 rows in dense order; index 18 is the Derelict.
pub const DEFS = fallback.DEFS;

pub fn defCount() i32 {
    if (def.content_override) |t| return t.def_count;
    return @intCast(i32, DEFS.len);
}

pub fn defAt(index: i32) def.CreatureDef {
    if (def.content_override) |t| {
        if (index < 0 or index >= t.def_count) {
            @panic("defAt: invalid creature index");
        }
        return t.defs[@intCast(usize, index)];
    }
    switch (index) {
        0 => return DEFS[0],
        1 => return DEFS[1],
        2 => return DEFS[2],
        3 => return DEFS[3],
        4 => return DEFS[4],
        5 => return DEFS[5],
        6 => return DEFS[6],
        7 => return DEFS[7],
        8 => return DEFS[8],
        9 => return DEFS[9],
        10 => return DEFS[10],
        11 => return DEFS[11],
        12 => return DEFS[12],
        13 => return DEFS[13],
        14 => return DEFS[14],
        15 => return DEFS[15],
        16 => return DEFS[16],
        17 => return DEFS[17],
        18 => return DEFS[18],
        else => @panic("defAt: invalid creature index"),
    }
}

pub fn rules() []const behavior.Rule {
    if (def.content_override) |t| {
        const n: usize = @intCast(usize, t.rule_count);
        return t.rules[0..n];
    }
    return RULES[0..];
}

pub const RULES = fallback.RULES;
