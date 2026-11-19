// save_v2_fixture.zig — one-shot deterministic v2 save fixture generator.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/save_v2_fixture.zig
//   sh "$OUT/build_target.sh" linux "$OUT/save_v2_fixture"
//   "$OUT/save_v2_fixture" examples/z98/undersanded/tests/fixtures/save_v2_valid.sav
//
// The committed fixture is generated once from this fixed World/Expedition
// state. The M7 tier never runs this generator; it only re-saves the fixture.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const game = @import("../game.zig");
const persist = @import("../persist.zig");

fn knownState(g: *def.GameState) void {
    game.newGame(g);
    const w = &g.world;
    w.cycle = 7;
    w.phase = 1;
    w.seen_mask[0] = 0x00000007;
    w.seen_mask[1] = 0;
    w.journal_mask[0] = 0x00000003;
    w.journal_mask[1] = 0;
    w.tooltip_shown = 0xABCDEF;
    w.field_phases = 23;
    w.hull = 150;
    w.family_overkill_mask = 0x00000123;
    w.wary_mask[0] = 0x00000002;
    w.wary_mask[1] = 0;
    w.rng_state = 0xDEADBEEF;
    w.money = 12345;
    w.tools_owned = 0x000000FE;
    w.tool_selected = 3;
    w.cosmetics_owned = 0x00000FFF;
    w.cosmetics_unlocked = 0x00000005;
    w.boss_variants_seen = 0x0000001F;
    w.boss_kills = 2;
    w.field_record_written = 1;
    w.score_subdued = 11;
    w.score_killed = 12;
    w.score_overkilled = 13;
    w.score_money_earned = 14;

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        w.boat[i] = 2;
    }
    i = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        w.expertise[i] = @intCast(i32, i % 6);
        w.materials[i] = @intCast(i32, i) * 3;
    }
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        w.release_bonus[i] = @intCast(i32, i) * 2;
        w.lockout_until[i] = @intCast(i32, i) + 100;
    }

    const fr = &w.field_record;
    fr.cycles = 4;
    fr.field_phases = 33;
    fr.creatures_seen = 10;
    fr.rares_seen = 4;
    fr.bosses_killed = 1;
    fr.final_phase2 = 1;
    fr.subdued = 20;
    fr.killed = 21;
    fr.overkilled = 22;
    fr.money_earned = 500;
    fr.cosmetics = 3;
    i = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        fr.expertise[i] = @intCast(i32, i % 6);
    }
    i = 0;
    while (i < 5) : (i += 1) {
        fr.boat[i] = 1;
    }

    const lr = &w.last_run;
    lr.cycles = 2;
    lr.phase2 = 1;
    lr.outcome = def.OUT_SUBDUE;
    lr.actions = 9;
    lr.hull_spent = 40;
    lr.boss_kills = 1;

    const ep = &g.exp;
    ep.active = 1;
    ep.zone = 2;
    ep.fight_index = 3;
    ep.seed = 0x00ABCDEF;
    ep.hold_n = 2;
    ep.tool = 4;
    ep.tool_charge = 1;
    ep.tool_broken = 0;
    ep.pending_cond = def.COND_SHAKY;
    i = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        ep.hold[i] = 0;
    }
    ep.hold[2] = 5;
    ep.hold[7] = 6;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    if (os.argc() != 2) {
        io.write("usage: save_v2_fixture <out.sav>\n");
        os.exit(2);
        return;
    }
    var g: def.GameState = undefined;
    knownState(&g);
    persist.saveWrite(os.argv(1), &g.world, &g.exp) catch {
        io.write("save_v2_fixture: write failed\n");
        os.exit(1);
        return;
    };
}
