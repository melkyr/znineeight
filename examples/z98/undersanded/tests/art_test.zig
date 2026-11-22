// art_test.zig — native gate for the M9 Task 4 art fight frame.
//
// Covers the pure glyph helper, §27 bar geometry (including max_res == 0),
// dotted borders + inline numerics, hidden / journal / Sonar Speed, the full
// tool status width, dirty coalescing/area, tween equal samples, shared
// msgLine parity, art modal/help determinism, and the pinned 640x480 art-fight
// framebuffer checksum.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/art_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/art_test"
//   "$OUT/art_test"

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const creatures = @import("../creatures_t1.zig");
const render = @import("../render_term.zig");
const art = @import("../render_art.zig");
const assets = @import("../assets.zig");
const tween = @import("../tween.zig");
const font = @import("../font8x16.zig");
const paths = @import("../paths.zig");
const core = @import("std_gfx_px_core.zig");

@cInclude("<sys/stat.h>");

extern "c" fn mkdir(path: [*]const u8, mode: u32) i32;

const GOLDEN_PATH = "examples/z98/undersanded/tests/fixtures/art_fight.golden";
const ASSETS_DIR = "examples/z98/undersanded/assets";
const MAL_DIR = "/tmp/z98_m10_art_manifest";
const MAL_OUT = "/tmp/z98_m10_art_manifest/out";

var fails: usize = 0;
var arena_buf: [64 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;
var copy_dir_arena_buf: [16 * 1024]u8 = undefined;
var copy_file_arena_buf: [64 * 1024]u8 = undefined;
var copy_man_buf: [16 * 1024]u8 = undefined;

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

fn dumpPix(d: []const u8, x: i32, y: i32) u16 {
    const off = (@intCast(usize, y) * 640 + @intCast(usize, x)) * 2;
    return @intCast(u16, d[off]) | (@intCast(u16, d[off + 1]) << 8);
}

fn surfPix(sf: *const core.Surface, x: i32, y: i32) u16 {
    const off = @intCast(usize, y) * @intCast(usize, sf.pitch)
        + @intCast(usize, x * 2);
    return @intCast(u16, sf.pixels[off])
        | (@intCast(u16, sf.pixels[off + 1]) << 8);
}

fn fnv(data: []const u8) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        h = (h ^ @intCast(u32, data[i])) *% 16777619;
    }
    return h;
}

fn setJournalBit(g: *def.GameState, d: i32) void {
    if (d < 0 or d >= 64) return;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    var mask: *[2]u32 = &g.world.journal_mask;
    mask[word] = mask[word] | (@intCast(u32, 1) << bit);
}

fn baseFight(g: *def.GameState) void {
    game.newGame(g);
    game.startFight(g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.exp.fight_index = 0;
    g.exp.seed = 98;
    g.world.phase = 1;
    g.world.money = 123;
    g.fight.hp = 42;
    g.fight.max_hp = 70;
    g.fight.res = 8;
    g.fight.max_res = 10;
    g.fight.hull = 80;
    g.fight.max_hull = 100;
    g.fight.margin_pct = 10;
    g.fight.tool = 4;
    g.fight.tool_charge = 1;
    g.fight.tool_broken = 0;
    g.fight.tool_active = 1;
    g.fight.round = 1;
    g.screen = def.SCREEN_FIGHT;
}

fn goldenFight(g: *def.GameState) void {
    baseFight(g);
    setJournalBit(g, g.fight.def_index);
    g.log_n = 3;
    g.log[0] = def.LogEntry{
        .class = def.LOG_NORMAL, .msg_id = def.MSG_STRIKE, .a = 17, .b = 0,
    };
    g.log[1] = def.LogEntry{
        .class = def.LOG_NORMAL, .msg_id = def.MSG_CREATURE_ATTACK,
        .a = 9, .b = 91,
    };
    g.log[2] = def.LogEntry{
        .class = def.LOG_NORMAL, .msg_id = def.MSG_INK, .a = 0, .b = 0,
    };
}

var empty_px: [1]u8 = [1]u8{0};

fn assetView(g: *const def.GameState) art.ArtAssets {
    var view = art.emptyAssets();
    const a = assets.current() orelse return view;
    view.bg = assets.ensureBackgroundZone(g.exp.zone);
    if (g.fight.def_index >= 0 and g.fight.def_index < creatures.defCount()) {
        const d = creatures.defAt(g.fight.def_index);
        view.sprite = assets.spriteForDef(a, d.id);
    }
    return view;
}

fn renderIntoView(g: *def.GameState, help_text: []const u8, full: bool,
    view: art.ArtAssets) []const u8 {
    const handle = core.gfxPxOpenMemory(640, 480) catch return empty_px[0..0];
    var sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, g, help_text, full, view);
    return core.gfxPxDump(handle);
}

