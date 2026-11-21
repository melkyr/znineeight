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
const tools = @import("tools.zig");
const creatures = @import("creatures_t1.zig");
const std_math = @import("std_math");
const fight_rules = @import("fight_rules.zig");
const fight_tools = @import("fight_tools.zig");

fn hookActive(s: *const def.GameState) bool {
    return fight_tools.hookActive(s);
}

fn shieldActive(s: *const def.GameState) bool {
    return fight_tools.shieldActive(s);
}

fn lureActive(s: *const def.GameState) bool {
    return fight_tools.lureActive(s);
}

fn sonarActive(s: *const def.GameState) bool {
    return fight_tools.sonarActive(s);
}

fn refreshPhase(s: *def.GameState, cdef: *const def.CreatureDef) void {
    fight_rules.refreshPhase(s, cdef);
}

fn resetActive(s: *def.GameState, cdef: *const def.CreatureDef) void {
    fight_rules.resetActive(s, cdef);
}

pub fn margin(s: *const def.GameState) i32 {
    return fight_rules.margin(s);
}

pub fn dangerHp(s: *const def.GameState) i32 {
    return fight_rules.dangerHp(s);
}

pub fn deathOutcomeFor(overshoot: i32, m: i32) i32 {
    return fight_rules.deathOutcomeFor(overshoot, m);
}

pub fn belowPct(v: i32, max: i32, pct: i32) bool {
    return fight_rules.belowPct(v, max, pct);
}

pub fn abovePct(v: i32, max: i32, pct: i32) bool {
    return fight_rules.abovePct(v, max, pct);
}

pub fn hitExceedsPct(v: i32, max: i32, pct: i32) bool {
    return fight_rules.hitExceedsPct(v, max, pct);
}

pub fn phaseState(s: *const def.GameState) i32 {
    return fight_rules.phaseState(s);
}

pub fn effectiveSpeed(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    return fight_rules.effectiveSpeed(s, cdef, rules);
}

pub fn effectiveAttack(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    return fight_rules.effectiveAttack(s, cdef, rules);
}

pub fn creatureFirst(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) bool {
    return fight_rules.creatureFirst(s, cdef, rules);
}

pub fn peekCreatureAction(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    return fight_rules.peekCreatureAction(s, cdef, rules);
}

pub fn effectiveArmorPct(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    return fight_rules.effectiveArmorPct(s, cdef, rules);
}

pub fn effectiveResistRestrain(s: *const def.GameState) i32 {
    return fight_rules.effectiveResistRestrain(s);
}

pub fn strikePct(cond: i32, armor_pct: i32) i32 {
    return fight_rules.strikePct(cond, armor_pct);
}

// ---- Player baseline (§8.1) ----------------------------------------------

pub const BASE_HULL: i32 = 100;
pub const BASE_SPEED: i32 = 10;
pub const STRIKE_MIN: i32 = 15;
pub const STRIKE_MAX: i32 = 25;
pub const RESTRAIN_MIN: i32 = 10;
pub const RESTRAIN_MAX: i32 = 18;
pub const DEFAULT_MARGIN_PCT: i32 = 10;

pub const PERCENT_BASE: i32 = fight_rules.PERCENT_BASE;
pub const DANGER_BASE: i32 = fight_rules.DANGER_BASE;
pub const DROWSY_STRIKE_PCT: i32 = fight_rules.DROWSY_STRIKE_PCT;
pub const EXPOSED_INCOMING_PCT: i32 = fight_rules.EXPOSED_INCOMING_PCT;
pub const SUBDUE_ROLL_MIN: i32 = 1;
pub const SUBDUE_ROLL_MAX: i32 = 100;
pub const PENDING_ON: i32 = 1;

// ---- Last Surge (§9.5) ----------------------------------------------------

pub const LAST_SURGE_RESTORE_PCT: i32 = 25;
pub const LAST_SURGE_ATK_PP: i32 = fight_rules.LAST_SURGE_ATK_PP;
pub const LAST_SURGE_SPEED_ADD: i32 = fight_rules.LAST_SURGE_SPEED_ADD;
pub const LAST_SURGE_SPEED_CAP: i32 = fight_rules.LAST_SURGE_SPEED_CAP;

// ---- Coupling gates (§8.5) ------------------------------------------------

pub const THRASH_GATE_PCT: i32 = 50;
pub const DESPAIR_GATE_PCT: i32 = 30;
pub const DESPAIR_RES_GATE_PCT: i32 = 50;

// ---- Stat thresholds / tools / flee kinds --------------------------------

