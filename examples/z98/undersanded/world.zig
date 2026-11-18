// world.zig — UNDERSANDED world calendar, respawn, and rare-chance pipeline.
//
// Spec §5 (calendar/renewal), §9.7 (release/wariness), §11 (boat tiers),
// §12 (rare-chance pipeline), §13 (base rare weights), §25.7 (World layout).
// Flat state only (R1/R8/R10); all arithmetic is i32.

const def = @import("def.zig");
const creatures = @import("creatures_t1.zig");

// ---- Calendar -------------------------------------------------------------

pub const PHASE_DAY: i32 = 0;
pub const PHASE_NIGHT: i32 = 1;

// ---- Boat axes (World.boat stores tier counts 0..3, §11) ------------------

pub const BOAT_HULL: i32 = 0;
pub const BOAT_SPEED: i32 = 1;
pub const BOAT_CARGO: i32 = 2;
pub const BOAT_OXYGEN: i32 = 3;
pub const BOAT_PRECISION: i32 = 4;

// Cumulative totals per tier; index by tier count 0..3.
pub const HULL_TABLE = [4]i32{ 100, 125, 150, 200 };
pub const SPEED_TABLE = [4]i32{ 10, 12, 15, 19 };
pub const CARGO_TABLE = [4]i32{ 0, 1, 2, 3 };
pub const OXYGEN_FIGHTS = [4]i32{ 3, 4, 5, 6 };
pub const PRECISION_TABLE = [4]i32{ 10, 15, 20, 25 };

pub const BASE_HULL: i32 = 100;

// ---- Respawn triple indexes (subdue/kill/overkill, §14.2) -----------------

pub const RESPAWN_SUBDUE: i32 = 0;
pub const RESPAWN_KILL: i32 = 1;
pub const RESPAWN_OVERKILL: i32 = 2;

// ---- Rare-chance pipeline constants (§12) --------------------------------

pub const RELEASE_BONUS_STEP: i32 = 8;
pub const RELEASE_BONUS_CAP: i32 = 40;
pub const WARY_RESOLVE_BONUS: i32 = 15;
pub const LOCKOUT_ECHO: i32 = 5;

// Base rare weight per zone/phase. §13 sums: Z2 day 5+10=15, night 10+10=20;
// Z3 day 20+15+10=45, night 10+15+15+10+15+10=75. Z1 and Z4..Z11 are 0.
pub const BASE_RARE = [def.MAX_ZONES][2]i32{
    [2]i32{ 0, 0 }, // Z1
    [2]i32{ 15, 20 }, // Z2
    [2]i32{ 45, 75 }, // Z3
    [2]i32{ 0, 0 }, // Z4
    [2]i32{ 0, 0 }, // Z5
    [2]i32{ 0, 0 }, // Z6
    [2]i32{ 0, 0 }, // Z7
    [2]i32{ 0, 0 }, // Z8
    [2]i32{ 0, 0 }, // D
    [2]i32{ 0, 0 },
    [2]i32{ 0, 0 },
    [2]i32{ 0, 0 },
};

fn validZone(zone: i32) bool {
    if (zone < 0) return false;
    return @intCast(usize, zone) < def.MAX_ZONES;
}

fn validDef(d: i32) bool {
    if (d < 0) return false;
    return @intCast(usize, d) < def.MAX_CREATURES;
}

fn phaseIndex(phase: i32) usize {
    switch (phase) {
        PHASE_DAY => return 0,
        PHASE_NIGHT => return 1,
        else => return 0,
    }
}

fn tierIndex(tier: i32) usize {
    switch (tier) {
        0 => return 0,
        1 => return 1,
        2 => return 2,
        3 => return 3,
        else => return 0,
    }
}

fn familyBit(family: i32) u32 {
    if (family < 0 or family >= 32) return 0;
    return @intCast(u32, 1) << @intCast(u32, family);
}

fn setDefBit(mask: *[2]u32, d: i32) void {
    if (!validDef(d)) return;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    const m: u32 = @intCast(u32, 1) << bit;
    mask[word] = mask[word] | m;
}

fn defBitSet(mask: *const [2]u32, d: i32) bool {
    if (!validDef(d)) return false;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    const m: u32 = @intCast(u32, 1) << bit;
    return (mask[word] & m) != 0;
}

fn readyIndex(zone: i32, d: i32) usize {
    return @intCast(usize, zone) * def.MAX_CREATURES + @intCast(usize, d);
}

// ---- Boat helpers ---------------------------------------------------------

pub fn hullMax(w: *const def.World) i32 {
    return HULL_TABLE[tierIndex(w.boat[BOAT_HULL])];
}

pub fn speedMax(w: *const def.World) i32 {
    return SPEED_TABLE[tierIndex(w.boat[BOAT_SPEED])];
}

pub fn cargoMax(w: *const def.World) i32 {
    return CARGO_TABLE[tierIndex(w.boat[BOAT_CARGO])];
}