fn renderInto(g: *def.GameState, help_text: []const u8, full: bool) []const u8 {
    return renderIntoView(g, help_text, full, assetView(g));
}

fn renderWithNotice(g: *def.GameState, notice: []const u8) []const u8 {
    const handle = core.gfxPxOpenMemory(640, 480) catch return empty_px[0..0];
    var sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, g, "", true, assetView(g));
    art.drawNotice(&sf, g, notice);
    return core.gfxPxDump(handle);
}

fn findWidget(g: *def.GameState, kind: i32, slot: i32) art.Widget {
    var ws: [art.MAX_WIDGETS]art.Widget = undefined;
    const n = art.layoutFight(g, &ws);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const w = ws[@intCast(usize, i)];
        if (w.kind == kind and (slot < 0 or w.a == slot)) return w;
    }
    return art.Widget{
        .x = 0, .y = 0, .w = 0, .h = 0, .kind = 0, .dirty = 0,
        .a = 0, .b = 0, .c = 0, .text_off = 0, .sprite = 0,
    };
}

fn tFontGlyphBlit() bool {
    if (font.GLYPH_COUNT != 95) return false;
    const space = font.glyph(' ');
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        if (space[i] != 0) return false;
    }
    const a = font.glyph('A');
    var sum: u32 = 0;
    i = 0;
    while (i < 16) : (i += 1) sum += @intCast(u32, a[i]);
    if (sum == 0) return false;
    const high = font.glyph(200);
    i = 0;
    while (i < 16) : (i += 1) {
        if (high[i] != 0) return false;
    }

    var buf: [64]u8 = [64]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const sf = core.Surface{
        .pixels = @ptrCast([*]u8, &buf[0]),
        .pitch = 32,
        .w = 8,
        .h = 2,
    };
    const bits: [2]u8 = [2]u8{ 0x80, 0x01 };
    core.pxCoreBlit1bpp(&sf, 0, 0, @ptrCast([*]const u8, &bits[0]),
        8, 2, 0xF800, 0x001F);
    if (surfPix(&sf, 0, 0) != 0xF800) return false;
    if (surfPix(&sf, 1, 0) != 0x001F) return false;
    if (surfPix(&sf, 7, 1) != 0xF800) return false;
    var k: usize = 16;
    while (k < 20) : (k += 1) {
        if (buf[k] != 0) return false;
    }
    return true;
}

fn tBarGeometry() bool {
    const z = art.barGeometry(100, 0, 100, 10);
    if (z.fill != 0 or z.red != 15) return false;
    const h = art.barGeometry(100, 50, 100, 10);
    if (h.fill != 50 or h.red != 15) return false;
    const m = art.barGeometry(100, 100, 100, 10);
    if (m.fill != 100 or m.red != 15) return false;
    const m25 = art.barGeometry(100, 50, 100, 25);
    if (m25.fill != 50 or m25.red != 0) return false;
    const over = art.barGeometry(100, 150, 100, 10);
    if (over.fill != 100 or over.red != 15) return false;
    const boss = art.barGeometry(100, 0, 0, 10);
    if (boss.fill != 0 or boss.red != 0) return false;
    const boss2 = art.barGeometry(100, 50, 0, 10);
    if (boss2.fill != 0 or boss2.red != 0) return false;
    const neg = art.barGeometry(100, 50, -5, 10);
    if (neg.fill != 0 or neg.red != 0) return false;
    const wide = art.barGeometry(200, 100, 100, 10);
    if (wide.fill != 200 or wide.red != 30) return false;
    return true;
}

