// boss_test.zig — native Linux tests for the Derelict boss layer (§15, §19, P31).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/boss_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/boss_test"
//   "$OUT/boss_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const boss = @import("../boss.zig");
const world = @import("../world.zig");
const journal = @import("../journal.zig");
const creatures = @import("../creatures_t1.zig");
const expedition = @import("../expedition.zig");
const render = @import("../render_text.zig");

const BOSS_INDEX: i32 = 18;

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

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn prepare(s: *def.GameState) void {
    game.newGame(s);
    s.exp.active = 1;
    s.exp.zone = 8;
    s.exp.fight_index = 0;
    s.exp.seed = 98;
    var d = creatures.defAt(BOSS_INDEX);
    fight.startFightDef(s, BOSS_INDEX, &d, creatures.rules());
}

fn setBoat(s: *def.GameState, hull: i32, speed: i32, cargo: i32, oxygen: i32, precision: i32) void {
    const w = &s.world;
    w.boat[world.BOAT_HULL] = hull;
    w.boat[world.BOAT_SPEED] = speed;
    w.boat[world.BOAT_CARGO] = cargo;
    w.boat[world.BOAT_OXYGEN] = oxygen;
    w.boat[world.BOAT_PRECISION] = precision;
}

fn step(s: *def.GameState, kind: i32) void {
    var d = creatures.defAt(BOSS_INDEX);
    fight.step(s, def.Action{ .kind = kind, .arg = 0 }, &d, creatures.rules());
}

fn countMsg(s: *const def.GameState, msg_id: i32) i32 {
    var n: i32 = 0;
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].msg_id == msg_id) n += 1;
    }
    return n;
}

fn hasMsg(s: *const def.GameState, msg_id: i32) bool {
    return countMsg(s, msg_id) > 0;
}

fn selectionOk(hull: i32, speed: i32, cargo: i32, oxygen: i32, precision: i32,
    want_axis: i32, want_variant: i32) bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, hull, speed, cargo, oxygen, precision);
    boss.startBoss(&s, &s.world);
    if (s.fight.boss_axis != want_axis) return false;
    if (s.fight.boss_variant != want_variant) return false;
    return true;
}

fn tVariantSelection() bool {
    if (!selectionOk(0, 0, 0, 0, 0, world.BOAT_HULL, boss.VARIANT_ARMOR)) return false;
    if (!selectionOk(1, 1, 1, 1, 1, world.BOAT_HULL, boss.VARIANT_ARMOR)) return false;
    if (!selectionOk(0, 1, 1, 1, 1, world.BOAT_PRECISION, boss.VARIANT_SLIVER)) return false;
    if (!selectionOk(0, 1, 1, 1, 0, world.BOAT_CARGO, boss.VARIANT_HOARD)) return false;
    if (!selectionOk(0, 1, 0, 1, 0, world.BOAT_OXYGEN, boss.VARIANT_DROWN)) return false;
    if (!selectionOk(0, 1, 0, 0, 0, world.BOAT_SPEED, boss.VARIANT_BLUR)) return false;
    if (!selectionOk(3, 2, 2, 2, 2, world.BOAT_HULL, boss.VARIANT_ARMOR)) return false;
    if (!selectionOk(1, 2, 0, 0, 0, world.BOAT_SPEED, boss.VARIANT_BLUR)) return false;
    return true;
}

fn expectedAxis(t: [5]i32) i32 {
    var max_tier: i32 = 0;
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        if (t[i] > max_tier) max_tier = t[i];
    }
    const priority = [5]i32{
        world.BOAT_HULL,
        world.BOAT_PRECISION,
        world.BOAT_CARGO,
        world.BOAT_OXYGEN,
        world.BOAT_SPEED,
    };
    var p: usize = 0;
    while (p < priority.len) : (p += 1) {
        const axis = priority[p];
        if (t[@intCast(usize, axis)] == max_tier) return axis;
    }
    return world.BOAT_HULL;
}

fn expectedVariant(axis: i32) i32 {
    switch (axis) {
        world.BOAT_HULL => return boss.VARIANT_ARMOR,
        world.BOAT_PRECISION => return boss.VARIANT_SLIVER,
        world.BOAT_CARGO => return boss.VARIANT_HOARD,
        world.BOAT_OXYGEN => return boss.VARIANT_DROWN,
        world.BOAT_SPEED => return boss.VARIANT_BLUR,
        else => return boss.VARIANT_ARMOR,
    }
}

