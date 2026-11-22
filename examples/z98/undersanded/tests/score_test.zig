// score_test.zig — native Linux tests for the M11 score/credits flow (§19, P31).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/score_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/score_test"
//   "$OUT/score_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const mem = @import("std_mem");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const boss = @import("../boss.zig");
const score = @import("../score.zig");
const journal = @import("../journal.zig");
const creatures = @import("../creatures_t1.zig");
const expedition = @import("../expedition.zig");
const render = @import("../render_term.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");
const undtool = @import("../undtool.zig");
const assets = @import("../assets.zig");
const art = @import("../render_art.zig");
const core = @import("std_gfx_px_core.zig");

const BOSS_INDEX: i32 = 18;
const ASSETS_DIR = "examples/z98/undersanded/assets";
const SCORE_GOLDEN = "examples/z98/undersanded/tests/fixtures/dump_grid_score.golden";
const CREDITS_GOLDEN = "examples/z98/undersanded/tests/fixtures/dump_grid_credits.golden";

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

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eq(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn goldenEq(path: []const u8, got: []const u8) bool {
    var storage: [16384]u8 = undefined;
    var arena = arena_mod.init(storage[0..]);
    const data = file_mod.readAll(&arena, path) catch return false;
    return eq(data, got);
}

// Hash only the Field Record boat panel so Last Run text changes do not count.
fn scoreArtBoatHash(g: *def.GameState) u32 {
    const a = assets.current() orelse return 0;
    var view = art.emptyAssets();
    view.boat = assets.boatSprite(a);
    view.paints = assets.boatPaints(a);
    view.overlays = assets.overlays(a);
    const handle = core.gfxPxOpenMemory(640, 480) catch return 0;
    var sf = core.pxCoreSurface(handle.opaque);
    const saved = g.screen;
    g.screen = def.NAV_SCORE;
    art.resetFrame();
    art.renderScreen(&sf, g, "", true, view);
    g.screen = saved;
    const dump = core.gfxPxDump(handle);
    var h: u32 = 2166136261;
    var y: i32 = 16;
    while (y < 174) : (y += 1) {
        var x: i32 = 428;
        while (x < 640) : (x += 1) {
            const off = (@intCast(usize, y) * 640 + @intCast(usize, x)) * 2;
            h = (h ^ @intCast(u32, dump[off])) *% 16777619;
            h = (h ^ @intCast(u32, dump[off + 1])) *% 16777619;
        }
    }
    return h;
}

fn key(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn setBoat(g: *def.GameState, hull: i32, speed: i32, cargo: i32, oxygen: i32, precision: i32) void {
    const w = &g.world;
    w.boat[world.BOAT_HULL] = hull;
    w.boat[world.BOAT_SPEED] = speed;
    w.boat[world.BOAT_CARGO] = cargo;
    w.boat[world.BOAT_OXYGEN] = oxygen;
    w.boat[world.BOAT_PRECISION] = precision;
}

fn startBossFight(g: *def.GameState) bool {
    var d = creatures.defAt(BOSS_INDEX);
    if (d.role != creatures.ROLE_BOSS) return false;
    fight.startFightDef(g, BOSS_INDEX, &d, creatures.rules());
    g.exp.fight_index += 1;
    g.fight.hull = g.world.hull;
    g.fight.max_hull = world.hullMax(&g.world);
    g.fight.player_speed = world.speedMax(&g.world);
    g.fight.margin_pct = world.precisionMargin(&g.world);
    boss.startBoss(g, &g.world);
    return true;
}

fn prepareBoss(g: *def.GameState) bool {
    game.newGame(g);
    g.exp.active = 1;
    g.exp.zone = 8;
    g.exp.fight_index = 0;
    g.exp.seed = 98;
    return startBossFight(g);
}

fn strikeBoss(g: *def.GameState, overkill: bool) bool {
    g.fight.hp = 1;
    g.fight.player_speed = 100;
    if (overkill) {
        g.fight.margin_pct = 0;
    } else {
        g.fight.margin_pct = 1000;
    }
    expedition.expeditionStep(g, def.ACT_STRIKE);
    const want = if (overkill) def.OUT_OVERKILL else def.OUT_KILL;
    return g.fight.outcome == want;
}

fn leaveCreditsAndScore(g: *def.GameState) bool {
    var st = nav.initState();
    if (nav.navStep(g, &st, key('c')) != def.NAV_SCORE) return false;
    if (g.screen != def.NAV_SCORE) return false;
    if (nav.navStep(g, &st, key('c')) != def.NAV_DOCK) return false;
    return g.screen == def.NAV_DOCK and g.exp.active == 0;
}

fn fieldSame(a: *const def.FieldRecord, b: *const def.FieldRecord) bool {
    var aa = a.*;
    var bb = b.*;
    aa.field_phases = 0;
    bb.field_phases = 0;
    return mem.eqlU8(@ptrCast([*]const u8, &aa), @ptrCast([*]const u8, &bb),
        @sizeOf(def.FieldRecord));
}

fn tScoreCopy() bool {
    var w: def.World = undefined;
    game.zeroWorld(&w);
    w.boss_variants_seen = 0x15;
    var p = score.scoreSnapshot(&w);
    var sc: render.Screen = undefined;
    render.renderScore(&p, &sc);
    var buf: [8192]u8 = undefined;
    const text = render.dump(&sc, buf[0..]);
    if (!contains(text, "UNDERSANDED  SCORE")) return false;
    if (!contains(text, "FIELD RECORD")) return false;
    if (!contains(text, "VARIANTS SEEN")) return false;
    if (!contains(text, "LAST RUN")) return false;
    if (!contains(text, "Variants: 3 / 5")) return false;
    if (!contains(text, "[x] The Armor")) return false;
    if (!contains(text, "[ ] The Sliver")) return false;
    if (!contains(text, "[x] The Hoard")) return false;
    if (!contains(text, "[ ] The Drown")) return false;
    if (!contains(text, "[x] The Blur")) return false;
    if (!contains(text, score.CLOSING)) return false;
    if (!contains(text, "[C]ontinue")) return false;
    return contains(text, "[?] Help");
}

fn tCreditsCopy() bool {
    var sc: render.Screen = undefined;
    render.renderCredits(&sc);
    var buf: [8192]u8 = undefined;
    const text = render.dump(&sc, buf[0..]);
    if (!contains(text, "UNDERSANDED")) return false;
    if (!contains(text, "A Z98 demo.")) return false;
    if (!contains(text, "Design, code, art, and data by the Undersanded team.")) return false;
    if (!contains(text, "[C]ontinue")) return false;
    return contains(text, "[?] Help");
}

fn tGolden(screen_id: []const u8, path: []const u8) bool {
    var buf: [8192]u8 = undefined;
    const text = undtool.dumpFixedScreen(screen_id, buf[0..]) orelse return false;
    return goldenEq(path, text);
}

fn tHelpAndAllow() bool {
    if (journal.helpPageNumber(def.NAV_SCORE) != 8) return false;
    if (journal.helpPageNumber(def.NAV_CREDITS) != 8) return false;
    if (def.NAV_SCORE < 25 or def.NAV_CREDITS < 25) return false;
    if (!nav.screenAllowed(def.NAV_SCORE)) return false;
    if (!nav.screenAllowed(def.NAV_CREDITS)) return false;
    return !nav.screenAllowed(def.SCREEN_FIGHT);
}

fn tFieldFreeze() bool {
    var w: def.World = undefined;
    game.zeroWorld(&w);
    w.cycle = 4;
    w.field_phases = 21;
    w.boss_kills = 1;
    w.score_subdued = 2;
    w.score_killed = 3;
    w.score_overkilled = 4;
    w.score_money_earned = 55;
    w.cosmetics_owned = 0x0000000D;
    w.boat[world.BOAT_HULL] = 2;
    w.expertise[1] = 3;
    score.freezeFieldRecord(&w, boss.VARIANT_HOARD);
    if (w.field_record_written != 1) return false;
    if (w.field_record.cycles != 4) return false;
    if (w.field_record.field_phases != 21) return false;
    if (w.field_record.bosses_killed != 1) return false;
    if (w.field_record.final_phase2 != boss.VARIANT_HOARD) return false;
    if (w.field_record.subdued != 2) return false;
    if (w.field_record.killed != 3) return false;
    if (w.field_record.overkilled != 4) return false;
    if (w.field_record.money_earned != 55) return false;
    if (w.field_record.cosmetics != 3) return false;
    if (w.field_record.cosmetics_mask != 0x0000000D) return false;
    if (w.field_record.boat[world.BOAT_HULL] != 2) return false;
    if (w.field_record.expertise[1] != 3) return false;

    var first = w.field_record;
    w.cycle = 9;
    w.field_phases = 99;
    w.boss_kills = 2;
    w.score_killed = 8;
    w.score_money_earned = 500;
    w.boat[world.BOAT_HULL] = 0;
    score.freezeFieldRecord(&w, boss.VARIANT_BLUR);
    return fieldSame(&first, &w.field_record);
}

fn tVariantsSurviveAscent() bool {
    var g: def.GameState = undefined;
    if (!prepareBoss(&g)) return false;
    g.fight.hp = 199;
    boss.bossPhaseUpdate(&g);
    const arm_bit: u32 = 1;
    if ((g.world.boss_variants_seen & arm_bit) == 0) return false;
    g.fight.hull = 0;
    expedition.expeditionStep(&g, 0);
    if ((g.world.boss_variants_seen & arm_bit) == 0) return false;
    if (g.world.boss_variants_seen != arm_bit) return false;
    if (g.exp.active != 0) return false;
    if (score.outcomeLabel(g.world.last_run.outcome)[0] != 'A') return false;
    return eq(score.outcomeLabel(g.world.last_run.outcome), "Ascent");
}

fn tLastRunOverwrite() bool {
    var g: def.GameState = undefined;
    if (!prepareBoss(&g)) return false;
    g.fight.actions = 7;
    g.fight.hull_spent = 42;
    score.recordLastRun(&g.world, &g.fight, def.OUT_PLAYER_FLED);
    if (g.world.last_run.outcome != def.OUT_PLAYER_FLED) return false;
    if (g.world.last_run.actions != 7) return false;
    if (g.world.last_run.hull_spent != 42) return false;

    g.fight.actions = 11;
    g.fight.hull_spent = 80;
    g.world.boss_kills = 1;
    score.recordLastRun(&g.world, &g.fight, def.OUT_OVERKILL);
    if (g.world.last_run.outcome != def.OUT_OVERKILL) return false;
    if (g.world.last_run.actions != 11) return false;
    if (g.world.last_run.hull_spent != 80) return false;
    if (g.world.last_run.boss_kills != 1) return false;
    return eq(score.outcomeLabel(g.world.last_run.outcome), "Overkill");
}

fn tDefeatRoute(overkill: bool) bool {
    var g: def.GameState = undefined;
    if (!prepareBoss(&g)) return false;
    setBoat(&g, 0, 0, 1, 0, 0);
    boss.startBoss(&g, &g.world);
    g.world.family_overkill_mask = 0xFFFFFFFF;
    const phases_before = g.world.field_phases;
    if (!strikeBoss(&g, overkill)) return false;

    if (g.screen != def.NAV_CREDITS) return false;
    if (g.exp.active != 1) return false;
    if (g.world.boss_kills != 1) return false;
    if (g.world.field_record_written != 1) return false;
    if (!journal.journalUnlocked(&g.world, BOSS_INDEX)) return false;
    if (g.world.family_overkill_mask != 0) return false;
    if (overkill) {
        if (g.world.score_overkilled != 1) return false;
        if (g.world.score_killed != 0) return false;
    } else {
        if (g.world.score_killed != 1) return false;
        if (g.world.score_overkilled != 0) return false;
    }
    const want = if (overkill) def.OUT_OVERKILL else def.OUT_KILL;
    if (g.world.last_run.outcome != want) return false;
    if (g.world.last_run.boss_kills != 1) return false;
    if (g.world.field_record.final_phase2 != boss.VARIANT_HOARD) return false;

    var st = nav.initState();
    if (nav.navStep(&g, &st, key('?')) != def.NAV_CREDITS) return false;
    if (st.help_page != 8) return false;
    if (nav.navStep(&g, &st, key('x')) != def.NAV_CREDITS) return false;
    if (nav.navStep(&g, &st, key('c')) != def.NAV_SCORE) return false;
    if (nav.navStep(&g, &st, key('?')) != def.NAV_SCORE) return false;
    if (st.help_page != 8) return false;
    if (nav.navStep(&g, &st, key('x')) != def.NAV_SCORE) return false;
    if (nav.navStep(&g, &st, key('c')) != def.NAV_DOCK) return false;
    if (g.exp.active != 0) return false;
    if (g.world.field_phases != phases_before + 5) return false;
    if (g.world.boss_kills != 1) return false;
    if (overkill) {
        if (g.world.score_overkilled != 1) return false;
    } else {
        if (g.world.score_killed != 1) return false;
    }
    return true;
}

fn tKillRoute() bool {
    return tDefeatRoute(false);
}

fn tOverkillRoute() bool {
    return tDefeatRoute(true);
}

fn tSecondDefeatKeepsRecord() bool {
    if (!assets.load(ASSETS_DIR)) return false;
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.world.cosmetics_owned = @intCast(u32, 1) << @intCast(u32, 1);
    if (expedition.depart(&g, 8).active != 1) return false;
    setBoat(&g, 0, 0, 1, 0, 0);
    if (!startBossFight(&g)) return false;
    if (!strikeBoss(&g, false)) return false;
    if (g.world.field_record.final_phase2 != boss.VARIANT_HOARD) return false;
    if (g.world.field_record.cosmetics_mask != g.world.cosmetics_owned) return false;
    var first = g.world.field_record;
    const first_boat = scoreArtBoatHash(&g);
    if (!leaveCreditsAndScore(&g)) return false;

    if (expedition.depart(&g, 8).active != 1) return false;
    g.world.cosmetics_owned |= @intCast(u32, 1) << @intCast(u32, 2);
    setBoat(&g, 0, 1, 0, 0, 0);
    if (!startBossFight(&g)) return false;
    if (!strikeBoss(&g, true)) return false;
    if (g.world.boss_kills != 2) return false;
    if (g.world.field_record_written != 1) return false;
    if (!fieldSame(&first, &g.world.field_record)) return false;
    if (g.world.field_record.cosmetics_mask !=
        (@intCast(u32, 1) << @intCast(u32, 1))) return false;
    if (scoreArtBoatHash(&g) != first_boat) return false;
    if (g.world.field_record.final_phase2 != boss.VARIANT_HOARD) return false;
    return eq(score.identityLabel(g.world.last_run.phase2), "The Blur");
}

fn tLossRecordsLastRun() bool {
    var g: def.GameState = undefined;
    if (!prepareBoss(&g)) return false;
    setBoat(&g, 0, 0, 0, 1, 0);
    boss.startBoss(&g, &g.world);
    g.fight.actions = 5;
    g.fight.hull_spent = 33;
    g.fight.outcome = def.OUT_PLAYER_FLED;
    expedition.expeditionStep(&g, 0);
    if (g.exp.active != 0) return false;
    if (g.world.last_run.outcome != def.OUT_PLAYER_FLED) return false;
    if (g.world.last_run.actions != 5) return false;
    if (g.world.last_run.hull_spent != 33) return false;
    if (eq(score.identityLabel(g.world.last_run.phase2), "The Drown") == false) return false;
    if (g.world.field_record_written != 0) return false;
    return true;
}

fn tNonBossCounters() bool {
    var k: def.GameState = undefined;
    game.newGame(&k);
    k.exp.active = 1;
    k.exp.zone = 0;
    var d = creatures.defAt(0);
    fight.startFightDef(&k, 0, &d, creatures.rules());
    k.fight.hp = 1;
    k.fight.player_speed = 100;
    k.fight.margin_pct = 1000;
    expedition.expeditionStep(&k, def.ACT_STRIKE);
    if (k.fight.outcome != def.OUT_KILL) return false;
    if (k.world.score_killed != 1) return false;
    if (k.world.score_overkilled != 0) return false;
    if (k.world.last_run.actions != 0) return false;

    var o: def.GameState = undefined;
    game.newGame(&o);
    o.exp.active = 1;
    o.exp.zone = 0;
    var od = creatures.defAt(0);
    fight.startFightDef(&o, 0, &od, creatures.rules());
    o.fight.hp = 1;
    o.fight.player_speed = 100;
    o.fight.margin_pct = 0;
    expedition.expeditionStep(&o, def.ACT_STRIKE);
    return o.fight.outcome == def.OUT_OVERKILL and o.world.score_overkilled == 1
        and o.world.score_killed == 0;
}

fn tSellMoney() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.world.rng_state = 0;
    _ = expedition.depart(&g, 1);
    expedition.expeditionStep(&g, expedition.EXP_HUNT);

    var guard: i32 = 0;
    while (expedition.isInFight(&g) and guard < 60) : (guard += 1) {
        if (g.screen == def.SCREEN_FIGHT) {
            expedition.expeditionStep(&g, def.ACT_RESTRAIN);
        } else {
            expedition.expeditionStep(&g, def.ACT_ATTEMPT);
        }
    }
    if (expedition.isInFight(&g)) return false;
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    if (g.world.score_subdued != 1) return false;
    if (g.screen != def.NAV_SUBDUE_INTRO) return false;
    const idx = g.fight.def_index;
    if (idx < 0 or idx >= creatures.defCount()) return false;
    const sale = creatures.defAt(idx).sale;
    expedition.expeditionStep(&g, expedition.SUB_SELL);
    if (g.world.money != sale) return false;
    if (g.world.score_money_earned != sale) return false;
    if (g.world.score_subdued != 1) return false;
    return g.fight.def_index == def.NO_FIGHT;
}

pub fn main() void {
    report("score_copy_exact", tScoreCopy());
    report("credits_copy_exact", tCreditsCopy());
    report("score_golden_exact", tGolden("score", SCORE_GOLDEN));
    report("credits_golden_exact", tGolden("credits", CREDITS_GOLDEN));
    report("score_help_and_allow_lists", tHelpAndAllow());
    report("field_record_freeze_once", tFieldFreeze());
    report("variants_bit_survives_ascent", tVariantsSurviveAscent());
    report("last_run_overwrites", tLastRunOverwrite());
    report("kill_defeat_route", tKillRoute());
    report("overkill_defeat_route", tOverkillRoute());
    report("field_record_second_defeat_identical", tSecondDefeatKeepsRecord());
    report("boss_loss_records_last_run", tLossRecordsLastRun());
    report("nonboss_score_counters", tNonBossCounters());
    report("sell_updates_money_earned", tSellMoney());

    if (fails != 0) os.exit(1);
    io.write("score_test PASS\n");
}
