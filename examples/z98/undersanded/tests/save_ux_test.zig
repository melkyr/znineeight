// save_ux_test.zig — native Linux tests for M7 save UX + first run (§20/§32/§33).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/save_ux_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/save_ux_test"
//   "$OUT/save_ux_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

@cInclude("<unistd.h>");
@cInclude("<sys/stat.h>");

extern "c" fn mkdir(path: [*]const u8, mode: u32) i32;
extern "c" fn rmdir(path: [*]const u8) i32;

const io = @import("std_io");
const os = @import("std_os");
const parse = @import("std_parse");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");
const persist = @import("../persist.zig");
const render = @import("../render_term.zig");
const save_ux = @import("../save_ux.zig");

var fails: usize = 0;
var prefix_buf: [128]u8 = undefined;
var prefix: []const u8 = prefix_buf[0..0];

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

fn copyInto(out: []u8, at: *usize, text: []const u8) void {
    var i: usize = 0;
    while (i < text.len and at.* < out.len) : (i += 1) {
        out[at.*] = text[i];
        at.* += 1;
    }
}

fn initPrefix() void {
    var at: usize = 0;
    copyInto(prefix_buf[0..], &at, "/tmp/m7t3_ux_");
    var digits_buf: [16]u8 = undefined;
    const digits = parse.itoa(digits_buf[0..], os.getpid());
    copyInto(prefix_buf[0..], &at, digits);
    prefix = prefix_buf[0..at];
}

fn filePath(name: []const u8, out: []u8) []const u8 {
    var at: usize = 0;
    copyInto(out, &at, prefix);
    copyInto(out, &at, "/");
    copyInto(out, &at, name);
    return out[0..at];
}

fn ensureDir(path: []const u8) bool {
    var buf: [256]u8 = undefined;
    if (path.len + 1 > buf.len) return false;
    var i: usize = 0;
    while (i < path.len) : (i += 1) buf[i] = path[i];
    buf[path.len] = 0;
    return mkdir(@ptrCast([*]const u8, &buf[0]), 493) == 0;
}

fn removeDir(path: []const u8) void {
    var buf: [256]u8 = undefined;
    if (path.len + 1 > buf.len) return;
    var i: usize = 0;
    while (i < path.len) : (i += 1) buf[i] = path[i];
    buf[path.len] = 0;
    _ = rmdir(@ptrCast([*]const u8, &buf[0]));
}

fn removeIfExists(path: []const u8) void {
    if (file_mod.exists(path)) file_mod.remove(path) catch {};
}

fn cleanAll() void {
    var buf: [256]u8 = undefined;
    removeIfExists(filePath("save0.dat", buf[0..]));
    removeIfExists(filePath("save1.dat", buf[0..]));
    removeIfExists(filePath("save.tmp", buf[0..]));
    removeIfExists(filePath("save.bak", buf[0..]));
    removeIfExists(filePath("options.cfg", buf[0..]));
    removeIfExists(filePath("errors.log", buf[0..]));
    removeIfExists(filePath("v1.sav", buf[0..]));
    removeIfExists(filePath("node.sav", buf[0..]));
}

fn writeFile(path: []const u8, bytes: []const u8) bool {
    file_mod.writeAll(path, bytes) catch return false;
    return true;
}

