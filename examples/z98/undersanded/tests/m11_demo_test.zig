// m11_demo_test.zig — native Linux M11 demo-gate driver (§15, §19, §34, P31).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/m11_demo_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/m11_demo_test"
//   M11_SAVE_DIR=/tmp/m11saves "$OUT/m11_demo_test"
// Prints a deterministic demo trace plus `ok - <case>` / `FAIL - <case>`;
// non-zero exit on any failure. The tier byte-compares stdout with
// fixtures/demo_loop.golden.
//
// The five saved-build cases use the real persist.saveWrite/saveRead path in
// separate files under M11_SAVE_DIR; only the boat tiers and the pre-boss world
// are staged. The demo loop starts from game.newGame (fresh install state) and
// drives the real nav/map/node/fight/credits/score/dock path.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const boss = @import("../boss.zig");
const score = @import("../score.zig");
const expedition = @import("../expedition.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");
const persist = @import("../persist.zig");
const paths = @import("../paths.zig");

const SAVE_DIR_DEFAULT = "/tmp/undersanded_m11_saves";

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

fn writeInt(v: i32) void {
    if (v == 0) {
        io.write("0");
        return;
    }
    var x = v;
    if (x < 0) {
        io.write("-");
        x = 0 - x;
    }
    var tmp: [16]u8 = undefined;
    var n: usize = 0;
    while (x > 0) : (x = x / 10) {
        tmp[n] = @intCast(u8, '0' + @intCast(i32, x % 10));
        n += 1;
    }
    while (n > 0) {
        n -= 1;
        io.writeByte(tmp[n]);
    }
}

