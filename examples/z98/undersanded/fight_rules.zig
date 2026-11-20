// fight_rules.zig — pure fight rule/effect math.
//
// Derived creature stats, threshold checks, phasing, and rule folding. No
// action/state-machine sequencing here; fight.zig owns that and applies these
// helpers.

const def = @import("def.zig");
const math = @import("math.zig");
const behavior = @import("behavior.zig");
const tools = @import("fight_tools.zig");

pub const PERCENT_BASE: i32 = 100;
pub const DANGER_BASE: i32 = 25;
pub const DROWSY_STRIKE_PCT: i32 = 80;
pub const EXPOSED_INCOMING_PCT: i32 = 125;

pub const LAST_SURGE_ATK_PP: i32 = 25;
pub const LAST_SURGE_SPEED_ADD: i32 = 2;
pub const LAST_SURGE_SPEED_CAP: i32 = 6;

pub const STAT_HP: i32 = 1;
pub const STAT_RES: i32 = 2;

pub const GRUDGE_ARMOR_PCT: i32 = 30;

pub const PHASE_SOLID: i32 = 0;
pub const PHASE_PHASED: i32 = 1;
pub const PHASE_ROUND_SPAN: i32 = 2;
pub const PHASE_LOCK_PCT: i32 = 30;
pub const PHASE_SOLID_RESIST_PCT: i32 = 50;

pub const CREATURE_ACT_ATTACK: i32 = 1;
pub const CREATURE_ACT_FLEE: i32 = 2;

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

// Persistent ADD_SPEED/MULT_ATK rows are evaluated on demand against the
// current state (one-shot rows are latched into FightState by applyEffect).
fn persistentSpeedAdd(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    var total: i32 = 0;
    var dummy = s.fight.rule_consumed;
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        if (rules[u].timing != behavior.TIMING_PERSISTENT) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.hp, s.fight.hp, s.fight.res, s.fight.res, s.fight.round, &dummy, ri);
        if (fired) |e| {
            if (e.op == behavior.ADD_SPEED) total += e.a;
        }
    }
    return total;
}

fn persistentAtkPctAdd(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    var total: i32 = 0;
    var dummy = s.fight.rule_consumed;
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        if (rules[u].timing != behavior.TIMING_PERSISTENT) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.hp, s.fight.hp, s.fight.res, s.fight.res, s.fight.round, &dummy, ri);
        if (fired) |e| {
            if (e.op == behavior.MULT_ATK) total += e.a - PERCENT_BASE;
        }
    }
    return total;
}

// §25.8 phasing: Solid/Phase alternates every two rounds; below 30% HP the
// creature stays Phase. The flag is the sole VM exception (no phase op).
pub fn phaseState(s: *const def.GameState) i32 {
    if ((s.fight.flags & def.F_PHASING) == 0) return PHASE_SOLID;
    if (belowPct(s.fight.hp, s.fight.max_hp, PHASE_LOCK_PCT)) return PHASE_PHASED;
    var r = s.fight.round - 1;
    if (r < 0) r = 0;
    const half = r / PHASE_ROUND_SPAN;
    return half % 2;
}

fn phasingResist(s: *const def.GameState) i32 {
    if ((s.fight.flags & def.F_PHASING) == 0) return 0;
    if (phaseState(s) == PHASE_SOLID) return PHASE_SOLID_RESIST_PCT;
    return PERCENT_BASE;
}

pub fn refreshPhase(s: *def.GameState, cdef: *const def.CreatureDef) void {
    s.fight.phase_state = phaseState(s);
    if ((cdef.flags & def.F_PHASING) != 0) {
        s.fight.active_resist_restrain = phasingResist(s);
    }
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
    sp += persistentSpeedAdd(s, cdef, rules);
    sp += s.fight.rule_speed_add;

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
    pct += persistentAtkPctAdd(s, cdef, rules);
    pct += s.fight.rule_atk_pct_add;

    if (s.fight.cond == def.COND_EXPOSED) pct = math.applyPct(pct, EXPOSED_INCOMING_PCT);

    return math.applyPct(cdef.attack, pct);
}

pub fn creatureFirst(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) bool {
    return effectiveSpeed(s, cdef, rules) > s.fight.player_speed;
}

// Sonar lookahead (P22.3): copy the flat FightState, decide on the copy, and
// discard it. M8 extends the latch-aware view: pending ink/decoy/blind and the
// phasing flip never mutate the real state, so repeated peeks are stable.
pub fn peekCreatureAction(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    var copy: def.GameState = undefined;
    copy.fight = s.fight;

    if (copy.fight.pending_flee != 0 and !tools.hookActive(&copy)) return CREATURE_ACT_FLEE;
    _ = effectiveAttack(&copy, cdef, rules);
    return CREATURE_ACT_ATTACK;
}

// Strike-time armor: compute from the def plus every persistent SET_ARMOR rule
// whose condition currently holds, instead of trusting the cache that
// applyRules refreshed on the previous action.
pub fn effectiveArmorPct(s: *const def.GameState, cdef: *const def.CreatureDef, rules: []const behavior.Rule) i32 {
    var a = cdef.armor_pct;
    if (a <= 0) a = PERCENT_BASE;
    if (cdef.armor_below_th > 0) {
        if (statBelowPct(s.fight.max_hp, s.fight.hp, cdef.armor_below_th)) {
            if (cdef.armor_below_pct > 0) a = cdef.armor_below_pct;
        }
    }

    var dummy = s.fight.rule_consumed;
    var ri: i32 = cdef.rule_start;
    const end: i32 = cdef.rule_start + cdef.rule_count;
    while (ri < end) : (ri += 1) {
        if (ri < 0) continue;
        const u: usize = @intCast(usize, ri);
        if (u >= rules.len) continue;
        if (rules[u].timing != behavior.TIMING_PERSISTENT) continue;
        const fired = behavior.ruleFire(rules[u], s.fight.hp, s.fight.hp, s.fight.res, s.fight.res, s.fight.round, &dummy, ri);
        if (fired) |e| {
            if (e.op == behavior.SET_ARMOR) a = e.a;
        }
    }

    if (s.fight.flags & def.F_GRUDGE_ARMOR != 0) a = GRUDGE_ARMOR_PCT;
    if (s.fight.tool_active != 0 and s.fight.tool == def.TOOL_PLATE) a = PERCENT_BASE;
    return a;
}

pub fn effectiveResistRestrain(s: *const def.GameState) i32 {
    var r = s.fight.active_resist_restrain;
    if ((s.fight.flags & def.F_PHASING) != 0) r = phasingResist(s);
    if (r <= 0) r = PERCENT_BASE;
    if (s.fight.tool_active != 0 and s.fight.tool == def.TOOL_BRINE_NET) r = PERCENT_BASE;
    return r;
}

pub fn resetActive(s: *def.GameState, cdef: *const def.CreatureDef) void {
    s.fight.active_armor_pct = cdef.armor_pct;
    if ((cdef.flags & def.F_PHASING) != 0) {
        s.fight.active_resist_restrain = phasingResist(s);
    } else {
        s.fight.active_resist_restrain = cdef.resist_restrain_pct;
    }
    s.fight.phase_state = phaseState(s);
}

// Combined Strike percentage: Drowsy and armor fold into ONE pct so
// applyPct runs exactly once (§25.4 "never chain applyPct").
pub fn strikePct(cond: i32, armor_pct: i32) i32 {
    var pct = PERCENT_BASE;
    if (cond == def.COND_DROWSY) pct = DROWSY_STRIKE_PCT;
    return math.applyPct(pct, armor_pct);
}
