// fight_test.zig — native Linux tests for M2 fight resolution (§8–§9, §25.3–§25.6).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/fight_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/fight_test"
//   "$OUT/fight_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const math = @import("../math.zig");
const behavior = @import("../behavior.zig");
const fight = @import("../fight.zig");
const game = @import("../game.zig");
const creatures = @import("../creatures_t1.zig");

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

// Neutrally-configured creature row for controlled cases.
fn neutralDef() def.CreatureDef {
    var d = creatures.defAt(2);
    d.id = 99;
    d.family = 0;
    d.role = creatures.ROLE_COMMON;
    d.hp = 100;
    d.resolve = 100;
    d.speed = 1;
    d.attack = 7;
    d.thrash_regen = 0;
    d.despair_regen = 0;
    d.armor_pct = 100;
    d.flags = 0;
    d.resist_restrain_pct = 100;
    d.blind_chance = 0;
    d.subdue_chance = 95;
    d.discharge_stat = 0;
    d.discharge_th = 0;
    d.discharge_dmg = 0;
    d.armor_below_th = 0;
    d.armor_below_pct = 0;
    d.speed_below_stat = 0;
    d.speed_below_th = 0;
    d.speed_below_add = 0;
    d.atk_below_th = 0;
    d.atk_below_pct = 0;
    d.flee_kind = 0;
    d.flee_th = 0;
    d.rule_start = 0;
    d.rule_count = 0;
    return d;
}

fn begin(s: *def.GameState, d: *const def.CreatureDef, rules: []const behavior.Rule) void {
    s.exp.seed = 98;
    s.exp.fight_index = 0;
    fight.startFightDef(s, 0, d, rules);
}

fn doStep(s: *def.GameState, kind: i32, d: *const def.CreatureDef) void {
    fight.step(s, def.Action{ .kind = kind, .arg = 0 }, d, noRules());
}

fn doStepWith(s: *def.GameState, kind: i32, d: *const def.CreatureDef, rules: []const behavior.Rule) void {
    fight.step(s, def.Action{ .kind = kind, .arg = 0 }, d, rules);
}

fn hasMsg(s: *const def.GameState, msg_id: i32) bool {
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].msg_id == msg_id) return true;
    }
    return false;
}

fn msgIndex(s: *const def.GameState, msg_id: i32) i32 {
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].msg_id == msg_id) return i;
    }
    return -1;
}

fn msgA(s: *const def.GameState, msg_id: i32) i32 {
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].msg_id == msg_id) return s.log[@intCast(usize, i)].a;
    }
    return -99999;
}

fn logsEqual(a: *const def.GameState, b: *const def.GameState) bool {
    if (a.log_n != b.log_n) return false;
    var i: usize = 0;
    while (i < def.MAX_LOG) : (i += 1) {
        if (a.log[i].class != b.log[i].class) return false;
        if (a.log[i].msg_id != b.log[i].msg_id) return false;
        if (a.log[i].a != b.log[i].a) return false;
        if (a.log[i].b != b.log[i].b) return false;
    }
    return true;
}

// (a) Lethal strike with overshoot >= margin -> OVERKILL; creature does not act.
fn tOverkillEndsFight() bool {
    var d = neutralDef();
    d.hp = 100;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.hp = 1;

    const hull_before = s.fight.hull;
    doStep(&s, def.ACT_STRIKE, &d);

    if (s.fight.outcome != def.OUT_OVERKILL) return false;
    if (s.fight.hull != hull_before) return false;
    if (hasMsg(&s, fight.MSG_CREATURE_ATTACK)) return false;
    return true;
}

// (b) Resolve <= 0, HP > 0, silent-common success -> SUBDUE; no creature action.
fn tSubdueSilentSuccess() bool {
    var d = neutralDef();
    d.resolve = 5;
    d.subdue_chance = 100;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 5;

    const hull_before = s.fight.hull;
    doStep(&s, def.ACT_RESTRAIN, &d);

    if (s.fight.outcome != def.OUT_SUBDUE) return false;
    if (s.fight.hull != hull_before) return false;
    if (hasMsg(&s, fight.MSG_CREATURE_ATTACK)) return false;
    return true;
}

