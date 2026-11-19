// persist_test.zig — native Linux tests for M7 persist.zig (§32).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/persist_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/persist_test"
//   "$OUT/persist_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const persist = @import("../persist.zig");
const creatures = @import("../creatures_t1.zig");

const P_VALID_A = "/tmp/m7t1_valid_a.dat";
const P_VALID_B = "/tmp/m7t1_valid_b.dat";
const P_BAD = "/tmp/m7t1_bad.dat";

var fails: usize = 0;
var file_buf: [256 * 1024]u8 = undefined;

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

fn replaceOnce(buf: []u8, needle: []const u8, repl: []const u8) bool {
    if (needle.len != repl.len) return false;
    if (buf.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= buf.len) : (i += 1) {
        if (!eq(buf[i .. i + needle.len], needle)) continue;
        var k: usize = 0;
        while (k < repl.len) : (k += 1) {
            buf[i + k] = repl[k];
        }
        return true;
    }
    return false;
}

fn writeFile(path: []const u8, bytes: []const u8) bool {
    file_mod.writeAll(path, bytes) catch return false;
    return true;
}

fn lineLenAfter(hay: []const u8, key: []const u8) usize {
    var i: usize = 0;
    while (i + key.len <= hay.len) : (i += 1) {
        if (!eq(hay[i .. i + key.len], key)) continue;
        var n: usize = 0;
        var k: usize = i;
        while (k < hay.len and hay[k] != '\n') : (k += 1) {
            n += 1;
        }
        return n;
    }
    return 0;
}

fn richState(g: *def.GameState) void {
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
        var d: i32 = 0;
        while (d < def.MAX_CREATURES) : (d += 1) {
            const ri: usize = i * def.MAX_CREATURES + @intCast(usize, d);
            if (d < creatures.defCount()) {
                w.ready[ri] = @intCast(i32, i) * 100 + d;
            } else {
                w.ready[ri] = 0;
            }
        }
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

    g.fight.def_index = 4;
    g.fight.outcome = def.OUT_SUBDUE;
}

fn expectErr(path: []const u8, w: *def.World, exp: *def.Expedition, want: persist.SaveErr) bool {
    var matched = false;
    persist.saveRead(path, w, exp) catch |e| {
        matched = e == want;
    };
    return matched;
}

fn tRoundTrip() bool {
    var g: def.GameState = undefined;
    richState(&g);
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var g2: def.GameState = undefined;
    game.newGame(&g2);
    persist.saveRead(P_VALID_A, &g2.world, &g2.exp) catch return false;
    persist.saveWrite(P_VALID_B, &g2.world, &g2.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const a = file_mod.readAll(&arena, P_VALID_A) catch return false;
    const b = file_mod.readAll(&arena, P_VALID_B) catch return false;
    if (!eq(a, b)) return false;
    if (g2.world.field_record.cycles != 4) return false;
    if (g2.exp.pending_cond != def.COND_SHAKY) return false;
    if (g2.exp.hold[7] != 6) return false;
    return true;
}

fn tCrcTamper() bool {
    var g: def.GameState = undefined;
    richState(&g);
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    if (!replaceOnce(raw, "cycle=7", "cycle=8")) return false;
    if (!writeFile(P_BAD, raw)) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    return expectErr(P_BAD, &w, &e, error.BadHash);
}

fn tVersionOne() bool {
    var g: def.GameState = undefined;
    richState(&g);
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    if (!replaceOnce(raw, "version=2", "version=1")) return false;
    if (!writeFile(P_BAD, raw)) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    return expectErr(P_BAD, &w, &e, error.BadVersion);
}

fn tDataVersionOne() bool {
    var g: def.GameState = undefined;
    richState(&g);
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    if (!replaceOnce(raw, "data_version=2", "data_version=1")) return false;
    if (!writeFile(P_BAD, raw)) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    return expectErr(P_BAD, &w, &e, error.BadDataVersion);
}

fn tUnknownCooldownId() bool {
    var g: def.GameState = undefined;
    richState(&g);
    const wr = &g.world;
    wr.ready[@intCast(usize, creatures.defCount())] = 1;
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    return expectErr(P_VALID_A, &w, &e, error.BadId);
}

fn tFailedLoadLeavesTarget() bool {
    var g: def.GameState = undefined;
    richState(&g);
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    if (!replaceOnce(raw, "version=2", "version=1")) return false;
    if (!writeFile(P_BAD, raw)) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    game.zeroWorld(&w);
    w.cycle = 777;
    w.hull = 42;
    w.money = -99;
    w.ready[0] = 555;
    memZeroExp(&e);
    e.active = -5;
    e.zone = 9;
    e.pending_cond = def.COND_EXPOSED;

    var ok = false;
    persist.saveRead(P_BAD, &w, &e) catch |err| {
        ok = err == error.BadVersion;
    };
    if (!ok) return false;
    if (w.cycle != 777 or w.hull != 42 or w.money != -99) return false;
    if (w.ready[0] != 555) return false;
    if (e.active != -5 or e.zone != 9 or e.pending_cond != def.COND_EXPOSED) return false;
    return true;
}

fn memZeroExp(e: *def.Expedition) void {
    e.active = 0;
    e.zone = 0;
    e.fight_index = 0;
    e.seed = 0;
    e.hold_n = 0;
    e.tool = 0;
    e.tool_charge = 0;
    e.tool_broken = 0;
    e.pending_cond = 0;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        e.hold[i] = 0;
    }
}

fn tReadyWorstCaseLine() bool {
    var g: def.GameState = undefined;
    richState(&g);
    const wr = &g.world;
    var z: usize = 0;
    while (z < def.MAX_ZONES) : (z += 1) {
        var d: i32 = 0;
        while (d < creatures.defCount()) : (d += 1) {
            const ri: usize = z * def.MAX_CREATURES + @intCast(usize, d);
            wr.ready[ri] = -2147483648;
        }
    }
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    const n = lineLenAfter(raw, "ready=");
    if (n <= 1000 or n > persist.MAX_LINE) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    persist.saveRead(P_VALID_A, &w, &e) catch return false;
    if (w.ready[0] != -2147483648) return false;
    return true;
}

fn tPendingSettlementNotSaved() bool {
    var g: def.GameState = undefined;
    richState(&g);
    g.fight.def_index = 5;
    g.fight.outcome = def.OUT_SUBDUE;
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    if (contains(raw, "outcome=")) return false;
    if (contains(raw, "def_index=")) return false;
    return true;
}

pub fn main() void {
    report("round_trip_byte_compare", tRoundTrip());
    report("crc_tamper_bad_hash", tCrcTamper());
    report("version_one_bad_version", tVersionOne());
    report("data_version_one_bad_data_version", tDataVersionOne());
    report("unknown_cooldown_id_bad_id", tUnknownCooldownId());
    report("failed_load_leaves_target_untouched", tFailedLoadLeavesTarget());
    report("ready_672_worst_case_line", tReadyWorstCaseLine());
    report("pending_settlement_not_saved", tPendingSettlementNotSaved());

    if (fails != 0) os.exit(1);
    io.write("persist_test PASS\n");
}
