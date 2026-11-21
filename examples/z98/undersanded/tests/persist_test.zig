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

const T_DIR = "/tmp/";
const T_SAVE0 = "/tmp/save0.dat";
const T_SAVE1 = "/tmp/save1.dat";
const T_TMP = "/tmp/save.tmp";
const T_BAK = "/tmp/save.bak";
const T_LOG = "/tmp/errors.log";
const P_ROLL = "/tmp/m7t2_roll_save0.dat";
const P_MISSING = "/tmp/m7t1_does_not_exist.dat";
const P_RESAVE = "/tmp/m7t1_fixture_resave.sav";
const FIXTURE_V2 = "examples/z98/undersanded/tests/fixtures/save_v2_valid.sav";
const FIXTURE_V2_OLD = "examples/z98/undersanded/tests/fixtures/save_v2_no_journal_viewed.sav";

var fails: usize = 0;
var file_buf: [256 * 1024]u8 = undefined;
var alt_buf: [persist.MAX_FILE]u8 = undefined;

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

fn removeIfExists(path: []const u8) void {
    if (file_mod.exists(path)) file_mod.remove(path) catch {};
}

fn readInto(path: []const u8, storage: []u8) ?[]const u8 {
    var arena = arena_mod.init(storage);
    const raw = file_mod.readAll(&arena, path) catch return null;
    return raw;
}

fn fileContains(path: []const u8, needle: []const u8) bool {
    var buf: [4096]u8 = undefined;
    const raw = readInto(path, buf[0..]) orelse return false;
    return contains(raw, needle);
}

fn cleanSlots() void {
    removeIfExists(P_ROLL);
    removeIfExists(T_SAVE0);
    removeIfExists(T_SAVE1);
    removeIfExists(T_TMP);
    removeIfExists(T_BAK);
    removeIfExists(T_LOG);
}

fn loadCycle(path: []const u8, out: *i32) bool {
    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    persist.saveRead(path, &w, &e) catch return false;
    out.* = w.cycle;
    return true;
}

fn seedTwoSaves(path: []const u8) bool {
    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 11;
    persist.saveWrite(path, &g.world, &g.exp) catch return false;
    g.world.cycle = 22;
    persist.saveWrite(path, &g.world, &g.exp) catch return false;
    return true;
}

fn win9xRename(old_path: []const u8, new_path: []const u8) file_mod.FileError!void {
    if (file_mod.exists(new_path)) return error.RenameFailed;
    return file_mod.rename(old_path, new_path);
}

fn failStep5Rename(old_path: []const u8, new_path: []const u8) file_mod.FileError!void {
    if (eq(old_path, T_TMP) and eq(new_path, P_ROLL)) return error.RenameFailed;
    return file_mod.rename(old_path, new_path);
}

