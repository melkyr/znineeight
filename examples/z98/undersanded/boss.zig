// boss.zig — UNDERSANDED Derelict boss layer (spec §15, §19, §38 P31).

const def = @import("def.zig");
const world = @import("world.zig");
const items = @import("items.zig");

pub const PHASE_1: i32 = 1;
pub const PHASE_2: i32 = 2;
pub const PHASE_3: i32 = 3;

pub const VARIANT_ARMOR: i32 = 0;
pub const VARIANT_SLIVER: i32 = 1;
pub const VARIANT_HOARD: i32 = 2;
pub const VARIANT_DROWN: i32 = 3;
pub const VARIANT_BLUR: i32 = 4;

pub const P1_SPEED: i32 = 7;
pub const P2_SPEED: i32 = 10;
pub const P3_SPEED: i32 = 12;

pub const P1_ATTACK: i32 = 10;
pub const VOLLEY_ATTACK: i32 = 15;
pub const VOLLEY_ATTACK_PLATE: i32 = 7;
pub const P3_ATTACK: i32 = 15;

pub const ARMOR_STRIKE_PCT: i32 = 50;
pub const SLIVER_EVEN_PCT: i32 = 25;

pub const DROWN_ROUND: i32 = 10;
pub const DROWN_HULL: i32 = 5;
pub const HOARD_ROUND_SPAN: i32 = 3;
pub const VOLLEY_ROUND_SPAN: i32 = 2;

const AXIS_PRIORITY = [5]i32{
    world.BOAT_HULL,
    world.BOAT_PRECISION,
    world.BOAT_CARGO,
    world.BOAT_OXYGEN,
    world.BOAT_SPEED,
};

pub fn isBoss(s: *const def.GameState) bool {
    return (s.fight.flags & def.F_BOSS) != 0;
}

pub fn isEngaged(s: *const def.GameState) bool {
    return s.fight.boss_phase != 0;
}

pub fn phaseForHp(hp: i32) i32 {
    if (hp <= 100) return PHASE_3;
    if (hp <= 200) return PHASE_2;
    return PHASE_1;
}

pub fn axisFromBoat(w: *const def.World) i32 {
    var max_tier: i32 = 0;
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        if (w.boat[i] > max_tier) max_tier = w.boat[i];
    }
    var p: usize = 0;
    while (p < AXIS_PRIORITY.len) : (p += 1) {
        const axis = AXIS_PRIORITY[p];
        if (w.boat[@intCast(usize, axis)] == max_tier) return axis;
    }
    return world.BOAT_HULL;
}

pub fn variantFromAxis(axis: i32) i32 {
    switch (axis) {
        world.BOAT_HULL => return VARIANT_ARMOR,
        world.BOAT_PRECISION => return VARIANT_SLIVER,
        world.BOAT_CARGO => return VARIANT_HOARD,
        world.BOAT_OXYGEN => return VARIANT_DROWN,
        world.BOAT_SPEED => return VARIANT_BLUR,
        else => return VARIANT_ARMOR,
    }
}

fn setVariantBit(s: *def.GameState) void {
    var v = s.fight.boss_variant;
    if (v < 0 or v > 4) v = VARIANT_ARMOR;
    const bit: u32 = @intCast(u32, 1) << @intCast(u32, v);
    const w = &s.world;
    w.boss_variants_seen = w.boss_variants_seen | bit;
}

fn logPhase2Entry(s: *def.GameState) void {
    var v = s.fight.boss_variant;
    if (v < 0 or v > 4) v = VARIANT_ARMOR;
    def.appendLog(s, def.LOG_NORMAL, def.MSG_BOSS_PHASE2, v + 1, 0);
}

pub fn startBoss(s: *def.GameState, w: *def.World) void {
    s.fight.boss_axis = axisFromBoat(w);
    s.fight.boss_variant = variantFromAxis(s.fight.boss_axis);
    s.fight.boss_phase = phaseForHp(s.fight.hp);
    s.fight.boss_volley_round = 0;
    s.fight.boss_start_hull = s.fight.hull;
    s.fight.boss_start_actions = s.fight.actions;
    s.fight.boss_defeat_done = 0;
    if (s.fight.boss_phase >= PHASE_2) {
        setVariantBit(s);
        logPhase2Entry(s);
    }
}

