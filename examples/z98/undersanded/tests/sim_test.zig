// sim_test.zig — native Linux tests for the M3 auto-sim policy and metrics
// (§25.9, §34).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/sim_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/sim_test"
//   "$OUT/sim_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const behavior = @import("../behavior.zig");
const fight = @import("../fight.zig");
const creatures = @import("../creatures_t1.zig");
const sim = @import("../sim.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn noRules() []const behavior.Rule {
    return creatures.RULES[0..0];
}

// A quiet trace fixture: player acts first (speed 1), the creature never
// damages the Hull (attack 0), and Resolve 10 falls in one Restrain. With no
// Shell the §25.9 subdue policy runs: Strike while HP > 50%, then Restrain
// until Resolve 0, where the 100% auto-roll subdues. The 5-fight trace at
// seed 68 is:
//
//   fight  seed  strikes            actions  outcome
//   1      68    S25 S25            3        SUBDUE
//   2      145   S18 S24 S16        4        SUBDUE
//   3      222   S24 S22 S23        4        SUBDUE
//   4      299   S17 S16 S16 S24    5        SUBDUE
//   5      376   S24 S21 S16        4        SUBDUE
//
// Every fight starts on Strike and later switches to Restrain exactly once.
// Totals: actions 3+4+4+5+4 = 20 -> avg 4; 5/5 fights switch -> 100%;
// prompts 0 (subdue 100 >= 90 auto-rolls); surges 0; ascents 0.
fn traceDef() def.CreatureDef {
    var d = creatures.defAt(0);
    d.id = 100;
    d.family = 0;
    d.role = creatures.ROLE_RARE;
    d.hp = 100;
    d.resolve = 10;
    d.speed = 1;
    d.attack = 0;
    d.thrash_regen = 0;
    d.despair_regen = 0;
    d.armor_pct = 100;
    d.flags = 0;
    d.resist_restrain_pct = 100;
    d.subdue_chance = 100;
    d.discharge_stat = 0;
    d.discharge_th = 0;
    d.discharge_dmg = 0;
    d.rule_start = 0;
    d.rule_count = 0;
    return d;
}

fn tTraceMetrics() bool {
    const d = traceDef();
    const r = sim.runSimDef(&d, noRules(), 5, 68, 100);

    if (r.fights != 5) return false;
    if (r.actions != 20) return false;
    if (sim.actionsAvg(&r) != 4) return false;
    if (r.rare_fights != 5) return false;
    if (r.rare_actions != 20) return false;
    if (sim.rareActionsAvg(&r) != 4) return false;
    if (r.ascents != 0) return false;
    if (sim.ascentPm(&r) != 0) return false;
    if (r.switch_fights != 5) return false;
    if (sim.barSwitchPct(&r) != 100) return false;
    if (r.prompts != 0) return false;
    if (r.rare_surges != 0) return false;
    if (sim.surgeAvgPm(&r) != 0) return false;
    if (r.subdue != 5) return false;
    if (r.kill != 0) return false;
    if (r.overkill != 0) return false;
    if (r.fled != 0) return false;
    return true;
}

// (b) No M2 def sets F_SHELL, so synthesize a shell copy of Mystic Eel. At
// full Resolve the kill path restrains (res > 50%) while the normal subdue
// path strikes (hp > 50%); at Resolve 0 the kill path strikes.
fn tShellKillPath() bool {
    const plain = creatures.defAt(0);
    var shell = creatures.defAt(0);
    shell.flags |= def.F_SHELL;

    var s: def.GameState = undefined;
    s.exp.seed = 98;
    s.exp.fight_index = 0;
    fight.startFightDef(&s, 0, &shell, noRules());
    if (sim.chooseAction(&s, &shell).kind != def.ACT_RESTRAIN) return false;

    s.fight.res = 0;
    if (sim.chooseAction(&s, &shell).kind != def.ACT_STRIKE) return false;

    var p: def.GameState = undefined;
    p.exp.seed = 98;
    p.exp.fight_index = 0;
    fight.startFightDef(&p, 0, &plain, noRules());
    if (sim.chooseAction(&p, &plain).kind != def.ACT_STRIKE) return false;
    return true;
}

// The sim always takes the player-equivalent modal action: Attempt, never
// Decline, in both modal screens.
fn tModalAttempt() bool {
    var d = creatures.defAt(3);
    var s: def.GameState = undefined;
    s.exp.seed = 98;
    s.exp.fight_index = 0;
    fight.startFightDef(&s, 0, &d, noRules());

    s.screen = fight.SCREEN_SUBDUE;
    if (sim.chooseAction(&s, &d).kind != def.ACT_ATTEMPT) return false;
    s.screen = fight.SCREEN_SUBDUE_POST;
    if (sim.chooseAction(&s, &d).kind != def.ACT_ATTEMPT) return false;
    return true;
}

