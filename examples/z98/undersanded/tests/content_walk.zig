// content_walk.zig — UNDERSANDED M8 scripted full-loop content walk.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/content_walk.zig
//   sh "$OUT/build_target.sh" linux "$OUT/content_walk"
//   "$OUT/content_walk" <save-dir>
//
// Starts a fresh game, fights through Z1-Z3, and stops at the boss gate:
// locked/telegraphed before six distinct non-boss creatures are seen, open at
// six. Each settled fight unlocks its journal entry; the driver opens one entry
// (setting journal_viewed) and proves both masks survive a save round-trip.
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const game = @import("../game.zig");
const expedition = @import("../expedition.zig");
const fight = @import("../fight.zig");
const render = @import("../render_term.zig");
const journal = @import("../journal.zig");
const persist = @import("../persist.zig");
const creatures = @import("../creatures_t1.zig");

const DOCK_SCREEN: i32 = 10;
const BOSS_SEEN_GATE: i32 = 6;
const SAFE_HULL: i32 = 500;
const LOCKED_ROW: []const u8 = "D   The Derelict        5   locked  Hull 150+ recommended.";
const OPEN_ROW: []const u8 = "D   The Derelict        5   open  Hull 150+ recommended.";

var fails: usize = 0;

const Walk = struct {
    ok: bool,
    locked_before: bool,
    open_at_six: bool,
    journal_ok: bool,
    seen: i32,
    unlocked: i32,
    fights: i32,
    zone_mask: i32,
};

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

fn mapText(g: *const def.GameState, buf: []u8) []const u8 {
    var sc: render.Screen = undefined;
    render.renderMap(g, &sc);
    return render.dump(&sc, buf);
}

fn mapLocked(g: *const def.GameState) bool {
    var buf: [8192]u8 = undefined;
    return contains(mapText(g, buf[0..]), LOCKED_ROW);
}

fn mapOpen(g: *const def.GameState) bool {
    var buf: [8192]u8 = undefined;
    return contains(mapText(g, buf[0..]), OPEN_ROW);
}

fn driveFight(g: *def.GameState) bool {
    var guard: i32 = 0;
    while (guard < 400) : (guard += 1) {
        if (expedition.isInFight(g)) {
            if (g.screen == def.SCREEN_SUBDUE or g.screen == def.SCREEN_SUBDUE_POST) {
                expedition.expeditionStep(g, def.ACT_ATTEMPT);
            } else if (g.fight.hp * 100 > g.fight.max_hp * 50) {
                expedition.expeditionStep(g, def.ACT_STRIKE);
            } else {
                expedition.expeditionStep(g, def.ACT_RESTRAIN);
            }
            continue;
        }
        if (g.fight.outcome == def.OUT_SUBDUE and g.fight.def_index != def.NO_FIGHT) {
            expedition.expeditionStep(g, expedition.SUB_SELL);
            continue;
        }
        return true;
    }
    return false;
}

fn unlockedCount(w: *const def.World) i32 {
    var d: i32 = 0;
    var n: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (journal.journalUnlocked(w, d)) n += 1;
    }
    return n;
}

fn firstUnlocked(w: *const def.World) i32 {
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (journal.journalUnlocked(w, d)) return d;
    }
    return -1;
}

