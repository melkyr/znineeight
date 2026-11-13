// fight.zig — UNDERSANDED fight resolution (spec §8–§9, §25.3–§25.6).
//
// Pure: no I/O, no rendering. Every entry point takes *GameState plus the
// immutable creature row/rule slice; resolution order is exactly §9.2:
//   player action -> effects/death -> subdue gate -> creature action ->
//   end-of-round coupling -> round++.
//
// Module-level constants only (R2); every switch has an else (R3); i32 combat
// math only (R6/R11); explicit state initialization (R8).

const def = @import("def.zig");
const math = @import("math.zig");
const rng = @import("rng.zig");
const behavior = @import("behavior.zig");
const std_math = @import("std_math");

// ---- Player baseline (§8.1) ----------------------------------------------

pub const BASE_HULL: i32 = 100;
pub const BASE_SPEED: i32 = 10;
pub const STRIKE_MIN: i32 = 15;
pub const STRIKE_MAX: i32 = 25;
pub const RESTRAIN_MIN: i32 = 10;
pub const RESTRAIN_MAX: i32 = 18;
pub const DEFAULT_MARGIN_PCT: i32 = 10;

pub const PERCENT_BASE: i32 = 100;
pub const DANGER_BASE: i32 = 25;
pub const DROWSY_STRIKE_PCT: i32 = 80;
pub const EXPOSED_INCOMING_PCT: i32 = 125;
pub const SUBDUE_ROLL_MIN: i32 = 1;
pub const SUBDUE_ROLL_MAX: i32 = 100;
pub const PENDING_ON: i32 = 1;

// ---- Last Surge (§9.5) ----------------------------------------------------

pub const LAST_SURGE_RESTORE_PCT: i32 = 30;
pub const LAST_SURGE_ATK_PP: i32 = 25;
pub const LAST_SURGE_SPEED_ADD: i32 = 2;
pub const LAST_SURGE_SPEED_CAP: i32 = 6;

// ---- Coupling gates (§8.5) ------------------------------------------------

pub const THRASH_GATE_PCT: i32 = 50;
pub const DESPAIR_GATE_PCT: i32 = 30;
pub const DESPAIR_RES_GATE_PCT: i32 = 50;

// ---- Stat thresholds / tools / flee kinds --------------------------------

pub const STAT_HP: i32 = 1;
pub const STAT_RES: i32 = 2;

pub const TOOL_PLATE: i32 = 1;
pub const TOOL_BRINE_NET: i32 = 2;

pub const FLEE_HIT_PCT: i32 = 1;

// ---- Screens / log message ids -------------------------------------------

pub const SCREEN_FIGHT: i32 = 0;
pub const SCREEN_SUBDUE: i32 = 1;
pub const SCREEN_SUBDUE_POST: i32 = 2;

pub const MSG_STRIKE: i32 = 2;
pub const MSG_RESTRAIN: i32 = 3;
pub const MSG_CREATURE_ATTACK: i32 = 4;
pub const MSG_SUBDUE_OK: i32 = 5;
pub const MSG_SUBDUE_FAIL: i32 = 6;
pub const MSG_KILL: i32 = 7;
pub const MSG_OVERKILL: i32 = 8;
pub const MSG_COUPLING: i32 = 9;
pub const MSG_DECLINE: i32 = 10;
pub const MSG_PLAYER_FLED: i32 = 11;
pub const MSG_CREATURE_FLED: i32 = 12;
pub const MSG_EQUIP: i32 = 13;
pub const MSG_DISCHARGE: i32 = 14;

// ---- Log ------------------------------------------------------------------

pub fn log(s: *def.GameState, class: i32, msg_id: i32, a: i32, b: i32) void {
    const e = def.LogEntry{ .class = class, .msg_id = msg_id, .a = a, .b = b };
    if (s.log_n < @intCast(i32, def.MAX_LOG)) {
        s.log[@intCast(usize, s.log_n)] = e;
        s.log_n += 1;
    } else {
        var i: usize = 1;
        while (i < def.MAX_LOG) : (i += 1) {
            s.log[i - 1] = s.log[i];
        }
        s.log[def.MAX_LOG - 1] = e;
    }
}

// ---- Overkill / danger display (§8.6) ------------------------------------

pub fn margin(s: *const def.GameState) i32 {
    var m = math.applyPct(s.fight.max_hp, s.fight.margin_pct);
    if (s.fight.cond == def.COND_SHAKY) m = m / 2;
    return m;
}

pub fn dangerHp(s: *const def.GameState) i32 {
    const d = DANGER_BASE - margin(s);
    if (d < 0) return 0;
    return d;
}