// Exhaustive 4^5 boat-tier matrix: max tier wins, tiebreak H>P>C>O>S, and
// all-zero resolves to Hull/The Armor through the same two-step helper.
fn tVariantMatrix() bool {
    var code: i32 = 0;
    while (code < 1024) : (code += 1) {
        var t: [5]i32 = undefined;
        t[world.BOAT_HULL] = code % 4;
        t[world.BOAT_SPEED] = (code / 4) % 4;
        t[world.BOAT_CARGO] = (code / 16) % 4;
        t[world.BOAT_OXYGEN] = (code / 64) % 4;
        t[world.BOAT_PRECISION] = (code / 256) % 4;
        const axis = expectedAxis(t);
        const variant = expectedVariant(axis);
        if (!selectionOk(
            t[world.BOAT_HULL],
            t[world.BOAT_SPEED],
            t[world.BOAT_CARGO],
            t[world.BOAT_OXYGEN],
            t[world.BOAT_PRECISION],
            axis,
            variant
        )) return false;
    }
    return true;
}

fn tPhaseBoundaries() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 0, 1, 0, 0, 0);
    boss.startBoss(&s, &s.world);
    if (s.fight.boss_phase != boss.PHASE_1) return false;
    if (s.world.boss_variants_seen != 0) return false;

    s.fight.hp = 201;
    boss.bossPhaseUpdate(&s);
    if (s.fight.boss_phase != boss.PHASE_1) return false;
    if (s.world.boss_variants_seen != 0) return false;

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);
    if (s.fight.boss_phase != boss.PHASE_2) return false;
    const blur_bit: u32 = @intCast(u32, 1) << @intCast(u32, boss.VARIANT_BLUR);
    if (s.world.boss_variants_seen != blur_bit) return false;

    s.fight.hp = 101;
    boss.bossPhaseUpdate(&s);
    if (s.fight.boss_phase != boss.PHASE_2) return false;

    s.fight.hp = 100;
    boss.bossPhaseUpdate(&s);
    if (s.fight.boss_phase != boss.PHASE_3) return false;
    return true;
}

fn tSpeedAttack() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 1, 0, 0, 0, 0);
    boss.startBoss(&s, &s.world);
    var d = creatures.defAt(BOSS_INDEX);
    const rules = creatures.rules();

    if (fight.effectiveSpeed(&s, &d, rules) != 7) return false;
    if (fight.effectiveAttack(&s, &d, rules) != 10) return false;
    if (fight.creatureFirst(&s, &d, rules)) return false;

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);
    if (fight.effectiveSpeed(&s, &d, rules) != 10) return false;
    if (fight.effectiveAttack(&s, &d, rules) != 15) return false;
    if (fight.creatureFirst(&s, &d, rules)) return false;

    s.fight.hp = 100;
    boss.bossPhaseUpdate(&s);
    if (fight.effectiveSpeed(&s, &d, rules) != 12) return false;
    if (fight.effectiveAttack(&s, &d, rules) != 15) return false;
    return fight.creatureFirst(&s, &d, rules);
}

fn tVolleyCadenceAndPlate() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 0, 0, 0, 0, 1);
    boss.startBoss(&s, &s.world);

    s.fight.round = 2;
    if (boss.attackCount(&s) != 1) return false;
    if (boss.volleyDue(&s)) return false;

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);

    s.fight.round = 1;
    if (boss.attackCount(&s) != 0) return false;
    s.fight.round = 2;
    if (boss.attackCount(&s) != 1) return false;
    if (s.fight.boss_volley_round != 2) return false;
    if (boss.effectiveAttack(&s) != 15) return false;
    s.fight.round = 3;
    if (boss.attackCount(&s) != 0) return false;
    s.fight.round = 4;
    if (boss.attackCount(&s) != 1) return false;

    s.fight.round = 2;
    s.fight.tool = def.TOOL_PLATE;
    s.fight.tool_active = 1;
    if (boss.effectiveAttack(&s) != 7) return false;
    if (boss.attackCount(&s) != 1) return false;
    s.fight.tool_active = 0;
    if (boss.effectiveAttack(&s) != 15) return false;
    return true;
}