fn tBarBorderAndNumeric() bool {
    var g: def.GameState = undefined;
    baseFight(&g);
    art.resetFrame();
    const d = renderInto(&g, "", true);
    const hp = findWidget(&g, art.W_HP, -1);
    if (hp.w != 520 or hp.h != 36) return false;
    if (dumpPix(d, hp.x, hp.y) != art.C_DOT) return false;
    if (dumpPix(d, hp.x + 1, hp.y) == art.C_DOT) return false;
    if (dumpPix(d, hp.x, hp.y + 1) == art.C_DOT) return false;
    if (dumpPix(d, hp.x, hp.y + 2) != art.C_DOT) return false;
    if (dumpPix(d, hp.x + hp.w - 1, hp.y) != art.C_DOT) return false;
    if (dumpPix(d, hp.x, hp.y + art.BAR_H - 1) != art.C_DOT) return false;
    if (dumpPix(d, hp.x + 1, hp.y + 1) == art.C_RED) return false;

    var numeric: i32 = 0;
    var y: i32 = hp.y + 4;
    while (y < hp.y + 20) : (y += 1) {
        var x: i32 = hp.x + 6;
        while (x < hp.x + 72) : (x += 1) {
            if (dumpPix(d, x, y) == art.C_TEXT) numeric += 1;
        }
    }
    if (numeric == 0) return false;

    g.fight.res = 0;
    g.fight.max_res = 0;
    art.resetFrame();
    const boss = renderInto(&g, "", true);
    const res = findWidget(&g, art.W_RES, -1);
    if (art.barGeometry(res.w - 2, res.a, res.b, res.c).fill != 0) return false;
    numeric = 0;
    y = res.y + 4;
    while (y < res.y + 20) : (y += 1) {
        var x: i32 = res.x + 6;
        while (x < res.x + 72) : (x += 1) {
            if (dumpPix(boss, x, y) == art.C_TEXT) numeric += 1;
        }
    }
    return numeric != 0;
}

fn tBarRedZoneBorder() bool {
    var g: def.GameState = undefined;
    baseFight(&g);
    art.resetFrame();
    const d = renderInto(&g, "", true);
    const hp = findWidget(&g, art.W_HP, -1);
    const bw = hp.w;
    const bh = art.BAR_H;
    const bar = art.barGeometry(bw - 2, hp.a, hp.b, hp.c);
    if (bar.red <= 4) return false;
    const rx = hp.x + 1 + (bw - 2) - bar.red;
    if (dumpPix(d, rx, hp.y + 1) != art.C_DOT) return false;
    if (dumpPix(d, rx + 2, hp.y + 1) != art.C_DOT) return false;
    if (dumpPix(d, rx + 1, hp.y + 1) == art.C_DOT) return false;
    if (dumpPix(d, rx, hp.y + 3) != art.C_DOT) return false;
    if (dumpPix(d, rx + bar.red - 1, hp.y + 1) != art.C_DOT) return false;
    if (dumpPix(d, rx + 1, hp.y + bh - 2) == art.C_DOT) return false;
    return true;
}

fn tShakeOnSubdueFail() bool {
    var g: def.GameState = undefined;
    baseFight(&g);
    art.resetFrame();
    art.shakeUpdate(&g, 1000, 1000);
    if (art.shakeOffsetX() != 0 or art.shakeOffsetY() != 0) return false;

    var i: usize = @intCast(usize, g.log_n);
    g.log[i] = def.LogEntry{
        .class = def.LOG_WARN, .msg_id = def.MSG_SUBDUE_FAIL, .a = 0, .b = 0,
    };
    g.log_n = g.log_n + 1;
    art.shakeUpdate(&g, 1000, 1000);
    const x0 = art.shakeOffsetX();
    const y0 = art.shakeOffsetY();
    if (x0 == 0 and y0 == 0) return false;

    art.shakeUpdate(&g, 1090, 1000);
    if (art.shakeOffsetX() == x0) return false;
    const x1 = art.shakeOffsetX();
    art.shakeUpdate(&g, 1090, 1000);
    if (art.shakeOffsetX() != x1) return false;

    art.shakeUpdate(&g, 1180, 1000);
    if (art.shakeOffsetX() != 0 or art.shakeOffsetY() != 0) return false;
    art.shakeUpdate(&g, 2000, 1000);
    if (art.shakeOffsetX() != 0) return false;

    i = @intCast(usize, g.log_n);
    g.log[i] = def.LogEntry{
        .class = def.LOG_WARN, .msg_id = def.MSG_SUBDUE_FAIL, .a = 0, .b = 0,
    };
    g.log_n = g.log_n + 1;
    art.shakeUpdate(&g, 2000, 1000);
    const retriggered = art.shakeOffsetX() != 0 or art.shakeOffsetY() != 0;
    art.resetFrame();
    return retriggered;
}