fn readInto(path: []const u8, storage: []u8) []const u8 {
    var arena = arena_mod.init(storage);
    return file_mod.readAll(&arena, path) catch storage[0..0];
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

fn tCanSaveMatrix() bool {
    var g: def.GameState = undefined;

    game.newGame(&g);
    if (save_ux.canSave(&g) != null) return false;

    g.exp.active = 1;
    g.exp.zone = 2;
    if (save_ux.canSave(&g) != null) return false;

    game.newGame(&g);
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_ONGOING;
    if (save_ux.canSave(&g) == null) return false;

    game.newGame(&g);
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_SUBDUE;
    if (save_ux.canSave(&g) == null) return false;

    game.newGame(&g);
    g.fight.def_index = def.NO_FIGHT;
    g.fight.outcome = def.OUT_SUBDUE;
    if (save_ux.canSave(&g) != null) return false;
    return true;
}

fn tQuitPrompt() bool {
    if (!eq(save_ux.QUIT_PROMPT, "Save before quitting? [Y] [N] [Cancel]")) return false;
    var g: def.GameState = undefined;
    game.newGame(&g);
    return save_ux.quitPromptNeeded(&g);
}

fn tReadSaveSlot() bool {
    var buf: [256]u8 = undefined;
    const path = filePath("options.cfg", buf[0..]);
    removeIfExists(path);
    if (save_ux.readSaveSlot(prefix) != 0) return false;
    if (!writeFile(path, "save_slot=1\n")) return false;
    if (save_ux.readSaveSlot(prefix) != 1) return false;
    if (!writeFile(path, "save_slot=0\n")) return false;
    if (save_ux.readSaveSlot(prefix) != 0) return false;
    if (!writeFile(path, "save_slot=2\n")) return false;
    if (save_ux.readSaveSlot(prefix) != 0) return false;
    if (!writeFile(path, "save_slot = 1\n")) return false;
    if (save_ux.readSaveSlot(prefix) != 1) return false;
    removeIfExists(path);
    return true;
}

fn seedState(g: *def.GameState) void {
    game.newGame(g);
    g.world.cycle = 7;
    g.world.phase = 1;
    g.world.hull = 100;
    g.world.money = 42;
}

fn tSaveErrorVersionOne() bool {
    var g: def.GameState = undefined;
    seedState(&g);
    var buf: [256]u8 = undefined;
    const base = filePath("save0.dat", buf[0..]);
    persist.saveWrite(base, &g.world, &g.exp) catch return false;

    var storage: [16384]u8 = undefined;
    const raw = readInto(base, storage[0..]);
    if (raw.len == 0) return false;
    if (!replaceOnce(storage[0..raw.len], "version=2", "version=1")) return false;

    var vbuf: [256]u8 = undefined;
    const vpath = filePath("v1.sav", vbuf[0..]);
    if (!writeFile(vpath, raw)) return false;

    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    var got: ?persist.SaveErr = null;
    persist.saveRead(vpath, &w, &exp) catch |e| {
        got = e;
    };
    const err = got orelse return false;
    if (err != error.BadVersion) return false;
    if (!eq(save_ux.saveErrText(err), "Save is from a different version.")) return false;

    var sc: render.Screen = undefined;
    render.renderSaveError(save_ux.saveErrText(err), &sc);
    var out: [8192]u8 = undefined;
    const text = render.dump(&sc, out[0..]);
    if (!contains(text, "Save is from a different version.")) return false;
    if (!contains(text, "[F]resh  [B]ackup slot  [Q]uit")) return false;
    if (contains(text, "Continue")) return false;

    g.screen = nav.NAV_SAVE_ERR;
    var st = nav.NavState{
        .armed = 0,
        .last = nav.NAV_RESULT_NONE,
        .save_err_kind = save_ux.saveErrKind(err),
    };
    var nav_buf: [8192]u8 = undefined;
    const nav_text = nav.drawCurrent(&g, &st, nav_buf[0..]);
    if (!contains(nav_text, "Save is from a different version.")) return false;
    if (!contains(nav_text, "[F]resh  [B]ackup slot  [Q]uit")) return false;
    if (contains(nav_text, "Save file is damaged.")) return false;
    return true;
}

fn appendLine(out: []u8, at: *usize, text: []const u8) void {
    copyInto(out, at, text);
    if (at.* < out.len) {
        out[at.*] = 10;
        at.* += 1;
    }
}

fn expectedLore(out: []u8) []const u8 {
    var at: usize = 0;
    appendLine(out, &at, "UNDERSANDED  LORE");
    appendLine(out, &at, "");
    appendLine(out, &at, "First line.");
    appendLine(out, &at, "");
    appendLine(out, &at, "Second paragraph.");
    var y: usize = 5;
    while (y < 29) : (y += 1) {
        appendLine(out, &at, "");
    }
    appendLine(out, &at, "[Enter] Begin");
    return out[0..at];
}

fn tFirstRun() bool {
    var buf: [256]u8 = undefined;
    removeIfExists(filePath("save0.dat", buf[0..]));
    removeIfExists(filePath("save.bak", buf[0..]));

    var t: def.Tables = undefined;
    t.text_count = 1;
    t.text_key[0] = "manual.1";
    t.text_val[0] = "First line.\n\nSecond paragraph.";
    t.content_version = 2;
    t.def_count = 18;
    def.content_override = &t;

    var sc: render.Screen = undefined;
    render.renderLore(save_ux.manualPageOne(), &sc);
    var out: [8192]u8 = undefined;
    const text = render.dump(&sc, out[0..]);

    var exp_buf: [8192]u8 = undefined;
    const expected = expectedLore(exp_buf[0..]);
    if (!eq(text, expected)) {
        def.content_override = null;
        io.write("---- lore frame ----\n");
        io.write(text);
        io.write("---- expected ----\n");
        io.write(expected);
        return false;
    }
    if (contains(text, "MAIN MENU")) {
        def.content_override = null;
        return false;
    }
    if (contains(text, "[N]ew Game")) {
        def.content_override = null;
        return false;
    }

    var g: def.GameState = undefined;
    save_ux.firstRunBegin(&g, prefix) catch {
        def.content_override = null;
        return false;
    };
    def.content_override = null;

    if (g.screen != nav.NAV_DOCK) return false;
    if (g.screen == nav.NAV_MENU) return false;
    if (g.world.money != 0) return false;
    if (g.world.field_record_written != 0) return false;
    if (g.world.boss_variants_seen != 0) return false;
    if (g.exp.active != 0) return false;

    const path = filePath("save0.dat", buf[0..]);
    if (!file_mod.exists(path)) return false;

    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(path, &w, &exp) catch return false;
    if (w.field_record_written != 0) return false;
    if (w.boss_variants_seen != 0) return false;
    if (w.money != 0) return false;
    return true;
}

fn tManualFallback() bool {
    def.content_override = null;
    if (!eq(save_ux.manualPageOne(), save_ux.MANUAL_UNAVAILABLE)) return false;
    var sc: render.Screen = undefined;
    render.renderLore(save_ux.manualPageOne(), &sc);
    var out: [8192]u8 = undefined;
    const text = render.dump(&sc, out[0..]);
    if (!contains(text, "(manual text unavailable)")) return false;
    if (!contains(text, "[Enter] Begin")) return false;
    return true;
}

fn tNodeRoundTrip() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    const ep = &g.exp;
    ep.active = 1;
    ep.zone = 2;
    ep.fight_index = 1;
    ep.seed = 0x00ABCDEF;
    ep.hold_n = 3;
    ep.hold[1] = 4;
    ep.hold[4] = 2;
    ep.pending_cond = def.COND_SHAKY;
    g.world.money = 55;
    if (save_ux.canSave(&g) != null) return false;

    var buf: [256]u8 = undefined;
    const path = filePath("node.sav", buf[0..]);
    persist.saveWrite(path, &g.world, &g.exp) catch return false;

    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(path, &w, &exp) catch return false;

    if (exp.active != 1) return false;
    if (exp.zone != 2) return false;
    if (exp.fight_index != 1) return false;
    if (exp.seed != 0x00ABCDEF) return false;
    if (exp.hold_n != 3) return false;
    if (exp.hold[1] != 4) return false;
    if (exp.hold[4] != 2) return false;
    if (exp.pending_cond != def.COND_SHAKY) return false;
    if (w.money != 55) return false;
    return true;
}

