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

const DATA_PATH = "examples/z98/undersanded/data.z98";
const MANUAL_KEYS = [_][]const u8{
    "manual.1", "manual.2", "manual.3", "manual.4",
    "manual.5", "manual.6", "manual.7", "manual.8",
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
    if (journal.helpPageNumber(def.NAV_DOCK) != 1) return false;
    if (journal.helpPageNumber(def.NAV_MAP) != 5) return false;
    if (journal.helpPageNumber(def.NAV_NODE) != 2) return false;
    if (journal.helpPageNumber(def.SCREEN_FIGHT) != 2) return false;
    if (journal.helpPageNumber(def.SCREEN_SUBDUE) != 2) return false;
    if (journal.helpPageNumber(def.NAV_SETTLE) != 3) return false;
    if (journal.helpPageNumber(def.NAV_REFINE) != 4) return false;
    if (journal.helpPageNumber(def.NAV_CRAFT) != 4) return false;
    if (journal.helpPageNumber(def.NAV_TOOLS) != 6) return false;
    if (journal.helpPageNumber(def.NAV_JOURNAL) != 7) return false;
    if (journal.helpPageNumber(def.NAV_BUY) != 8) return false;
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
    if (!pageEquals(def.NAV_NODE, "manual.2")) return false;
    if (!pageEquals(def.NAV_SETTLE, "manual.3")) return false;
    if (!pageEquals(def.NAV_REFINE, "manual.4")) return false;
    if (!pageEquals(def.NAV_MAP, "manual.5")) return false;
    if (!pageEquals(def.NAV_TOOLS, "manual.6")) return false;
    if (!pageEquals(def.NAV_JOURNAL, "manual.7")) return false;
    if (!pageEquals(def.NAV_BUY, "manual.8")) return false;
    return true;
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
    var st = nav.NavState{
        .armed = 0,
        .last = def.NAV_RESULT_NONE,
        .save_err_kind = 0,
        .help_page = nav.HELP_PAGE_NONE,
        .tip = nav.TIP_NONE,
        .journal_sel = 0,
    };
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
    report("help_screen_render_deterministic", tRenderDeterministic());
    report("help_overlay_no_action", tOverlayNoAction());

    if (fails != 0) {
        io.write("help_test FAIL\n");
        os.exit(1);
    }
    io.write("help_test PASS\n");
}