// (b2) Rare modal: ATTEMPT consumes exactly one draw and can succeed.
fn tSubdueModalAttemptSuccess() bool {
    var d = neutralDef();
    d.resolve = 5;
    d.subdue_chance = 80;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 5;

    doStep(&s, def.ACT_RESTRAIN, &d);
    if (s.screen != fight.SCREEN_SUBDUE) return false;
    if (s.fight.outcome != def.OUT_ONGOING) return false;

    const hull_before = s.fight.hull;
    doStep(&s, def.ACT_ATTEMPT, &d);

    if (s.fight.outcome != def.OUT_SUBDUE) return false;
    if (s.fight.hull != hull_before) return false;
    if (hasMsg(&s, fight.MSG_CREATURE_ATTACK)) return false;
    return true;
}

// (c) Failure -> Last Surge (res ceil, atk +25pp once, speed +2) and the
// creature acts that same round.
fn tLastSurgeAndCreatureActs() bool {
    var d = neutralDef();
    d.subdue_chance = 60;
    d.attack = 8;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 5;
    s.fight.hp = 40;

    doStep(&s, def.ACT_RESTRAIN, &d);
    if (s.screen != fight.SCREEN_SUBDUE) return false;

    doStep(&s, def.ACT_ATTEMPT, &d);

    if (s.fight.outcome != def.OUT_ONGOING) return false;
    if (s.fight.surge_count != 1) return false;
    if (s.fight.surge_atk_applied != 1) return false;
    if (s.fight.res != 30) return false;
    if (!hasMsg(&s, def.MSG_LAST_SURGE)) return false;
    if (!hasMsg(&s, fight.MSG_CREATURE_ATTACK)) return false;
    if (msgIndex(&s, def.MSG_LAST_SURGE) > msgIndex(&s, fight.MSG_CREATURE_ATTACK)) return false;
    if (s.fight.hull != 90) return false;
    if (fight.effectiveAttack(&s, &d, noRules()) != 10) return false;
    if (fight.effectiveSpeed(&s, &d, noRules()) != 3) return false;
    return true;
}

// (c2) Surge stacking: attack +25pp only once, speed +2/surge capped at +6.
fn tSurgeCaps() bool {
    var d = neutralDef();
    d.attack = 8;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());

    fight.lastSurge(&s);
    const atk1 = fight.effectiveAttack(&s, &d, noRules());
    fight.lastSurge(&s);
    fight.lastSurge(&s);
    fight.lastSurge(&s);

    if (s.fight.surge_count != 4) return false;
    if (atk1 != 10) return false;
    if (fight.effectiveAttack(&s, &d, noRules()) != 10) return false;
    if (fight.effectiveSpeed(&s, &d, noRules()) != 7) return false;
    return true;
}

// (d) Coupling regen: row values REPLACE the default +5.
fn tCouplingThrashReplace() bool {
    var d = neutralDef();
    d.thrash_regen = 8;
    d.attack = 0;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 40;

    doStep(&s, def.ACT_EQUIP, &d);
    return s.fight.res == 48;
}

fn tCouplingThrashDefault() bool {
    var d = neutralDef();
    d.thrash_regen = 0;
    d.attack = 0;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 40;

    doStep(&s, def.ACT_EQUIP, &d);
    return s.fight.res == 45;
}

fn tCouplingDespairReplace() bool {
    var d = neutralDef();
    d.despair_regen = 10;
    d.attack = 0;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.hp = 20;

    doStep(&s, def.ACT_EQUIP, &d);
    return s.fight.hp == 30;
}

fn tCouplingDespairTwelve() bool {
    var d = neutralDef();
    d.despair_regen = 12;
    d.attack = 0;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.hp = 20;

    doStep(&s, def.ACT_EQUIP, &d);
    return s.fight.hp == 32;
}