fn tLoreDeterministic() bool {
    var t: def.Tables = undefined;
    t.text_count = 1;
    t.text_key[0] = "manual.1";
    t.text_val[0] = "Alpha\nBeta\n\nGamma";
    t.content_version = 2;
    t.def_count = 18;
    def.content_override = &t;

    var sc1: render.Screen = undefined;
    var sc2: render.Screen = undefined;
    render.renderLore(save_ux.manualPageOne(), &sc1);
    render.renderLore(save_ux.manualPageOne(), &sc2);
    def.content_override = null;

    var b1: [8192]u8 = undefined;
    var b2: [8192]u8 = undefined;
    const a = render.dump(&sc1, b1[0..]);
    const b = render.dump(&sc2, b2[0..]);
    if (!eq(a, b)) return false;
    if (!contains(a, "Alpha")) return false;
    if (!contains(a, "Beta")) return false;
    if (!contains(a, "Gamma")) return false;
    return true;
}

fn tMenuScreen() bool {
    var sc: render.Screen = undefined;
    render.renderMenu(&sc);
    var out: [8192]u8 = undefined;
    const text = render.dump(&sc, out[0..]);
    if (!contains(text, "UNDERSANDED  MAIN MENU")) return false;
    if (!contains(text, "[C]ontinue")) return false;
    if (!contains(text, "[N]ew Game")) return false;
    if (!contains(text, "[O]ptions (unavailable until M12)")) return false;
    if (!contains(text, "[Q]uit")) return false;
    return true;
}