fn tSpeedReveal() bool {
    var g: def.GameState = undefined;
    baseFight(&g);
    g.fight.tool = 0;
    g.fight.tool_active = 0;
    if (render.speedRevealed(&g)) return false;
    var w = findWidget(&g, art.W_STATS, -1);
    if (w.a != -1) return false;

    setJournalBit(&g, g.fight.def_index);
    if (!render.speedRevealed(&g)) return false;
    var d = creatures.defAt(g.fight.def_index);
    w = findWidget(&g, art.W_STATS, -1);
    if (w.a != render.effectiveSpeed(&g, &d)) return false;

    var mask: *[2]u32 = &g.world.journal_mask;
    mask[0] = 0;
    mask[1] = 0;
    g.fight.tool = def.TOOL_SONAR;
    g.fight.tool_active = 1;
    if (!render.speedRevealed(&g)) return false;
    w = findWidget(&g, art.W_STATS, -1);
    if (w.a != render.effectiveSpeed(&g, &d)) return false;

    g.fight.tool_active = 0;
    if (render.speedRevealed(&g)) return false;
    w = findWidget(&g, art.W_STATS, -1);
    return w.a == -1;
}

fn tStatsCondition() bool {
    var g: def.GameState = undefined;
    baseFight(&g);
    g.fight.cond = def.COND_EXPOSED;
    const w = findWidget(&g, art.W_STATS, -1);
    if (w.sprite != def.COND_EXPOSED) return false;
    if (!eq(render.conditionName(w.sprite), "Exposed")) return false;

    art.resetFrame();
    const shown = fnv(renderInto(&g, "", true));
    g.fight.cond = def.COND_NONE;
    art.resetFrame();
    const plain = fnv(renderInto(&g, "", true));
    return shown != plain;
}

fn tStatsPhase() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    game.startFight(&g, 14);
    g.fight.round = 1;
    var w = findWidget(&g, art.W_STATS, -1);
    if (w.text_off != fight.PHASE_SOLID) return false;
    g.fight.round = 3;
    w = findWidget(&g, art.W_STATS, -1);
    if (w.text_off != fight.PHASE_PHASED) return false;
    g.fight.def_index = 0;
    w = findWidget(&g, art.W_STATS, -1);
    return w.text_off == -1;
}

fn tNoticeKeepsNewestLog() bool {
    const newest = art.LOG_Y + (art.LOG_LINES - 1) * art.LINE_H;
    if (art.noticeY(2) != art.LOG_Y + 2 * art.LINE_H) return false;
    if (art.noticeY(art.LOG_LINES) == newest) return false;
    if (art.noticeY(art.LOG_LINES + 4) == newest) return false;

    var g: def.GameState = undefined;
    goldenFight(&g);
    g.log_n = art.LOG_LINES;
    var i: i32 = 0;
    while (i < art.LOG_LINES) : (i += 1) {
        g.log[@intCast(usize, i)] = def.LogEntry{
            .class = def.LOG_NORMAL, .msg_id = def.MSG_STRIKE,
            .a = 10 + i, .b = 0,
        };
    }

    art.resetFrame();
    const plain = renderInto(&g, "", true);
    art.resetFrame();
    const noted = renderWithNotice(&g, "Status line");
    if (plain.len != noted.len) return false;

    var x: i32 = 0;
    while (x < 640) : (x += 1) {
        if (dumpPix(plain, x, newest) != dumpPix(noted, x, newest)) return false;
    }
    return true;
}

fn tToolStatusWidth() bool {
    var g: def.GameState = undefined;
    baseFight(&g);
    var sc: render.Screen = undefined;
    render.clear(&sc);
    render.renderToolStatus(&sc, &g, 0);
    var last: usize = 0;
    var i: usize = 0;
    while (i < render.COLS) : (i += 1) {
        if (sc.cells[i] != ' ') last = i + 1;
    }
    if (last != 69) return false;
    if (last * 8 > 640) return false;

    art.resetFrame();
    const d = renderInto(&g, "", true);
    var max_x: i32 = -1;
    var y: i32 = art.HUD_Y + 16;
    while (y < art.HUD_Y + art.HUD_H) : (y += 1) {
        var x: i32 = 0;
        while (x < 640) : (x += 1) {
            if (dumpPix(d, x, y) == art.C_TEXT and x > max_x) max_x = x;
        }
    }
    return max_x >= 4 and max_x < 640;
}

