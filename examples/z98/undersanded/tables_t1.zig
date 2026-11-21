// tables_t1.zig — T1 encounter weights, travel ladder, tools, upgrades and
// cosmetics (spec §13). The rows are generated from data.z98 into
// fallback_rows.zig by `undtool --emit-fallback`; this module keeps the
// override-aware access API.

const def = @import("def.zig");
const fallback = @import("fallback_rows.zig");

pub const PHASE_DAY = fallback.PHASE_DAY;
pub const PHASE_NIGHT = fallback.PHASE_NIGHT;

// ---- §12 travel-cost ladder ----------------------------------------------
//
// Travel phases each way per zone. Z1..Z8 then the boss route D at index 8;
// unused slots are 0. Boss detection is a flag column so callers never spell
// the dense index.
pub const ZONE_COST = fallback.ZONE_COST;
pub const ZONE_IS_BOSS = fallback.ZONE_IS_BOSS;

pub const EMPTY = fallback.EMPTY;

pub fn fallbackRows(zone: i32, phase: i32) []const def.EncounterRow {
    switch (zone) {
        0 => {
            if (phase == PHASE_NIGHT) return fallback.ENCOUNTERS[0][1];
            return fallback.ENCOUNTERS[0][0];
        },
        1 => {
            if (phase == PHASE_NIGHT) return fallback.ENCOUNTERS[1][1];
            return fallback.ENCOUNTERS[1][0];
        },
        2 => {
            if (phase == PHASE_NIGHT) return fallback.ENCOUNTERS[2][1];
            return fallback.ENCOUNTERS[2][0];
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

// ---- §10 tools / §11 upgrades / §11 cosmetics ----------------------------
pub const TOOLS = fallback.TOOLS;
pub const UPGRADES = fallback.UPGRADES;
pub const COSMETICS = fallback.COSMETICS;
