// tools_test.zig — native Linux tests for M5 tool lifecycle + fight wiring
// (spec §10, §14.5, §25.3, P22.2/P22.5/P22.8).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/tools_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/tools_test"
//   "$OUT/tools_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const std_mem = @import("std_mem");
const def = @import("../def.zig");
const world = @import("../world.zig");
const rng = @import("../rng.zig");
const behavior = @import("../behavior.zig");
const fight = @import("../fight.zig");
const game = @import("../game.zig");
const expedition = @import("../expedition.zig");
const creatures = @import("../creatures_t1.zig");
const tools = @import("../tools.zig");

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

fn newGame() def.GameState {
    var g: def.GameState = undefined;
    game.newGame(&g);
    return g;
}

fn toolMask(tool: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, tool);
}

fn setBoat(g: *def.GameState, axis: i32, tier: i32) void {
    // Z98 lowers `g.world.array[i]` through a struct copy; use a pointer.
    const wp = &g.world;
    wp.boat[@intCast(usize, axis)] = tier;
}

fn setTool(s: *def.GameState, id: i32, charge: i32) void {
    s.fight.tool = id;
    s.fight.tool_charge = charge;
    s.fight.tool_broken = 0;
    s.fight.tool_active = 0;
    s.exp.tool = id;
    s.exp.tool_charge = charge;
    s.exp.tool_broken = 0;
}

fn neutralDef() def.CreatureDef {
    var d = creatures.defAt(2);
    d.id = 99;
    d.family = 0;
    d.role = creatures.ROLE_COMMON;
    d.hp = 100;
    d.resolve = 100;
    d.speed = 1;
    d.attack = 0;
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
    s.exp.tool = 0;
    s.exp.tool_charge = 0;
    s.exp.tool_broken = 0;
    fight.startFightDef(s, 0, d, rules);
}

fn hasMsg(s: *const def.GameState, msg_id: i32) bool {
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].msg_id == msg_id) return true;
    }
    return false;
}

fn countMsg(s: *const def.GameState, msg_id: i32) i32 {
    var n: i32 = 0;
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].msg_id == msg_id) n += 1;
    }
    return n;
}

fn huntOnce(g: *def.GameState, zone: i32) bool {
    _ = expedition.depart(g, zone);
    expedition.expeditionStep(g, expedition.EXP_HUNT);
    return expedition.isInFight(g);
}

// ---- ids / kinds ----------------------------------------------------------

fn tToolKinds() bool {
    if (!tools.isRigged(1) or tools.isActivated(1)) return false;
    if (!tools.isRigged(2) or tools.isActivated(2)) return false;
    if (!tools.isActivated(3) or tools.isRigged(3)) return false;
    if (!tools.isActivated(4) or tools.isRigged(4)) return false;
    if (!tools.isRigged(5) or tools.isActivated(5)) return false;
    if (!tools.isActivated(6) or tools.isRigged(6)) return false;
    if (!tools.isRigged(7) or tools.isActivated(7)) return false;
    if (tools.isRigged(0) or tools.isActivated(0)) return false;
    return true;
}

// ---- Plate / Brine --------------------------------------------------------

fn tPlateNegatesArmor() bool {
    var d = creatures.defAt(2); // Steel Tuna: armor 60%
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    if (fight.effectiveArmorPct(&s, &d, noRules()) != 60) return false;

    s.fight.tool = fight.TOOL_PLATE;
    s.fight.tool_active = 1;
    return fight.effectiveArmorPct(&s, &d, noRules()) == 100;
}

fn tBrineNetIgnoresShell() bool {
    var d = neutralDef();
    d.resist_restrain_pct = 50;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    if (fight.effectiveResistRestrain(&s) != 50) return false;

    s.fight.tool = fight.TOOL_BRINE_NET;
    s.fight.tool_active = 1;
    return fight.effectiveResistRestrain(&s) == 100;
}

// ---- Coral Shield ---------------------------------------------------------