fn tLayoutButtons() bool {
    if (art.HUD_Y != 0 or art.HUD_H != 32) return false;
    if (art.STAGE_Y != 32 or art.STAGE_H != 200) return false;
    if (art.LOG_Y != 232 or art.LOG_H != 140) return false;
    if (art.BUTTON_Y != 372 or art.BUTTON_H != 56) return false;
    if (art.SPRITE_X != 8 or art.SPRITE_Y != 56) return false;
    if (art.SPRITE_W != 96 or art.SPRITE_H != 96) return false;
    if (art.STATS_X != 120) return false;

    var b: i32 = 0;
    while (b < 4) : (b += 1) {
        const r = art.BUTTON_RECTS[@intCast(usize, b)];
        if (r.x != b * art.BUTTON_W or r.y != art.BUTTON_Y) return false;
        if (r.w != art.BUTTON_W or r.h != art.BUTTON_H) return false;
        if (art.hitButton(r.x + 2, r.y + 2) != b) return false;
    }
    if (art.hitButton(639, 371) != -1) return false;
    if (art.hitButton(0, 480) != -1) return false;

    var g: def.GameState = undefined;
    baseFight(&g);
    var ws: [art.MAX_WIDGETS]art.Widget = undefined;
    const n = art.layoutFight(&g, &ws);
    if (n != 18) return false;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const w = ws[@intCast(usize, i)];
        if (w.y < 0 or w.y + w.h > 480) return false;
        if (w.x < 0 or w.x + w.w > 640) return false;
    }
    return true;
}

fn tDirtyCoalesce() bool {
    var out: [32]art.Rect = undefined;
    const overlap = [2]art.Rect{
        art.Rect{ .x = 0, .y = 0, .w = 10, .h = 10 },
        art.Rect{ .x = 5, .y = 5, .w = 10, .h = 10 },
    };
    if (art.coalesceRects(overlap[0..], out[0..]) != 1) return false;
    if (out[0].w != 15 or out[0].h != 15) return false;

    const touch = [2]art.Rect{
        art.Rect{ .x = 20, .y = 0, .w = 10, .h = 10 },
        art.Rect{ .x = 30, .y = 0, .w = 10, .h = 10 },
    };
    if (art.coalesceRects(touch[0..], out[0..]) != 1) return false;
    if (out[0].x != 20 or out[0].w != 20) return false;

    const apart = [2]art.Rect{
        art.Rect{ .x = 0, .y = 0, .w = 10, .h = 10 },
        art.Rect{ .x = 20, .y = 0, .w = 10, .h = 10 },
    };
    if (art.coalesceRects(apart[0..], out[0..]) != 2) return false;
    if (out[0].x != 0 or out[1].x != 20) return false;

    var many: [33]art.Rect = undefined;
    var i: usize = 0;
    while (i < 33) : (i += 1) {
        many[i] = art.Rect{
            .x = @intCast(i32, i) * 4, .y = 0, .w = 1, .h = 1,
        };
    }
    const on = art.coalesceRects(many[0..], out[0..]);
    if (on != 1) return false;
    if (out[0].w != 640 or out[0].h != 480) return false;

    var exact: [32]art.Rect = undefined;
    i = 0;
    while (i < 32) : (i += 1) {
        exact[i] = art.Rect{
            .x = @intCast(i32, i) * 4, .y = 0, .w = 1, .h = 1,
        };
    }
    if (art.coalesceRects(exact[0..], out[0..]) != 32) return false;
    return true;
}

fn tDirtyActionArea() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    game.startFight(&g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.exp.fight_index = 0;
    g.world.phase = 1;
    g.fight.margin_pct = 10;
    g.screen = def.SCREEN_FIGHT;

    art.resetFrame();
    _ = renderInto(&g, "", true);
    game.gameStep(&g, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 });
    if (g.log_n == 0) return false;
    const d = renderInto(&g, "", false);
    _ = d;

    var rs: [art.MAX_PRESENT]art.Rect = undefined;
    const n = art.dirtyRects(rs[0..]);
    if (n <= 0 or n > art.MAX_PRESENT) return false;
    if (rs[0].w == 640 and rs[0].h == 480) return false;
    const area = art.areaOf(rs[0..@intCast(usize, n)]);
    const total = 640 * 480;
    if (area < total * 8 / 100) return false;
    if (area > total * 25 / 100) return false;
    return true;
}

