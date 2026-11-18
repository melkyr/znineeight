// grudge_test.zig — native Linux tests for M5 grudges + run scope (§10, §9.5).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/grudge_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/grudge_test"
//   "$OUT/grudge_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const creatures = @import("../creatures_t1.zig");
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");

const DEF_MYSTIC_EEL: i32 = 0;
const DEF_STEEL_TUNA: i32 = 2;
const DEF_MILEEL: i32 = 10;
const DEF_TUNISTEEL: i32 = 11;

const GRUDGE_RES_VALUE: i32 = 30;
const GRUDGE_ARMOR_PCT: i32 = 30;

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

fn newGame() def.GameState {
    var g: def.GameState = undefined;
    game.newGame(&g);
    return g;
}

fn familyBit(family: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, family);
}

fn overkillFamily(g: *def.GameState, def_index: i32) void {
    world.markTaken(&g.world, 0, def_index, def.OUT_OVERKILL);
}

// Force a Z2 day hunt onto `def_index` by making every other zone-1 row
// unavailable. Departing Z2 from Night lands on Day after the travel phases.
fn huntDef(g: *def.GameState, def_index: i32) bool {
    // Z98 lowers `g.world.ready[i]` through a struct copy; mutate via pointer.
    const wp = &g.world;
    wp.phase = world.PHASE_NIGHT;
    wp.cycle = 0;
    var i: usize = 0;
    while (i < def.MAX_ZONES * def.MAX_CREATURES) : (i += 1) {
        wp.ready[i] = 999;
    }
    const ri: usize = def.MAX_CREATURES + @intCast(usize, def_index);
    wp.ready[ri] = 0;
    g.exp.fight_index = 0;

    _ = expedition.depart(g, 1);
    expedition.expeditionStep(g, expedition.EXP_HUNT);
    return expedition.isInFight(g) and g.fight.def_index == def_index;
}

// §10/§9.5: an Eel-family overkill gives Mileel +30 Resolve on both res and
// max_res, so Last Surge's 25% ceil uses the real maximum (43 of 170).
fn tResGrudgeRaisesResAndMax() bool {
    var g = newGame();
    overkillFamily(&g, DEF_MYSTIC_EEL);
    if (!huntDef(&g, DEF_MILEEL)) return false;

    const base = creatures.defAt(DEF_MILEEL).resolve;
    const raised = base + GRUDGE_RES_VALUE;
    if (g.fight.res != raised) return false;
    if (g.fight.max_res != raised) return false;

    fight.lastSurge(&g);
    return g.fight.res == 43 and g.fight.max_res == raised;
}

// §10 P10: "this run" persists across expeditions; only the Derelict kill
// (runReset) clears it. Depart must not reset the mask.
fn tGrudgePersistsAcrossDepart() bool {
    var g = newGame();
    overkillFamily(&g, DEF_MYSTIC_EEL);
    const bit = familyBit(creatures.FAMILY_EEL);
    if ((g.world.family_overkill_mask & bit) == 0) return false;

    const raised = creatures.defAt(DEF_MILEEL).resolve + GRUDGE_RES_VALUE;
    if (!huntDef(&g, DEF_MILEEL)) return false;
    if (g.fight.res != raised) return false;

    _ = expedition.depart(&g, 1);
    if ((g.world.family_overkill_mask & bit) == 0) return false;

    if (!huntDef(&g, DEF_MILEEL)) return false;
    return g.fight.res == raised and g.fight.max_res == raised;
}

// world.runReset is the Derelict-kill boundary: mask cleared, next run clean.
fn tRunResetClears() bool {
    var g = newGame();
    overkillFamily(&g, DEF_MYSTIC_EEL);
    if (g.world.family_overkill_mask == 0) return false;

    world.runReset(&g.world);
    if (g.world.family_overkill_mask != 0) return false;

    if (!huntDef(&g, DEF_MILEEL)) return false;
    const base = creatures.defAt(DEF_MILEEL).resolve;
    return g.fight.res == base and g.fight.max_res == base;
}

// Tunisteel grudge armor is flat 30% unless an active Steel Plate negates it.
fn tGrudgeArmorAndPlate() bool {
    var g = newGame();
    overkillFamily(&g, DEF_STEEL_TUNA);
    if (!huntDef(&g, DEF_TUNISTEEL)) return false;

    const d = creatures.defAt(DEF_TUNISTEEL);
    if (g.fight.flags & def.F_GRUDGE_ARMOR == 0) return false;
    if (fight.effectiveArmorPct(&g, &d, creatures.RULES[0..]) != GRUDGE_ARMOR_PCT) return false;

    g.fight.tool = fight.TOOL_PLATE;
    g.fight.tool_active = 1;
    return fight.effectiveArmorPct(&g, &d, creatures.RULES[0..]) == fight.PERCENT_BASE;
}

// A creature with no grudge row is unaffected even when its family's mask bit
// is set (Steel Tuna keeps 60% armor and base Resolve).
fn tNonGrudgeUnaffected() bool {
    var g = newGame();
    overkillFamily(&g, DEF_STEEL_TUNA);
    if (!huntDef(&g, DEF_STEEL_TUNA)) return false;

    const d = creatures.defAt(DEF_STEEL_TUNA);
    if (g.fight.flags & def.F_GRUDGE_ARMOR != 0) return false;
    if (g.fight.res != d.resolve) return false;
    return fight.effectiveArmorPct(&g, &d, creatures.RULES[0..]) == d.armor_pct;
}

// The standalone game.startFight fixture path applies the run mask too.
fn tGameStartFightAppliesGrudge() bool {
    var g = newGame();
    overkillFamily(&g, DEF_MYSTIC_EEL);
    game.startFight(&g, DEF_MILEEL);
    const raised = creatures.defAt(DEF_MILEEL).resolve + GRUDGE_RES_VALUE;
    if (g.fight.res != raised) return false;
    if (g.fight.max_res != raised) return false;

    var h = newGame();
    overkillFamily(&h, DEF_STEEL_TUNA);
    game.startFight(&h, DEF_TUNISTEEL);
    return h.fight.flags & def.F_GRUDGE_ARMOR != 0;
}

pub fn main() void {
    report("grudge_res_raises_res_and_max", tResGrudgeRaisesResAndMax());
    report("grudge_persists_across_depart", tGrudgePersistsAcrossDepart());
    report("run_reset_clears_mask", tRunResetClears());
    report("grudge_armor_30_plate_100", tGrudgeArmorAndPlate());
    report("non_grudge_family_unaffected", tNonGrudgeUnaffected());
    report("game_start_fight_applies_grudge", tGameStartFightAppliesGrudge());

    if (fails != 0) os.exit(1);
    io.write("grudge_test PASS\n");
}
