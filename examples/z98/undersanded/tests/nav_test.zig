// nav_test.zig — UNDERSANDED M4 Task 4c pure navigation driver.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/nav_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/nav_test"
//   "$OUT/nav_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");

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

fn key(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn escKey() input.Key {
    return input.Key{ .ch = input.KEY_ESC, .code = 0 };
}

fn newNav() nav.NavState {
    return nav.initState();
}

fn setHold(g: *def.GameState, part: i32, n: i32) void {
    const ep = &g.exp;
    ep.hold[@intCast(usize, part)] = n;
}

fn pending(g: *const def.GameState) bool {
    return g.fight.outcome == def.OUT_SUBDUE and g.fight.def_index != def.NO_FIGHT;
}

fn holdNonZero(h: *const [def.MAX_PARTS]i32) bool {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (h[i] > 0) return true;
    }
    return false;
}

// (a) dock -> map -> Z2 node. Depart is 1 dock action + 2 travel phases.
fn tDockMapNode() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();

    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (g.screen != def.NAV_MAP) return false;
    if (g.world.field_phases != 0) return false;

    if (nav.navStep(&g, &st, key('2')) != def.NAV_NODE) return false;
    if (g.screen != def.NAV_NODE) return false;
    if (g.exp.active != 1) return false;
    if (g.exp.zone != 1) return false;
    if (g.world.field_phases != 3) return false;
    return true;
}

// (b) deterministic policy fight to Subdue, Release, surface, dock.
fn tPolicySubdueReleaseSurface() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();
    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (nav.navStep(&g, &st, key('2')) != def.NAV_NODE) return false;
    if (g.world.field_phases != 3) return false;

    // Hunt, then the pinned policy: modal -> Attempt, else Strike above 50%
    // HP, else Restrain.
    _ = nav.navStep(&g, &st, key('h'));
    var guard: i32 = 0;
    while (expedition.isInFight(&g) and guard < 200) : (guard += 1) {
        if (g.screen == def.SCREEN_SUBDUE or g.screen == def.SCREEN_SUBDUE_POST) {
            _ = nav.navStep(&g, &st, key('a'));
        } else if (g.fight.hp * 100 > g.fight.max_hp * 50) {
            _ = nav.navStep(&g, &st, key('s'));
        } else {
            _ = nav.navStep(&g, &st, key('r'));
        }
    }
    if (expedition.isInFight(&g)) return false;
    if (!pending(&g)) return false;
    if (g.screen != def.NAV_SUBDUE_INTRO) return false;
    if (g.exp.hold_n <= 0) return false;
    if (!holdNonZero(&g.exp.hold)) return false;

    // Intro is Continue-only: R/S and the settle digits are no-ops.
    if (nav.navStep(&g, &st, key('r')) != def.NAV_SUBDUE_INTRO) return false;
    if (nav.navStep(&g, &st, key('s')) != def.NAV_SUBDUE_INTRO) return false;
    if (nav.navStep(&g, &st, key('1')) != def.NAV_SUBDUE_INTRO) return false;
    if (nav.navStep(&g, &st, key('2')) != def.NAV_SUBDUE_INTRO) return false;
    if (!pending(&g)) return false;
    if (nav.navStep(&g, &st, key('c')) != def.NAV_SETTLE) return false;

    const money = g.world.money;
    if (nav.navStep(&g, &st, key('1')) != def.NAV_NODE) return false;
    if (pending(&g)) return false;
    if (g.exp.active != 1) return false;
    if (g.world.money != money) return false;
    if (g.world.field_phases != 3) return false;

    if (nav.navStep(&g, &st, key('s')) != def.NAV_DOCK) return false;
    if (g.screen != def.NAV_DOCK) return false;
    if (g.exp.active != 0) return false;
    if (g.world.money != money) return false;
    if (g.world.field_phases != 5) return false; // + 2 return travel
    if (!holdNonZero(&g.exp.hold)) return false;
    return true;
}

// (c) Dock Rest 60 -> 100 and exactly one phase (the non-clamped case).
fn tDockRestHealsOnePhase() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();
    g.world.hull = 60;
    g.world.field_phases = 0;

    if (nav.navStep(&g, &st, key('t')) != def.NAV_DOCK) return false;
    if (g.world.hull != 100) return false;
    if (g.world.field_phases != 1) return false;
    if (g.exp.active != 0) return false;
    return true;
}

// (d) Locked boss route refuses to depart.
fn tLockedBossStaysMap() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();

    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (nav.navStep(&g, &st, key('9')) != def.NAV_MAP) return false;
    if (g.screen != def.NAV_MAP) return false;
    if (g.exp.active != 0) return false;
    if (g.world.field_phases != 0) return false;
    return true;
}