fn tTweenEqualSamples() bool {
    var tw: tween.Tween = undefined;
    tween.tweenBegin(&tw, 0, 100, 1000);
    tween.tweenAdvance(&tw, 1000, 1000);
    if (tw.pos != 0 or tw.done != 0) return false;
    tween.tweenAdvance(&tw, 1000, 1000);
    if (tw.pos != 0 or tw.done != 0) return false;
    tween.tweenAdvance(&tw, 1090, 1000);
    if (tw.pos != 50 or tw.done != 0) return false;
    tween.tweenAdvance(&tw, 1180, 1000);
    if (tw.pos != 100 or tw.done != 1) return false;

    tween.tweenBegin(&tw, 5, 9, 7);
    tween.tweenAdvance(&tw, 7, 0);
    if (tw.done != 1) return false;

    tween.tweenBegin(&tw, 10, 4, 200);
    tween.tweenAdvance(&tw, 290, 1000);
    if (tw.pos != 7 or tw.done != 0) return false;
    return true;
}

fn tMsgLineParity() bool {
    const ids = [26]i32{
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
        13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 37,
    };
    var d = creatures.defAt(0);
    var i: usize = 0;
    while (i < ids.len) : (i += 1) {
        const e = def.LogEntry{
            .class = def.LOG_NORMAL, .msg_id = ids[i], .a = 7, .b = 3,
        };
        var a_buf: [128]u8 = undefined;
        var b_buf: [128]u8 = undefined;
        const a = art.logLine(e, &d, a_buf[0..]);
        const b = render.msgLine(e, &d, b_buf[0..]);
        if (!eq(a, b)) return false;
        if (a.len == 0) return false;
    }
    return true;
}

fn tModalHelpDeterministic() bool {
    var g: def.GameState = undefined;
    baseFight(&g);

    g.screen = def.SCREEN_SUBDUE;
    art.resetFrame();
    const m1 = fnv(renderInto(&g, "", true));
    art.resetFrame();
    const m2 = fnv(renderInto(&g, "", true));
    if (m1 != m2) return false;

    var sc: render.Screen = undefined;
    render.clear(&sc);
    var d = creatures.defAt(g.fight.def_index);
    render.renderModal(&sc, &g, &d);
    var found: bool = false;
    var i: usize = 0;
    while (i < render.CELLS) : (i += 1) {
        if (sc.cells[i] == 'S') found = true;
    }
    if (!found) return false;

    g.screen = def.SCREEN_FIGHT;
    art.resetFrame();
    const fight_cs = fnv(renderInto(&g, "", true));
    art.resetFrame();
    const h1 = fnv(renderInto(&g, "Manual page two text.", true));
    art.resetFrame();
    const h2 = fnv(renderInto(&g, "Manual page two text.", true));
    if (h1 != h2) return false;
    if (h1 == fight_cs) return false;
    return m1 != fight_cs;
}

fn parseHex(text: []const u8) u32 {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '0' and i + 1 < text.len and (text[i + 1] == 'x' or text[i + 1] == 'X')) {
            i += 2;
            break;
        }
        if ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')) break;
    }
    var v: u32 = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        var d: u32 = 0;
        if (c >= '0' and c <= '9') {
            d = @intCast(u32, c - '0');
        } else if (c >= 'a' and c <= 'f') {
            d = @intCast(u32, c - 'a') + 10;
        } else if (c >= 'A' and c <= 'F') {
            d = @intCast(u32, c - 'A') + 10;
        } else {
            break;
        }
        v = v * 16 + d;
    }
    return v;
}

fn spriteHash(sprite: *const core.Sprite) u32 {
    const total: usize = @intCast(usize, sprite.w) * @intCast(usize, sprite.h);
    return fnv(sprite.idx[0..total]);
}

fn tAssetsDecode() bool {
    const a = assets.current() orelse return false;
    if (assets.spriteForDef(a, 1) == null) return false;
    if (assets.spriteForDef(a, 17) == null) return false;
    if (assets.spriteForDef(a, 2) == null) return false;
    if (assets.spriteForDef(a, 19) == null) return false;
    const base = assets.spriteForDef(a, 1) orelse return false;
    const recolor = assets.spriteForDef(a, 2) orelse return false;
    return base.lut != recolor.lut;
}