fn key(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn setSeenSix(w: *def.World) void {
    // Indices 0..5 are all non-boss, so the §15 six-distinct gate opens
    // without claiming the Derelict itself was seen.
    w.seen_mask[0] = 0x0000003F;
    w.seen_mask[1] = 0;
}

fn demoBuild(g: *def.GameState) void {
    // Hull T3 (200) is the survivable demo loadout and stays the dominant axis
    // (Armor). Hull T3 is Heavy, so the D-route costs 5 + 1 each way.
    const w = &g.world;
    w.boat[world.BOAT_HULL] = 3;
    w.boat[world.BOAT_SPEED] = 2;
    w.boat[world.BOAT_CARGO] = 1;
    w.boat[world.BOAT_OXYGEN] = 1;
    w.boat[world.BOAT_PRECISION] = 2;
    w.hull = world.hullMax(w);
    w.tools_owned = @intCast(u32, 1) << @intCast(u32, def.TOOL_PLATE);
    w.tool_selected = def.TOOL_PLATE;
}

fn savePath(name: []const u8, out: []u8) ?[]u8 {
    const dir = os.env("M11_SAVE_DIR") orelse SAVE_DIR_DEFAULT;
    return paths.join(dir, name, out);
}

fn savedIdentity(name: []const u8, axis: i32, want: i32) bool {
    var path_buf: [4096]u8 = undefined;
    const path = savePath(name, path_buf[0..]) orelse return false;

    var g: def.GameState = undefined;
    game.newGame(&g);
    const w = &g.world;
    w.boat[@intCast(usize, axis)] = 3;
    w.hull = world.hullMax(w);
    setSeenSix(w);
    persist.saveWrite(path, &g.world, &g.exp) catch return false;

    var s: def.GameState = undefined;
    game.newGame(&s);
    persist.saveRead(path, &s.world, &s.exp) catch return false;

    if (s.world.boat[axis] != 3) return false;
    if (!world.bossGateOpen(&s.world)) return false;

    _ = expedition.depart(&s, 8);
    expedition.expeditionStep(&s, expedition.EXP_HUNT);
    if (!expedition.isInFight(&s)) return false;
    if (s.fight.boss_variant != want) return false;

    s.fight.hp = 199;
    boss.bossPhaseUpdate(&s);
    if (s.fight.boss_phase != boss.PHASE_2) return false;
    const bit: u32 = @intCast(u32, 1) << @intCast(u32, want);
    if ((s.world.boss_variants_seen & bit) == 0) return false;
    return eq(score.identityLabel(s.fight.boss_variant), score.identityLabel(want));
}

fn demoLoop(label: []const u8, overkill: bool) bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.screen = def.NAV_DOCK;
    setSeenSix(&g.world);
    demoBuild(&g);

    const start_phases = g.world.field_phases;
    var st = nav.initState();

    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (!world.bossGateOpen(&g.world)) return false;
    if (nav.navStep(&g, &st, key('9')) != def.NAV_NODE) return false;
    if (g.exp.active != 1 or g.exp.zone != 8) return false;
    const depart_phases = g.world.field_phases;
    const outbound = depart_phases - start_phases;
    const travel = expedition.travelCostForZone(&g, 8);
    if (travel != 6) return false;
    if (outbound != 1 + travel) return false;

    if (nav.navStep(&g, &st, key('h')) != def.SCREEN_FIGHT) return false;
    if (!expedition.isInFight(&g)) return false;
    if ((g.fight.flags & def.F_BOSS) == 0) return false;
    if (g.fight.boss_variant != boss.VARIANT_ARMOR) return false;

    // Deterministic outcome selection: margin only classifies the killing
    // overshoot, so this drives the same real action stream to Kill/Overkill.
    if (overkill) {
        g.fight.margin_pct = 0;
    } else {
        g.fight.margin_pct = 1000;
    }

    var guard: i32 = 0;
    while (expedition.isInFight(&g) and guard < 400) : (guard += 1) {
        _ = nav.navStep(&g, &st, key('s'));
    }
    if (guard >= 400) return false;
    const want = if (overkill) def.OUT_OVERKILL else def.OUT_KILL;
    if (g.fight.outcome != want) return false;
    if (g.screen != def.NAV_CREDITS) return false;
    if (g.exp.active != 1) return false;
    if (g.world.field_phases != depart_phases) return false;

    if (g.world.field_record_written != 1) return false;
    if (g.world.field_record.bosses_killed != 1) return false;
    if (g.world.field_record.final_phase2 != boss.VARIANT_ARMOR) return false;
    if ((g.world.boss_variants_seen & 1) == 0) return false;
    if (g.world.boss_kills != 1) return false;
    if (g.world.last_run.outcome != want) return false;
    if (g.world.last_run.phase2 != boss.VARIANT_ARMOR) return false;
    if (g.world.last_run.actions != g.fight.actions) return false;
    if (g.world.last_run.hull_spent != g.fight.hull_spent) return false;
    if (g.world.last_run.boss_kills != 1) return false;
    if (overkill) {
        if (g.world.score_overkilled != 1 or g.world.score_killed != 0) return false;
    } else {
        if (g.world.score_killed != 1 or g.world.score_overkilled != 0) return false;
    }

    if (nav.navStep(&g, &st, key('c')) != def.NAV_SCORE) return false;
    if (g.screen != def.NAV_SCORE) return false;
    if (nav.navStep(&g, &st, key('c')) != def.NAV_DOCK) return false;
    if (g.screen != def.NAV_DOCK) return false;
    if (g.exp.active != 0) return false;

    const return_travel = g.world.field_phases - depart_phases;
    if (return_travel != travel) return false;

    io.write("demo ");
    io.write(label);
    io.write(" outbound=");
    writeInt(outbound);
    io.write(" return=");
    writeInt(return_travel);
    io.write(" actions=");
    writeInt(g.world.last_run.actions);
    io.write(" hull_spent=");
    writeInt(g.world.last_run.hull_spent);
    io.write(" outcome=");
    io.write(score.outcomeLabel(g.world.last_run.outcome));
    io.write(" identity=");
    io.write(score.identityLabel(g.world.last_run.phase2));
    io.write(" variants=");
    writeInt(score.variantsCount(g.world.boss_variants_seen));
    io.write(" boss_kills=");
    writeInt(g.world.boss_kills);
    io.write(" field=");
    writeInt(g.world.field_record_written);
    io.write(" score=");
    writeInt(g.world.score_killed);
    io.write("/");
    writeInt(g.world.score_overkilled);
    io.write("\n");
    return true;
}

pub fn main() void {
    report("saved_boat_armor_identity", savedIdentity("armor.dat", world.BOAT_HULL, boss.VARIANT_ARMOR));
    report("saved_boat_sliver_identity", savedIdentity("sliver.dat", world.BOAT_PRECISION, boss.VARIANT_SLIVER));
    report("saved_boat_hoard_identity", savedIdentity("hoard.dat", world.BOAT_CARGO, boss.VARIANT_HOARD));
    report("saved_boat_drown_identity", savedIdentity("drown.dat", world.BOAT_OXYGEN, boss.VARIANT_DROWN));
    report("saved_boat_blur_identity", savedIdentity("blur.dat", world.BOAT_SPEED, boss.VARIANT_BLUR));
    report("demo_loop_kill", demoLoop("kill", false));
    report("demo_loop_overkill", demoLoop("overkill", true));

    if (fails != 0) os.exit(1);
    io.write("m11_demo_test PASS\n");
}