// Creature action is logged before the end-of-round coupling regen.
fn tCouplingAfterCreatureAttack() bool {
    var d = neutralDef();
    d.thrash_regen = 8;
    d.attack = 7;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 40;

    doStep(&s, def.ACT_EQUIP, &d);

    if (s.fight.res != 48) return false;
    if (s.fight.hull != 93) return false;
    const ai = msgIndex(&s, fight.MSG_CREATURE_ATTACK);
    const ci = msgIndex(&s, fight.MSG_COUPLING);
    if (ai < 0 or ci < 0) return false;
    if (ai > ci) return false;
    return true;
}

// Exact-rational boundaries for non-100-divisible maxima (115 / 95 / 105).
fn tExactPctHelpers() bool {
    if (!fight.belowPct(57, 115, 50)) return false;
    if (fight.belowPct(58, 115, 50)) return false;
    if (!fight.belowPct(28, 95, 30)) return false;
    if (fight.belowPct(29, 95, 30)) return false;
    if (!fight.abovePct(58, 115, 50)) return false;
    if (fight.abovePct(57, 115, 50)) return false;
    if (!fight.hitExceedsPct(37, 105, 35)) return false;
    if (fight.hitExceedsPct(36, 105, 35)) return false;
    return true;
}

fn tCouplingExactBoundary115() bool {
    var d = creatures.defAt(3);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.hp = 95;
    s.fight.res = 57;

    doStepWith(&s, def.ACT_EQUIP, &d, creatures.RULES[0..]);
    return s.fight.res == 67;
}

fn tCouplingExactBoundary95() bool {
    var d = creatures.defAt(3);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.hp = 28;
    s.fight.res = 115;

    doStepWith(&s, def.ACT_EQUIP, &d, creatures.RULES[0..]);
    return s.fight.hp == 33;
}

// Persistent rule effects fire exactly once per action/round.
fn tPersistentRegenOnce() bool {
    var d = neutralDef();
    d.attack = 0;
    var rules = [_]behavior.Rule{
        behavior.Rule{
            .cond_op = behavior.ALWAYS,
            .cond_a = 0,
            .cond_b = 0,
            .effect_op = behavior.REGEN_RES,
            .effect_a = 5,
            .effect_b = 0,
            .timing = behavior.TIMING_PERSISTENT,
        },
    };
    d.rule_start = 0;
    d.rule_count = 1;

    var s: def.GameState = undefined;
    begin(&s, &d, rules[0..]);
    s.fight.res = 50;

    doStepWith(&s, def.ACT_EQUIP, &d, rules[0..]);
    return s.fight.res == 55;
}

// Drowsy (80%) + armor (60%) fold into one pct (48) then applyPct once.
fn tStrikeSingleTruncation() bool {
    const pct = fight.strikePct(def.COND_DROWSY, 60);
    if (pct != 48) return false;
    if (math.applyPct(21, pct) != 10) return false;
    if (math.applyPct(21, pct) == 9) return false;
    if (fight.strikePct(def.COND_NONE, 60) != 60) return false;
    return true;
}

fn tLastSurgeRaisedMaxRes() bool {
    var d = neutralDef();
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.max_res = 130;
    s.fight.res = 10;

    fight.lastSurge(&s);
    return s.fight.res == 39;
}


// (e) Overkill margin arithmetic and the Kill boundary.
fn tMarginArithmetic() bool {
    var d = neutralDef();
    d.hp = 200;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    if (fight.margin(&s) != 20) return false;
    if (fight.deathOutcomeFor(19, 20) != def.OUT_KILL) return false;
    if (fight.deathOutcomeFor(20, 20) != def.OUT_OVERKILL) return false;
    if (fight.deathOutcomeFor(0, 20) != def.OUT_KILL) return false;
    return true;
}

fn tKillWhenOvershootBelowMargin() bool {
    var d = neutralDef();
    d.hp = 200;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.hp = 15;

    doStep(&s, def.ACT_STRIKE, &d);

    if (s.fight.outcome != def.OUT_KILL) return false;
    if (s.fight.hull != 100) return false;
    return true;
}