fn tBackgroundResidency() bool {
    if (!assets.load(ASSETS_DIR)) return false;
    if (assets.backgroundLoaded()) return false;

    const s0 = assets.ensureBackgroundZone(0) orelse return false;
    if (!assets.backgroundLoaded()) return false;
    const buf = s0.idx;
    const h0 = spriteHash(s0);
    if (spriteHash(assets.ensureBackgroundZone(99) orelse return false) != h0) {
        return false;
    }

    const s1 = assets.ensureBackgroundZone(1) orelse return false;
    if (s1.idx != buf) return false;
    const h1 = spriteHash(s1);
    if (h1 == h0) return false;

    const s2 = assets.ensureBackgroundZone(2) orelse return false;
    if (s2.idx != buf) return false;
    const h2 = spriteHash(s2);
    if (h2 == h0 or h2 == h1) return false;

    const s8 = assets.ensureBackgroundZone(8) orelse return false;
    if (s8.idx != buf) return false;
    const h8 = spriteHash(s8);
    if (h8 == h0 or h8 == h1 or h8 == h2) return false;

    const s0b = assets.ensureBackgroundZone(0) orelse return false;
    return s0b.idx == buf and spriteHash(s0b) == h0;
}

fn ensureMalDir(path: []const u8) void {
    var b: [512]u8 = undefined;
    if (path.len + 1 > b.len) return;
    var i: usize = 0;
    while (i < path.len) : (i += 1) b[i] = path[i];
    b[path.len] = 0;
    _ = mkdir(@ptrCast([*]const u8, &b[0]), 493);
}

fn copyZspTree(src_dir: []const u8, dst_dir: []const u8) bool {
    var dir_arena = arena_mod.init(copy_dir_arena_buf[0..]);
    var file_arena = arena_mod.init(copy_file_arena_buf[0..]);
    var d = file_mod.openDir(&dir_arena, src_dir) catch return false;
    defer file_mod.closeDir(&d);
    while (true) {
        const ent = (file_mod.readDir(&dir_arena, &d) catch return false) orelse break;
        if (ent.is_dir) continue;
        if (ent.name.len < 5 or !eq(ent.name[ent.name.len - 4 ..], ".zsp")) continue;

        var src_path_buf: [512]u8 = undefined;
        const src_path = paths.join(src_dir, ent.name, src_path_buf[0..]) orelse return false;
        arena_mod.reset(&file_arena);
        const data = file_mod.readAll(&file_arena, src_path) catch return false;

        var dst_path_buf: [512]u8 = undefined;
        const dst_path = paths.join(dst_dir, ent.name, dst_path_buf[0..]) orelse return false;
        file_mod.writeAll(dst_path, data) catch return false;
    }
    return true;
}

