// screens_test.zig — UNDERSANDED M4 Task 4 dock/map/node screens + release/sell.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/screens_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/screens_test"
//   "$OUT/screens_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const sim = @import("../sim.zig");
const creatures = @import("../creatures_t1.zig");
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");
const render = @import("../render_term.zig");
const undtool = @import("../undtool.zig");

const DOCK_GOLDEN = "examples/z98/undersanded/tests/fixtures/dump_grid_dock.golden";
const MAP_GOLDEN = "examples/z98/undersanded/tests/fixtures/dump_grid_map.golden";
const NODE_GOLDEN = "examples/z98/undersanded/tests/fixtures/dump_grid_node.golden";

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

fn newGame() def.GameState {
    var g: def.GameState = undefined;
    sim.zeroState(&g);
    game.zeroWorld(&g.world);
    g.fight.def_index = -1;
    g.fight.outcome = -1;
    return g;
}

fn holdNonZero(h: *const [def.MAX_PARTS]i32) bool {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (h[i] > 0) return true;
    }
    return false;
}

// Real end-to-end drive: depart Z2 (seed 0), roll a fight, Restrain to the
// subdue gate (Attempt if a rare opens the prompt) and stop with the choice
// pending. The last expeditionStep already awarded the hold.
fn realSubdue() def.GameState {
    var g = newGame();
    g.world.rng_state = 0;
    _ = expedition.depart(&g, 1);
    expedition.expeditionStep(&g, expedition.EXP_HUNT);

    var guard: i32 = 0;
    while (expedition.isInFight(&g) and guard < 60) : (guard += 1) {
        if (g.screen == fight.SCREEN_FIGHT) {
            expedition.expeditionStep(&g, def.ACT_RESTRAIN);
        } else {
            expedition.expeditionStep(&g, def.ACT_ATTEMPT);
        }
    }
    return g;
}

// ---- Screens --------------------------------------------------------------

fn tDockLines() bool {
    var buf: [8192]u8 = undefined;
    const text = undtool.dumpFixedScreen("dock", buf[0..]) orelse return false;
    if (!contains(text, "UNDERSANDED  DOCK")) return false;
    if (!contains(text, "Hull 100/100")) return false;
    if (!contains(text, "Coins 0")) return false;
    if (!contains(text, "Boat: Hull T0 Speed T0 Cargo T0 Oxygen T0 Precision T0")) return false;
    if (!contains(text, "Materials: Chitin 0(E0)")) return false;
    if (!contains(text, "Luminescence 0(E0)")) return false;
    if (!contains(text, "Tools owned: 0  Selected: none")) return false;
    if (!contains(text, "[R]efine [U]pgrade [C]raft [B]uy [E]quip [T] Rest [D]epart [Q]uit")) return false;
    if (!contains(text, "[Esc] Save")) return false;
    if (contains(text, "not yet")) return false;
    return true;
}

fn tDockSaveBlockedLine() bool {
    var g = newGame();
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_ONGOING;
    var sc: render.Screen = undefined;
    render.renderDock(&g, &sc);
    var buf: [8192]u8 = undefined;
    const text = render.dump(&sc, buf[0..]);
    return contains(text, "[Esc] Save - Cannot save during a fight.");
}