// (f) danger_hp = 25 - margin, clamped >= 0.
fn tDangerHpClamp() bool {
    var d = neutralDef();
    d.hp = 300;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    if (fight.dangerHp(&s) != 0) return false;

    d.hp = 120;
    var s2: def.GameState = undefined;
    begin(&s2, &d, noRules());
    if (fight.margin(&s2) != 12) return false;
    if (fight.dangerHp(&s2) != 13) return false;

    s2.fight.cond = def.COND_SHAKY;
    if (fight.margin(&s2) != 6) return false;
    if (fight.dangerHp(&s2) != 19) return false;
    return true;
}

// §9.2: death is checked before the subdue gate.
fn tDeathBeforeSubdue() bool {
    var d = neutralDef();
    d.subdue_chance = 100;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.hp = 1;
    s.fight.res = 0;

    doStep(&s, def.ACT_STRIKE, &d);

    if (s.fight.outcome == def.OUT_SUBDUE) return false;
    if (s.fight.outcome != def.OUT_OVERKILL) return false;
    if (hasMsg(&s, fight.MSG_SUBDUE_OK)) return false;
    if (!hasMsg(&s, fight.MSG_OVERKILL)) return false;
    return true;
}

// Bar switches count Strike<->Restrain only; Equipment does not switch.
fn tBarSwitches() bool {
    var d = neutralDef();
    d.hp = 1000;
    d.resolve = 1000;
    d.attack = 0;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());

    doStep(&s, def.ACT_STRIKE, &d);
    doStep(&s, def.ACT_RESTRAIN, &d);
    doStep(&s, def.ACT_EQUIP, &d);
    doStep(&s, def.ACT_RESTRAIN, &d);
    doStep(&s, def.ACT_STRIKE, &d);

    if (s.fight.switches != 2) return false;
    if (s.fight.last_bar != def.BAR_STRIKE) return false;
    return true;
}

fn tDischargeMysticElectricEel() bool {
    var d = creatures.defAt(1);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.res = 55;

    doStepWith(&s, def.ACT_RESTRAIN, &d, creatures.RULES[0..]);

    if (msgA(&s, fight.MSG_DISCHARGE) != 8) return false;
    if ((s.fight.rule_consumed & @intCast(u32, 1)) == 0) return false;
    return true;
}

fn tDischargeAnemoniacus() bool {
    var d = creatures.defAt(3);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.hp = 50;

    doStepWith(&s, def.ACT_STRIKE, &d, creatures.RULES[0..]);

    if (msgA(&s, fight.MSG_DISCHARGE) != 10) return false;
    return true;
}

// Freezing Perch: >35% of 105 is 37 (36 does not trigger); flee next turn.
fn tFreezingPerchFlee() bool {
    if (fight.hitExceedsPct(36, 105, 35)) return false;
    if (!fight.hitExceedsPct(37, 105, 35)) return false;

    var d = creatures.defAt(4);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.pending_flee = fight.PENDING_ON;

    doStepWith(&s, def.ACT_EQUIP, &d, creatures.RULES[0..]);

    if (s.fight.outcome != def.OUT_CREATURE_FLED) return false;
    if (hasMsg(&s, fight.MSG_CREATURE_ATTACK)) return false;
    return true;
}

fn tCreatureDefsAndFields() bool {
    if (creatures.DEFS.len != 5) return false;

    const tuna = creatures.DEFS[2];
    if (tuna.hp != 120) return false;
    if (tuna.resolve != 70) return false;
    if (tuna.speed != 6) return false;
    if (tuna.attack != 8) return false;
    if (tuna.subdue_chance != 95) return false;
    if (tuna.speed_below_add != 4) return false;

    const mee = creatures.DEFS[1];
    const rme = creatures.RULES[@intCast(usize, mee.rule_start)];
    if (mee.discharge_th != rme.cond_a) return false;
    if (mee.discharge_dmg != rme.effect_a) return false;

    const ane = creatures.DEFS[3];
    const ran = creatures.RULES[@intCast(usize, ane.rule_start)];
    if (ane.discharge_th != 48) return false;
    if (ane.discharge_th != ran.cond_a) return false;
    if (ane.discharge_dmg != ran.effect_a) return false;
    return true;
}

