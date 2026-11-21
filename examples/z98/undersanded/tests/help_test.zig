// help_test.zig — UNDERSANDED M8 `?` / manual page driver.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/help_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/help_test"
//   "$OUT/help_test"
//
// Asserts the per-screen page map, that manual.1..8 all exist, that the help
// screen renders deterministically, and that `?` mid-fight opens a
// non-consuming overlay (dismissing it changes no combat state).

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");
const render = @import("../render_term.zig");
const journal = @import("../journal.zig");
const data = @import("../data.zig");
const creatures = @import("../creatures_t1.zig");

const DATA_PATH = "examples/z98/undersanded/data.z98";
const MANUAL_KEYS = [_][]const u8{
    "manual.1", "manual.2", "manual.3", "manual.4", "manual.5",
    "manual.6", "manual.7", "manual.8", "manual.9",
};

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

fn pageEquals(screen: i32, key: []const u8) bool {
    const page = journal.helpPage(screen) orelse return false;
    const want = data.textFind(key) orelse return false;
    return eq(page, want);
}

fn tPageMap() bool {
    // Exact §7.1 page map.
    if (journal.helpPageNumber(def.NAV_DOCK) != 1) return false;
    if (journal.helpPageNumber(def.NAV_MAP) != 5) return false;
    if (journal.helpPageNumber(def.NAV_NODE) != 5) return false;
    if (journal.helpPageNumber(def.SCREEN_FIGHT) != 2) return false;
    if (journal.helpPageNumber(def.SCREEN_SUBDUE) != 2) return false;
    if (journal.helpPageNumber(def.SCREEN_SUBDUE_POST) != 2) return false;
    if (journal.helpPageNumber(def.NAV_SUBDUE_INTRO) != 3) return false;
    if (journal.helpPageNumber(def.NAV_SETTLE) != 3) return false;
    if (journal.helpPageNumber(def.NAV_REFINE) != 4) return false;
    if (journal.helpPageNumber(def.NAV_UPGRADE) != 4) return false;
    if (journal.helpPageNumber(def.NAV_CRAFT) != 6) return false;
    if (journal.helpPageNumber(def.NAV_TOOLS) != 6) return false;
    if (journal.helpPageNumber(def.NAV_JOURNAL) != 9) return false;
    if (journal.helpPageNumber(def.NAV_BUY) != 8) return false;
    if (journal.helpPageNumber(def.NAV_LORE) != 1) return false;
    if (journal.helpPageNumber(def.NAV_MENU) != 1) return false;
    if (journal.helpPageNumber(def.NAV_SAVE_ERR) != 1) return false;
    // Unknown/boot screens fall back to page 1 so `?` works everywhere.
    if (journal.helpPageNumber(-999) != 1) return false;
    if (journal.helpPageNumber(def.NAV_HELP) != 1) return false;
    return true;
}

fn tPagesPresent() bool {
    var i: usize = 0;
    while (i < MANUAL_KEYS.len) : (i += 1) {
        const text = data.textFind(MANUAL_KEYS[i]) orelse return false;
        if (text.len == 0) return false;
    }
    if (!pageEquals(def.NAV_DOCK, "manual.1")) return false;
    if (!pageEquals(def.NAV_NODE, "manual.5")) return false;
    if (!pageEquals(def.NAV_SETTLE, "manual.3")) return false;
    if (!pageEquals(def.NAV_REFINE, "manual.4")) return false;
    if (!pageEquals(def.NAV_MAP, "manual.5")) return false;
    if (!pageEquals(def.NAV_TOOLS, "manual.6")) return false;
    if (!pageEquals(def.NAV_CRAFT, "manual.6")) return false;
    if (!pageEquals(def.NAV_JOURNAL, "manual.9")) return false;
    if (!pageEquals(def.NAV_BUY, "manual.8")) return false;
    return true;
}