// Write assets.man to `dst_dir`; when `needle` is non-empty, replace that
// exact-length line/field sequence with `repl` (used to corrupt one V row).
fn writeManifestVariant(dst_dir: []const u8, needle: []const u8, repl: []const u8) bool {
    var man_arena = arena_mod.init(copy_file_arena_buf[0..]);
    const src = file_mod.readAll(&man_arena, "examples/z98/undersanded/assets/assets.man") catch return false;
    if (src.len > copy_man_buf.len) return false;

    var i: usize = 0;
    while (i < src.len) : (i += 1) copy_man_buf[i] = src[i];
    if (needle.len > 0) {
        if (needle.len != repl.len) return false;
        var found = false;
        i = 0;
        while (i + needle.len <= src.len) : (i += 1) {
            var j: usize = 0;
            while (j < needle.len and copy_man_buf[i + j] == needle[j]) : (j += 1) {}
            if (j == needle.len) {
                j = 0;
                while (j < repl.len) : (j += 1) copy_man_buf[i + j] = repl[j];
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    var path_buf: [512]u8 = undefined;
    const path = paths.join(dst_dir, "assets.man", path_buf[0..]) orelse return false;
    file_mod.writeAll(path, copy_man_buf[0..src.len]) catch return false;
    return true;
}

fn tMalformedVManifestFallsBack() bool {
    ensureMalDir(MAL_DIR);
    ensureMalDir(MAL_OUT);

    var out_buf: [512]u8 = undefined;
    const src_out = paths.join(ASSETS_DIR, "out", out_buf[0..]) orelse return false;
    if (!copyZspTree(src_out, MAL_OUT)) return false;

    if (!writeManifestVariant(MAL_DIR, "", "")) return false;
    if (!assets.load(MAL_DIR) or !assets.available()) return false;

    // V base must be a decoded creature A row, not a lazily loaded background.
    // from_ramp 0 matches the background base's un-decoded runtime ramp slot,
    // so only the isCreatureA guard can reject this row.
    if (!writeManifestVariant(MAL_DIR, "V id2 eel00 6 1", "V id2 bg_a  0 5")) return false;
    if (assets.load(MAL_DIR)) return false;
    if (assets.available()) return false;

    // from_ramp must match the decoded creature base .ZSP header ramp.
    if (!writeManifestVariant(MAL_DIR, "V id2 eel00 6 1", "V id2 eel00 5 1")) return false;
    if (assets.load(MAL_DIR)) return false;
    if (assets.available()) return false;

    return assets.load(ASSETS_DIR);
}

fn tAssetsMissingFallback() bool {
    if (assets.load("examples/z98/undersanded/tests/fixtures/no_such_assets")) {
        return false;
    }
    if (assets.available()) return false;

    var g: def.GameState = undefined;
    goldenFight(&g);
    const none = art.emptyAssets();
    art.resetFrame();
    const h1 = fnv(renderIntoView(&g, "", true, none));
    art.resetFrame();
    const h2 = fnv(renderIntoView(&g, "", true, none));
    if (h1 != h2) return false;

    if (!assets.load(ASSETS_DIR)) return false;
    art.resetFrame();
    const real = fnv(renderInto(&g, "", true));
    return real != h1;
}

fn tScoreCreditsArtDeterministic() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.screen = def.NAV_SCORE;
    g.world.boss_variants_seen = 0x15;
    g.world.boss_kills = 1;
    g.world.score_subdued = 2;
    g.world.score_killed = 3;
    g.world.score_overkilled = 1;
    g.world.score_money_earned = 55;
    g.world.field_record_written = 1;
    g.world.last_run.outcome = def.OUT_KILL;

    art.resetFrame();
    const score1 = fnv(renderInto(&g, "", true));
    art.resetFrame();
    const score2 = fnv(renderInto(&g, "", true));
    if (score1 != score2) return false;

    g.screen = def.NAV_CREDITS;
    art.resetFrame();
    const credits1 = fnv(renderInto(&g, "", true));
    art.resetFrame();
    const credits2 = fnv(renderInto(&g, "", true));
    if (credits1 != credits2) return false;
    return score1 != credits1;
}

fn tGolden() bool {
    var g: def.GameState = undefined;
    goldenFight(&g);
    art.resetFrame();
    const d = renderInto(&g, "", true);
    if (d.len != 640 * 480 * 2) return false;
    const got = fnv(d);
    arena = arena_mod.init(arena_buf[0..]);
    const raw = file_mod.readAll(&arena, GOLDEN_PATH) catch return false;
    const want = parseHex(raw);
    return got == want;
}

pub fn main() void {
    _ = assets.load(ASSETS_DIR);
    report("font_glyph_blit_pitch_pad", tFontGlyphBlit());
    report("bar_geometry_zero_half_max", tBarGeometry());
    report("bar_dotted_border_numeric", tBarBorderAndNumeric());
    report("bar_red_zone_dotted_border", tBarRedZoneBorder());
    report("shake_on_subdue_fail", tShakeOnSubdueFail());
    report("speed_hidden_journal_sonar", tSpeedReveal());
    report("stats_condition_visible", tStatsCondition());
    report("stats_phase_visible", tStatsPhase());
    report("notice_keeps_newest_log_line", tNoticeKeepsNewestLog());
    report("tool_status_69_cols_80_safe", tToolStatusWidth());
    report("layout_bands_buttons", tLayoutButtons());
    report("dirty_coalesce_order_overflow", tDirtyCoalesce());
    report("dirty_action_area_bounds", tDirtyActionArea());
    report("tween_equal_samples", tTweenEqualSamples());
    report("msg_line_parity_all_ids", tMsgLineParity());
    report("modal_help_deterministic", tModalHelpDeterministic());
    report("assets_manifest_decode_26a_12v", tAssetsDecode());
    report("background_one_resident_slot", tBackgroundResidency());
    report("assets_missing_fallback_deterministic", tAssetsMissingFallback());
    report("assets_malformed_v_manifest_falls_back", tMalformedVManifestFallsBack());
    report("score_credits_art_deterministic", tScoreCreditsArtDeterministic());
    report("golden_art_fight_640x480", tGolden());

    if (fails != 0) os.exit(1);
    io.write("art_test PASS\n");
}