fn tStartFightWorldZeroed() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 0);

    if (s.world.cycle != 0) return false;
    if (s.world.phase != 0) return false;
    if (s.world.ready[0] != 0) return false;
    if (s.world.seen_mask[0] != 0) return false;
    if (s.world.boat[0] != 0) return false;
    if (s.world.expertise[0] != 0) return false;
    if (s.world.money != 0) return false;
    if (s.world.boss_kills != 0) return false;
    if (s.exp.active != 0) return false;
    if (s.exp.zone != 0) return false;
    return true;
}

// (g) Turn order: ties go to the player; Steel Tuna HP<30% Speed+4 is live.
fn tTurnOrderTiePlayerFirst() bool {
    var d = neutralDef();
    d.speed = 10;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());

    doStep(&s, def.ACT_STRIKE, &d);
    if (s.log_n < 2) return false;
    if (s.log[0].msg_id != fight.MSG_STRIKE) return false;
    return true;
}

fn tSteelTunaSpeedImmediate() bool {
    var d = creatures.defAt(2);
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.hp = 30;

    if (fight.effectiveSpeed(&s, &d, noRules()) != 10) return false;
    if (fight.creatureFirst(&s, &d, noRules())) return false;

    doStep(&s, def.ACT_RESTRAIN, &d);
    if (s.log_n < 2) return false;
    if (s.log[0].msg_id != fight.MSG_RESTRAIN) return false;
    return true;
}

fn tCreatureFasterActsFirst() bool {
    var d = neutralDef();
    d.speed = 11;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());

    doStep(&s, def.ACT_EQUIP, &d);
    if (s.log_n < 2) return false;
    if (s.log[0].msg_id != fight.MSG_CREATURE_ATTACK) return false;
    return true;
}

// (h) DECLINE consumes no RNG; the gate only re-fires while not declined.
fn tDeclineNoRngAndGate() bool {
    var d = neutralDef();
    d.resolve = 5;
    d.subdue_chance = 60;
    d.attack = 0;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.fight.res = 5;

    doStep(&s, def.ACT_RESTRAIN, &d);
    if (s.screen != fight.SCREEN_SUBDUE) return false;

    const rng_before = s.fight.rng_state;
    doStep(&s, def.ACT_DECLINE, &d);
    if (s.fight.rng_state != rng_before) return false;
    if (s.fight.subdue_declined != 1) return false;
    if (s.screen != fight.SCREEN_FIGHT) return false;

    s.fight.outcome = def.OUT_ONGOING;
    s.fight.hp = 100;
    s.fight.res = 0;
    doStep(&s, def.ACT_EQUIP, &d);
    if (s.screen != fight.SCREEN_FIGHT) return false;
    if (s.fight.subdue_declined != 1) return false;

    s.fight.outcome = def.OUT_ONGOING;
    s.fight.subdue_declined = 0;
    s.fight.res = 0;
    s.fight.hp = 100;
    doStep(&s, def.ACT_EQUIP, &d);
    if (s.screen != fight.SCREEN_SUBDUE) return false;
    return true;
}

// Creature attack reduces Hull by its Attack value.
fn tCreatureAttackHull() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 2);

    const before = s.fight.hull;
    game.gameStep(&s, def.Action{ .kind = def.ACT_EQUIP, .arg = 0 });

    if (s.fight.hull != before - 8) return false;
    if (msgA(&s, fight.MSG_CREATURE_ATTACK) != 8) return false;
    return true;
}