fn tManualCopy() bool {
    const m1 = data.textFind("manual.1") orelse return false;
    if (!contains(m1, "[R]efine") or !contains(m1, "[D]epart")) return false;
    const m2 = data.textFind("manual.2") orelse return false;
    if (!contains(m2, "SPD ??")) return false;
    const m3 = data.textFind("manual.3") orelse return false;
    if (!contains(m3, "Release") or !contains(m3, "Sell")) return false;
    if (!contains(m3, "parts") or !contains(m3, "+15 Resolve")) return false;
    const m5 = data.textFind("manual.5") orelse return false;
    if (!contains(m5, "rough sleep") or !contains(m5, "Drowsy")) return false;
    if (!contains(m5, "Shaky") or !contains(m5, "Exposed")) return false;
    if (!contains(m5, "phase")) return false;
    const m6 = data.textFind("manual.6") orelse return false;
    if (!contains(m6, "Electric Gland")) return false;
    if (!contains(m6, "Steel Plate")) return false;
    if (!contains(m6, "Bioluminescent Lure")) return false;
    if (!contains(m6, "Pressure Hook")) return false;
    if (!contains(m6, "Sonar Ping")) return false;
    if (!contains(m6, "Brine Net")) return false;
    if (!contains(m6, "Coral Shield")) return false;
    const m7 = data.textFind("manual.7") orelse return false;
    if (!contains(m7, "six distinct") or !contains(m7, "Derelict")) return false;
    const m8 = data.textFind("manual.8") orelse return false;
    if (!contains(m8, "zone milestone")) return false;
    const m9 = data.textFind("manual.9") orelse return false;
    if (!contains(m9, "Journal") or !contains(m9, "SPD ??")) return false;
    if (!contains(m9, "Speed") or !contains(m9, "[J]")) return false;
    return true;
}

fn hasText(sc: *const render.Screen, buf: []u8, want: []const u8) bool {
    return contains(render.dump(sc, buf), want);
}

