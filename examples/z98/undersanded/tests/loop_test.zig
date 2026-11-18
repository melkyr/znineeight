// loop_test.zig — UNDERSANDED M4 Task 5 scripted expedition-loop driver.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/loop_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/loop_test"
//   "$OUT/loop_test"
// Prints a deterministic trace plus `ok - <case>` / `FAIL - <case>`; non-zero
// exit on any failure. The tier byte-compares stdout with loop_golden.txt.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");

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

fn writeHold(g: *const def.GameState) void {
    io.write("hold");
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        const count = g.exp.hold[i];
        if (count == 0) continue;
        io.write(" p");
        writeInt(@intCast(i32, i));
        io.write("=");
        writeInt(count);
    }
    io.write("\n");
}

fn driveSubdue(g: *def.GameState) i32 {
    var actions: i32 = 0;
    var guard: i32 = 0;
    while (expedition.isInFight(g) and guard < 200) : (guard += 1) {
        if (g.screen == fight.SCREEN_SUBDUE or g.screen == fight.SCREEN_SUBDUE_POST) {
            expedition.expeditionStep(g, def.ACT_ATTEMPT);
        } else if (g.fight.hp * 100 > g.fight.max_hp * 50) {
            expedition.expeditionStep(g, def.ACT_STRIKE);
        } else {
            expedition.expeditionStep(g, def.ACT_RESTRAIN);
        }
        actions += 1;
    }
    return actions;
}

fn driveKill(g: *def.GameState) i32 {
    var actions: i32 = 0;
    var guard: i32 = 0;
    while (expedition.isInFight(g) and guard < 200) : (guard += 1) {
        if (g.screen == fight.SCREEN_SUBDUE or g.screen == fight.SCREEN_SUBDUE_POST) {
            expedition.expeditionStep(g, def.ACT_ATTEMPT);
        } else if (g.fight.res * 100 > g.fight.max_res * 50) {
            expedition.expeditionStep(g, def.ACT_RESTRAIN);
        } else {
            expedition.expeditionStep(g, def.ACT_STRIKE);
        }
        actions += 1;
    }
    return actions;
}

fn isWary(w: *const def.World, d: i32) bool {
    if (d < 0) return false;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    const mask: u32 = @intCast(u32, 1) << bit;
    return (w.wary_mask[word] & mask) != 0;
}

fn holdMatches(a: *const def.GameState, snap: *const [def.MAX_PARTS]i32) bool {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (a.exp.hold[i] != snap[i]) return false;
    }
    return true;
}

fn copyHold(snap: *[def.MAX_PARTS]i32, g: *const def.GameState) void {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        snap[i] = g.exp.hold[i];
    }
}

fn fullLoop() bool {
    var s: def.GameState = undefined;
    game.newGame(&s);
    _ = expedition.depart(&s, 1);
    if (s.world.field_phases != 3) return false;

    expedition.expeditionStep(&s, expedition.EXP_HUNT);
    const f1_actions = driveSubdue(&s);
    const f1_out = s.fight.outcome;
    if (f1_out != def.OUT_SUBDUE) return false;
    const f1_idx = s.fight.def_index;
    if (f1_idx == expedition.NO_FIGHT) return false;
    if (s.exp.hold_n <= 0) return false;

    expedition.expeditionStep(&s, expedition.SUB_RELEASE);
    if (s.world.release_bonus[1] != 8) return false;
    if (!isWary(&s.world, f1_idx)) return false;
    if (s.fight.def_index != expedition.NO_FIGHT) return false;

    s.world.hull = 200;
    expedition.expeditionStep(&s, expedition.EXP_HUNT);
    const f2_actions = driveKill(&s);
    const f2_out = s.fight.outcome;
    if (f2_out != def.OUT_KILL) return false;
    if (s.fight.def_index != expedition.NO_FIGHT) return false;

    expedition.expeditionStep(&s, expedition.EXP_SURFACE);
    if (s.exp.active != 0) return false;

    io.write("full phases_out=3 f1=");
    writeInt(f1_out);
    io.write(" f1_actions=");
    writeInt(f1_actions);
    io.write(" bonus=8 f2=");
    writeInt(f2_out);
    io.write(" f2_actions=");
    writeInt(f2_actions);
    io.write(" hull=");
    writeInt(s.world.hull);
    io.write(" money=");
    writeInt(s.world.money);
    io.write("\n");
    writeHold(&s);
    return true;
}

fn ascentKeepsLoot() bool {
    var s: def.GameState = undefined;
    game.newGame(&s);
    _ = expedition.depart(&s, 1);

    expedition.expeditionStep(&s, expedition.EXP_HUNT);
    _ = driveKill(&s);
    if (s.fight.outcome != def.OUT_KILL and s.fight.outcome != def.OUT_OVERKILL) return false;
    if (s.exp.hold_n <= 0) return false;

    var snap: [def.MAX_PARTS]i32 = undefined;
    copyHold(&snap, &s);
    const hold_n = s.exp.hold_n;

    s.world.hull = 1;
    expedition.expeditionStep(&s, expedition.EXP_HUNT);
    var guard: i32 = 0;
    while (s.exp.active != 0 and guard < 200) : (guard += 1) {
        expedition.expeditionStep(&s, def.ACT_STRIKE);
    }
    if (s.exp.active != 0) return false;
    if (s.world.hull != 0) return false;
    if (s.exp.hold_n != hold_n) return false;
    if (!holdMatches(&s, &snap)) return false;

    io.write("ascent hold_kept=1 hull=0\n");
    return true;
}

fn emptyPoolRest() bool {
    var s: def.GameState = undefined;
    game.newGame(&s);
    s.world.hull = 50;
    _ = expedition.depart(&s, 3);
    expedition.expeditionStep(&s, expedition.EXP_REST);

    if (s.world.hull != 80) return false;
    if (s.pending_cond != def.COND_NONE) return false;

    io.write("empty_rest hull=80 cond=0\n");
    return true;
}

fn dockRest() bool {
    var s: def.GameState = undefined;
    game.newGame(&s);
    s.world.hull = 20;
    expedition.restAtDock(&s);
    const exact = s.world.hull;
    if (exact != 60) return false;
    if (s.world.field_phases != 1) return false;

    s.world.hull = 90;
    expedition.restAtDock(&s);
    if (s.world.hull != 100) return false;
    if (s.world.field_phases != 2) return false;

    io.write("dock_rest exact=");
    writeInt(exact);
    io.write(" clamp=100 phases=2\n");
    return true;
}

pub fn main() void {
    report("full_subdue_release_kill_surface", fullLoop());
    report("ascent_keeps_fight1_loot", ascentKeepsLoot());
    report("empty_pool_rest_safe", emptyPoolRest());
    report("dock_rest_exact_clamp_phases", dockRest());

    if (fails != 0) os.exit(1);
    io.write("loop_test PASS\n");
}