// Same seed + same action stream -> byte-identical log (incl. msg_ids).
fn tLogDeterminism() bool {
    var a: def.GameState = undefined;
    var b: def.GameState = undefined;
    game.startFight(&a, 2);
    game.startFight(&b, 2);

    const kinds = [10]i32{
        def.ACT_STRIKE, def.ACT_RESTRAIN, def.ACT_STRIKE, def.ACT_RESTRAIN,
        def.ACT_EQUIP, def.ACT_STRIKE, def.ACT_RESTRAIN, def.ACT_STRIKE,
        def.ACT_RESTRAIN, def.ACT_STRIKE,
    };

    var i: usize = 0;
    while (i < kinds.len) : (i += 1) {
        const act = def.Action{ .kind = kinds[i], .arg = 0 };
        game.gameStep(&a, act);
        game.gameStep(&b, act);
        if (!logsEqual(&a, &b)) return false;
        if (a.fight.rng_state != b.fight.rng_state) return false;
        if (a.fight.outcome != b.fight.outcome) return false;
        if (a.screen != b.screen) return false;
    }
    return true;
}

fn tFleeOutcome() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 0);
    game.gameStep(&s, def.Action{ .kind = def.ACT_FLEE, .arg = 0 });
    return s.fight.outcome == def.OUT_PLAYER_FLED;
}

fn tLogDropOldest() bool {
    var d = neutralDef();
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());

    var i: i32 = 0;
    while (i < 70) : (i += 1) {
        fight.log(&s, def.LOG_NORMAL, i, 0, 0);
    }

    if (s.log_n != 64) return false;
    if (s.log[0].msg_id != 6) return false;
    if (s.log[63].msg_id != 69) return false;
    return true;
}

pub fn main() void {
    report("overkill_ends_fight_no_creature_action", tOverkillEndsFight());
    report("subdue_silent_success_no_creature_action", tSubdueSilentSuccess());
    report("subdue_modal_attempt_success", tSubdueModalAttemptSuccess());
    report("last_surge_and_creature_acts", tLastSurgeAndCreatureActs());
    report("surge_attack_once_speed_cap", tSurgeCaps());
    report("coupling_thrash_override_replaces", tCouplingThrashReplace());
    report("coupling_thrash_default_five", tCouplingThrashDefault());
    report("coupling_despair_override_ten", tCouplingDespairReplace());
    report("coupling_despair_override_twelve", tCouplingDespairTwelve());
    report("coupling_after_creature_attack", tCouplingAfterCreatureAttack());
    report("exact_pct_boundaries_115_95_105", tExactPctHelpers());
    report("coupling_exact_boundary_115", tCouplingExactBoundary115());
    report("coupling_exact_boundary_95", tCouplingExactBoundary95());
    report("persistent_regen_once_per_round", tPersistentRegenOnce());
    report("strike_single_truncation", tStrikeSingleTruncation());
    report("last_surge_raised_max_res", tLastSurgeRaisedMaxRes());
    report("overkill_margin_arithmetic", tMarginArithmetic());
    report("kill_when_overshoot_below_margin", tKillWhenOvershootBelowMargin());
    report("danger_hp_clamp", tDangerHpClamp());
    report("death_before_subdue", tDeathBeforeSubdue());
    report("bar_switches_strike_restrain_only", tBarSwitches());
    report("discharge_mystic_electric_eel", tDischargeMysticElectricEel());
    report("discharge_anemoniacus", tDischargeAnemoniacus());
    report("freezing_perch_flee_boundary", tFreezingPerchFlee());
    report("creature_defs_and_fields", tCreatureDefsAndFields());
    report("start_fight_world_zeroed", tStartFightWorldZeroed());
    report("turn_order_tie_player_first", tTurnOrderTiePlayerFirst());
    report("steel_tuna_speed_immediate_tie_player", tSteelTunaSpeedImmediate());
    report("creature_faster_acts_first", tCreatureFasterActsFirst());
    report("decline_no_rng_gate_refire", tDeclineNoRngAndGate());
    report("creature_attack_reduces_hull", tCreatureAttackHull());
    report("same_seed_stream_log_bytes", tLogDeterminism());
    report("flee_outcome", tFleeOutcome());
    report("log_drop_oldest_64", tLogDropOldest());

    if (fails != 0) os.exit(1);
    io.write("fight_test PASS\n");
}