fn tCoralShieldElectricEel() bool {
    var d = creatures.defAt(1);
    d.attack = 0;
    var control: def.GameState = undefined;
    begin(&control, &d, creatures.RULES[0..]);
    control.fight.res = 55;
    fight.step(&control, def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 }, &d, creatures.RULES[0..]);
    if (control.fight.hull != 92) return false;
    if (!hasMsg(&control, fight.MSG_DISCHARGE)) return false;

    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.res = 55;
    s.fight.tool = fight.TOOL_CORAL_SHIELD;
    s.fight.tool_active = 1;
    fight.step(&s, def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 }, &d, creatures.RULES[0..]);
    if (s.fight.hull != 100) return false;
    if (hasMsg(&s, fight.MSG_DISCHARGE)) return false;
    return true;
}

fn tCoralShieldAnemoniacus() bool {
    var d = creatures.defAt(3);
    d.attack = 0;
    var control: def.GameState = undefined;
    begin(&control, &d, creatures.RULES[0..]);
    control.fight.hp = 50;
    fight.step(&control, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, creatures.RULES[0..]);
    if (control.fight.hull != 90) return false;
    if (!hasMsg(&control, fight.MSG_DISCHARGE)) return false;

    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.hp = 50;
    s.fight.tool = fight.TOOL_CORAL_SHIELD;
    s.fight.tool_active = 1;
    fight.step(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, creatures.RULES[0..]);
    if (s.fight.hull != 100) return false;
    if (hasMsg(&s, fight.MSG_DISCHARGE)) return false;
    return true;
}

// ---- Pressure Hook --------------------------------------------------------

// Find a pre-draw rng state whose next 15..25 roll is exactly `want`.
fn seedForStrike(want: i32) u32 {
    var seed: u32 = 1;
    while (seed < 200000) : (seed += 1) {
        var st = seed;
        if (rng.rngRange(&st, fight.STRIKE_MIN, fight.STRIKE_MAX) == want) return seed;
    }
    return 0;
}

fn fleeOnMaxHit(def_index: i32, hook: bool, want_flee: bool) bool {
    var d = creatures.defAt(def_index);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.player_speed = 99;
    s.fight.rng_state = seedForStrike(fight.STRIKE_MAX);
    if (hook) {
        s.fight.tool = fight.TOOL_PRESSURE_HOOK;
        s.fight.tool_active = 1;
    }

    fight.step(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, creatures.RULES[0..]);
    if (want_flee) {
        return s.fight.outcome == def.OUT_CREATURE_FLED;
    }
    return s.fight.outcome == def.OUT_ONGOING and s.fight.pending_flee == 0;
}

fn tPressureHookBlocksFlee() bool {
    // Mileel (30% of 80 = 24, strict >) and Freezing Perch (20% of 105 = 21).
    if (!fleeOnMaxHit(10, false, true)) return false;
    if (!fleeOnMaxHit(10, true, false)) return false;
    if (!fleeOnMaxHit(4, false, true)) return false;
    if (!fleeOnMaxHit(4, true, false)) return false;
    return true;
}

const FLEE_RULE = [_]behavior.Rule{
    behavior.Rule{
        .cond_op = behavior.ALWAYS,
        .cond_a = 0,
        .cond_b = 0,
        .effect_op = behavior.SET_FLEE,
        .effect_a = 1,
        .effect_b = 0,
        .timing = behavior.TIMING_ONESHOT,
    },
};

fn tPressureHookBlocksSetFleeRule() bool {
    var d = neutralDef();
    d.rule_start = 0;
    d.rule_count = 1;

    var control: def.GameState = undefined;
    begin(&control, &d, FLEE_RULE[0..]);
    fight.step(&control, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, FLEE_RULE[0..]);
    if (control.fight.outcome != def.OUT_CREATURE_FLED) return false;

    var s: def.GameState = undefined;
    begin(&s, &d, FLEE_RULE[0..]);
    s.fight.tool = fight.TOOL_PRESSURE_HOOK;
    s.fight.tool_active = 1;
    fight.step(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, FLEE_RULE[0..]);
    if (s.fight.outcome != def.OUT_ONGOING) return false;
    return s.fight.pending_flee == 0;
}

// ---- Electric Gland stun --------------------------------------------------

