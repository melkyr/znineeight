// ui_test.zig — native Linux tests for M2 Task 4 (input + terminal render +
// creature table completeness), plus scripted Subdue/Kill/Overkill smoke.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/ui_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/ui_test"
//   "$OUT/ui_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const behavior = @import("../behavior.zig");
const fight = @import("../fight.zig");
const game = @import("../game.zig");
const creatures = @import("../creatures_t1.zig");
const input = @import("../input.zig");
const render = @import("../render_term.zig");

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

fn key(ch: u8) input.Key {
    return input.Key{ .ch = ch, .code = 0 };
}

fn kindOf(screen: i32, k: input.Key) i32 {
    const a = input.mapKey(screen, k) orelse return -1;
    return a.kind;
}

// ---- Input mapping --------------------------------------------------------

fn tFightKeys() bool {
    if (kindOf(fight.SCREEN_FIGHT, key('s')) != def.ACT_STRIKE) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('S')) != def.ACT_STRIKE) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('1')) != def.ACT_STRIKE) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('r')) != def.ACT_RESTRAIN) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('R')) != def.ACT_RESTRAIN) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('2')) != def.ACT_RESTRAIN) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('e')) != def.ACT_EQUIP) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('E')) != def.ACT_EQUIP) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('3')) != def.ACT_EQUIP) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('f')) != def.ACT_FLEE) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('F')) != def.ACT_FLEE) return false;
    if (kindOf(fight.SCREEN_FIGHT, key('4')) != def.ACT_FLEE) return false;
    if (input.mapKey(fight.SCREEN_FIGHT, key('x')) != null) return false;
    if (input.mapKey(fight.SCREEN_FIGHT, key(27)) != null) return false;
    return true;
}

fn tModalKeys() bool {
    if (kindOf(fight.SCREEN_SUBDUE, key('a')) != def.ACT_ATTEMPT) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key('A')) != def.ACT_ATTEMPT) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key('f')) != def.ACT_DECLINE) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key('F')) != def.ACT_DECLINE) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key(27)) != def.ACT_DECLINE) return false;
    if (kindOf(fight.SCREEN_SUBDUE_POST, key('a')) != def.ACT_ATTEMPT) return false;
    if (kindOf(fight.SCREEN_SUBDUE_POST, key('f')) != def.ACT_DECLINE) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key('s')) != -1) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key('r')) != -1) return false;
    if (kindOf(fight.SCREEN_SUBDUE, key('e')) != -1) return false;
    return true;
}

fn tEscByCode() bool {
    const esc_code = input.Key{ .ch = 0, .code = input.VK_ESC };
    if (kindOf(fight.SCREEN_SUBDUE, esc_code) != def.ACT_DECLINE) return false;
    const esc_vk27 = input.Key{ .ch = 0, .code = 27 };
    if (kindOf(fight.SCREEN_SUBDUE, esc_vk27) != def.ACT_DECLINE) return false;
    if (input.mapKey(fight.SCREEN_FIGHT, esc_code) != null) return false;
    return true;
}

// ---- Render smoke ---------------------------------------------------------

fn dumpScreen(sc: *const render.Screen, out: []u8) []const u8 {
    return render.dump(sc, out);
}

fn tRenderFightFrame() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 2);
    const d = creatures.defAt(2);

    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);

    var buf: [4096]u8 = undefined;
    const text = dumpScreen(&sc, buf[0..]);

    if (!contains(text, "HP")) return false;
    if (!contains(text, "RESOLVE")) return false;
    if (!contains(text, "HULL")) return false;
    if (!contains(text, "120/120")) return false;
    if (!contains(text, "70/70")) return false;
    if (!contains(text, "100/100")) return false;
    if (!contains(text, "Steel Tuna")) return false;
    if (!contains(text, "common")) return false;
    if (!contains(text, "SPD 6")) return false;
    if (!contains(text, "[S]trike [R]estrain [E]quipment [F]lee")) return false;
    return true;
}