fn tArmorVariant() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 1, 0, 0, 0, 0);
    boss.startBoss(&s, &s.world);
    var d = creatures.defAt(BOSS_INDEX);
    const rules = creatures.rules();

    if (fight.effectiveArmorPct(&s, &d, rules) != 100) return false;
    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);
    s.fight.round = 1;
    if (fight.effectiveArmorPct(&s, &d, rules) != 50) return false;

    s.fight.tool = def.TOOL_PLATE;
    s.fight.tool_active = 1;
    if (fight.effectiveArmorPct(&s, &d, rules) != 100) return false;
    return true;
}

fn tSliverVariant() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 0, 0, 0, 0, 1);
    boss.startBoss(&s, &s.world);
    var d = creatures.defAt(BOSS_INDEX);
    const rules = creatures.rules();

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);
    s.fight.round = 1;
    if (fight.effectiveArmorPct(&s, &d, rules) != 100) return false;
    s.fight.round = 2;
    if (fight.effectiveArmorPct(&s, &d, rules) != 25) return false;
    s.fight.round = 3;
    if (fight.effectiveArmorPct(&s, &d, rules) != 100) return false;

    s.fight.round = 2;
    s.fight.tool = def.TOOL_PLATE;
    s.fight.tool_active = 1;
    return fight.effectiveArmorPct(&s, &d, rules) == 25;
}

fn tHoardVariant() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 0, 0, 1, 0, 0);
    boss.startBoss(&s, &s.world);

    const ep = &s.exp;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        ep.hold[i] = 0;
    }
    ep.hold[2] = 5;
    ep.hold[3] = 2;
    ep.hold[8] = 4;

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);

    s.fight.round = 2;
    boss.endRound(&s);
    if (ep.hold[2] != 5) return false;

    s.fight.round = 3;
    boss.endRound(&s);
    if (ep.hold[2] != 0) return false;
    if (ep.hold[3] != 2) return false;
    if (ep.hold[8] != 4) return false;
    if (ep.hold_n != 2) return false;
    if (!hasMsg(&s, def.MSG_BOSS_HOARD)) return false;

    s.fight.round = 6;
    boss.endRound(&s);
    if (ep.hold[3] != 0) return false;
    if (ep.hold[8] != 4) return false;
    if (ep.hold_n != 1) return false;

    s.fight.round = 9;
    boss.endRound(&s);
    return ep.hold[8] == 4;
}

fn tDrownVariant() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 0, 0, 0, 1, 0);
    boss.startBoss(&s, &s.world);

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);

    s.fight.round = 10;
    boss.endRound(&s);
    if (s.fight.hull != 100) return false;

    s.fight.round = 11;
    boss.endRound(&s);
    if (s.fight.hull != 95) return false;
    if (s.fight.hull_spent != 5) return false;

    s.fight.round = 12;
    boss.endRound(&s);
    if (s.fight.hull != 90) return false;
    if (s.fight.hull_spent != 10) return false;
    return countMsg(&s, def.MSG_BOSS_DROWN) == 2;
}

fn tBlurVariant() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 0, 1, 0, 0, 0);
    boss.startBoss(&s, &s.world);

    s.fight.hp = 200;
    boss.bossPhaseUpdate(&s);
    s.fight.player_speed = 100;
    if (!boss.creatureFirst(&s)) return false;

    s.fight.round = 2;
    if (boss.attackCount(&s) != 1) return false;
    s.fight.round = 6;
    if (boss.attackCount(&s) != 2) return false;

    s.fight.hp = 100;
    boss.bossPhaseUpdate(&s);
    s.fight.round = 9;
    if (boss.attackCount(&s) != 2) return false;

    var t: def.GameState = undefined;
    prepare(&t);
    setBoat(&t, 0, 1, 0, 0, 0);
    boss.startBoss(&t, &t.world);
    t.fight.hp = 150;
    boss.bossPhaseUpdate(&t);
    t.fight.round = 6;
    t.fight.hull = 100;
    t.fight.player_speed = 100;
    step(&t, def.ACT_STRIKE);
    if (t.fight.hull != 70) return false;
    return countMsg(&t, def.MSG_CREATURE_ATTACK) == 2;
}