fn tDockSaveEsc() bool {
    var buf: [256]u8 = undefined;
    removeIfExists(filePath("save0.dat", buf[0..]));
    removeIfExists(filePath("save1.dat", buf[0..]));
    removeIfExists(filePath("save.tmp", buf[0..]));
    removeIfExists(filePath("save.bak", buf[0..]));
    removeIfExists(filePath("options.cfg", buf[0..]));

    var g: def.GameState = undefined;
    seedState(&g);
    const out = save_ux.dockSave(&g, prefix);
    if (!out.ok) return false;
    if (!eq(out.text, "Saved.")) return false;

    const path = filePath("save0.dat", buf[0..]);
    if (!file_mod.exists(path)) return false;
    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(path, &w, &exp) catch return false;
    return w.cycle == 7;
}

fn tDockSaveBlocked() bool {
    var buf: [256]u8 = undefined;
    removeIfExists(filePath("save0.dat", buf[0..]));
    removeIfExists(filePath("save1.dat", buf[0..]));
    removeIfExists(filePath("options.cfg", buf[0..]));

    var g: def.GameState = undefined;
    game.newGame(&g);
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_ONGOING;
    const out = save_ux.dockSave(&g, prefix);
    if (out.ok) return false;
    if (!eq(out.text, "Cannot save during a fight.")) return false;
    if (file_mod.exists(filePath("save0.dat", buf[0..]))) return false;
    if (file_mod.exists(filePath("save1.dat", buf[0..]))) return false;
    return true;
}

fn tQuitDecisions() bool {
    var buf: [256]u8 = undefined;
    removeIfExists(filePath("save0.dat", buf[0..]));
    removeIfExists(filePath("save1.dat", buf[0..]));
    removeIfExists(filePath("save.bak", buf[0..]));
    removeIfExists(filePath("options.cfg", buf[0..]));

    var g: def.GameState = undefined;
    seedState(&g);

    const yes = save_ux.quitDecision(&g, prefix, 'Y');
    if (!yes.quit or !yes.saved) return false;
    if (!eq(yes.text, "Saved.")) return false;
    if (!file_mod.exists(filePath("save0.dat", buf[0..]))) return false;

    removeIfExists(filePath("save0.dat", buf[0..]));
    removeIfExists(filePath("save.bak", buf[0..]));
    const no = save_ux.quitDecision(&g, prefix, 'N');
    if (!no.quit or no.saved) return false;
    if (no.text.len != 0) return false;
    if (file_mod.exists(filePath("save0.dat", buf[0..]))) return false;

    const cancel = save_ux.quitDecision(&g, prefix, 'X');
    if (cancel.quit or cancel.saved) return false;
    if (cancel.text.len != 0) return false;
    if (file_mod.exists(filePath("save0.dat", buf[0..]))) return false;
    return true;
}