pub fn deathOutcomeFor(overshoot: i32, m: i32) i32 {
    if (overshoot >= m) return def.OUT_OVERKILL;
    return def.OUT_KILL;
}

// ---- Start / reset --------------------------------------------------------

pub fn startFightDef(s: *def.GameState, def_index: i32, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    _ = rules;

    s.fight.def_index = def_index;
    s.fight.hp = cdef.hp;
    s.fight.max_hp = cdef.hp;
    s.fight.res = cdef.resolve;
    s.fight.max_res = cdef.resolve;
    s.fight.hull = BASE_HULL;
    s.fight.max_hull = BASE_HULL;
    s.fight.player_speed = BASE_SPEED;
    s.fight.margin_pct = DEFAULT_MARGIN_PCT;
    s.fight.round = 1;
    s.fight.actions = 0;
    s.fight.outcome = def.OUT_ONGOING;
    s.fight.flags = cdef.flags;
    s.fight.prev_hp = cdef.hp;
    s.fight.prev_res = cdef.resolve;
    s.fight.subdue_declined = 0;
    s.fight.surge_count = 0;
    s.fight.surge_atk_applied = 0;
    s.fight.tool = 0;
    s.fight.tool_charge = 0;
    s.fight.tool_broken = 0;
    s.fight.tool_active = 0;
    s.fight.phase_state = 0;
    s.fight.boss_phase = 0;
    s.fight.boss_axis = 0;
    s.fight.last_bar = def.BAR_NONE;
    s.fight.switches = 0;
    s.fight.hull_spent = 0;
    s.fight.rng_state = 0;
    s.fight.rule_consumed = 0;
    s.fight.pending_blind = 0;
    s.fight.pending_ink = 0;
    s.fight.pending_flee = 0;
    s.fight.active_armor_pct = cdef.armor_pct;
    s.fight.active_resist_restrain = cdef.resist_restrain_pct;
    s.fight.cond = def.COND_NONE;

    const fi: u32 = @intCast(u32, s.exp.fight_index);
    const off: u32 = fi * @intCast(u32, 77);
    const seed: u32 = s.exp.seed + off;
    rng.rngSeed(&s.fight.rng_state, seed);

    s.log_n = 0;
    var i: usize = 0;
    while (i < def.MAX_LOG) : (i += 1) {
        s.log[i] = def.LogEntry{ .class = 0, .msg_id = 0, .a = 0, .b = 0 };
    }
    s.pending_cond = def.COND_NONE;
    s.screen = SCREEN_FIGHT;
}

// ---- Derived creature stats ----------------------------------------------

// Exact-rational threshold checks. "below X%" means `v*100 < max*pct`
// (not floor-then-strict-<), so non-100-divisible maxima keep the spec
// boundary (e.g. 115 -> 50% is still below at 57).
pub fn belowPct(v: i32, max: i32, pct: i32) bool {
    return v * PERCENT_BASE < max * pct;
}

pub fn abovePct(v: i32, max: i32, pct: i32) bool {
    return v * PERCENT_BASE > max * pct;
}

pub fn hitExceedsPct(v: i32, max: i32, pct: i32) bool {
    return v * PERCENT_BASE > max * pct;
}

fn statBelowPct(max: i32, now: i32, pct: i32) bool {
    return belowPct(now, max, pct);
}

fn surgeSpeedBonus(count: i32) i32 {
    var b = count * LAST_SURGE_SPEED_ADD;
    if (b > LAST_SURGE_SPEED_CAP) b = LAST_SURGE_SPEED_CAP;
    return b;
}

pub fn effectiveSpeed(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    var sp = cdef.speed;

    if (cdef.speed_below_th > 0) {
        var below: bool = false;
        if (cdef.speed_below_stat == STAT_RES) {
            below = statBelowPct(s.fight.max_res, s.fight.res, cdef.speed_below_th);
        } else {
            below = statBelowPct(s.fight.max_hp, s.fight.hp, cdef.speed_below_th);
        }
        if (below) sp += cdef.speed_below_add;
    }

    sp += surgeSpeedBonus(s.fight.surge_count);

    var dummy = s.fight.rule_consumed;
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.hp, s.fight.hp, s.fight.res, s.fight.res, s.fight.round, &dummy, ri);
        if (fired) |e| {
            if (e.op == behavior.ADD_SPEED) sp += e.a;
        }
    }

    return sp;
}