fn tRenderNoMutation() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 0);
    const d = creatures.defAt(0);

    const hp = s.fight.hp;
    const res = s.fight.res;
    const hull = s.fight.hull;
    const outcome = s.fight.outcome;
    const screen = s.screen;
    const log_n = s.log_n;

    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);

    if (s.fight.hp != hp) return false;
    if (s.fight.res != res) return false;
    if (s.fight.hull != hull) return false;
    if (s.fight.outcome != outcome) return false;
    if (s.screen != screen) return false;
    if (s.log_n != log_n) return false;
    return true;
}

fn tRenderZeroAndMaxBars() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 2);
    const d = creatures.defAt(2);

    var sc: render.Screen = undefined;
    var buf: [4096]u8 = undefined;

    s.fight.hp = 0;
    s.fight.res = 0;
    s.fight.hull = 0;
    render.renderFrame(&s, &d, &sc);
    var text = dumpScreen(&sc, buf[0..]);
    if (!contains(text, "0/120")) return false;
    if (!contains(text, "0/70")) return false;
    if (!contains(text, "0/100")) return false;

    s.fight.hp = s.fight.max_hp;
    s.fight.res = s.fight.max_res;
    s.fight.hull = s.fight.max_hull;
    render.renderFrame(&s, &d, &sc);
    text = dumpScreen(&sc, buf[0..]);
    if (!contains(text, "120/120")) return false;
    if (!contains(text, "70/70")) return false;
    if (!contains(text, "100/100")) return false;
    return true;
}

fn tRenderLogLine() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 0);
    const d = creatures.defAt(0);

    game.gameStep(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 });

    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);
    var buf: [4096]u8 = undefined;
    const text = dumpScreen(&sc, buf[0..]);
    return contains(text, "You Strike for");
}

fn tRenderEffectiveSpeed() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 2);
    const d = creatures.defAt(2);

    var sc: render.Screen = undefined;
    var buf: [4096]u8 = undefined;

    s.fight.hp = 35;
    render.renderFrame(&s, &d, &sc);
    if (!contains(dumpScreen(&sc, buf[0..]), "SPD 10")) return false;

    s.fight.hp = 36;
    render.renderFrame(&s, &d, &sc);
    if (!contains(dumpScreen(&sc, buf[0..]), "SPD 6")) return false;
    return true;
}

fn tRenderSurgedSpeed() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 0);
    const d = creatures.defAt(0);

    fight.lastSurge(&s);
    fight.lastSurge(&s);

    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);
    var buf: [4096]u8 = undefined;
    var text = dumpScreen(&sc, buf[0..]);
    if (!contains(text, "SPD 14")) return false;

    fight.lastSurge(&s);
    fight.lastSurge(&s);
    render.renderFrame(&s, &d, &sc);
    text = dumpScreen(&sc, buf[0..]);
    return contains(text, "SPD 16");
}

fn tRenderSubdueLogCopy() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 0);
    const d = creatures.defAt(0);

    var i: i32 = 0;
    while (i < 20 and s.fight.outcome == def.OUT_ONGOING) : (i += 1) {
        game.gameStep(&s, def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 });
    }
    if (s.fight.outcome != def.OUT_SUBDUE) return false;

    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);
    var buf: [4096]u8 = undefined;
    return contains(dumpScreen(&sc, buf[0..]), "Subdued Mystic Eel (95%).");
}

fn tRenderModal() bool {
    var s: def.GameState = undefined;
    game.startFight(&s, 3);
    const d = creatures.defAt(3);
    s.screen = fight.SCREEN_SUBDUE;

    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);
    var buf: [4096]u8 = undefined;
    const text = dumpScreen(&sc, buf[0..]);

    if (!contains(text, "SUBDUE ATTEMPT")) return false;
    if (!contains(text, "Anemoniacus")) return false;
    if (!contains(text, "60% chance")) return false;
    if (!contains(text, "[A]ttempt")) return false;
    if (!contains(text, "[F] Fight on")) return false;
    if (contains(text, "[F]lee")) return false;
    if (!contains(text, "[Esc]")) return false;
    return true;
}