fn tRestrainRejected() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 1, 0, 0, 0, 0);
    boss.startBoss(&s, &s.world);

    const rng_before = s.fight.rng_state;
    const round_before = s.fight.round;
    const hp_before = s.fight.hp;
    const res_before = s.fight.res;
    const actions_before = s.fight.actions;

    step(&s, def.ACT_RESTRAIN);

    if (s.fight.rng_state != rng_before) return false;
    if (s.fight.round != round_before) return false;
    if (s.fight.hp != hp_before) return false;
    if (s.fight.res != res_before) return false;
    if (s.fight.actions != actions_before) return false;
    if (!hasMsg(&s, def.MSG_BOSS_RESTRAIN)) return false;
    if (hasMsg(&s, def.MSG_RESTRAIN)) return false;

    var d = creatures.defAt(BOSS_INDEX);
    var buf: [128]u8 = undefined;
    const line = render.msgLine(s.log[0], &d, buf[0..]);
    return eq(line, "The machine has no will to break.");
}

fn tSubdueRejected() bool {
    var s: def.GameState = undefined;
    prepare(&s);
    setBoat(&s, 1, 0, 0, 0, 0);
    boss.startBoss(&s, &s.world);
    var d = creatures.defAt(BOSS_INDEX);
    if (d.subdue_chance != -1) return false;
    s.fight.hp = 200;
    s.fight.res = 0;
    if (fight.gateOpen(&s, &d)) return false;
    s.fight.hp = 1;
    return !fight.gateOpen(&s, &d);
}

fn bookkeepCase(overkill: bool) bool {
    var s: def.GameState = undefined;
    prepare(&s);
    if (s.world.cycle != 0) return false;
    const eel_bit: u32 = @intCast(u32, 1) << @intCast(u32, creatures.FAMILY_EEL);
    s.world.family_overkill_mask = eel_bit;
    setBoat(&s, 1, 0, 0, 0, 0);
    boss.startBoss(&s, &s.world);
    s.world.family_overkill_mask = eel_bit;

    s.fight.hp = 1;
    s.fight.player_speed = 100;
    if (overkill) {
        s.fight.margin_pct = 0;
    } else {
        s.fight.margin_pct = 1000;
    }
    expedition.expeditionStep(&s, def.ACT_STRIKE);

    if (overkill) {
        if (s.fight.outcome != def.OUT_OVERKILL) return false;
        if (s.world.score_overkilled != 1) return false;
        if (s.world.score_killed != 0) return false;
    } else {
        if (s.fight.outcome != def.OUT_KILL) return false;
        if (s.world.score_killed != 1) return false;
        if (s.world.score_overkilled != 0) return false;
    }
    if (s.world.boss_kills != 1) return false;
    if (!journal.journalUnlocked(&s.world, BOSS_INDEX)) return false;
    if (s.world.family_overkill_mask != 0) return false;
    if (s.fight.def_index != def.NO_FIGHT) return false;

    const idx: usize = 8 * def.MAX_CREATURES + 18;
    const ready = s.world.ready[idx];
    if (overkill) {
        if (ready != 40) return false;
    } else {
        if (ready != 20) return false;
    }

    s.fight.outcome = def.OUT_KILL;
    if (overkill) s.fight.outcome = def.OUT_OVERKILL;
    _ = boss.onDefeat(&s);
    if (s.world.boss_kills != 1) return false;
    if (s.world.score_killed > 1 or s.world.score_overkilled > 1) return false;
    return true;
}

fn tKillBookkeeping() bool {
    return bookkeepCase(false);
}

fn tOverkillBookkeeping() bool {
    return bookkeepCase(true);
}

pub fn main() void {
    report("variant_selection", tVariantSelection());
    report("variant_matrix_all_boats", tVariantMatrix());
    report("phase_boundaries_200_100", tPhaseBoundaries());
    report("speed_attack_bands", tSpeedAttack());
    report("volley_cadence_plate", tVolleyCadenceAndPlate());
    report("armor_variant", tArmorVariant());
    report("sliver_variant", tSliverVariant());
    report("hoard_variant", tHoardVariant());
    report("drown_variant", tDrownVariant());
    report("blur_variant", tBlurVariant());
    report("restrain_rejected", tRestrainRejected());
    report("subdue_rejected", tSubdueRejected());
    report("kill_bookkeeping", tKillBookkeeping());
    report("overkill_bookkeeping", tOverkillBookkeeping());

    if (fails != 0) os.exit(1);
    io.write("boss_test PASS\n");
}