pub fn effectiveAttack(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    var pct: i32 = PERCENT_BASE;

    if (cdef.atk_below_th > 0) {
        if (statBelowPct(s.fight.max_hp, s.fight.hp, cdef.atk_below_th)) {
            pct += cdef.atk_below_pct;
        }
    }
    if (s.fight.surge_atk_applied != 0) pct += LAST_SURGE_ATK_PP;

    var dummy = s.fight.rule_consumed;
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.hp, s.fight.hp, s.fight.res, s.fight.res, s.fight.round, &dummy, ri);
        if (fired) |e| {
            if (e.op == behavior.MULT_ATK) pct += e.a - PERCENT_BASE;
        }
    }

    if (s.fight.cond == def.COND_EXPOSED) pct = math.applyPct(pct, EXPOSED_INCOMING_PCT);

    return math.applyPct(cdef.attack, pct);
}

pub fn creatureFirst(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) bool {
    return effectiveSpeed(s, cdef, rules) > s.fight.player_speed;
}

fn effectiveArmor(s: *const def.GameState, cdef: *const def.CreatureDef) i32 {
    var a = s.fight.active_armor_pct;
    if (a <= 0) a = PERCENT_BASE;
    if (cdef.armor_below_th > 0) {
        if (statBelowPct(s.fight.max_hp, s.fight.hp, cdef.armor_below_th)) {
            if (cdef.armor_below_pct > 0) a = cdef.armor_below_pct;
        }
    }
    if (s.fight.tool_active != 0 and s.fight.tool == TOOL_PLATE) a = PERCENT_BASE;
    return a;
}

fn effectiveResist(s: *const def.GameState) i32 {
    var r = s.fight.active_resist_restrain;
    if (r <= 0) r = PERCENT_BASE;
    if (s.fight.tool_active != 0 and s.fight.tool == TOOL_BRINE_NET) r = PERCENT_BASE;
    return r;
}

fn resetActive(s: *def.GameState, cdef: *const def.CreatureDef) void {
    s.fight.active_armor_pct = cdef.armor_pct;
    s.fight.active_resist_restrain = cdef.resist_restrain_pct;
}

// ---- Rule VM dispatch -----------------------------------------------------

fn applyEffect(s: *def.GameState, e: def.Effect) void {
    switch (e.op) {
        behavior.REGEN_RES => {
            s.fight.res = std_math.min(s.fight.max_res, s.fight.res + e.a);
        },
        behavior.REGEN_HP => {
            s.fight.hp = std_math.min(s.fight.max_hp, s.fight.hp + e.a);
        },
        behavior.HULL_DMG => {
            var d = e.a;
            if (d < 0) d = 0;
            s.fight.hull -= d;
            if (s.fight.hull < 0) s.fight.hull = 0;
            s.fight.hull_spent += d;
            log(s, def.LOG_NORMAL, MSG_DISCHARGE, d, s.fight.hull);
        },
        behavior.SET_ARMOR => {
            s.fight.active_armor_pct = e.a;
        },
        behavior.SET_FLEE => {
            if (e.a != 0) {
                s.fight.pending_flee = e.a;
            } else {
                s.fight.pending_flee = PENDING_ON;
            }
        },
        behavior.SET_BLIND => {
            if (e.b != 0) {
                s.fight.pending_blind = e.b;
            } else {
                s.fight.pending_blind = e.a;
            }
        },
        behavior.SET_INK => {
            if (e.b != 0) {
                s.fight.pending_ink = e.b;
            } else {
                s.fight.pending_ink = e.a;
            }
        },
        behavior.ADD_SPEED => {},
        behavior.MULT_ATK => {},
        behavior.MISS_STRIKE => {},
        else => {},
    }
}

fn applyRules(s: *def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    resetActive(s, cdef);
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.prev_hp, s.fight.hp, s.fight.prev_res, s.fight.res, s.fight.round, &s.fight.rule_consumed, ri);
        if (fired) |e| {
            applyEffect(s, e);
        }
    }
}

// ---- Last Surge -----------------------------------------------------------

pub fn lastSurge(s: *def.GameState) void {
    s.fight.res = math.ceilPct30(s.fight.max_res);
    s.fight.surge_count += 1;
    if (s.fight.surge_atk_applied == 0) s.fight.surge_atk_applied = 1;
    log(s, def.LOG_NORMAL, def.MSG_LAST_SURGE, s.fight.surge_count, s.fight.res);
}

// ---- Subdue gate ----------------------------------------------------------