pub const STAT_HP: i32 = fight_rules.STAT_HP;
pub const STAT_RES: i32 = fight_rules.STAT_RES;

pub const GRUDGE_ARMOR_PCT: i32 = fight_rules.GRUDGE_ARMOR_PCT;

pub const FLEE_HIT_PCT: i32 = 1;

// Phasing (§25.8): Solid/Phase every 2 rounds, locked Phase below 30% HP.
pub const PHASE_SOLID: i32 = fight_rules.PHASE_SOLID;
pub const PHASE_PHASED: i32 = fight_rules.PHASE_PHASED;
pub const PHASE_ROUND_SPAN: i32 = fight_rules.PHASE_ROUND_SPAN;
pub const PHASE_LOCK_PCT: i32 = fight_rules.PHASE_LOCK_PCT;
pub const PHASE_SOLID_RESIST_PCT: i32 = fight_rules.PHASE_SOLID_RESIST_PCT;
// MSG_LURE reveal kind for decoy/target creatures (0/1 are Solid/Phase).
pub const LURE_REVEAL_DECOY: i32 = 2;

// Ink (§25.5/§25.6): one draw maps to Strike/Restrain/Equipment, never Flee.
pub const INK_ACT_MIN: i32 = 0;
pub const INK_ACT_MAX: i32 = 2;

// Sonar lookahead vocabulary (M8: latch-aware attack/flee prediction).
pub const CREATURE_ACT_ATTACK: i32 = fight_rules.CREATURE_ACT_ATTACK;
pub const CREATURE_ACT_FLEE: i32 = fight_rules.CREATURE_ACT_FLEE;

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
    s.fight.pending_miss = 0;
    s.fight.pending_stun = 0;
    s.fight.active_armor_pct = cdef.armor_pct;
    s.fight.active_resist_restrain = cdef.resist_restrain_pct;
    s.fight.rule_speed_add = 0;
    s.fight.rule_atk_pct_add = 0;
    s.fight.cond = def.COND_NONE;
    refreshPhase(s, cdef);

    const fi: u32 = @intCast(u32, s.exp.fight_index);
    const off: u32 = fi * @intCast(u32, 77);
    const seed: u32 = s.exp.seed + off;
    rng.rngSeed(&s.fight.rng_state, seed);

    s.log_n = 0;
    var i: usize = 0;
    while (i < def.MAX_LOG) : (i += 1) {
        s.log[i] = def.LogEntry{ .class = 0, .msg_id = 0, .a = 0, .b = 0 };
    }
    s.exp.pending_cond = def.COND_NONE;
    s.screen = def.SCREEN_FIGHT;
}

// ---- Grudges (§10) --------------------------------------------------------
//
// A named creature's grudge fires when any member of its family was overkilled
// this run. The world mask is run-scoped (world.runReset ends a run); `mask` is
// passed explicitly so game.startFight can apply the pre-reset run mask.
pub fn applyGrudge(s: *def.GameState, cdef: *const def.CreatureDef, mask: u32) void {
    if (cdef.grudge_kind == 0) return;
    if (cdef.grudge_family < 0 or cdef.grudge_family >= 32) return;
    const bit: u32 = @intCast(u32, 1) << @intCast(u32, cdef.grudge_family);
    if ((mask & bit) == 0) return;

    var applied = false;
    switch (cdef.grudge_kind) {
        creatures.GRUDGE_RES => {
            s.fight.res += cdef.grudge_value;
            s.fight.max_res += cdef.grudge_value;
            applied = true;
        },
        creatures.GRUDGE_ARMOR => {
            s.fight.flags = s.fight.flags | def.F_GRUDGE_ARMOR;
            applied = true;
        },
        else => {},
    }
    if (applied) {
        log(s, def.LOG_NORMAL, def.MSG_GRUDGE, cdef.grudge_kind, 0);
    }
}


// ---- Rule VM dispatch -----------------------------------------------------