fn tDockSubmenus() bool {
    var g = newGame();
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;

    render.renderRefine(&g, &sc);
    var text = render.dump(&sc, buf[0..]);
    if (!contains(text, "DOCK - REFINE")) return false;
    if (!contains(text, "Shell Chip x0 -> 0 Chitin")) return false;
    if (!contains(text, "[1-7] Refine material")) return false;

    render.renderUpgrade(&g, &sc);
    text = render.dump(&sc, buf[0..]);
    if (!contains(text, "DOCK - UPGRADE")) return false;
    if (!contains(text, "Hull T0 -> T1: Chitin x3")) return false;
    if (!contains(text, "[1-5] Upgrade axis")) return false;

    render.renderCraft(&g, &sc);
    text = render.dump(&sc, buf[0..]);
    if (!contains(text, "DOCK - CRAFT")) return false;
    if (!contains(text, "Steel Plate Tool [rigged] Plate Scrap x3")) return false;
    if (!contains(text, "[1-7] Craft tool")) return false;

    render.renderBuy(&g, &sc);
    text = render.dump(&sc, buf[0..]);
    if (!contains(text, "DOCK - BUY")) return false;
    if (!contains(text, "Foam White 150 (locked)")) return false;
    if (!contains(text, "[1-9,a-c] Buy cosmetic")) return false;

    render.renderTools(&g, &sc);
    text = render.dump(&sc, buf[0..]);
    if (!contains(text, "DOCK - EQUIP")) return false;
    if (!contains(text, "Steel Plate Tool (not owned)")) return false;
    if (!contains(text, "[1-7] Select tool")) return false;
    return true;
}

fn tMapLines() bool {
    var buf: [8192]u8 = undefined;
    const text = undtool.dumpFixedScreen("map", buf[0..]) orelse return false;
    if (!contains(text, "UNDERSANDED  MAP")) return false;
    if (!contains(text, "Z1  The Shallows")) return false;
    if (!contains(text, "Z3  Trench-Edge")) return false;
    if (!contains(text, "Z8  The Trench")) return false;
    if (!contains(text, "D   The Derelict")) return false;
    if (!contains(text, "locked")) return false;
    if (!contains(text, "Hull 150+ recommended.")) return false;
    return true;
}

fn tBossGate() bool {
    var g = newGame();
    if (render.seenNonBossCount(&g) != 0) return false;
    if (render.bossGateOpen(&g)) return false;

    var i: i32 = 0;
    var n: i32 = 0;
    while (i < creatures.defCount() and n < 6) : (i += 1) {
        if (creatures.defAt(i).role == 4) continue;
        world.markSeen(&g.world, i);
        n += 1;
    }
    if (render.seenNonBossCount(&g) != 6) return false;
    if (!render.bossGateOpen(&g)) return false;

    var sc: render.Screen = undefined;
    render.renderMap(&g, &sc);
    var buf: [8192]u8 = undefined;
    const text = render.dump(&sc, buf[0..]);
    if (contains(text, "locked")) return false;
    if (!contains(text, "Hull 150+ recommended.")) return false;
    return true;
}

fn tNodeLines() bool {
    var buf: [8192]u8 = undefined;
    const text = undtool.dumpFixedScreen("node", buf[0..]) orelse return false;
    if (!contains(text, "UNDERSANDED  NODE")) return false;
    if (!contains(text, "The Shallows")) return false;
    if (!contains(text, "Fights left 3")) return false;
    if (!contains(text, "Hull 100/100")) return false;
    if (!contains(text, "[H]unt [R]est [S]urface")) return false;
    return true;
}

fn tGolden(screen_id: []const u8, path: []const u8) bool {
    var buf: [8192]u8 = undefined;
    const text = undtool.dumpFixedScreen(screen_id, buf[0..]) orelse return false;
    return goldenEq(path, text);
}

// ---- Release / sell -------------------------------------------------------

fn tRelease() bool {
    var g = realSubdue();
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    const idx = g.fight.def_index;
    if (idx < 0) return false;
    if (!holdNonZero(&g.exp.hold)) return false;

    const cdef = creatures.defAt(idx);
    const cycle = g.world.cycle;
    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);

    expedition.resolveSubdueChoice(&g, expedition.SUB_RELEASE);

    if (g.world.release_bonus[1] != world.RELEASE_BONUS_STEP) return false;
    if (g.world.money != 0) return false;
    if (world.consumeWariness(&g.world, idx) != world.WARY_RESOLVE_BONUS) return false;
    if (g.world.ready[ri] != cycle + cdef.respawn[@intCast(usize, world.RESPAWN_SUBDUE)]) return false;
    if (g.fight.def_index != expedition.NO_FIGHT) return false;

    // Idempotency: the cleared pending marker makes a second call a no-op.
    const bonus = g.world.release_bonus[1];
    const ready = g.world.ready[ri];
    expedition.resolveSubdueChoice(&g, expedition.SUB_RELEASE);
    if (g.world.release_bonus[1] != bonus) return false;
    if (g.world.ready[ri] != ready) return false;

    expedition.expeditionStep(&g, expedition.EXP_SURFACE);
    return holdNonZero(&g.exp.hold);
}