// (c) Commons auto-roll silently: 200 fights against Mystic Eel never enter
// the subdue modal, so the prompt counter stays 0 (§34).
fn tCommonNeverPrompts() bool {
    const r = sim.runSim(0, 200, 98, 100);
    if (r.fights != 200) return false;
    if (r.prompts != 0) return false;
    return true;
}

// (d) A creature that empties the Hull on its first action counts as an
// Emergency Ascent and stops the fight after that one game step.
fn tAscentStopsFight() bool {
    var d = creatures.defAt(0);
    d.id = 101;
    d.family = 0;
    d.role = creatures.ROLE_COMMON;
    d.hp = 1000;
    d.resolve = 1000;
    d.speed = 99;
    d.attack = 100;
    d.thrash_regen = 0;
    d.despair_regen = 0;
    d.armor_pct = 100;
    d.flags = 0;
    d.resist_restrain_pct = 100;
    d.subdue_chance = 95;
    d.discharge_stat = 0;
    d.discharge_th = 0;
    d.discharge_dmg = 0;
    d.rule_start = 0;
    d.rule_count = 0;

    const r = sim.runSimDef(&d, noRules(), 1, 98, 100);
    if (r.fights != 1) return false;
    if (r.ascents != 1) return false;
    if (sim.ascentPm(&r) != 1000) return false;
    if (r.actions != 1) return false;
    if (sim.actionsAvg(&r) != 1) return false;
    if (r.subdue != 0) return false;
    if (r.kill != 0) return false;
    if (r.overkill != 0) return false;
    if (r.fled != 0) return false;
    return true;
}

// The sim's `hull` loadout parameter (base 100, ascent gate 125). A creature
// that drains exactly 100 Hull on each of its (creature-first) turns reaches
// Hull 0 after ceil(max_hull/100) steps: 1 step at hull 100, 2 steps at hull
// 125 — so the single-fight action count proves max_hull was actually set to
// 125 rather than left at 100.
fn drainDef() def.CreatureDef {
    var d = creatures.defAt(0);
    d.id = 102;
    d.family = 0;
    d.role = creatures.ROLE_COMMON;
    d.hp = 1000;
    d.resolve = 1000;
    d.speed = 99;
    d.attack = 100;
    d.thrash_regen = 0;
    d.despair_regen = 0;
    d.armor_pct = 100;
    d.flags = 0;
    d.resist_restrain_pct = 100;
    d.subdue_chance = 95;
    d.discharge_stat = 0;
    d.discharge_th = 0;
    d.discharge_dmg = 0;
    d.rule_start = 0;
    d.rule_count = 0;
    return d;
}

fn tHullLoadout() bool {
    const d = drainDef();
    const h100 = sim.runSimDef(&d, noRules(), 1, 98, 100);
    if (h100.ascents != 1) return false;
    if (h100.actions != 1) return false;

    const h125 = sim.runSimDef(&d, noRules(), 1, 98, 125);
    if (h125.ascents != 1) return false;
    if (h125.actions != 2) return false;

    // Anemoniacus (index 3) ascends at base hull; a larger Hull leaves more
    // fights resolved before Hull 0, so the ascent rate must not rise.
    const b100 = sim.runSim(3, 200, 0, 100);
    const b125 = sim.runSim(3, 200, 0, 125);
    if (sim.ascentPm(&b100) <= 0) return false;
    if (sim.ascentPm(&b125) > sim.ascentPm(&b100)) return false;
    return true;
}

// Report arithmetic is integer division: 10/3 -> 3, 1/3 -> 333 per-mille,
// 1/3 -> 33 per-cent, 5/2 -> 2 and 1/2 -> 500 per-mille.
fn tIntegerMath() bool {
    const r = sim.SimReport{
        .fights = 3,
        .actions = 10,
        .rare_fights = 2,
        .rare_actions = 5,
        .ascents = 1,
        .switch_fights = 1,
        .prompts = 0,
        .subdue = 1,
        .kill = 1,
        .overkill = 0,
        .fled = 0,
        .rare_surges = 1,
    };
    if (sim.actionsAvg(&r) != 3) return false;
    if (sim.rareActionsAvg(&r) != 2) return false;
    if (sim.ascentPm(&r) != 333) return false;
    if (sim.barSwitchPct(&r) != 33) return false;
    if (sim.surgeAvgPm(&r) != 500) return false;
    return true;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    _ = argv;

    report("sim_trace_metrics", tTraceMetrics());
    report("shell_kill_path", tShellKillPath());
    report("modal_attempt", tModalAttempt());
    report("common_never_prompts", tCommonNeverPrompts());
    report("ascent_stops_fight", tAscentStopsFight());
    report("hull_loadout", tHullLoadout());
    report("integer_math", tIntegerMath());

    if (fails != 0) {
        io.write("sim_test FAIL\n");
        os.exit(1);
    }
    io.write("sim_test PASS\n");
}
