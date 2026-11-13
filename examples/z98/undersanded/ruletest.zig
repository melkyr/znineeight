// ruletest.zig — UNDERSANDED `--test-rules` driver (spec §34 T5, M3 Task 3).
//
// Runs the behavior rule VM (behavior.ruleFire) over the full condition ×
// effect × timing matrix against scripted flat FightState fixtures, counting
// passes. The op vocabulary and the 5×10×2 = 100 fixed total are pinned in
// behavior.zig / behavior_test.zig; nothing here redefines an op value.
//
// `rulePassCount()` is the pure counter; `testRules()` prints `rules_ok=<n>`
// on stdout and returns 0 (all 100 pass) or 1 (any fail).

const io = @import("std_io");
const def = @import("def.zig");
const behavior = @import("behavior.zig");

fn makeRule(cond_op: i32, cond_a: i32, cond_b: i32, effect_op: i32, effect_a: i32, effect_b: i32, timing: i32) behavior.Rule {
    return behavior.Rule{
        .cond_op = cond_op,
        .cond_a = cond_a,
        .cond_b = cond_b,
        .effect_op = effect_op,
        .effect_a = effect_a,
        .effect_b = effect_b,
        .timing = timing,
    };
}

fn bitMask(bit: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, bit);
}

// Flat FightState fixture with every field initialized (R8). The rule VM reads
// only prev_hp/hp/prev_res/res/round and the consumed bitset, but the fixture
// is a full def.FightState so the tool exercises the real state layout.
fn fixtureFight() def.FightState {
    return def.FightState{
        .def_index = 0,
        .hp = 100, .max_hp = 100, .res = 100, .max_res = 100,
        .hull = 100, .max_hull = 100,
        .player_speed = 10, .margin_pct = 10,
        .round = 1, .actions = 0, .outcome = def.OUT_ONGOING, .flags = 0,
        .prev_hp = 100, .prev_res = 100,
        .subdue_declined = 0, .surge_count = 0, .surge_atk_applied = 0,
        .tool = 0, .tool_charge = 0, .tool_broken = 0, .tool_active = 0,
        .phase_state = 0, .boss_phase = 0, .boss_axis = 0,
        .last_bar = def.BAR_NONE, .switches = 0, .hull_spent = 0,
        .rng_state = 0,
        .rule_consumed = 0,
        .pending_blind = 0, .pending_ink = 0, .pending_flee = 0,
        .active_armor_pct = 100, .active_resist_restrain = 100,
        .cond = def.COND_NONE,
    };
}

// Choose threshold args (cond_a/cond_b) and shape the fixture so `cond_op`
// holds — and, for a one-shot threshold, so the crossing occurs. Returns false
// for an unknown condition op (never hit by the 1..5 loop).
fn setCond(cond_op: i32, s: *def.FightState, a: *i32, b: *i32) bool {
    switch (cond_op) {
        behavior.HP_BELOW => {
            a.* = 50;
            b.* = 0;
            s.prev_hp = 60;
            s.hp = 49;
            s.prev_res = 100;
            s.res = 100;
            s.round = 1;
            return true;
        },
        behavior.RES_BELOW => {
            a.* = 50;
            b.* = 0;
            s.prev_hp = 100;
            s.hp = 100;
            s.prev_res = 60;
            s.res = 49;
            s.round = 1;
            return true;
        },
        behavior.ROUND_MOD => {
            a.* = 3;
            b.* = 1;
            s.prev_hp = 100;
            s.hp = 100;
            s.prev_res = 100;
            s.res = 100;
            s.round = 1;
            return true;
        },
        behavior.FIRST_ROUND => {
            a.* = 0;
            b.* = 0;
            s.prev_hp = 100;
            s.hp = 100;
            s.prev_res = 100;
            s.res = 100;
            s.round = 1;
            return true;
        },
        behavior.ALWAYS => {
            a.* = 0;
            b.* = 0;
            s.prev_hp = 100;
            s.hp = 100;
            s.prev_res = 100;
            s.res = 100;
            s.round = 1;
            return true;
        },
        else => return false,
    }
}

// One (cond, effect, timing) combination against the rule VM. Persistent rows
// must report the effect on every evaluation; one-shot rows must fire exactly
// once (consumed bit set) and then go quiet. Any unexpected effect, op, or
// no-op fails the pair.
fn runPair(cond_op: i32, effect_op: i32, timing: i32) bool {
    var s: def.FightState = fixtureFight();
    var ca: i32 = 0;
    var cb: i32 = 0;
    if (!setCond(cond_op, &s, &ca, &cb)) return false;

    const ea: i32 = 100 + effect_op;
    const eb: i32 = 200 + effect_op;
    const r = makeRule(cond_op, ca, cb, effect_op, ea, eb, timing);

    const bit: i32 = 0;
    var consumed: u32 = 0;

    if (timing == behavior.TIMING_PERSISTENT) {
        const e = behavior.ruleFire(r, s.prev_hp, s.hp, s.prev_res, s.res, s.round, &consumed, bit) orelse return false;
        if (e.op != effect_op) return false;
        if (e.a != ea) return false;
        if (e.b != eb) return false;
        if (consumed != 0) return false;

        const e2 = behavior.ruleFire(r, s.prev_hp, s.hp, s.prev_res, s.res, s.round, &consumed, bit) orelse return false;
        if (e2.op != effect_op) return false;
        if (e2.a != ea) return false;
        if (e2.b != eb) return false;
        return true;
    }

    // TIMING_ONESHOT
    const e = behavior.ruleFire(r, s.prev_hp, s.hp, s.prev_res, s.res, s.round, &consumed, bit) orelse return false;
    if (e.op != effect_op) return false;
    if (e.a != ea) return false;
    if (e.b != eb) return false;
    if ((consumed & bitMask(bit)) == 0) return false;

    if (behavior.ruleFire(r, s.prev_hp, s.hp, s.prev_res, s.res, s.round, &consumed, bit) != null) return false;
    return true;
}

// Count passing combinations across the pinned 5 × 10 × 2 = 100 matrix.
pub fn rulePassCount() i32 {
    var ok: i32 = 0;
    var cond_op: i32 = behavior.HP_BELOW;
    while (cond_op <= behavior.ALWAYS) : (cond_op += 1) {
        var effect_op: i32 = behavior.REGEN_RES;
        while (effect_op <= behavior.MISS_STRIKE) : (effect_op += 1) {
            var timing: i32 = behavior.TIMING_ONESHOT;
            while (timing <= behavior.TIMING_PERSISTENT) : (timing += 1) {
                if (runPair(cond_op, effect_op, timing)) ok += 1;
            }
        }
    }
    return ok;
}

pub fn testRules() i32 {
    const n = rulePassCount();
    io.write("rules_ok=");
    io.printInt(n);
    io.write("\n");
    if (n == 100) return 0;
    return 1;
}