fn tSell() bool {
    var g = realSubdue();
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    const idx = g.fight.def_index;
    if (idx < 0) return false;
    if (!holdNonZero(&g.exp.hold)) return false;

    const cdef = creatures.defAt(idx);
    const cycle = g.world.cycle;
    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);

    expedition.resolveSubdueChoice(&g, expedition.SUB_SELL);

    if (g.world.money != cdef.sale) return false;
    if (g.world.release_bonus[1] != 0) return false;
    if (world.consumeWariness(&g.world, idx) != 0) return false;
    if (g.world.ready[ri] != cycle + cdef.respawn[@intCast(usize, world.RESPAWN_SUBDUE)]) return false;
    if (g.fight.def_index != expedition.NO_FIGHT) return false;

    const money = g.world.money;
    expedition.resolveSubdueChoice(&g, expedition.SUB_SELL);
    if (g.world.money != money) return false;

    expedition.expeditionStep(&g, expedition.EXP_SURFACE);
    return holdNonZero(&g.exp.hold);
}

fn tResolveGuards() bool {
    var g = realSubdue();
    if (g.fight.def_index < 0) return false;
    g.fight.outcome = def.OUT_KILL;
    const money = g.world.money;
    const bonus = g.world.release_bonus[1];
    expedition.resolveSubdueChoice(&g, expedition.SUB_RELEASE);
    if (g.world.money != money) return false;
    if (g.world.release_bonus[1] != bonus) return false;

    var h = realSubdue();
    if (h.fight.def_index < 0) return false;
    const h_idx = h.fight.def_index;
    h.exp.active = 0;
    const h_money = h.world.money;
    expedition.resolveSubdueChoice(&h, expedition.SUB_SELL);
    if (h.world.money != h_money) return false;
    if (h.fight.def_index != h_idx) return false;
    return true;
}

fn tUnresolvedRenewsBoth() bool {
    var r = realSubdue();
    var s = realSubdue();
    if (r.fight.def_index < 0 or s.fight.def_index < 0) return false;
    const idx = r.fight.def_index;
    if (s.fight.def_index != idx) return false;
    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);
    const cycle = r.world.cycle;

    expedition.resolveSubdueChoice(&r, expedition.SUB_RELEASE);
    expedition.resolveSubdueChoice(&s, expedition.SUB_SELL);
    const want = cycle + creatures.defAt(idx).respawn[0];
    if (r.world.ready[ri] != want) return false;
    if (s.world.ready[ri] != want) return false;
    return true;
}

pub fn main() void {
    report("dock_screen_key_lines", tDockLines());
    report("dock_save_blocked_line", tDockSaveBlockedLine());
    report("dock_submenu_screens", tDockSubmenus());
    report("map_screen_ladder_locked_boss", tMapLines());
    report("map_boss_gate_six_distinct_nonboss", tBossGate());
    report("node_screen_key_lines", tNodeLines());
    report("dock_golden_exact", tGolden("dock", DOCK_GOLDEN));
    report("map_golden_exact", tGolden("map", MAP_GOLDEN));
    report("node_golden_exact", tGolden("node", NODE_GOLDEN));
    report("release_keeps_parts_bonus_wary_renews", tRelease());
    report("sell_keeps_parts_money_renews", tSell());
    report("resolve_guards_outcome_and_active", tResolveGuards());
    report("release_and_sell_both_renew_subdue", tUnresolvedRenewsBoth());

    if (fails != 0) os.exit(1);
    io.write("screens_test PASS\n");
}