// ---- Creature table completeness (spec §14.2/§14.3) -----------------------

fn tCreatureTable() bool {
    if (creatures.DEFS.len != 5) return false;

    const ids = [5]i32{ 1, 2, 4, 18, 19 };
    const hps = [5]i32{ 70, 80, 120, 95, 105 };
    const res = [5]i32{ 80, 100, 70, 115, 95 };
    const spd = [5]i32{ 10, 16, 6, 7, 13 };
    const atk = [5]i32{ 6, 7, 8, 9, 10 };
    const sub = [5]i32{ 95, 95, 95, 60, 60 };
    const sale = [5]i32{ 20, 30, 20, 50, 55 };
    const r0 = [5]i32{ 3, 3, 3, 6, 6 };
    const r1 = [5]i32{ 9, 9, 9, 18, 18 };
    const r2 = [5]i32{ 15, 15, 15, 30, 30 };
    const roles = [5]i32{ 1, 1, 1, 3, 3 };
    const fams = [5]i32{ 1, 1, 2, 10, 11 };

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const d = creatures.DEFS[i];
        if (d.id != ids[i]) return false;
        if (d.role != roles[i]) return false;
        if (d.family != fams[i]) return false;
        if (d.hp != hps[i]) return false;
        if (d.resolve != res[i]) return false;
        if (d.speed != spd[i]) return false;
        if (d.attack != atk[i]) return false;
        if (d.subdue_chance != sub[i]) return false;
        if (d.sale != sale[i]) return false;
        if (d.respawn[0] != r0[i]) return false;
        if (d.respawn[1] != r1[i]) return false;
        if (d.respawn[2] != r2[i]) return false;
    }
    return true;
}

fn tCreatureBehaviors() bool {
    const eel = creatures.DEFS[0];
    if (eel.despair_regen != 8) return false;

    const mee = creatures.DEFS[1];
    if (mee.thrash_regen != 8) return false;
    if (mee.discharge_stat != fight.STAT_RES) return false;
    if (mee.discharge_th != 50) return false;
    if (mee.discharge_dmg != 8) return false;

    const tuna = creatures.DEFS[2];
    if (tuna.armor_pct != 60) return false;
    if (tuna.speed_below_stat != fight.STAT_HP) return false;
    if (tuna.speed_below_th != 30) return false;
    if (tuna.speed_below_add != 4) return false;

    const ane = creatures.DEFS[3];
    if (ane.thrash_regen != 10) return false;
    if (ane.discharge_stat != fight.STAT_HP) return false;
    if (ane.discharge_th != 48) return false;
    if (ane.discharge_dmg != 10) return false;

    const perch = creatures.DEFS[4];
    if (perch.despair_regen != 8) return false;
    if (perch.flee_kind != fight.FLEE_HIT_PCT) return false;
    if (perch.flee_th != 20) return false;

    if (creatures.RULES.len != 2) return false;
    const r0 = creatures.RULES[0];
    if (r0.cond_op != behavior.RES_BELOW or r0.cond_a != 50) return false;
    if (r0.effect_op != behavior.HULL_DMG or r0.effect_a != 8) return false;
    if (r0.timing != behavior.TIMING_ONESHOT) return false;

    const r1 = creatures.RULES[1];
    if (r1.cond_op != behavior.HP_BELOW or r1.cond_a != 48) return false;
    if (r1.effect_op != behavior.HULL_DMG or r1.effect_a != 10) return false;
    if (r1.timing != behavior.TIMING_ONESHOT) return false;
    return true;
}

// ---- Scripted smoke: one fight per outcome -------------------------------

const Smoke = struct { outcome: i32, steps: i32, saw_modal: bool };