pub fn gateOpen(s: *const def.GameState, cdef: *const def.CreatureDef) bool {
    if (s.fight.hp <= 0) return false;
    if (s.fight.res > 0) return false;
    if (s.fight.subdue_declined != 0) return false;
    if (cdef.subdue_chance < 0) return false;
    return true;
}

fn subdueSuccess(s: *def.GameState, cdef: *const def.CreatureDef) bool {
    const roll = rng.rngRange(&s.fight.rng_state, SUBDUE_ROLL_MIN, SUBDUE_ROLL_MAX);
    return roll <= cdef.subdue_chance;
}

fn finishSubdue(s: *def.GameState) void {
    s.fight.outcome = def.OUT_SUBDUE;
    s.screen = SCREEN_FIGHT;
    log(s, def.LOG_NORMAL, MSG_SUBDUE_OK, 0, 0);
}

fn finishSurgeFailure(s: *def.GameState) void {
    log(s, def.LOG_WARN, MSG_SUBDUE_FAIL, 0, 0);
    lastSurge(s);
}

// ---- Death ----------------------------------------------------------------

fn checkDeath(s: *def.GameState) bool {
    if (s.fight.hp > 0) return false;

    const overshoot = 0 - s.fight.hp;
    const m = margin(s);
    const out = deathOutcomeFor(overshoot, m);
    s.fight.outcome = out;

    var msg = MSG_KILL;
    var class = def.LOG_NORMAL;
    if (out == def.OUT_OVERKILL) {
        msg = MSG_OVERKILL;
        class = def.LOG_WARN;
    }
    log(s, class, msg, overshoot, m);
    return true;
}

// ---- Player actions -------------------------------------------------------

fn noteBar(s: *def.GameState, bar: i32) void {
    if (s.fight.last_bar != def.BAR_NONE and s.fight.last_bar != bar) {
        s.fight.switches += 1;
    }
    s.fight.last_bar = bar;
}

// Combined Strike percentage: Drowsy and armor fold into ONE pct so
// applyPct runs exactly once (§25.4 "never chain applyPct").
pub fn strikePct(cond: i32, armor_pct: i32) i32 {
    var pct = PERCENT_BASE;
    if (cond == def.COND_DROWSY) pct = DROWSY_STRIKE_PCT;
    return math.applyPct(pct, armor_pct);
}

fn strike(s: *def.GameState, cdef: *const def.CreatureDef) void {
    var dmg = rng.rngRange(&s.fight.rng_state, STRIKE_MIN, STRIKE_MAX);
    dmg = math.applyPct(dmg, strikePct(s.fight.cond, effectiveArmor(s, cdef)));
    if (dmg < 0) dmg = 0;

    s.fight.hp -= dmg;
    log(s, def.LOG_NORMAL, MSG_STRIKE, dmg, s.fight.hp);

    if (cdef.flee_kind == FLEE_HIT_PCT and cdef.flee_th > 0) {
        if (hitExceedsPct(dmg, s.fight.max_hp, cdef.flee_th)) {
            s.fight.pending_flee = PENDING_ON;
        }
    }
}

fn restrain(s: *def.GameState) void {
    var dmg = rng.rngRange(&s.fight.rng_state, RESTRAIN_MIN, RESTRAIN_MAX);
    dmg = math.applyPct(dmg, effectiveResist(s));
    if (dmg < 0) dmg = 0;

    s.fight.res -= dmg;
    log(s, def.LOG_NORMAL, MSG_RESTRAIN, dmg, s.fight.res);
}

fn playerAction(s: *def.GameState, a: def.Action, cdef: *const def.CreatureDef) void {
    switch (a.kind) {
        def.ACT_STRIKE => {
            noteBar(s, def.BAR_STRIKE);
            s.fight.actions += 1;
            strike(s, cdef);
        },
        def.ACT_RESTRAIN => {
            noteBar(s, def.BAR_RESTRAIN);
            s.fight.actions += 1;
            restrain(s);
        },
        def.ACT_EQUIP => {
            s.fight.actions += 1;
            s.fight.tool = a.arg;
            s.fight.tool_active = 1;
            log(s, def.LOG_NORMAL, MSG_EQUIP, a.arg, 0);
        },
        def.ACT_FLEE => {
            s.fight.outcome = def.OUT_PLAYER_FLED;
            log(s, def.LOG_NORMAL, MSG_PLAYER_FLED, 0, 0);
        },
        else => {},
    }
}

// ---- Creature action / coupling ------------------------------------------