fn tStunSkipsOneAction() bool {
    var d = neutralDef();
    d.attack = 5;
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.world.tools_owned = toolMask(fight.TOOL_ELECTRIC_GLAND);
    setTool(&s, fight.TOOL_ELECTRIC_GLAND, 1);

    fight.step(&s, def.Action{ .kind = def.ACT_EQUIP, .arg = 0 }, &d, noRules());
    if (s.fight.tool_active != 1) return false;
    if (s.fight.tool_charge != 0) return false;
    if (s.exp.tool_charge != 0) return false;
    if (s.fight.pending_stun != 0) return false;
    if (s.fight.hull != 100) return false;
    if (countMsg(&s, fight.MSG_STUN) != 1) return false;
    if (hasMsg(&s, fight.MSG_CREATURE_ATTACK)) return false;

    // Exactly one action lost: the next creature action lands.
    fight.step(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, noRules());
    if (s.fight.hull != 95) return false;
    if (countMsg(&s, fight.MSG_STUN) != 1) return false;
    return true;
}

// ---- EQUIP gating ---------------------------------------------------------

fn tEquipChargeOneUse() bool {
    var d = neutralDef();
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());
    s.world.tools_owned = toolMask(4); // Bioluminescent Lure: activated
    setTool(&s, 4, 1);

    fight.step(&s, def.Action{ .kind = def.ACT_EQUIP, .arg = 0 }, &d, noRules());
    if (s.fight.tool_active != 1) return false;
    if (s.fight.tool_charge != 0) return false;
    if (s.exp.tool_charge != 0) return false;
    if (s.fight.tool != 4) return false;

    const round = s.fight.round;
    const actions = s.fight.actions;
    const rng_state = s.fight.rng_state;
    const log_n = s.log_n;

    fight.step(&s, def.Action{ .kind = def.ACT_EQUIP, .arg = 0 }, &d, noRules());
    if (s.fight.round != round) return false;
    if (s.fight.actions != actions) return false;
    if (s.fight.rng_state != rng_state) return false;
    if (s.log_n != log_n) return false;
    return true;
}

fn tEquipRefusalNoRoundNoRng() bool {
    var d = neutralDef();
    var s: def.GameState = undefined;
    begin(&s, &d, noRules());

    const round = s.fight.round;
    const actions = s.fight.actions;
    const rng_state = s.fight.rng_state;
    const log_n = s.log_n;
    fight.step(&s, def.Action{ .kind = def.ACT_EQUIP, .arg = 0 }, &d, noRules());
    if (s.fight.round != round) return false;
    if (s.fight.actions != actions) return false;
    if (s.fight.rng_state != rng_state) return false;
    if (s.log_n != log_n) return false;

    // Broken activated tool is refused too.
    s.world.tools_owned = toolMask(3);
    setTool(&s, 3, 1);
    s.fight.tool_broken = 1;
    s.exp.tool_broken = 1;
    const r2 = s.fight.round;
    const a2 = s.fight.actions;
    const g2 = s.fight.rng_state;
    fight.step(&s, def.Action{ .kind = def.ACT_EQUIP, .arg = 0 }, &d, noRules());
    if (s.fight.round != r2) return false;
    if (s.fight.actions != a2) return false;
    if (s.fight.rng_state != g2) return false;
    return true;
}

// ---- Fragile --------------------------------------------------------------

fn tFragileBoundary() bool {
    var g = newGame();
    setBoat(&g, world.BOAT_PRECISION, 1);
    g.fight.tool = fight.TOOL_PLATE;
    g.fight.tool_active = 1;
    g.exp.tool = fight.TOOL_PLATE;

    tools.onHullHit(&g, 15);
    if (g.fight.tool_broken != 0) return false;
    if (g.fight.tool_active != 1) return false;

    setBoat(&g, world.BOAT_PRECISION, 2);
    tools.onHullHit(&g, 14);
    if (g.fight.tool_broken != 0) return false;

    tools.onHullHit(&g, 15);
    if (g.fight.tool_broken != 1) return false;
    if (g.fight.tool_active != 0) return false;
    return g.exp.tool_broken == 1;
}

// ---- rigged at fight start / break persistence ----------------------------

fn tRiggedActiveAtFightStart() bool {
    var g = newGame();
    g.world.tools_owned = toolMask(fight.TOOL_PLATE);
    g.world.tool_selected = fight.TOOL_PLATE;
    if (!huntOnce(&g, 0)) return false;

    if (g.fight.tool != fight.TOOL_PLATE) return false;
    if (g.fight.tool_active != 1) return false;
    if (g.fight.tool_charge != 0) return false;
    if (g.exp.tool_charge != 0) return false;
    return g.fight.tool_broken == 0;
}