fn applyEffect(s: *def.GameState, e: def.Effect, timing: i32) void {
    switch (e.op) {
        behavior.REGEN_RES => {
            s.fight.res = std_math.min(s.fight.max_res, s.fight.res + e.a);
        },
        behavior.REGEN_HP => {
            s.fight.hp = std_math.min(s.fight.max_hp, s.fight.hp + e.a);
        },
        behavior.HULL_DMG => {
            // Coral Shield negates discharge-type Hull damage entirely (§10).
            if (shieldActive(s)) return;
            var d = e.a;
            if (d < 0) d = 0;
            s.fight.hull -= d;
            if (s.fight.hull < 0) s.fight.hull = 0;
            s.fight.hull_spent += d;
            log(s, def.LOG_NORMAL, def.MSG_DISCHARGE, d, s.fight.hull);
        },
        behavior.SET_ARMOR => {
            s.fight.active_armor_pct = e.a;
        },
        behavior.SET_FLEE => {
            // Pressure Hook prevents the creature from escaping (§10).
            if (hookActive(s)) return;
            if (e.a != 0) {
                s.fight.pending_flee = e.a;
            } else {
                s.fight.pending_flee = PENDING_ON;
            }
        },
        behavior.SET_BLIND => {
            // Lure reveals the true shape and suppresses blind (§10/§14.5).
            if (lureActive(s)) return;
            const chance = if (e.b != 0) e.b else e.a;
            s.fight.pending_blind = chance;
        },
        behavior.SET_INK => {
            // Sonar prevents ink (§10/§14.5).
            if (sonarActive(s)) return;
            const v = if (e.b != 0) e.b else e.a;
            s.fight.pending_ink = if (v != 0) v else PENDING_ON;
        },
        behavior.ADD_SPEED => {
            // One-shot rows latch their bonus; persistent rows are folded by
            // effectiveSpeed against the current state (§25.6 applied once).
            if (timing == behavior.TIMING_ONESHOT) s.fight.rule_speed_add += e.a;
        },
        behavior.MULT_ATK => {
            // One-shot rows latch their pp; persistent rows are folded by
            // effectiveAttack (single applyPct after all multipliers).
            if (timing == behavior.TIMING_ONESHOT) s.fight.rule_atk_pct_add += e.a - PERCENT_BASE;
        },
        behavior.MISS_STRIKE => {
            // Decoy: the next Strike misses deterministically unless Lure.
            if (lureActive(s)) return;
            s.fight.pending_miss = PENDING_ON;
        },
        else => {},
    }
}

// FIRST_ROUND decoy rows must arm before the player's round-1 action, so this
// pre-action pass evaluates only MISS_STRIKE rows (and honours their consumed
// bit). The regular post-action applyRules pass then sees the bit set.
fn armStrikeRules(s: *def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        if (rules[u].effect_op != behavior.MISS_STRIKE) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.hp, s.fight.hp, s.fight.res, s.fight.res, s.fight.round, &s.fight.rule_consumed, ri);
        if (fired) |e| {
            applyEffect(s, e, rules[u].timing);
        }
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
            applyEffect(s, e, rules[u].timing);
        }
    }
}

// ---- Last Surge -----------------------------------------------------------

pub fn lastSurge(s: *def.GameState) void {
    s.fight.res = math.ceilPct(s.fight.max_res, LAST_SURGE_RESTORE_PCT);
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
    s.screen = def.SCREEN_FIGHT;
    log(s, def.LOG_NORMAL, def.MSG_SUBDUE_OK, 0, 0);
}

fn finishSurgeFailure(s: *def.GameState) void {
    log(s, def.LOG_WARN, def.MSG_SUBDUE_FAIL, 0, 0);
    lastSurge(s);
}

// ---- Death ----------------------------------------------------------------