fn tSlotOneBackup() bool {
    var b0: [256]u8 = undefined;
    var b1: [256]u8 = undefined;
    var bb: [256]u8 = undefined;
    var bo: [256]u8 = undefined;
    const save0 = filePath("save0.dat", b0[0..]);
    const save1 = filePath("save1.dat", b1[0..]);
    const bak = filePath("save.bak", bb[0..]);
    const options = filePath("options.cfg", bo[0..]);
    removeIfExists(save0);
    removeIfExists(save1);
    removeIfExists(bak);
    removeIfExists(options);

    var g: def.GameState = undefined;
    seedState(&g);
    g.world.cycle = 11;
    persist.saveWrite(save0, &g.world, &g.exp) catch return false;
    g.world.cycle = 22;
    persist.saveWrite(save0, &g.world, &g.exp) catch return false;

    if (!writeFile(options, "save_slot=1\n")) return false;

    var h: def.GameState = undefined;
    seedState(&h);
    h.world.cycle = 44;
    const out = save_ux.dockSave(&h, prefix);
    if (!out.ok) return false;
    if (!eq(out.text, "Saved.")) return false;

    if (!file_mod.exists(save1)) return false;
    if (!file_mod.exists(save0)) return false;
    if (!file_mod.exists(bak)) return false;

    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(save0, &w, &exp) catch return false;
    if (w.cycle != 22) return false;
    persist.saveRead(bak, &w, &exp) catch return false;
    if (w.cycle != 11) return false;
    persist.saveRead(save1, &w, &exp) catch return false;
    if (w.cycle != 44) return false;

    removeIfExists(options);
    return true;
}