pub fn oxygenFights(w: *const def.World) i32 {
    return OXYGEN_FIGHTS[tierIndex(w.boat[BOAT_OXYGEN])];
}

pub fn precisionMargin(w: *const def.World) i32 {
    return PRECISION_TABLE[tierIndex(w.boat[BOAT_PRECISION])];
}

pub fn maxFights(w: *const def.World) i32 {
    return 3 + w.boat[BOAT_OXYGEN];
}

// ---- Calendar -------------------------------------------------------------

pub fn advancePhase(w: *def.World) void {
    switch (w.phase) {
        PHASE_DAY => {
            w.phase = PHASE_NIGHT;
        },
        PHASE_NIGHT => {
            w.phase = PHASE_DAY;
            w.cycle += 1;
        },
        else => {
            w.phase = PHASE_NIGHT;
        },
    }
    w.field_phases += 1;
}

// ---- Availability / renewal ----------------------------------------------

pub fn available(w: *const def.World, zone: i32, d: i32) bool {
    if (!validZone(zone) or !validDef(d)) return false;
    const r = w.ready[readyIndex(zone, d)];
    if (w.cycle > r) return true;
    if (w.cycle == r) return w.phase == PHASE_DAY;
    return false;
}

// markTaken records a fight outcome for one zone/creature instance.
//
// `outcome` is a `def.OUT_*` fight code, mapped internally to a respawn triple
// index: OUT_SUBDUE -> subdue (0), OUT_KILL -> kill (1), OUT_OVERKILL ->
// overkill (2). Creature-flee renews on the subdue index (§5).
//
// OUT_ONGOING, OUT_PLAYER_FLED, and any unknown value are deliberate no-ops:
// player flee/ascent must not renew. Callers must not call here for those; this
// guard is defensive.
pub fn markTaken(w: *def.World, zone: i32, d: i32, outcome: i32) void {
    if (!validZone(zone)) return;
    if (d < 0 or d >= creatures.defCount()) return;
    var respawn_index: i32 = 0;
    switch (outcome) {
        def.OUT_SUBDUE, def.OUT_CREATURE_FLED => respawn_index = RESPAWN_SUBDUE,
        def.OUT_KILL => respawn_index = RESPAWN_KILL,
        def.OUT_OVERKILL => respawn_index = RESPAWN_OVERKILL,
        else => return,
    }
    const cdef = creatures.defAt(d);
    w.ready[readyIndex(zone, d)] = w.cycle + cdef.respawn[@intCast(usize, respawn_index)];
    if (outcome == def.OUT_OVERKILL) {
        w.family_overkill_mask = w.family_overkill_mask | familyBit(cdef.family);
        // §9.8: any overkill zeroes that node's rare chance for 5 cycles. The
        // take cycle is inclusive (locked at c..c+4) because rareChance tests
        // `lockout_until > cycle`.
        w.lockout_until[zone] = w.cycle + 5;
    }
}

// ---- Release bonus / wariness / seen -------------------------------------

pub fn applyRelease(w: *def.World, zone: i32, d: i32) void {
    if (!validZone(zone)) return;
    const z: usize = @intCast(usize, zone);
    if (BASE_RARE[z][0] != 0 or BASE_RARE[z][1] != 0) {
        var bonus = w.release_bonus[zone] + RELEASE_BONUS_STEP;
        if (bonus > RELEASE_BONUS_CAP) bonus = RELEASE_BONUS_CAP;
        w.release_bonus[zone] = bonus;
    }
    setDefBit(&w.wary_mask, d);
}

pub fn clearReleaseBonus(w: *def.World, zone: i32) void {
    if (!validZone(zone)) return;
    w.release_bonus[zone] = 0;
}

pub fn consumeWariness(w: *def.World, d: i32) i32 {
    if (!defBitSet(&w.wary_mask, d)) return 0;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    const m: u32 = @intCast(u32, 1) << bit;
    w.wary_mask[word] = w.wary_mask[word] ^ m;
    return WARY_RESOLVE_BONUS;
}

pub fn markSeen(w: *def.World, d: i32) void {
    setDefBit(&w.seen_mask, d);
}

// ---- Rare chance (§12) ----------------------------------------------------

pub fn lockedNodeCount(w: *const def.World) i32 {
    var n: i32 = 0;
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        if (w.lockout_until[i] > w.cycle) n += 1;
    }
    return n;
}

pub fn rareChance(w: *const def.World, zone: i32) i32 {
    if (!validZone(zone)) return 0;
    if (w.lockout_until[zone] > w.cycle) return 0;
    const base = BASE_RARE[@intCast(usize, zone)][phaseIndex(w.phase)];
    if (base == 0) return 0;
    var bonus = w.release_bonus[zone];
    if (bonus < 0) bonus = 0;
    if (bonus > RELEASE_BONUS_CAP) bonus = RELEASE_BONUS_CAP;
    var total = base + bonus - LOCKOUT_ECHO * lockedNodeCount(w);
    if (total < 0) total = 0;
    if (total > 100) total = 100;
    return total;
}
