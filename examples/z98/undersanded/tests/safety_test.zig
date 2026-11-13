// safety_test.zig — native Linux safety-net tests for the M3 fight gate
// (spec §34 "Subdue determinism", §9.3, §9.5).
//
// Three nets, all deterministic (fixed seed) and driven through the public
// surfaces only:
//   (a) DECLINE (and its F / Esc key equivalents) consumes zero RNG draws.
//   (b) Commons never enter the subdue modal: runSim(token 0, n=200) has a
//       zero prompt counter.
//   (c) Repeated subdue failures fire Last Surge; the attack bonus applies at
//       most once (+25 pp, never re-applied) and the speed bonus caps at +6.
//
// Plus the `--dump-grid` smoke: the `--screen fight` payload (undtool.zig) is
// non-empty and carries the fight header, creature name, bars, and a strike
// log line (the exact grid golden is Task 5, not here).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/safety_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/safety_test"
//   "$OUT/safety_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const behavior = @import("../behavior.zig");
const fight = @import("../fight.zig");
const creatures = @import("../creatures_t1.zig");
const sim = @import("../sim.zig");
const input = @import("../input.zig");
const undtool = @import("../undtool.zig");

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

fn contains(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len and hay[i + j] == needle[j]) : (j += 1) {}
        if (j == needle.len) return true;
    }
    return false;
}

// --dump-grid `--screen fight` produces non-empty text carrying the fight
// header, the creature name, the three bars, and a strike log line.
fn tDumpGridFightText() bool {
    var buf: [8192]u8 = undefined;
    const text = undtool.dumpFightFrame(0, 98, buf[0..]);
    if (text.len == 0) return false;
    if (!contains(text, "UNDERSANDED")) return false;
    if (!contains(text, "Mystic Eel")) return false;
    if (!contains(text, "HP")) return false;
    if (!contains(text, "RESOLVE")) return false;
    if (!contains(text, "HULL")) return false;
    if (!contains(text, "Strike")) return false;
    return true;
}

// A rare modal creature (subdue 60 < SUBDUE_PROMPT_BELOW 90), player first
// (speed 1), no creature damage (attack 0), no rules, no flags.
fn rareModalDef() def.CreatureDef {
    var d = creatures.defAt(0);
    d.id = 201;
    d.family = 0;
    d.role = creatures.ROLE_RARE;
    d.hp = 100;
    d.resolve = 100;
    d.speed = 1;
    d.attack = 0;
    d.thrash_regen = 0;
    d.despair_regen = 0;
    d.armor_pct = 100;
    d.flags = 0;
    d.resist_restrain_pct = 100;
    d.subdue_chance = 60;
    d.discharge_stat = 0;
    d.discharge_th = 0;
    d.discharge_dmg = 0;
    d.rule_start = 0;
    d.rule_count = 0;
    return d;
}

// Start a fight, drain Resolve, and land in the subdue modal.
fn intoModal(s: *def.GameState, d: *const def.CreatureDef) bool {
    s.exp.seed = 98;
    s.exp.fight_index = 0;
    fight.startFightDef(s, 0, d, noRules());
    s.fight.res = 1;
    fight.step(s, def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 }, d, noRules());
    return s.screen == fight.SCREEN_SUBDUE;
}

// (a) DECLINE consumes zero RNG draws: rng_state byte-identical after.
fn tDeclineNoRng() bool {
    var d = rareModalDef();
    var s: def.GameState = undefined;
    if (!intoModal(&s, &d)) return false;

    const before = s.fight.rng_state;
    fight.step(&s, def.Action{ .kind = def.ACT_DECLINE, .arg = 0 }, &d, noRules());

    if (s.fight.rng_state != before) return false;
    if (s.fight.subdue_declined != 1) return false;
    if (s.screen != fight.SCREEN_FIGHT) return false;
    return true;
}