fn walk(g: *def.GameState) Walk {
    var r = Walk{
        .ok = false,
        .locked_before = false,
        .open_at_six = false,
        .journal_ok = false,
        .seen = 0,
        .unlocked = 0,
        .fights = 0,
        .zone_mask = 0,
    };
    game.newGame(g);
    g.screen = DOCK_SCREEN;
    g.world.hull = SAFE_HULL;

    if (render.bossGateOpen(g)) return r;
    r.locked_before = mapLocked(g);

    var seen = render.seenNonBossCount(g);
    var zone_mask: i32 = 0;
    var z: i32 = 0;
    var guard: i32 = 0;
    while (guard < 80) : (guard += 1) {
        if (seen >= BOSS_SEEN_GATE and zone_mask == 7) break;

        if (g.exp.active == 0) {
            g.world.hull = SAFE_HULL;
            _ = expedition.depart(g, z);
        }
        expedition.expeditionStep(g, expedition.EXP_HUNT);
        if (expedition.isInFight(g)) {
            const zbit = @intCast(u32, 1) << @intCast(u32, z);
            zone_mask = zone_mask | @intCast(i32, zbit);
            r.fights += 1;
            if (!driveFight(g)) return r;

            seen = render.seenNonBossCount(g);
            if (seen < BOSS_SEEN_GATE) {
                if (render.bossGateOpen(g)) return r;
                if (!mapLocked(g)) return r;
                r.locked_before = true;
            } else if (seen == BOSS_SEEN_GATE) {
                if (!render.bossGateOpen(g)) return r;
                if (!mapOpen(g)) return r;
                r.open_at_six = true;
            } else if (!render.bossGateOpen(g)) {
                return r;
            }
            if (g.exp.active != 0) expedition.expeditionStep(g, expedition.EXP_SURFACE);
        } else if (g.exp.active != 0) {
            expedition.expeditionStep(g, expedition.EXP_SURFACE);
        }

        z += 1;
        if (z > 2) z = 0;
    }

    r.seen = seen;
    r.zone_mask = zone_mask;
    r.unlocked = unlockedCount(&g.world);
    const had_new = journal.journalHasNew(&g.world);
    const d = firstUnlocked(&g.world);
    if (d >= 0) _ = journal.journalOpen(&g.world, d);
    const viewed = d >= 0 and journal.journalViewed(&g.world, d);
    r.journal_ok = r.unlocked == seen and had_new and viewed;
    r.ok = r.fights > 0 and zone_mask == 7 and seen >= BOSS_SEEN_GATE and
        r.locked_before and r.open_at_six and r.journal_ok;
    return r;
}

fn copyInto(dst: []u8, src: []const u8) []const u8 {
    var i: usize = 0;
    while (i < src.len and i < dst.len) : (i += 1) dst[i] = src[i];
    return dst[0..i];
}

fn joinInto(dir: []const u8, name: []const u8, out: []u8) ?[]const u8 {
    var at: usize = 0;
    while (at < dir.len and at < out.len) : (at += 1) out[at] = dir[at];
    if (at > 0 and out[at - 1] != '/') {
        if (at >= out.len) return null;
        out[at] = '/';
        at += 1;
    }
    var i: usize = 0;
    while (i < name.len and at < out.len) : (i += 1) {
        out[at] = name[i];
        at += 1;
    }
    if (i != name.len) return null;
    return out[0..at];
}

fn maskEq(a: *const [2]u32, b: *const [2]u32) bool {
    return a[0] == b[0] and a[1] == b[1];
}

fn masksNonZero(m: *const [2]u32) bool {
    return m[0] != 0 or m[1] != 0;
}

fn roundTrip(g: *const def.GameState, dir: []const u8) bool {
    var path_buf: [4096]u8 = undefined;
    const path = joinInto(dir, "save0.dat", path_buf[0..]) orelse return false;

    persist.saveWriteDirect(path, &g.world, &g.exp) catch return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    persist.saveRead(path, &w, &e) catch return false;

    if (!maskEq(&w.journal_mask, &g.world.journal_mask)) return false;
    if (!maskEq(&w.journal_viewed, &g.world.journal_viewed)) return false;
    if (!masksNonZero(&w.journal_mask)) return false;
    if (!masksNonZero(&w.journal_viewed)) return false;
    return true;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);

    var dir_buf: [4096]u8 = undefined;
    var dir: []const u8 = ".";
    if (os.argc() > 1) {
        dir = copyInto(dir_buf[0..], os.argv(1));
    }

    var g: def.GameState = undefined;
    const r = walk(&g);

    report("full_loop_z1_z3_fights_to_boss_gate", r.ok);
    report("boss_node_locked_before_six_seen", r.locked_before);
    report("boss_node_open_telegraph_at_six_seen", r.open_at_six);
    report("journal_unlocks_and_viewed_bits", r.journal_ok);
    report("journal_masks_survive_save_roundtrip", r.journal_ok and roundTrip(&g, dir));

    io.write("content_walk seen=");
    io.printInt(r.seen);
    io.write(" unlocked=");
    io.printInt(r.unlocked);
    io.write(" fights=");
    io.printInt(r.fights);
    io.write(" zones=");
    io.printInt(r.zone_mask);
    io.write("\n");

    if (fails != 0) os.exit(1);
    io.write("content_walk PASS\n");
}