fn creatureAct(s: *def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    if (s.fight.pending_flee != 0) {
        s.fight.pending_flee = 0;
        s.fight.outcome = def.OUT_CREATURE_FLED;
        log(s, def.LOG_NORMAL, MSG_CREATURE_FLED, 0, 0);
        return;
    }

    var dmg = effectiveAttack(s, cdef, rules);
    if (dmg < 0) dmg = 0;

    s.fight.hull -= dmg;
    s.fight.hull_spent += dmg;
    if (s.fight.hull < 0) s.fight.hull = 0;
    log(s, def.LOG_NORMAL, MSG_CREATURE_ATTACK, dmg, s.fight.hull);
}

fn endRound(s: *def.GameState, cdef: *const def.CreatureDef) void {
    if (belowPct(s.fight.res, s.fight.max_res, THRASH_GATE_PCT) and abovePct(s.fight.hp, s.fight.max_hp, THRASH_GATE_PCT)) {
        var regen = cdef.thrash_regen;
        if (regen == 0) regen = def.COUPLING_REGEN_DEFAULT;
        s.fight.res = std_math.min(s.fight.max_res, s.fight.res + regen);
        log(s, def.LOG_NORMAL, MSG_COUPLING, regen, 1);
    } else if (belowPct(s.fight.hp, s.fight.max_hp, DESPAIR_GATE_PCT) and abovePct(s.fight.res, s.fight.max_res, DESPAIR_RES_GATE_PCT)) {
        var regen = cdef.despair_regen;
        if (regen == 0) regen = def.COUPLING_REGEN_DEFAULT;
        s.fight.hp = std_math.min(s.fight.max_hp, s.fight.hp + regen);
        log(s, def.LOG_NORMAL, MSG_COUPLING, regen, 2);
    }

    s.fight.round += 1;
    s.fight.prev_hp = s.fight.hp;
    s.fight.prev_res = s.fight.res;
}

// ---- Modal resume ---------------------------------------------------------

fn resolveModal(s: *def.GameState, a: def.Action, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    const post = s.screen == SCREEN_SUBDUE_POST;

    if (a.kind == def.ACT_ATTEMPT) {
        if (subdueSuccess(s, cdef)) {
            finishSubdue(s);
            return;
        }
        s.screen = SCREEN_FIGHT;
        finishSurgeFailure(s);
        if (!post) {
            creatureAct(s, cdef, rules);
            if (s.fight.outcome != def.OUT_ONGOING) return;
        }
        endRound(s, cdef);
        return;
    }

    if (a.kind == def.ACT_DECLINE) {
        s.fight.subdue_declined = 1;
        log(s, def.LOG_NORMAL, MSG_DECLINE, 0, 0);
        s.screen = SCREEN_FIGHT;
        if (!post) {
            creatureAct(s, cdef, rules);
            if (s.fight.outcome != def.OUT_ONGOING) return;
        }
        endRound(s, cdef);
        return;
    }
}

// ---- §9.2 resolution ------------------------------------------------------

pub fn step(s: *def.GameState, a: def.Action, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    if (s.fight.outcome != def.OUT_ONGOING) return;

    if (s.screen == SCREEN_SUBDUE or s.screen == SCREEN_SUBDUE_POST) {
        resolveModal(s, a, cdef, rules);
        return;
    }

    switch (a.kind) {
        def.ACT_STRIKE, def.ACT_RESTRAIN, def.ACT_EQUIP, def.ACT_FLEE => {},
        else => return,
    }

    const player_first = !creatureFirst(s, cdef, rules);
    var creature_acted: bool = false;

    if (!player_first) {
        creatureAct(s, cdef, rules);
        creature_acted = true;
        if (s.fight.outcome != def.OUT_ONGOING) return;
    }

    s.fight.prev_hp = s.fight.hp;
    s.fight.prev_res = s.fight.res;
    playerAction(s, a, cdef);
    if (s.fight.outcome != def.OUT_ONGOING) return;

    // Exactly one rule evaluation per action, using the pre-action values.
    applyRules(s, cdef, rules);

    if (checkDeath(s)) return;

    if (gateOpen(s, cdef)) {
        if (cdef.subdue_chance >= def.SUBDUE_PROMPT_BELOW) {
            if (subdueSuccess(s, cdef)) {
                finishSubdue(s);
                return;
            }
            finishSurgeFailure(s);
        } else {
            if (creature_acted) {
                s.screen = SCREEN_SUBDUE_POST;
            } else {
                s.screen = SCREEN_SUBDUE;
            }
            return;
        }
    }

    if (!creature_acted) {
        creatureAct(s, cdef, rules);
        if (s.fight.outcome != def.OUT_ONGOING) return;
    }

    endRound(s, cdef);
}