// (a2) F and Esc both map to DECLINE in the modal and consume zero RNG draws,
// each in a separate run (the replay recorder dedupes both to `decline`).
fn tFAndEscDeclineNoRng() bool {
    var d = rareModalDef();

    const f_action = input.mapKey(fight.SCREEN_SUBDUE, input.Key{ .ch = 'f', .code = 0 }) orelse return false;
    if (f_action.kind != def.ACT_DECLINE) return false;
    const esc_action = input.mapKey(fight.SCREEN_SUBDUE, input.Key{ .ch = 0, .code = input.VK_ESC }) orelse return false;
    if (esc_action.kind != def.ACT_DECLINE) return false;

    var s: def.GameState = undefined;
    if (!intoModal(&s, &d)) return false;
    const before_f = s.fight.rng_state;
    fight.step(&s, f_action, &d, noRules());
    if (s.fight.rng_state != before_f) return false;

    if (!intoModal(&s, &d)) return false;
    const before_esc = s.fight.rng_state;
    fight.step(&s, esc_action, &d, noRules());
    if (s.fight.rng_state != before_esc) return false;

    return true;
}

// (b) Commons never prompt: token 0 (Mystic Eel, subdue 95) over 200 fights.
fn tCommonNeverPrompts() bool {
    const r = sim.runSim(0, 200, 98, 100);
    if (r.fights != 200) return false;
    if (r.prompts != 0) return false;
    return true;
}

// (c) A creature whose subdue always fails (chance 0 < 90 opens the modal,
// roll 1..100 <= 0 never succeeds), so every Attempt fires Last Surge.
fn surgeFailDef() def.CreatureDef {
    var d = creatures.defAt(0);
    d.id = 200;
    d.family = 0;
    d.role = creatures.ROLE_RARE;
    d.hp = 1000;
    d.resolve = 1000;
    d.speed = 1;
    d.attack = 8;
    d.thrash_regen = 0;
    d.despair_regen = 0;
    d.armor_pct = 100;
    d.flags = 0;
    d.resist_restrain_pct = 100;
    d.subdue_chance = 0;
    d.discharge_stat = 0;
    d.discharge_th = 0;
    d.discharge_dmg = 0;
    d.rule_start = 0;
    d.rule_count = 0;
    return d;
}

fn failOnce(s: *def.GameState, d: *const def.CreatureDef) bool {
    s.fight.hp = 1000;
    s.fight.res = 1;
    s.fight.outcome = def.OUT_ONGOING;
    s.fight.subdue_declined = 0;
    fight.step(s, def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 }, d, noRules());
    if (s.screen != fight.SCREEN_SUBDUE) return false;
    fight.step(s, def.Action{ .kind = def.ACT_ATTEMPT, .arg = 0 }, d, noRules());
    if (s.fight.outcome != def.OUT_ONGOING) return false;
    return true;
}

// (c2) Four real failures: attack +25pp exactly once (8*125/100 == 10),
// speed +2/surge capped at +6 (1 + 6 == 7), flags never re-applied.
fn tSurgeCapsViaFailures() bool {
    var d = surgeFailDef();
    var s: def.GameState = undefined;
    s.exp.seed = 98;
    s.exp.fight_index = 0;
    fight.startFightDef(&s, 0, &d, noRules());

    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        if (!failOnce(&s, &d)) return false;
    }

    if (s.fight.surge_count != 4) return false;
    if (s.fight.surge_atk_applied != 1) return false;
    if (fight.effectiveAttack(&s, &d, noRules()) != 10) return false;
    if (fight.effectiveSpeed(&s, &d, noRules()) != 7) return false;

    if (!failOnce(&s, &d)) return false;
    if (s.fight.surge_count != 5) return false;
    if (s.fight.surge_atk_applied != 1) return false;
    if (fight.effectiveAttack(&s, &d, noRules()) != 10) return false;
    if (fight.effectiveSpeed(&s, &d, noRules()) != 7) return false;
    return true;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    _ = argv;

    report("decline_no_rng", tDeclineNoRng());
    report("f_esc_decline_no_rng", tFAndEscDeclineNoRng());
    report("common_never_prompts", tCommonNeverPrompts());
    report("surge_caps_via_failures", tSurgeCapsViaFailures());
    report("dump_grid_fight_text", tDumpGridFightText());

    if (fails != 0) {
        io.write("safety_test FAIL\n");
        os.exit(1);
    }
    io.write("safety_test PASS\n");
}