fn tFooterHelpEveryScreen() bool {
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;
    var g: def.GameState = undefined;
    var v: render.View = undefined;

    game.newGame(&g);
    g.screen = def.NAV_DOCK;
    nav.prepareDock(&g, &v);
    render.renderDock(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_MAP;
    nav.prepareMap(&g, &v);
    render.renderMap(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_NODE;
    g.exp.active = 1;
    g.exp.zone = 1;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_SETTLE;
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_SUBDUE;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_SUBDUE_INTRO;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_REFINE;
    nav.prepareRefine(&g, &v);
    render.renderRefine(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_UPGRADE;
    nav.prepareUpgrade(&g, &v);
    render.renderUpgrade(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    render.renderCraft(&g, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    g.screen = def.NAV_BUY;
    nav.prepareBuy(&g, &v);
    render.renderBuy(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    render.renderTools(&g, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    nav.prepareJournal(&g, 0, &v);
    render.renderJournal(&v, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    game.newGame(&g);
    game.startFight(&g, 0);
    var d = creatures.defAt(0);
    render.renderFrame(&g, &d, &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;

    render.renderLore("The Undersanded.", &sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;
    render.renderMenu(&sc);
    if (!hasText(&sc, buf[0..], "[?] Help")) return false;
    render.renderSaveError("Damaged.", &sc);
    return hasText(&sc, buf[0..], "[?] Help");
}

fn tJournalHintDockField() bool {
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;
    var g: def.GameState = undefined;
    var v: render.View = undefined;

    game.newGame(&g);
    g.screen = def.NAV_DOCK;
    nav.prepareDock(&g, &v);
    render.renderDock(&v, &sc);
    if (!hasText(&sc, buf[0..], "[J]ournal")) return false;

    g.screen = def.NAV_MAP;
    nav.prepareMap(&g, &v);
    render.renderMap(&v, &sc);
    if (!hasText(&sc, buf[0..], "[J]ournal")) return false;

    g.screen = def.NAV_NODE;
    g.exp.active = 1;
    g.exp.zone = 1;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    if (!hasText(&sc, buf[0..], "[J]ournal")) return false;

    g.screen = def.NAV_SETTLE;
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_SUBDUE;
    nav.prepareNode(&g, &v);
    render.renderNode(&v, &sc);
    return hasText(&sc, buf[0..], "[J]ournal");
}

fn tToolEffectCopy() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;

    render.renderCraft(&g, &sc);
    var text = render.dump(&sc, buf[0..]);
    if (!contains(text, "Effect:")) return false;
    if (!contains(text, "Stuns the creature for one turn.")) return false;
    if (!contains(text, "Negates armor")) return false;
    if (!contains(text, "Restrain ignores Shell")) return false;

    render.renderTools(&g, &sc);
    text = render.dump(&sc, buf[0..]);
    return contains(text, "Reveals Speed and next action")
        and contains(text, "Negates discharge-type Hull damage.");
}

fn tAxisEffectCopy() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var v: render.View = undefined;
    nav.prepareUpgrade(&g, &v);
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;
    render.renderUpgrade(&v, &sc);
    const text = render.dump(&sc, buf[0..]);
    return contains(text, "max Hull 125")
        and contains(text, "player Speed 12")
        and contains(text, "Cargo +1 part per drop")
        and contains(text, "4 fights per expedition")
        and contains(text, "overkill margin 15%");
}

fn tCosmeticLockCopy() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var v: render.View = undefined;
    nav.prepareBuy(&g, &v);
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;
    render.renderBuy(&v, &sc);
    const text = render.dump(&sc, buf[0..]);
    return contains(text, "Foam White 150 (locked) Reach Z1")
        and contains(text, "Derelict Cog 200 (locked) Kill the Derelict");
}

fn renderPage(screen: i32, buf: []u8) ?[]const u8 {
    var sc: render.Screen = undefined;
    const text = journal.helpPage(screen) orelse return null;
    render.renderHelp(text, &sc);
    return render.dump(&sc, buf);
}

fn tRenderDeterministic() bool {
    var b1: [8192]u8 = undefined;
    var b2: [8192]u8 = undefined;
    const a = renderPage(def.NAV_DOCK, b1[0..]) orelse return false;
    if (!contains(a, "UNDERSANDED  HELP")) return false;
    if (!contains(a, "pressure and patience")) return false;
    if (!contains(a, "[Any key] Back")) return false;
    const repeated = renderPage(def.NAV_DOCK, b2[0..]) orelse return false;
    if (!eq(a, repeated)) return false;

    var b3: [8192]u8 = undefined;
    const map = renderPage(def.NAV_MAP, b3[0..]) orelse return false;
    return contains(map, "Days and nights alternate");
}

fn tOverlayNoAction() bool {
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
    // Dismissing consumes the key but forwards no fight action.
    _ = nav.navStep(&g, &st, input.Key{ .ch = 's', .code = 0 });
    if (st.help_page != nav.HELP_PAGE_NONE) return false;
    return g.fight.hp == hp and g.fight.res == res and g.fight.hull == hull and
        g.fight.rng_state == rng;
}

fn keyCh(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn helpNoAction(g: *def.GameState, st: *nav.NavState, page: i32) bool {
    const phases = g.world.field_phases;
    const cycle = g.world.cycle;
    const phase = g.world.phase;
    const money = g.world.money;
    const hull = g.world.hull;
    const frng = g.fight.rng_state;
    const wrng = g.world.rng_state;
    const outcome = g.fight.outcome;
    const def_index = g.fight.def_index;
    const bonus = g.world.release_bonus[1];

    _ = nav.navStep(g, st, keyCh('?'));
    if (st.help_page != page) return false;
    _ = nav.navStep(g, st, keyCh('x'));
    if (st.help_page != nav.HELP_PAGE_NONE) return false;
    return g.world.field_phases == phases and g.world.cycle == cycle
        and g.world.phase == phase and g.world.money == money
        and g.world.hull == hull and g.fight.rng_state == frng
        and g.world.rng_state == wrng and g.fight.outcome == outcome
        and g.fight.def_index == def_index and g.world.release_bonus[1] == bonus;
}

fn tHelpNoRngEveryScreen() bool {
    var d: def.GameState = undefined;
    game.newGame(&d);
    d.screen = def.NAV_DOCK;
    var dst = nav.initState();
    if (!helpNoAction(&d, &dst, 1)) return false;

    var m: def.GameState = undefined;
    game.newGame(&m);
    m.screen = def.NAV_MAP;
    var mst = nav.initState();
    if (!helpNoAction(&m, &mst, 5)) return false;

    var n: def.GameState = undefined;
    game.newGame(&n);
    n.exp.active = 1;
    n.exp.zone = 1;
    n.screen = def.NAV_NODE;
    var nst = nav.initState();
    if (!helpNoAction(&n, &nst, 5)) return false;

    var s: def.GameState = undefined;
    game.newGame(&s);
    s.exp.active = 1;
    s.exp.zone = 1;
    s.fight.def_index = 0;
    s.fight.outcome = def.OUT_SUBDUE;
    s.screen = def.NAV_SETTLE;
    var sst = nav.initState();
    if (!helpNoAction(&s, &sst, 3)) return false;

    var f: def.GameState = undefined;
    game.newGame(&f);
    game.startFight(&f, 0);
    f.exp.active = 1;
    f.exp.zone = 0;
    var fst = nav.initState();
    return helpNoAction(&f, &fst, 2);
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

    report("help_page_map", tPageMap());
    report("help_pages_present", tPagesPresent());
    report("manual_copy_s7_1", tManualCopy());
    report("help_screen_render_deterministic", tRenderDeterministic());
    report("help_overlay_no_action", tOverlayNoAction());
    report("help_no_rng_no_phase_every_screen", tHelpNoRngEveryScreen());
    report("footer_help_every_screen", tFooterHelpEveryScreen());
    report("journal_hint_dock_field", tJournalHintDockField());
    report("tool_effect_copy_craft_and_tools", tToolEffectCopy());
    report("axis_effect_copy_upgrade", tAxisEffectCopy());
    report("cosmetic_lock_copy_buy", tCosmeticLockCopy());

    if (fails != 0) {
        io.write("help_test FAIL\n");
        os.exit(1);
    }
    io.write("help_test PASS\n");
}
