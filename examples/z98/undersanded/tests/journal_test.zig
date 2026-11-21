// journal_test.zig — UNDERSANDED M8 journal/help/tooltips/zone flavour driver.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/journal_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/journal_test"
//   "$OUT/journal_test"

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");
const render = @import("../render_term.zig");
const journal = @import("../journal.zig");
const data = @import("../data.zig");
const persist = @import("../persist.zig");
const creatures = @import("../creatures_t1.zig");

const DATA_PATH = "examples/z98/undersanded/data.z98";
const TMP_SAVE = "/tmp/m8_journal_roundtrip.sav";

var fails: usize = 0;
var arena_buf: [256 * 1024]u8 = undefined;

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

fn contains(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (hay.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (eq(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn bitSet(mask: *const [2]u32, d: i32) bool {
    if (d < 0 or d >= 64) return false;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    return (mask[word] & (@intCast(u32, 1) << bit)) != 0;
}

fn setBit(mask: *[2]u32, d: i32) void {
    if (d < 0 or d >= 64) return;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    mask[word] = mask[word] | (@intCast(u32, 1) << bit);
}

fn prepare(g: *def.GameState) i32 {
    game.newGame(g);
    game.startFight(g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.exp.fight_index = 0;
    g.exp.seed = 98;
    return g.fight.def_index;
}

fn triggerKill(g: *def.GameState, overkill: bool) bool {
    const idx = prepare(g);
    if (overkill) {
        g.fight.margin_pct = 0;
    } else {
        g.fight.margin_pct = 1000;
    }
    g.fight.hp = 1;
    expedition.expeditionStep(g, def.ACT_STRIKE);
    if (g.fight.outcome != def.OUT_KILL and g.fight.outcome != def.OUT_OVERKILL) return false;
    return journal.journalUnlocked(&g.world, idx);
}

fn triggerPlayerFlee(g: *def.GameState) bool {
    const idx = prepare(g);
    expedition.expeditionStep(g, def.ACT_FLEE);
    if (g.fight.outcome != def.OUT_PLAYER_FLED) return false;
    return journal.journalUnlocked(&g.world, idx);
}

fn triggerCreatureFlee(g: *def.GameState) bool {
    const idx = prepare(g);
    g.fight.pending_flee = 1;
    expedition.expeditionStep(g, def.ACT_STRIKE);
    if (g.fight.outcome != def.OUT_CREATURE_FLED) return false;
    return journal.journalUnlocked(&g.world, idx);
}

fn triggerAscent(g: *def.GameState) bool {
    const idx = prepare(g);
    g.fight.hull = 1;
    expedition.expeditionStep(g, def.ACT_RESTRAIN);
    if (g.exp.active != 0) return false;
    if (g.world.hull != 0) return false;
    return journal.journalUnlocked(&g.world, idx);
}

fn triggerSubdue(g: *def.GameState) bool {
    const idx = prepare(g);
    g.fight.hp = 1;
    g.fight.res = 0;
    g.screen = def.SCREEN_SUBDUE;
    var guard: i32 = 0;
    while (g.fight.outcome == def.OUT_ONGOING and guard < 50) : (guard += 1) {
        if (g.screen != def.SCREEN_SUBDUE and g.screen != def.SCREEN_SUBDUE_POST) {
            g.screen = def.SCREEN_SUBDUE;
            g.fight.res = 0;
            g.fight.hp = 1;
        }
        expedition.expeditionStep(g, def.ACT_ATTEMPT);
    }
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    return journal.journalUnlocked(&g.world, idx);
}

fn tTriggerMatrix() bool {
    var g: def.GameState = undefined;
    if (!triggerKill(&g, false)) return false;
    if (!triggerKill(&g, true)) return false;
    if (!triggerPlayerFlee(&g)) return false;
    if (!triggerCreatureFlee(&g)) return false;
    if (!triggerAscent(&g)) return false;
    if (!triggerSubdue(&g)) return false;

    // Boss: fight end never unlocks; the M11 kill hook does.
    game.newGame(&g);
    const boss = creatures.defCount() - 1;
    journal.journalOnFightEnd(&g.world, boss);
    if (journal.journalUnlocked(&g.world, boss)) return false;
    journal.journalOnBossKill(&g.world);
    return journal.journalUnlocked(&g.world, boss);
}

fn tViewedIndicator() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    if (journal.journalHasNew(&g.world)) return false;

    setBit(&g.world.journal_viewed, 0);
    journal.journalOnFightEnd(&g.world, 0);
    if (journal.journalViewed(&g.world, 0)) return false;
    if (!journal.journalHasNew(&g.world)) return false;
    if (!journal.journalOpen(&g.world, 0)) return false;
    if (!journal.journalViewed(&g.world, 0)) return false;
    if (journal.journalHasNew(&g.world)) return false;

    journal.journalOnFightEnd(&g.world, 1);
    if (!journal.journalHasNew(&g.world)) return false;
    journal.journalOnFightEnd(&g.world, 1);
    if (journal.journalViewed(&g.world, 1)) return false;

    var key_buf: [24]u8 = undefined;
    if (!eq(journal.journalKey(18, key_buf[0..]), "journal.19")) return false;
    if (!eq(journal.journalKey(0, key_buf[0..]), "journal.1")) return false;
    return !journal.journalOpen(&g.world, 5);
}

fn tHelpMap() bool {
    if (journal.helpPageNumber(def.NAV_DOCK) != 1) return false;
    if (journal.helpPageNumber(def.NAV_MAP) != 5) return false;
    if (journal.helpPageNumber(def.NAV_NODE) != 5) return false;
    if (journal.helpPageNumber(def.SCREEN_FIGHT) != 2) return false;
    if (journal.helpPageNumber(def.SCREEN_SUBDUE) != 2) return false;
    if (journal.helpPageNumber(def.NAV_SUBDUE_INTRO) != 3) return false;
    if (journal.helpPageNumber(def.NAV_SETTLE) != 3) return false;
    if (journal.helpPageNumber(def.NAV_REFINE) != 4) return false;
    if (journal.helpPageNumber(def.NAV_UPGRADE) != 4) return false;
    if (journal.helpPageNumber(def.NAV_CRAFT) != 6) return false;
    if (journal.helpPageNumber(def.NAV_TOOLS) != 6) return false;
    if (journal.helpPageNumber(def.NAV_JOURNAL) != 9) return false;
    if (journal.helpPageNumber(def.NAV_BUY) != 8) return false;

    if (journal.helpPage(def.NAV_DOCK)) |text| {
        if (!contains(text, "pressure and patience")) return false;
    } else {
        return false;
    }
    if (journal.helpPage(def.NAV_MAP)) |text| {
        if (!contains(text, "Days and nights alternate")) return false;
    } else {
        return false;
    }
    return true;
}

fn tTooltipOnce() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    const a = journal.tooltip(journal.TOOLTIP_RESTRAIN) orelse return false;
    const b = journal.tooltip(journal.TOOLTIP_RED_ZONE) orelse return false;
    if (!eq(a, "Restrain damages Resolve, not HP.")) return false;
    if (!eq(b, "Past the red zone is overkill. It costs you the rare.")) return false;

    if (journal.tooltipShow(&g.world, journal.TOOLTIP_RESTRAIN) == null) return false;
    if (journal.tooltipShow(&g.world, journal.TOOLTIP_RESTRAIN) != null) return false;
    if (!journal.tooltipShown(&g.world, journal.TOOLTIP_RESTRAIN)) return false;
    if (journal.tooltipShown(&g.world, journal.TOOLTIP_RED_ZONE)) return false;

    if (journal.tooltipShow(&g.world, journal.TOOLTIP_RED_ZONE) == null) return false;
    if (journal.tooltipShow(&g.world, journal.TOOLTIP_RED_ZONE) != null) return false;

    // Trigger through the real fight path: first Restrain action.
    game.newGame(&g);
    game.startFight(&g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    var st = nav.initState();
    _ = nav.navStep(&g, &st, input.Key{ .ch = 'r', .code = 0 });
    if (st.tip != journal.TOOLTIP_RESTRAIN + 1) return false;
    if (!journal.tooltipShown(&g.world, journal.TOOLTIP_RESTRAIN)) return false;

    // First red-zone entry in a fresh install.
    game.newGame(&g);
    game.startFight(&g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.fight.hp = 10;
    st.tip = nav.TIP_NONE;
    _ = nav.navStep(&g, &st, input.Key{ .ch = 'e', .code = 0 });
    return st.tip == journal.TOOLTIP_RED_ZONE + 1;
}

fn tHelpOverlayNoAction() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    game.startFight(&g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    var st = nav.initState();
    const hp = g.fight.hp;
    const res = g.fight.res;
    const hull = g.fight.hull;
    const rng = g.fight.rng_state;
    _ = nav.navStep(&g, &st, input.Key{ .ch = '?', .code = 0 });
    if (st.help_page != journal.helpPageNumber(def.SCREEN_FIGHT)) return false;
    // Dismissing the overlay consumes the key but changes no fight state.
    _ = nav.navStep(&g, &st, input.Key{ .ch = 's', .code = 0 });
    if (st.help_page != nav.HELP_PAGE_NONE) return false;
    return g.fight.hp == hp and g.fight.res == res and g.fight.hull == hull and g.fight.rng_state == rng;
}

fn tJournalScreenAndOpen() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    journal.journalOnFightEnd(&g.world, 0);
    var sc: render.Screen = undefined;
    var v: render.View = undefined;
    var buf: [8192]u8 = undefined;

    nav.prepareJournal(&g, 0, &v);
    render.renderJournal(&v, &sc);
    var text = render.dump(&sc, buf[0..]);
    if (!contains(text, "UNDERSANDED  JOURNAL")) return false;
    if (!contains(text, "Mystic Eel")) return false;
    if (!contains(text, "*NEW*")) return false;

    g.screen = def.NAV_JOURNAL;
    var st = nav.initState();
    _ = nav.navStep(&g, &st, input.Key{ .ch = '1', .code = 0 });
    if (st.journal_sel != 1) return false;
    if (!journal.journalViewed(&g.world, 0)) return false;
    nav.prepareJournal(&g, st.journal_sel, &v);
    render.renderJournal(&v, &sc);
    text = render.dump(&sc, buf[0..]);
    if (!contains(text, "I saw a Mystic Eel")) return false;
    return !journal.journalHasNew(&g.world);
}

fn tZoneFlavour() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.exp.zone = 1;
    var sc: render.Screen = undefined;
    var v: render.View = undefined;
    var buf: [8192]u8 = undefined;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (!contains(render.dump(&sc, buf[0..]), "The Reef is louder than it looks")) return false;

    g.exp.zone = 8;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (!contains(render.dump(&sc, buf[0..]), "The Derelict rests where the trench forgets to end")) return false;

    // Z4 flavour is deferred to M13: the name renders, no paragraph.
    g.exp.zone = 3;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (contains(render.dump(&sc, buf[0..]), "Trench-Edge drops without warning")) return false;
    return true;
}

fn tContentKeys() bool {
    var n: i32 = 1;
    while (n <= 19) : (n += 1) {
        var key: [24]u8 = undefined;
        const text = journal.journalKey(n - 1, key[0..]);
        const v = data.textFind(text) orelse return false;
        if (v.len == 0) return false;
    }
    if (data.textFind("journal.19") == null) return false;
    const boss = data.textFind("journal.19") orelse return false;
    if (!contains(boss, "a signal, not a machine")) return false;

    n = 1;
    while (n <= 9) : (n += 1) {
        var key: [24]u8 = undefined;
        var at: usize = 0;
        const prefix: []const u8 = "manual.";
        var i: usize = 0;
        while (i < prefix.len) : (i += 1) {
            key[at] = prefix[i];
            at += 1;
        }
        key[at] = @intCast(u8, '0' + n);
        at += 1;
        if (data.textFind(key[0..at]) == null) return false;
    }
    if (data.textFind("legend.1") == null) return false;
    if (data.textFind("legend.2") == null) return false;
    if (data.textFind("zone.1") == null) return false;
    if (data.textFind("zone.2") == null) return false;
    if (data.textFind("zone.3") == null) return false;
    if (data.textFind("zone.9") == null) return false;
    if (data.textFind("zone.4") != null) return false;
    return true;
}

fn tSpeedRevealSurvivesSave() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    game.startFight(&g, 2);
    const d = creatures.defAt(2);
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;

    render.renderFrame(&g, &d, &sc);
    if (!contains(render.dump(&sc, buf[0..]), "SPD ??")) return false;

    setBit(&g.world.journal_mask, 2);
    persist.saveWriteDirect(TMP_SAVE, &g.world, &g.exp) catch return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    persist.saveRead(TMP_SAVE, &w, &e) catch return false;
    file_mod.remove(TMP_SAVE) catch {};

    if (!bitSet(&w.journal_mask, 2)) return false;

    var g2: def.GameState = undefined;
    game.newGame(&g2);
    game.startFight(&g2, 2);
    g2.world = w;
    render.renderFrame(&g2, &d, &sc);
    if (!contains(render.dump(&sc, buf[0..]), "SPD 6")) return false;

    // Sonar always reveals exact Speed even without a journal entry.
    game.newGame(&g2);
    game.startFight(&g2, 2);
    g2.fight.tool = def.TOOL_SONAR;
    g2.fight.tool_active = 1;
    render.renderFrame(&g2, &d, &sc);
    return contains(render.dump(&sc, buf[0..]), "SPD 6");
}

pub fn main() void {
    var arena = arena_mod.init(arena_buf[0..]);
    var t: def.Tables = undefined;
    data.loadFile(&arena, DATA_PATH, &t) catch {
        io.write("FAIL - data.z98 load\n");
        os.exit(1);
        return;
    };
    data.install(&t);

    report("journal_trigger_matrix", tTriggerMatrix());
    report("journal_viewed_indicator", tViewedIndicator());
    report("help_page_map", tHelpMap());
    report("tooltip_once", tTooltipOnce());
    report("help_overlay_no_action", tHelpOverlayNoAction());
    report("journal_screen_open_sets_viewed", tJournalScreenAndOpen());
    report("zone_flavour_render", tZoneFlavour());
    report("content_text_keys", tContentKeys());
    report("speed_reveal_survives_save", tSpeedRevealSurvivesSave());

    if (fails != 0) {
        io.write("journal_test FAIL\n");
        os.exit(1);
    }
    io.write("journal_test PASS\n");
}