fn corruptWrite(path: []const u8, data: []const u8) file_mod.FileError!void {
    _ = data;
    return file_mod.writeAll(path, "corrupt save\n");
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

fn findSeq(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (hay.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (eq(hay[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn copyTo(out: []u8, at: *usize, src: []const u8) bool {
    if (at.* + src.len > out.len) return false;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        out[at.* + i] = src[i];
    }
    at.* += src.len;
    return true;
}

fn hexNib(n: u32) u8 {
    if (n < 10) return @intCast(u8, @intCast(u32, '0') + n);
    return @intCast(u8, @intCast(u32, 'a') + n - 10);
}

fn appendHex8(out: []u8, at: *usize, v: u32) bool {
    if (at.* + 8 > out.len) return false;
    var shift: i32 = 28;
    while (shift >= 0) : (shift -= 4) {
        out[at.*] = hexNib((v >> @intCast(u32, shift)) & 0xF);
        at.* += 1;
    }
    return true;
}

// Insert one line just before [crc32] and recompute the hash so crafted input
// reaches the post-CRC range checks instead of failing as BadHash.
fn rewriteBeforeCrc(raw: []const u8, insert: []const u8, out: []u8) ?[]const u8 {
    const idx = findSeq(raw, "[crc32]\n") orelse return null;
    var at: usize = 0;
    if (!copyTo(out, &at, raw[0..idx])) return null;
    if (!copyTo(out, &at, insert)) return null;
    const hash = persist.crcOf(out[0..at]);
    if (!copyTo(out, &at, "[crc32]\nhash=0x")) return null;
    if (!appendHex8(out, &at, hash)) return null;
    if (!copyTo(out, &at, "\n")) return null;
    return out[0..at];
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
    w.journal_viewed[0] = 0x00000001;
    w.journal_viewed[1] = 0;
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

fn tHappyPathSlots() bool {
    cleanSlots();
    if (!seedTwoSaves(P_ROLL)) return false;
    if (!file_mod.exists(P_ROLL) or !file_mod.exists(T_BAK)) return false;
    var c: i32 = 0;
    if (!loadCycle(P_ROLL, &c) or c != 22) return false;
    if (!loadCycle(T_BAK, &c) or c != 11) return false;
    return true;
}

fn tSecondSaveWithPreExistingBak() bool {
    cleanSlots();
    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 11;
    persist.saveWrite(P_ROLL, &g.world, &g.exp) catch return false;
    if (!writeFile(T_BAK, "stale backup\n")) return false;

    g.world.cycle = 22;
    var wrote = true;
    persist.fs_rename = win9xRename;
    persist.saveWrite(P_ROLL, &g.world, &g.exp) catch {
        wrote = false;
    };
    persist.fs_rename = file_mod.rename;
    if (!wrote) return false;

    var c: i32 = 0;
    if (!loadCycle(P_ROLL, &c) or c != 22) return false;
    if (!loadCycle(T_BAK, &c) or c != 11) return false;
    return true;
}

fn tStep5FailureRollsBack() bool {
    cleanSlots();
    if (!seedTwoSaves(P_ROLL)) return false;
    if (!file_mod.exists(T_BAK)) return false;

    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 33;

    var got_io = false;
    persist.fs_rename = failStep5Rename;
    persist.saveWrite(P_ROLL, &g.world, &g.exp) catch |e| {
        got_io = e == error.Io;
    };
    persist.fs_rename = file_mod.rename;
    if (!got_io) return false;

    if (!file_mod.exists(P_ROLL)) return false;
    var c: i32 = 0;
    if (!loadCycle(P_ROLL, &c) or c != 22) return false;
    return true;
}

fn tStep3VerifyFailureAborts() bool {
    cleanSlots();
    if (!seedTwoSaves(P_ROLL)) return false;
    if (!file_mod.exists(T_BAK)) return false;

    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 33;

    var got_err = false;
    persist.fs_write = corruptWrite;
    persist.saveWrite(P_ROLL, &g.world, &g.exp) catch |verr| {
        got_err = verr == error.Damaged or verr == error.BadHash;
    };
    persist.fs_write = file_mod.writeAll;
    if (!got_err) return false;

    var c: i32 = 0;
    if (!loadCycle(P_ROLL, &c) or c != 22) return false;
    if (!loadCycle(T_BAK, &c) or c != 11) return false;
    if (file_mod.exists(T_TMP)) return false;
    return true;
}

fn makeCrashState() bool {
    cleanSlots();
    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 11;
    persist.saveWrite(T_SAVE0, &g.world, &g.exp) catch return false;
    persist.fs_rename(T_SAVE0, T_BAK) catch return false;
    if (file_mod.exists(T_SAVE0)) return false;
    if (!writeFile(T_TMP, "stale temp\n")) return false;
    return true;
}

fn tRecoveryRestoresAndLogs() bool {
    if (!makeCrashState()) return false;
    persist.recoverAtBoot(T_DIR);
    if (!file_mod.exists(T_SAVE0)) return false;
    if (file_mod.exists(T_TMP)) return false;
    if (file_mod.exists(T_BAK)) return false;
    var c: i32 = 0;
    if (!loadCycle(T_SAVE0, &c) or c != 11) return false;
    if (!fileContains(T_LOG, "recovery")) return false;
    if (!fileContains(T_LOG, "save.bak")) return false;
    return true;
}

fn tStaleTmpDeleted() bool {
    cleanSlots();
    if (!writeFile(T_TMP, "stale temp\n")) return false;
    persist.recoverAtBoot(T_DIR);
    return !file_mod.exists(T_TMP);
}

fn bootWouldFreshInstall() bool {
    return !file_mod.exists(T_SAVE0);
}

fn tRecoveryPrecedesFreshInstall() bool {
    if (!makeCrashState()) return false;
    if (!bootWouldFreshInstall()) return false;
    persist.recoverAtBoot(T_DIR);
    if (bootWouldFreshInstall()) return false;
    return file_mod.exists(T_SAVE0);
}

fn tFixtureCanonicalResave() bool {
    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, FIXTURE_V2) catch return false;
    if (raw.len == 0) return false;
    if (!contains(raw, "journal_viewed=1,0")) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    persist.saveRead(FIXTURE_V2, &w, &e) catch return false;
    persist.saveWrite(P_RESAVE, &w, &e) catch return false;

    var arena2 = arena_mod.init(alt_buf[0..]);
    const saved = file_mod.readAll(&arena2, P_RESAVE) catch return false;
    removeIfExists(P_RESAVE);
    if (!eq(raw, saved)) return false;
    if (e.pending_cond != def.COND_SHAKY) return false;
    if (e.zone != 2 or e.tool != 4 or e.hold[7] != 6) return false;
    return w.cycle == 7 and w.boss_variants_seen == 0x1F;
}

// Additive optional key: an M7-era save with no [journal] journal_viewed line
// still loads, defaulting the mask to zero. The current writer always emits it.
fn tOldSaveWithoutJournalViewedLoads() bool {
    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    game.zeroWorld(&w);
    persist.saveRead(FIXTURE_V2_OLD, &w, &e) catch return false;
    if (w.journal_viewed[0] != 0 or w.journal_viewed[1] != 0) return false;
    if (w.journal_mask[0] != 0x00000003 or w.journal_mask[1] != 0) return false;
    if (w.cycle != 7 or w.boss_variants_seen != 0x1F) return false;

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, FIXTURE_V2_OLD) catch return false;
    if (contains(raw, "journal_viewed=")) return false;

    // The current writer upgrades the old image by adding the key.
    persist.saveWrite(P_RESAVE, &w, &e) catch return false;
    const saved = fileContains(P_RESAVE, "journal_viewed=0,0");
    removeIfExists(P_RESAVE);
    return saved;
}

fn craftedBad(kind: i32) bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    const ep = &g.exp;
    const wp = &g.world;
    switch (kind) {
        0 => ep.active = 2,
        1 => ep.zone = @intCast(i32, def.MAX_ZONES),
        2 => ep.zone = -1,
        3 => ep.fight_index = -1,
        4 => ep.tool = -1,
        5 => ep.tool = 8,
        6 => ep.tool_charge = -1,
        7 => ep.tool_broken = 2,
        8 => ep.pending_cond = 4,
        9 => ep.hold[0] = -1,
        10 => wp.boss_variants_seen = 32,
        11 => wp.tools_owned = @intCast(u32, 1) << @intCast(u32, 8),
        12 => wp.cosmetics_owned = @intCast(u32, 1) << @intCast(u32, 12),
        13 => wp.cosmetics_unlocked = @intCast(u32, 1) << @intCast(u32, 12),
        else => return false,
    }
    persist.saveWrite(P_BAD, &g.world, &g.exp) catch {
        io.write(" saveWrite failed\n");
        return false;
    };

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    if (!expectErr(P_BAD, &w, &e, error.Damaged)) {
        io.write(" expectErr missed\n");
        return false;
    }
    return true;
}

fn tCraftedCrcValidRejected() bool {
    cleanSlots();
    var k: i32 = 0;
    while (k < 14) : (k += 1) {
        if (!craftedBad(k)) {
            io.write("crafted kind failed: ");
            io.printInt(k);
            io.write("\n");
            return false;
        }
    }
    removeIfExists(P_BAD);
    cleanSlots();
    return true;
}

fn seedValidA() bool {
    var g: def.GameState = undefined;
    richState(&g);
    persist.saveWrite(P_VALID_A, &g.world, &g.exp) catch return false;
    return true;
}

fn tOptionsUnknownSkipped() bool {
    if (!seedValidA()) return false;
    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    const rewritten = rewriteBeforeCrc(raw, "mystery=1\n", alt_buf[0..]) orelse return false;
    if (!writeFile(P_BAD, rewritten)) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    persist.saveRead(P_BAD, &w, &e) catch return false;
    return w.cycle == 7 and e.pending_cond == def.COND_SHAKY and e.hold[7] == 6;
}

fn tTrailingAfterCrcRejected() bool {
    if (!seedValidA()) return false;
    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    var at: usize = 0;
    if (!copyTo(alt_buf[0..], &at, raw)) return false;
    if (!copyTo(alt_buf[0..], &at, "junk\n")) return false;
    if (!writeFile(P_BAD, alt_buf[0..at])) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    return expectErr(P_BAD, &w, &e, error.Damaged);
}

fn tOverMaxLineRejected() bool {
    if (!seedValidA()) return false;
    var line: [persist.MAX_LINE + 2]u8 = undefined;
    var i: usize = 0;
    while (i <= persist.MAX_LINE) : (i += 1) {
        line[i] = 'a';
    }
    line[persist.MAX_LINE + 1] = '\n';

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, P_VALID_A) catch return false;
    const rewritten = rewriteBeforeCrc(raw, line[0..], alt_buf[0..]) orelse return false;
    if (!writeFile(P_BAD, rewritten)) return false;

    var w: def.World = undefined;
    var e: def.Expedition = undefined;
    return expectErr(P_BAD, &w, &e, error.Damaged);
}

fn poisonedUntouched(path: []const u8, want: persist.SaveErr) bool {
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

    var got: ?persist.SaveErr = null;
    persist.saveRead(path, &w, &e) catch |err| {
        got = err;
    };
    const err = got orelse return false;
    if (err != want) return false;
    if (w.cycle != 777 or w.hull != 42 or w.money != -99) return false;
    if (w.ready[0] != 555) return false;
    return e.active == -5 and e.zone == 9 and e.pending_cond == def.COND_EXPOSED;
}

fn tFailedLoadAllClasses() bool {
    cleanSlots();
    if (!seedValidA()) return false;
    var arena = arena_mod.init(file_buf[0..]);
    const base = file_mod.readAll(&arena, P_VALID_A) catch return false;
    var at: usize = 0;

    at = 0;
    if (!copyTo(alt_buf[0..], &at, base)) return false;
    if (!replaceOnce(alt_buf[0..at], "version=2", "version=1")) return false;
    if (!writeFile(P_BAD, alt_buf[0..at])) return false;
    if (!poisonedUntouched(P_BAD, error.BadVersion)) return false;

    at = 0;
    if (!copyTo(alt_buf[0..], &at, base)) return false;
    if (!replaceOnce(alt_buf[0..at], "data_version=2", "data_version=1")) return false;
    if (!writeFile(P_BAD, alt_buf[0..at])) return false;
    if (!poisonedUntouched(P_BAD, error.BadDataVersion)) return false;

    at = 0;
    if (!copyTo(alt_buf[0..], &at, base)) return false;
    if (!replaceOnce(alt_buf[0..at], "cycle=7", "cycle=8")) return false;
    if (!writeFile(P_BAD, alt_buf[0..at])) return false;
    if (!poisonedUntouched(P_BAD, error.BadHash)) return false;

    at = 0;
    if (!copyTo(alt_buf[0..], &at, base)) return false;
    if (!copyTo(alt_buf[0..], &at, "junk\n")) return false;
    if (!writeFile(P_BAD, alt_buf[0..at])) return false;
    if (!poisonedUntouched(P_BAD, error.Damaged)) return false;

    var gid: def.GameState = undefined;
    richState(&gid);
    const gid_world = &gid.world;
    gid_world.ready[@intCast(usize, creatures.defCount())] = 1;
    persist.saveWrite(P_BAD, &gid.world, &gid.exp) catch return false;
    if (!poisonedUntouched(P_BAD, error.BadId)) return false;

    if (!poisonedUntouched(P_MISSING, error.Missing)) return false;
    removeIfExists(P_BAD);
    cleanSlots();
    return true;
}

fn tRecoveryNoTrailingSep() bool {
    if (!makeCrashState()) return false;
    persist.recoverAtBoot("/tmp");
    if (!file_mod.exists(T_SAVE0)) return false;
    if (file_mod.exists(T_TMP)) return false;
    if (file_mod.exists(T_BAK)) return false;
    var c: i32 = 0;
    if (!loadCycle(T_SAVE0, &c) or c != 11) return false;
    return fileContains(T_LOG, "recovery") and fileContains(T_LOG, "save.bak");
}

fn tLogErrorNoTrailingSep() bool {
    cleanSlots();
    persist.logError("/tmp", "log probe no trailing separator");
    if (!file_mod.exists(T_LOG)) return false;
    return fileContains(T_LOG, "log probe no trailing separator");
}

fn tBackupSlotNoTrailingSep() bool {
    cleanSlots();
    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 45;
    persist.saveBackupSlot("/tmp", &g.world, &g.exp) catch return false;
    if (!file_mod.exists(T_SAVE1)) return false;
    var c: i32 = 0;
    if (!loadCycle(T_SAVE1, &c) or c != 45) return false;
    return fileContains(T_LOG, "backup slot");
}

fn tBackupSlotManual() bool {
    cleanSlots();
    var g: def.GameState = undefined;
    richState(&g);
    g.world.cycle = 44;
    persist.saveBackupSlot(T_DIR, &g.world, &g.exp) catch return false;
    if (!file_mod.exists(T_SAVE1)) return false;
    if (file_mod.exists(T_SAVE0)) return false;
    if (file_mod.exists(T_BAK)) return false;
    var c: i32 = 0;
    if (!loadCycle(T_SAVE1, &c) or c != 44) return false;
    if (!fileContains(T_LOG, "backup slot")) return false;
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
    report("happy_path_saves_save0_and_bak", tHappyPathSlots());
    report("second_save_with_preexisting_bak", tSecondSaveWithPreExistingBak());
    report("step5_failure_rolls_back_save0", tStep5FailureRollsBack());
    report("step3_verify_failure_aborts_untouched", tStep3VerifyFailureAborts());
    report("startup_recovery_restores_and_logs", tRecoveryRestoresAndLogs());
    report("startup_recovery_deletes_stale_tmp", tStaleTmpDeleted());
    report("startup_recovery_precedes_fresh_install", tRecoveryPrecedesFreshInstall());
    report("backup_slot_writes_save1_manually", tBackupSlotManual());
    report("fixture_v2_canonical_resave", tFixtureCanonicalResave());
    report("old_save_without_journal_viewed_loads", tOldSaveWithoutJournalViewedLoads());
    report("crafted_crc_valid_rejected", tCraftedCrcValidRejected());
    report("options_unknown_keys_skipped", tOptionsUnknownSkipped());
    report("trailing_content_after_crc_rejected", tTrailingAfterCrcRejected());
    report("over_max_line_rejected", tOverMaxLineRejected());
    report("failed_load_all_classes_untouched", tFailedLoadAllClasses());
    report("recovery_no_trailing_separator", tRecoveryNoTrailingSep());
    report("log_error_no_trailing_separator", tLogErrorNoTrailingSep());
    report("backup_slot_no_trailing_separator", tBackupSlotNoTrailingSep());

    if (fails != 0) os.exit(1);
    io.write("persist_test PASS\n");
}