fn tBreakPersistsAcrossFightsAndClearsOnDepart() bool {
    var g = newGame();
    setBoat(&g, world.BOAT_PRECISION, 2);
    g.world.tools_owned = toolMask(fight.TOOL_PLATE);
    g.world.tool_selected = fight.TOOL_PLATE;
    if (!huntOnce(&g, 0)) return false;

    tools.onHullHit(&g, 15);
    if (g.exp.tool_broken != 1) return false;

    // Settle by creature flee, then hunt the next fight in the same trip.
    g.fight.outcome = def.OUT_CREATURE_FLED;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (!expedition.isInFight(&g)) return false;
    if (g.fight.tool != fight.TOOL_PLATE) return false;
    if (g.fight.tool_broken != 1) return false;
    if (g.fight.tool_active != 0) return false;

    _ = expedition.depart(&g, 0);
    if (g.exp.tool_broken != 0) return false;
    return true;
}

// ---- peek -----------------------------------------------------------------

fn tPeekCreatureAction() bool {
    var d = creatures.defAt(10); // Mileel
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);

    if (fight.peekCreatureAction(&s, &d, creatures.RULES[0..]) != fight.CREATURE_ACT_ATTACK) return false;

    s.fight.pending_flee = fight.PENDING_ON;
    if (fight.peekCreatureAction(&s, &d, creatures.RULES[0..]) != fight.CREATURE_ACT_FLEE) return false;

    // Pressure Hook suppresses the flee prediction too.
    s.fight.tool = fight.TOOL_PRESSURE_HOOK;
    s.fight.tool_active = 1;
    if (fight.peekCreatureAction(&s, &d, creatures.RULES[0..]) != fight.CREATURE_ACT_ATTACK) return false;
    return true;
}

fn tPeekLeavesStateByteIdentical() bool {
    var d = creatures.defAt(10);
    var s: def.GameState = undefined;
    begin(&s, &d, creatures.RULES[0..]);
    s.fight.pending_flee = fight.PENDING_ON;
    fight.log(&s, def.LOG_NORMAL, fight.MSG_STRIKE, 7, 93);

    var before = s;
    _ = fight.peekCreatureAction(&s, &d, creatures.RULES[0..]);

    return std_mem.eqlU8(
        @ptrCast([*]const u8, &s),
        @ptrCast([*]const u8, &before),
        @sizeOf(def.GameState),
    );
}

// ---- Speed / Precision loadout --------------------------------------------

fn tSpeedPrecisionLoadout() bool {
    var g = newGame();
    setBoat(&g, world.BOAT_SPEED, 2);
    setBoat(&g, world.BOAT_PRECISION, 3);
    if (!huntOnce(&g, 0)) return false;

    if (g.fight.player_speed != 15) return false;
    return g.fight.margin_pct == 25;
}

pub fn main() void {
    report("tool_kinds_from_table", tToolKinds());
    report("plate_negates_armor_60_to_100", tPlateNegatesArmor());
    report("brine_net_ignores_shell_50_to_100", tBrineNetIgnoresShell());
    report("coral_shield_electric_eel_discharge_zero", tCoralShieldElectricEel());
    report("coral_shield_anemoniacus_discharge_zero", tCoralShieldAnemoniacus());
    report("pressure_hook_blocks_flee", tPressureHookBlocksFlee());
    report("pressure_hook_blocks_set_flee_rule", tPressureHookBlocksSetFleeRule());
    report("electric_gland_stun_skips_one_action", tStunSkipsOneAction());
    report("activated_tool_one_use_per_expedition", tEquipChargeOneUse());
    report("equip_refusal_no_round_no_rng", tEquipRefusalNoRoundNoRng());
    report("fragile_boundary_precision_1_2", tFragileBoundary());
    report("rigged_active_at_fight_start_no_charge", tRiggedActiveAtFightStart());
    report("break_persists_and_clears_on_depart", tBreakPersistsAcrossFightsAndClearsOnDepart());
    report("peek_creature_action_attack_flee", tPeekCreatureAction());
    report("peek_leaves_state_byte_identical", tPeekLeavesStateByteIdentical());
    report("speed_precision_loadout_applied", tSpeedPrecisionLoadout());

    if (fails != 0) os.exit(1);
    io.write("tools_test PASS\n");
}
