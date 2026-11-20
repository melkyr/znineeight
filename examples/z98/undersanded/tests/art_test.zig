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
const tween = @import("../tween.zig");
const font = @import("../font8x16.zig");
const core = @import("std_gfx_px_core.zig");

const GOLDEN_PATH = "examples/z98/undersanded/tests/fixtures/art_fight.golden";

var fails: usize = 0;
var arena_buf: [64 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;

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

fn renderInto(g: *def.GameState, help_text: []const u8, full: bool) []const u8 {
    const handle = core.gfxPxOpenMemory(640, 480) catch return empty_px[0..0];
    var sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, g, help_text, full);
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
    const ids = [23]i32{
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
        13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
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
    report("font_glyph_blit_pitch_pad", tFontGlyphBlit());
    report("bar_geometry_zero_half_max", tBarGeometry());
    report("bar_dotted_border_numeric", tBarBorderAndNumeric());
    report("speed_hidden_journal_sonar", tSpeedReveal());
    report("tool_status_69_cols_80_safe", tToolStatusWidth());
    report("layout_bands_buttons", tLayoutButtons());
    report("dirty_coalesce_order_overflow", tDirtyCoalesce());
    report("dirty_action_area_bounds", tDirtyActionArea());
    report("tween_equal_samples", tTweenEqualSamples());
    report("msg_line_parity_all_ids", tMsgLineParity());
    report("modal_help_deterministic", tModalHelpDeterministic());
    report("golden_art_fight_640x480", tGolden());

    if (fails != 0) os.exit(1);
    io.write("art_test PASS\n");
}