fn key(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn tBootRouting() bool {
    if (nav.bootStartScreen(true) != nav.NAV_MENU) return false;
    if (nav.bootStartScreen(false) != nav.NAV_LORE) return false;
    if (nav.menuAction(key('c')) != nav.BOOT_ACT_CONTINUE) return false;
    if (nav.menuAction(key('N')) != nav.BOOT_ACT_NEW) return false;
    if (nav.menuAction(key('o')) != nav.BOOT_ACT_OPTIONS) return false;
    if (nav.menuAction(key('q')) != nav.BOOT_ACT_QUIT) return false;
    if (nav.menuAction(key('x')) != nav.BOOT_ACT_NONE) return false;
    if (nav.confirmAction(key('Y')) != nav.BOOT_ACT_YES) return false;
    if (nav.confirmAction(key('n')) != nav.BOOT_ACT_NO) return false;
    if (nav.confirmAction(key('x')) != nav.BOOT_ACT_NONE) return false;
    if (nav.errorAction(key('f')) != nav.BOOT_ACT_FRESH) return false;
    if (nav.errorAction(key('b')) != nav.BOOT_ACT_BACKUP) return false;
    if (nav.errorAction(key('q')) != nav.BOOT_ACT_QUIT) return false;
    if (nav.errorAction(key('x')) != nav.BOOT_ACT_NONE) return false;
    if (!nav.firstRunAdvance(key(10))) return false;
    if (!nav.firstRunAdvance(key(13))) return false;
    if (nav.firstRunAdvance(key('x'))) return false;
    if (!eq(save_ux.NEW_GAME_CONFIRM, "Erase this save? [Y] [N]")) return false;
    return true;
}

fn tBootFreshFirstRun() bool {
    var b0: [256]u8 = undefined;
    var bb: [256]u8 = undefined;
    var bo: [256]u8 = undefined;
    var b1: [256]u8 = undefined;
    const save0 = filePath("save0.dat", b0[0..]);
    const bak = filePath("save.bak", bb[0..]);
    const options = filePath("options.cfg", bo[0..]);
    const save1 = filePath("save1.dat", b1[0..]);
    removeIfExists(save0);
    removeIfExists(save1);
    removeIfExists(bak);
    removeIfExists(options);

    if (nav.bootStartScreen(save_ux.saveSlotExists(prefix, 0)) != nav.NAV_LORE) return false;
    if (!nav.firstRunAdvance(key(13))) return false;

    var g: def.GameState = undefined;
    save_ux.firstRunBeginSlot(&g, prefix, 0) catch return false;
    if (g.screen != nav.NAV_DOCK) return false;
    if (g.screen == nav.NAV_MENU) return false;
    if (!file_mod.exists(save0)) return false;
    if (nav.bootStartScreen(save_ux.saveSlotExists(prefix, 0)) != nav.NAV_MENU) return false;

    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(save0, &w, &exp) catch return false;
    return w.money == 0 and w.cycle == 0 and exp.active == 0;
}

fn tBootContinueLoads() bool {
    var b0: [256]u8 = undefined;
    const save0 = filePath("save0.dat", b0[0..]);
    removeIfExists(save0);

    var seed: def.GameState = undefined;
    seedState(&seed);
    seed.world.cycle = 77;
    seed.world.money = 123;
    persist.saveWrite(save0, &seed.world, &seed.exp) catch return false;

    var g: def.GameState = undefined;
    game.newGame(&g);
    g.world.money = 999;
    save_ux.loadSlot(&g, prefix, 0) catch return false;
    if (g.world.cycle != 77) return false;
    if (g.world.money != 123) return false;
    if (g.screen != nav.NAV_DOCK) return false;
    if (g.fight.def_index != def.NO_FIGHT) return false;
    return true;
}

fn tBootNewGameConfirm() bool {
    var b0: [256]u8 = undefined;
    const save0 = filePath("save0.dat", b0[0..]);
    removeIfExists(save0);

    var old: def.GameState = undefined;
    seedState(&old);
    old.world.cycle = 55;
    old.world.money = 9;
    persist.saveWrite(save0, &old.world, &old.exp) catch return false;

    if (nav.confirmAction(key('n')) != nav.BOOT_ACT_NO) return false;
    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(save0, &w, &exp) catch return false;
    if (w.cycle != 55) return false;

    if (nav.confirmAction(key('y')) != nav.BOOT_ACT_YES) return false;
    var g: def.GameState = undefined;
    game.newGame(&g);
    const out = save_ux.saveToSlot(&g, prefix, 0);
    if (!out.ok) return false;

    persist.saveRead(save0, &w, &exp) catch return false;
    if (w.cycle != 0) return false;
    if (w.money != 0) return false;
    return true;
}

fn tBootBadVersionFresh() bool {
    var b0: [256]u8 = undefined;
    var bb: [256]u8 = undefined;
    const save0 = filePath("save0.dat", b0[0..]);
    const bak = filePath("save.bak", bb[0..]);
    removeIfExists(save0);
    removeIfExists(bak);

    var seed: def.GameState = undefined;
    seedState(&seed);
    persist.saveWrite(save0, &seed.world, &seed.exp) catch return false;

    var storage: [16384]u8 = undefined;
    const raw = readInto(save0, storage[0..]);
    if (raw.len == 0) return false;
    if (!replaceOnce(storage[0..raw.len], "version=2", "version=1")) return false;
    if (!writeFile(save0, raw)) return false;

    var g: def.GameState = undefined;
    game.newGame(&g);
    g.world.money = 999;
    var got: ?persist.SaveErr = null;
    save_ux.loadSlot(&g, prefix, 0) catch |e| {
        got = e;
    };
    const err = got orelse return false;
    if (err != error.BadVersion) return false;
    if (g.world.money != 999) return false;
    if (!eq(save_ux.saveErrText(err), "Save is from a different version.")) return false;

    if (nav.errorAction(key('f')) != nav.BOOT_ACT_FRESH) return false;
    save_ux.eraseSlot(prefix, 0);
    if (file_mod.exists(save0)) return false;
    if (nav.bootStartScreen(save_ux.saveSlotExists(prefix, 0)) != nav.NAV_LORE) return false;

    var fresh: def.GameState = undefined;
    save_ux.firstRunBeginSlot(&fresh, prefix, 0) catch return false;
    if (fresh.screen != nav.NAV_DOCK) return false;
    if (!file_mod.exists(save0)) return false;
    return true;
}

fn tBootBackupSlot() bool {
    var b0: [256]u8 = undefined;
    var b1: [256]u8 = undefined;
    var bo: [256]u8 = undefined;
    var bb: [256]u8 = undefined;
    const save0 = filePath("save0.dat", b0[0..]);
    const save1 = filePath("save1.dat", b1[0..]);
    const options = filePath("options.cfg", bo[0..]);
    const bak = filePath("save.bak", bb[0..]);
    removeIfExists(save0);
    removeIfExists(save1);
    removeIfExists(options);
    removeIfExists(bak);

    var seed: def.GameState = undefined;
    seedState(&seed);
    seed.world.cycle = 11;
    seed.world.money = 10;
    persist.saveWrite(save0, &seed.world, &seed.exp) catch return false;

    var storage: [16384]u8 = undefined;
    const raw = readInto(save0, storage[0..]);
    if (raw.len == 0) return false;
    if (!replaceOnce(storage[0..raw.len], "version=2", "version=1")) return false;
    if (!writeFile(save0, raw)) return false;

    var backup: def.GameState = undefined;
    seedState(&backup);
    backup.world.cycle = 22;
    backup.world.money = 20;
    const out = save_ux.saveToSlot(&backup, prefix, 1);
    if (!out.ok) return false;
    if (!file_mod.exists(save1)) return false;

    if (save_ux.readSaveSlot(prefix) != 0) return false;
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.world.money = 999;
    var failed = false;
    save_ux.loadSlot(&g, prefix, 0) catch {
        failed = true;
    };
    if (!failed) return false;
    if (g.world.money != 999) return false;

    if (nav.errorAction(key('b')) != nav.BOOT_ACT_BACKUP) return false;
    const slot = save_ux.otherSlot(0);
    save_ux.loadSlot(&g, prefix, slot) catch return false;
    if (g.world.cycle != 22) return false;
    if (g.world.money != 20) return false;
    if (g.screen != nav.NAV_DOCK) return false;

    if (nav.errorAction(key('q')) != nav.BOOT_ACT_QUIT) return false;
    return true;
}

pub fn main() void {
    initPrefix();
    _ = ensureDir(prefix);
    cleanAll();

    report("canSave_matrix", tCanSaveMatrix());
    report("quit_prompt_text", tQuitPrompt());
    report("options_cfg_save_slot", tReadSaveSlot());
    report("save_error_screen_version_one", tSaveErrorVersionOne());
    report("first_run_golden", tFirstRun());
    report("manual_fallback_line", tManualFallback());
    report("node_save_load_round_trip", tNodeRoundTrip());
    report("lore_render_deterministic", tLoreDeterministic());
    report("menu_screen", tMenuScreen());
    report("dock_save_esc_success", tDockSaveEsc());
    report("dock_save_blocked_reason", tDockSaveBlocked());
    report("quit_decisions", tQuitDecisions());
    report("slot_one_manual_backup", tSlotOneBackup());
    report("boot_routing_and_keys", tBootRouting());
    report("boot_fresh_first_run_no_menu", tBootFreshFirstRun());
    report("boot_continue_loads_slot", tBootContinueLoads());
    report("boot_new_game_confirm", tBootNewGameConfirm());
    report("boot_bad_version_fresh", tBootBadVersionFresh());
    report("boot_backup_slot", tBootBackupSlot());

    cleanAll();
    removeDir(prefix);
    if (fails != 0) os.exit(1);
    io.write("save_ux_test PASS\n");
}