fn checkDeath(s: *def.GameState) bool {
    if (s.fight.hp > 0) return false;

    const overshoot = 0 - s.fight.hp;
    const m = margin(s);
    const out = deathOutcomeFor(overshoot, m);
    s.fight.outcome = out;

    var msg = def.MSG_KILL;
    var class = def.LOG_NORMAL;
    if (out == def.OUT_OVERKILL) {
        msg = def.MSG_OVERKILL;
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


fn strike(s: *def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    // Phasing: a Phase Strike misses deterministically (§25.8).
    var phase_miss = false;
    if ((s.fight.flags & def.F_PHASING) != 0) {
        if (phaseState(s) == PHASE_PHASED) phase_miss = true;
    }

    // Blind rolls exactly one draw at Strike time (Lure suppresses; §25.5).
    var blind_miss = false;
    if (s.fight.pending_blind != 0) {
        const chance = s.fight.pending_blind;
        if (!lureActive(s)) {
            const roll = rng.rngRange(&s.fight.rng_state, SUBDUE_ROLL_MIN, SUBDUE_ROLL_MAX);
            blind_miss = roll <= chance;
        }
        s.fight.pending_blind = 0;
    }

    // Decoy misses deterministically (no draw); Lure suppresses it.
    var decoy_miss = false;
    if (s.fight.pending_miss != 0) {
        if (!lureActive(s)) decoy_miss = true;
        s.fight.pending_miss = 0;
    }

    if (phase_miss) {
        log(s, def.LOG_NORMAL, def.MSG_PHASE, 0, 0);
        return;
    }
    if (decoy_miss) {
        log(s, def.LOG_NORMAL, def.MSG_DECOY, 0, 0);
        return;
    }
    if (blind_miss) {
        log(s, def.LOG_NORMAL, def.MSG_BLIND, 0, 0);
        return;
    }

    var dmg = rng.rngRange(&s.fight.rng_state, STRIKE_MIN, STRIKE_MAX);
    dmg = math.applyPct(dmg, strikePct(s.fight.cond, effectiveArmorPct(s, cdef, rules)));
    if (dmg < 0) dmg = 0;

    s.fight.hp -= dmg;
    log(s, def.LOG_NORMAL, def.MSG_STRIKE, dmg, s.fight.hp);

    if (cdef.flee_kind == FLEE_HIT_PCT and cdef.flee_th > 0) {
        if (hitExceedsPct(dmg, s.fight.max_hp, cdef.flee_th)) {
            if (!hookActive(s)) s.fight.pending_flee = PENDING_ON;
        }
    }
}

fn restrain(s: *def.GameState) void {
    var dmg = rng.rngRange(&s.fight.rng_state, RESTRAIN_MIN, RESTRAIN_MAX);
    dmg = math.applyPct(dmg, effectiveResistRestrain(s));
    if (dmg < 0) dmg = 0;

    s.fight.res -= dmg;
    log(s, def.LOG_NORMAL, def.MSG_RESTRAIN, dmg, s.fight.res);
}

fn playerAction(s: *def.GameState, a: def.Action, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    switch (a.kind) {
        def.ACT_STRIKE => {
            noteBar(s, def.BAR_STRIKE);
            s.fight.actions += 1;
            strike(s, cdef, rules);
        },
        def.ACT_RESTRAIN => {
            noteBar(s, def.BAR_RESTRAIN);
            s.fight.actions += 1;
            restrain(s);
        },
        def.ACT_EQUIP => {
            // The equipped tool comes from Depart (hunt copies it); the action
            // argument is ignored. Re-check at activation time: a faster
            // creature may have broken the tool after step()'s pre-turn check.
            if (!tools.canEquip(s, s.fight.tool)) return;
            s.fight.actions += 1;
            s.fight.tool_active = 1;
            s.fight.tool_charge -= 1;
            if (s.fight.tool_charge < 0) s.fight.tool_charge = 0;
            s.exp.tool_charge = s.fight.tool_charge;
            log(s, def.LOG_NORMAL, def.MSG_EQUIP, s.fight.tool, 0);
            if (s.fight.tool == def.TOOL_ELECTRIC_GLAND) s.fight.pending_stun = 1;
            if (s.fight.tool == def.TOOL_LURE) {
                // Lure reveals only creatures whose identity is concealed:
                // Solid/Phase for a phaser, the true target for a decoy.
                if ((cdef.flags & def.F_PHASING) != 0) {
                    log(s, def.LOG_NORMAL, def.MSG_LURE, phaseState(s), 0);
                } else if ((cdef.flags & def.F_DECOY) != 0) {
                    log(s, def.LOG_NORMAL, def.MSG_LURE, LURE_REVEAL_DECOY, 0);
                }
            }
            if (s.fight.tool == def.TOOL_SONAR) {
                var reveal = peekCreatureAction(s, cdef, rules);
                // Sonar also shows the Ghost-Ray phase flip (encoded as tens).
                if ((cdef.flags & def.F_PHASING) != 0) {
                    reveal += phaseState(s) * 10;
                }
                log(s, def.LOG_NORMAL, def.MSG_SONAR, effectiveSpeed(s, cdef, rules), reveal);
            }
        },
        def.ACT_FLEE => {
            s.fight.outcome = def.OUT_PLAYER_FLED;
            log(s, def.LOG_NORMAL, def.MSG_PLAYER_FLED, 0, 0);
        },
        else => {},
    }
}

// ---- Creature action / coupling ------------------------------------------

fn creatureAct(s: *def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    // Electric Gland stun: exactly one creature action is lost.
    if (s.fight.pending_stun != 0) {
        s.fight.pending_stun = 0;
        log(s, def.LOG_NORMAL, def.MSG_STUN, 0, 0);
        return;
    }

    if (s.fight.pending_flee != 0 and !hookActive(s)) {
        s.fight.pending_flee = 0;
        s.fight.outcome = def.OUT_CREATURE_FLED;
        log(s, def.LOG_NORMAL, def.MSG_CREATURE_FLED, 0, 0);
        return;
    }

    var dmg = effectiveAttack(s, cdef, rules);
    if (dmg < 0) dmg = 0;

    s.fight.hull -= dmg;
    s.fight.hull_spent += dmg;
    if (s.fight.hull < 0) s.fight.hull = 0;
    log(s, def.LOG_NORMAL, def.MSG_CREATURE_ATTACK, dmg, s.fight.hull);

    // Fragile tools: a single incoming hit, not cumulative damage.
    tools.onHullHit(s, dmg);
}

fn endRound(s: *def.GameState, cdef: *const def.CreatureDef) void {
    if (belowPct(s.fight.res, s.fight.max_res, THRASH_GATE_PCT) and abovePct(s.fight.hp, s.fight.max_hp, THRASH_GATE_PCT)) {
        var regen = cdef.thrash_regen;
        if (regen == 0) regen = def.COUPLING_REGEN_DEFAULT;
        s.fight.res = std_math.min(s.fight.max_res, s.fight.res + regen);
        log(s, def.LOG_NORMAL, def.MSG_COUPLING, regen, 1);
    } else if (belowPct(s.fight.hp, s.fight.max_hp, DESPAIR_GATE_PCT) and abovePct(s.fight.res, s.fight.max_res, DESPAIR_RES_GATE_PCT)) {
        var regen = cdef.despair_regen;
        if (regen == 0) regen = def.COUPLING_REGEN_DEFAULT;
        s.fight.hp = std_math.min(s.fight.max_hp, s.fight.hp + regen);
        log(s, def.LOG_NORMAL, def.MSG_COUPLING, regen, 2);
    }

    s.fight.round += 1;
    s.fight.prev_hp = s.fight.hp;
    s.fight.prev_res = s.fight.res;
}

// ---- Modal resume ---------------------------------------------------------

fn resolveModal(s: *def.GameState, a: def.Action, cdef: *const def.CreatureDef, rules: []const behavior.Rule) void {
    const post = s.screen == def.SCREEN_SUBDUE_POST;

    if (a.kind == def.ACT_ATTEMPT) {
        if (subdueSuccess(s, cdef)) {
            finishSubdue(s);
            return;
        }
        s.screen = def.SCREEN_FIGHT;
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
        // §9.3: the recovering-will copy is Thrash-only (Resolve regen); Despair
        // HP regen does not promise the will returning.
        if (belowPct(s.fight.res, s.fight.max_res, THRASH_GATE_PCT) and abovePct(s.fight.hp, s.fight.max_hp, THRASH_GATE_PCT)) {
            log(s, def.LOG_NORMAL, def.MSG_DECLINE, 0, 0);
        } else {
            log(s, def.LOG_NORMAL, def.MSG_DECLINE_PLAIN, 0, 0);
        }
        s.screen = def.SCREEN_FIGHT;
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

    if (s.screen == def.SCREEN_SUBDUE or s.screen == def.SCREEN_SUBDUE_POST) {
        resolveModal(s, a, cdef, rules);
        return;
    }

    refreshPhase(s, cdef);
    armStrikeRules(s, cdef, rules);

    switch (a.kind) {
        def.ACT_STRIKE, def.ACT_RESTRAIN, def.ACT_EQUIP, def.ACT_FLEE => {},
        else => return,
    }

    // Ink: the next combat action is randomised with one draw (never Flee).
    // Sonar suppresses the effect; the latch is cleared either way.
    var act = a;
    if (s.fight.pending_ink != 0) {
        s.fight.pending_ink = 0;
        if (!sonarActive(s)) {
            const roll = rng.rngRange(&s.fight.rng_state, INK_ACT_MIN, INK_ACT_MAX);
            var forced = def.ACT_STRIKE;
            if (roll == 1) {
                forced = def.ACT_RESTRAIN;
            } else if (roll == 2) {
                forced = def.ACT_EQUIP;
            }
            act = def.Action{ .kind = forced, .arg = 0 };
            log(s, def.LOG_NORMAL, def.MSG_INK, forced, 0);
        }
    }

    // EQUIP is refused before turn order: no round, no creature action, no RNG.
    // The equipped tool comes from Depart; the action arg is never consulted.
    if (act.kind == def.ACT_EQUIP) {
        const equipped = if (s.fight.tool != 0) s.fight.tool else s.exp.tool;
        if (!tools.canEquip(s, equipped)) return;
        if (s.fight.tool == 0) {
            s.fight.tool = equipped;
            s.fight.tool_charge = s.exp.tool_charge;
            s.fight.tool_broken = s.exp.tool_broken;
        }
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
    playerAction(s, act, cdef, rules);
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
                s.screen = def.SCREEN_SUBDUE_POST;
            } else {
                s.screen = def.SCREEN_SUBDUE;
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