pub fn bossPhaseUpdate(s: *def.GameState) void {
    const p = phaseForHp(s.fight.hp);
    if (s.fight.boss_phase == 0) {
        s.fight.boss_phase = p;
        if (p >= PHASE_2) {
            setVariantBit(s);
            logPhase2Entry(s);
        }
        return;
    }
    if (p <= s.fight.boss_phase) return;
    const old = s.fight.boss_phase;
    s.fight.boss_phase = p;
    if (old < PHASE_2 and p >= PHASE_2) {
        setVariantBit(s);
        logPhase2Entry(s);
    }
}

pub fn effectiveSpeed(s: *const def.GameState) i32 {
    switch (s.fight.boss_phase) {
        PHASE_2 => return P2_SPEED,
        PHASE_3 => return P3_SPEED,
        else => return P1_SPEED,
    }
}

pub fn plateActive(s: *const def.GameState) bool {
    return s.fight.tool_active != 0 and s.fight.tool == def.TOOL_PLATE;
}

pub fn volleyDue(s: *const def.GameState) bool {
    if (s.fight.boss_phase != PHASE_2) return false;
    return (s.fight.round % VOLLEY_ROUND_SPAN) == 0;
}

pub fn effectiveAttack(s: *const def.GameState) i32 {
    switch (s.fight.boss_phase) {
        PHASE_2 => {
            if (plateActive(s)) return VOLLEY_ATTACK_PLATE;
            return VOLLEY_ATTACK;
        },
        PHASE_3 => return P3_ATTACK,
        else => return P1_ATTACK,
    }
}

pub fn attackCount(s: *def.GameState) i32 {
    if (s.fight.boss_phase == PHASE_2 and !volleyDue(s)) return 0;
    if (s.fight.boss_phase == PHASE_2) s.fight.boss_volley_round = s.fight.round;
    var n: i32 = 1;
    if (s.fight.boss_phase >= PHASE_2 and s.fight.boss_variant == VARIANT_BLUR) {
        if ((s.fight.round % 3) == 0) n = 2;
    }
    return n;
}

pub fn creatureFirst(s: *const def.GameState) bool {
    if (s.fight.boss_phase >= PHASE_2 and s.fight.boss_variant == VARIANT_BLUR) return true;
    return effectiveSpeed(s) > s.fight.player_speed;
}

pub fn strikePctOverride(s: *const def.GameState) i32 {
    if (s.fight.boss_phase < PHASE_2) return 0;
    switch (s.fight.boss_variant) {
        VARIANT_ARMOR => {
            if (plateActive(s)) return 0;
            return ARMOR_STRIKE_PCT;
        },
        VARIANT_SLIVER => {
            if ((s.fight.round % 2) == 0) return SLIVER_EVEN_PCT;
            return 0;
        },
        else => return 0,
    }
}

fn recountHold(s: *def.GameState) void {
    const ep = &s.exp;
    var n: i32 = 0;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (ep.hold[i] > 0) n += 1;
    }
    ep.hold_n = n;
}

fn jettison(s: *def.GameState) void {
    const ep = &s.exp;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (ep.hold[i] <= 0) continue;
        const part = @intCast(i32, i);
        if (items.isKeystone(part)) continue;
        ep.hold[i] = 0;
        recountHold(s);
        def.appendLog(s, def.LOG_NORMAL, def.MSG_BOSS_HOARD, part, 0);
        return;
    }
}

fn flood(s: *def.GameState) void {
    s.fight.hull -= DROWN_HULL;
    if (s.fight.hull < 0) s.fight.hull = 0;
    s.fight.hull_spent += DROWN_HULL;
    def.appendLog(s, def.LOG_NORMAL, def.MSG_BOSS_DROWN, DROWN_HULL, s.fight.hull);
}

pub fn endRound(s: *def.GameState) void {
    if (s.fight.boss_phase < PHASE_2) return;
    if (s.fight.boss_variant == VARIANT_HOARD) {
        if ((s.fight.round % HOARD_ROUND_SPAN) == 0) jettison(s);
    }
    if (s.fight.boss_variant == VARIANT_DROWN) {
        if (s.fight.round > DROWN_ROUND) flood(s);
    }
}

pub fn onDefeat(s: *def.GameState) bool {
    if (!isEngaged(s)) return false;
    if (s.fight.outcome != def.OUT_KILL and s.fight.outcome != def.OUT_OVERKILL) return false;
    if (s.fight.boss_defeat_done != 0) return false;
    s.fight.boss_defeat_done = 1;

    const w = &s.world;
    w.boss_kills += 1;
    if (s.fight.outcome == def.OUT_OVERKILL) {
        w.score_overkilled += 1;
    } else {
        w.score_killed += 1;
    }
    world.runReset(w);
    return true;
}