fn runSequence(def_index: i32, seq: []const u8) Smoke {
    var s: def.GameState = undefined;
    game.startFight(&s, def_index);

    var r = Smoke{ .outcome = s.fight.outcome, .steps = 0, .saw_modal = false };
    var i: usize = 0;
    while (i < seq.len and s.fight.outcome == def.OUT_ONGOING) : (i += 1) {
        if (s.screen != fight.SCREEN_FIGHT) r.saw_modal = true;
        const a = input.mapKey(s.screen, key(seq[i])) orelse {
            r.outcome = -1;
            return r;
        };
        game.gameStep(&s, a);
        r.steps += 1;

        var sc: render.Screen = undefined;
        const d = creatures.defAt(def_index);
        render.renderFrame(&s, &d, &sc);
    }
    r.outcome = s.fight.outcome;
    return r;
}

fn outcomeName(o: i32) []const u8 {
    switch (o) {
        def.OUT_SUBDUE => return "SUBDUE",
        def.OUT_KILL => return "KILL",
        def.OUT_OVERKILL => return "OVERKILL",
        def.OUT_CREATURE_FLED => return "CREATURE_FLED",
        def.OUT_PLAYER_FLED => return "PLAYER_FLED",
        else => return "ONGOING",
    }
}

fn printSmoke(label: []const u8, r: Smoke) void {
    io.write("SMOKE ");
    io.write(label);
    io.write(" outcome=");
    io.write(outcomeName(r.outcome));
    io.write(" steps=");
    io.printInt(r.steps);
    io.write("\n");
}

fn tSmokeSubdue() bool {
    const r = runSequence(0, "RRRRRRRR");
    printSmoke("subdue", r);
    if (r.outcome != def.OUT_SUBDUE) return false;
    if (r.saw_modal) return false;
    if (r.steps != 8) return false;
    return true;
}

fn tSmokeKill() bool {
    const r = runSequence(2, "SSSSSSSSSSSS");
    printSmoke("kill", r);
    if (r.outcome != def.OUT_KILL) return false;
    return r.steps == 12;
}

fn tSmokeOverkill() bool {
    const r = runSequence(0, "SSSS");
    printSmoke("overkill", r);
    if (r.outcome != def.OUT_OVERKILL) return false;
    return r.steps == 4;
}

// Rare path smoke: all-Restrain drives Anemoniacus to the modal, then A rolls.
fn tSmokeRareModalSubdue() bool {
    const r = runSequence(3, "RRRRRRRRRRRRRRRRRRARRRRRRRARRRRRRRRRA");
    printSmoke("rare_modal_subdue", r);
    if (r.outcome != def.OUT_SUBDUE) return false;
    if (!r.saw_modal) return false;
    return r.steps == 37;
}

pub fn main() void {
    report("input_fight_keys_sr_ef", tFightKeys());
    report("input_modal_keys_a_f_esc", tModalKeys());
    report("input_esc_by_code", tEscByCode());
    report("render_fight_frame_fields", tRenderFightFrame());
    report("render_no_game_state_mutation", tRenderNoMutation());
    report("render_zero_and_max_bars_no_panic", tRenderZeroAndMaxBars());
    report("render_log_line_from_msg_table", tRenderLogLine());
    report("render_effective_speed_steel_tuna", tRenderEffectiveSpeed());
    report("render_effective_speed_last_surge_cap", tRenderSurgedSpeed());
    report("render_subdue_log_copy_9_4", tRenderSubdueLogCopy());
    report("render_subdue_modal", tRenderModal());
    report("creatures_table_5_rows_14_2", tCreatureTable());
    report("creatures_behaviors_14_3", tCreatureBehaviors());
    report("smoke_subdue", tSmokeSubdue());
    report("smoke_kill", tSmokeKill());
    report("smoke_overkill", tSmokeOverkill());
    report("smoke_rare_modal_subdue", tSmokeRareModalSubdue());

    if (fails != 0) os.exit(1);
    io.write("ui_test PASS\n");
}
