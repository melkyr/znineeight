// sim.zig — UNDERSANDED auto-sim harness and metrics (spec §25.9, §34).
//
// The sim drives the pure fight resolver headless with the pinned §25.9
// policy and aggregates the M3 gate metrics. Tooling module: it owns no I/O
// and no rendering, but unlike game.zig it may be called with a synthetic
// CreatureDef (the Shell policy fixture) through runSimDef.
//
// Metric definitions (also printed by undtool --sim):
//   actions = gameStep-equivalent fight.step calls per fight (never
//             FightState.actions, which excludes Attempt/Decline/Flee)
//   ascent  = FightState.hull reached 0 at any point; that fight stops and
//             counts as an Emergency Ascent (M2 clamps Hull at 0)
//   bars    = fights with FightState.switches > 0
//   prompt  = each non-modal -> modal screen entry when the creature's
//             subdue_chance is below SUBDUE_PROMPT_BELOW (commons auto-roll)
//
// Averages/rates are integer division (R6: no floats): per-cent for the
// bar-switch rate, per-mille for ascent and surges.

const def = @import("def.zig");
const fight = @import("fight.zig");
const behavior = @import("behavior.zig");
const creatures = @import("creatures_t1.zig");

// Defensive stop; the policy always terminates on the five M2 rows.
const MAX_STEPS_PER_FIGHT: i32 = 10000;

pub const SimReport = struct {
    fights: i32,
    actions: i32,
    rare_fights: i32,
    rare_actions: i32,
    ascents: i32,
    switch_fights: i32,
    prompts: i32,
    subdue: i32,
    kill: i32,
    overkill: i32,
    fled: i32,
    rare_surges: i32,
};

fn zeroReport() SimReport {
    return SimReport{
        .fights = 0,
        .actions = 0,
        .rare_fights = 0,
        .rare_actions = 0,
        .ascents = 0,
        .switch_fights = 0,
        .prompts = 0,
        .subdue = 0,
        .kill = 0,
        .overkill = 0,
        .fled = 0,
        .rare_surges = 0,
    };
}

fn isModal(screen: i32) bool {
    if (screen == fight.SCREEN_SUBDUE) return true;
    if (screen == fight.SCREEN_SUBDUE_POST) return true;
    return false;
}

// §25.9 policy. Shell creatures take the kill path; everything else the
// subdue path. Any modal state gets the player-equivalent Attempt.
pub fn chooseAction(s: *const def.GameState, cdef: *const def.CreatureDef) def.Action {
    if (isModal(s.screen)) {
        return def.Action{ .kind = def.ACT_ATTEMPT, .arg = 0 };
    }

    if ((cdef.flags & def.F_SHELL) != 0) {
        if (fight.abovePct(s.fight.res, s.fight.max_res, 50)) {
            return def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 };
        }
        return def.Action{ .kind = def.ACT_STRIKE, .arg = 0 };
    }

    if (fight.abovePct(s.fight.hp, s.fight.max_hp, 50)) {
        return def.Action{ .kind = def.ACT_STRIKE, .arg = 0 };
    }
    return def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 };
}

// Run `n_fights` fights of one creature definition, fight i seeded from
// `seed0 + i*77` (fight.startFightDef owns the formula). `hull` is the
// starting/max Hull for each fight (base 100; ascent gate measured at 125).
pub fn runSimDef(cdef: *const def.CreatureDef, rules: []const behavior.Rule, n_fights: i32, seed0: u32, hull: i32) SimReport {
    var r = zeroReport();
    if (n_fights <= 0) return r;

    r.fights = n_fights;
    const rare = cdef.role == creatures.ROLE_RARE;

    var i: i32 = 0;
    while (i < n_fights) : (i += 1) {
        var s: def.GameState = undefined;
        s.exp.seed = seed0;
        s.exp.fight_index = i;
        fight.startFightDef(&s, 0, cdef, rules);
        s.fight.hull = hull;
        s.fight.max_hull = hull;

        var steps: i32 = 0;
        var ascended = false;
        while (s.fight.outcome == def.OUT_ONGOING) {
            const was_modal = isModal(s.screen);
            const a = chooseAction(&s, cdef);
            fight.step(&s, a, cdef, rules);
            steps += 1;

            if (!was_modal and isModal(s.screen) and cdef.subdue_chance < def.SUBDUE_PROMPT_BELOW) {
                r.prompts += 1;
            }

            if (s.fight.hull == 0) {
                ascended = true;
                break;
            }
            if (steps >= MAX_STEPS_PER_FIGHT) break;
        }

        r.actions += steps;
        if (rare) r.rare_actions += steps;
        if (s.fight.switches > 0) r.switch_fights += 1;
        if (rare) r.rare_surges += s.fight.surge_count;

        if (ascended) {
            r.ascents += 1;
        } else {
            switch (s.fight.outcome) {
                def.OUT_SUBDUE => r.subdue += 1,
                def.OUT_KILL => r.kill += 1,
                def.OUT_OVERKILL => r.overkill += 1,
                def.OUT_CREATURE_FLED, def.OUT_PLAYER_FLED => r.fled += 1,
                else => {},
            }
        }
    }

    if (rare) r.rare_fights = n_fights;
    return r;
}

// DEFS[5] wrapper used by undtool --sim.
pub fn runSim(def_index: i32, n_fights: i32, seed0: u32, hull: i32) SimReport {
    var d = creatures.defAt(def_index);
    return runSimDef(&d, creatures.RULES[0..], n_fights, seed0, hull);
}

// ---- Integer report arithmetic -------------------------------------------

pub fn actionsAvg(r: *const SimReport) i32 {
    if (r.fights <= 0) return 0;
    return r.actions / r.fights;
}

pub fn rareActionsAvg(r: *const SimReport) i32 {
    if (r.rare_fights <= 0) return 0;
    return r.rare_actions / r.rare_fights;
}

pub fn ascentPm(r: *const SimReport) i32 {
    if (r.fights <= 0) return 0;
    return r.ascents * 1000 / r.fights;
}

pub fn barSwitchPct(r: *const SimReport) i32 {
    if (r.fights <= 0) return 0;
    return r.switch_fights * 100 / r.fights;
}

pub fn surgeAvgPm(r: *const SimReport) i32 {
    if (r.rare_fights <= 0) return 0;
    return r.rare_surges * 1000 / r.rare_fights;
}