// (e) Hull-0 ascent aborts the expedition and returns to the dock.
fn tHullZeroAscentReturnsDock() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();
    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (nav.navStep(&g, &st, key('2')) != def.NAV_NODE) return false;

    // Enter the next fight at 1 Hull; a Restrain leaves Resolve above 0 on the
    // first round, so the creature's hit zeroes Hull and postFight performs the
    // Emergency Ascent.
    g.world.hull = 1;
    var guard: i32 = 0;
    while (g.exp.active != 0 and guard < 200) : (guard += 1) {
        if (expedition.isInFight(&g)) {
            _ = nav.navStep(&g, &st, key('r'));
        } else if (pending(&g)) {
            if (g.screen == def.NAV_SUBDUE_INTRO) {
                _ = nav.navStep(&g, &st, key('c'));
            } else {
                _ = nav.navStep(&g, &st, key('1'));
            }
        } else {
            _ = nav.navStep(&g, &st, key('h'));
        }
    }
    if (g.exp.active != 0) return false;
    if (g.screen != def.NAV_DOCK) return false;
    if (g.world.hull != 0) return false;
    return true;
}

// (f) Dock keys open each sub-menu and Esc backs out.
fn tDockMenuKeys() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();

    if (nav.navStep(&g, &st, key('r')) != def.NAV_REFINE) return false;
    if (nav.navStep(&g, &st, escKey()) != def.NAV_DOCK) return false;
    if (nav.navStep(&g, &st, key('u')) != def.NAV_UPGRADE) return false;
    if (nav.navStep(&g, &st, escKey()) != def.NAV_DOCK) return false;
    if (nav.navStep(&g, &st, key('c')) != def.NAV_CRAFT) return false;
    if (nav.navStep(&g, &st, escKey()) != def.NAV_DOCK) return false;
    if (nav.navStep(&g, &st, key('b')) != def.NAV_BUY) return false;
    if (nav.navStep(&g, &st, escKey()) != def.NAV_DOCK) return false;
    if (nav.navStep(&g, &st, key('e')) != def.NAV_TOOLS) return false;
    if (nav.navStep(&g, &st, escKey()) != def.NAV_DOCK) return false;
    if (g.world.field_phases != 0) return false;
    return true;
}

// (g) Rare batch arms once, confirms on the same key, common refines at once.
fn tRareConfirmKeys() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();
    setHold(&g, 1, 2);
    setHold(&g, 6, 3);
    const rng = g.world.rng_state;

    if (nav.navStep(&g, &st, key('r')) != def.NAV_REFINE) return false;
    if (nav.navStep(&g, &st, key('6')) != def.NAV_REFINE) return false;
    if (st.armed != 6) return false;
    if (st.last != def.NAV_RESULT_PREVIEW) return false;
    if (g.exp.hold[6] != 3) return false;
    if (g.world.field_phases != 0) return false;

    if (nav.navStep(&g, &st, key('6')) != def.NAV_REFINE) return false;
    if (st.armed != 0) return false;
    if (st.last != 0) return false;
    if (g.exp.hold[6] != 0) return false;
    if (g.world.expertise[6] != 1) return false;
    if (g.world.materials[6] != 0) return false;
    if (g.world.field_phases != 1) return false;

    if (nav.navStep(&g, &st, key('1')) != def.NAV_REFINE) return false;
    if (g.exp.hold[1] != 0) return false;
    if (g.world.materials[1] != 2) return false;
    if (g.world.field_phases != 2) return false;
    if (g.world.rng_state != rng) return false;
    return true;
}

// (h) Any other key cancels an armed rare batch without refining it.
fn tRareCancelKeys() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();
    setHold(&g, 1, 2);
    setHold(&g, 6, 3);

    if (nav.navStep(&g, &st, key('r')) != def.NAV_REFINE) return false;
    if (nav.navStep(&g, &st, key('6')) != def.NAV_REFINE) return false;
    if (st.armed != 6) return false;

    if (nav.navStep(&g, &st, key('x')) != def.NAV_REFINE) return false;
    if (st.armed != 0) return false;
    if (g.exp.hold[6] != 3) return false;
    if (g.exp.hold[1] != 2) return false;
    if (g.world.field_phases != 0) return false;

    // Esc from the sub-menu backs out to the dock.
    if (nav.navStep(&g, &st, escKey()) != def.NAV_DOCK) return false;
    return true;
}

pub fn main() void {
    report("dock_map_z2_node_phases", tDockMapNode());
    report("policy_subdue_release_surface_dock", tPolicySubdueReleaseSurface());
    report("dock_rest_60_to_100_one_phase", tDockRestHealsOnePhase());
    report("locked_boss_stays_map", tLockedBossStaysMap());
    report("hull_zero_ascent_returns_dock", tHullZeroAscentReturnsDock());
    report("dock_menu_keys_and_esc", tDockMenuKeys());
    report("rare_batch_two_press_confirm", tRareConfirmKeys());
    report("rare_batch_other_key_cancels", tRareCancelKeys());

    if (fails != 0) os.exit(1);
    io.write("nav_test PASS\n");
}
