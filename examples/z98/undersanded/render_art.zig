// render_art.zig — UNDERSANDED fixed 640x480 art fight renderer (spec §27).
//
// Pure software rendering: draws into a core px Surface and never imports
// std_gfx/std_gfx_pal/std_gfx_px (the Windows wrapper owns lock/present in
// Task 5). Widgets are the §27 flat retained shape; layoutFight rebuilds them
// per screen and renderScreen repaints dirty rects or the whole frame.
//
// Terminal copy is shared, not duplicated: msgLine, renderModal,
// renderToolStatus and speedRevealed are exported from render_term and used
// here for the log, subdue modal, HUD tool line and hidden-Speed reveal.

const def = @import("def.zig");
const fight = @import("fight.zig");
const creatures = @import("creatures_t1.zig");
const render = @import("render_term.zig");
const render_text = @import("render_text.zig");
const font = @import("font8x16.zig");
const px = @import("std_gfx_px_core.zig");

pub const GLYPH_W: i32 = 8;
pub const GLYPH_H: i32 = 16;
pub const LINE_H: i32 = 16;

pub const HUD_Y: i32 = 0;
pub const HUD_H: i32 = 32;
pub const STAGE_Y: i32 = 32;
pub const STAGE_H: i32 = 200;
pub const LOG_Y: i32 = 232;
pub const LOG_H: i32 = 140;
pub const LOG_LINES: i32 = 8;
pub const BUTTON_Y: i32 = 372;
pub const BUTTON_H: i32 = 56;
pub const BUTTON_W: i32 = 160;

pub const SPRITE_X: i32 = 8;
pub const SPRITE_Y: i32 = 56;
pub const SPRITE_W: i32 = 96;
pub const SPRITE_H: i32 = 96;
pub const STATS_X: i32 = 120;

pub const BAR_H: i32 = 24;

pub const MAX_WIDGETS: usize = 64;
pub const MAX_PRESENT: usize = 32;

pub const W_HUD: i32 = 1;
pub const W_SPRITE: i32 = 2;
pub const W_STATS: i32 = 3;
pub const W_HP: i32 = 4;
pub const W_RES: i32 = 5;
pub const W_HULL: i32 = 6;
pub const W_LOG: i32 = 10;
pub const W_BUTTON: i32 = 20;

pub const C_BG: u16 = 0x0861;
pub const C_PANEL: u16 = 0x10A2;
pub const C_PANEL2: u16 = 0x18E3;
pub const C_LOG: u16 = 0x0841;
pub const C_TRACK: u16 = 0x2104;
pub const C_TEXT: u16 = 0xFFFF;
pub const C_TITLE: u16 = 0xFD20;
pub const C_DIM: u16 = 0x8410;
pub const C_BORDER: u16 = 0x7BEF;
pub const C_DOT: u16 = 0x4208;
pub const C_RED: u16 = 0xF800;
pub const C_HP: u16 = 0x07E0;
pub const C_RES: u16 = 0x03FF;
pub const C_HULL: u16 = 0xFFE0;
pub const C_TAG: u16 = 0xF81F;

pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

pub const Widget = struct {
    x: i32, y: i32, w: i32, h: i32,
    kind: i32, dirty: i32,
    a: i32, b: i32, c: i32,
    text_off: i32, sprite: i32,
};

pub const BUTTON_RECTS = [4]Rect{
    Rect{ .x = 0, .y = BUTTON_Y, .w = BUTTON_W, .h = BUTTON_H },
    Rect{ .x = 160, .y = BUTTON_Y, .w = BUTTON_W, .h = BUTTON_H },
    Rect{ .x = 320, .y = BUTTON_Y, .w = BUTTON_W, .h = BUTTON_H },
    Rect{ .x = 480, .y = BUTTON_Y, .w = BUTTON_W, .h = BUTTON_H },
};

const BUTTON_LABELS = [4][]const u8{
    "[S] Strike",
    "[R] Restrain",
    "[E] Equipment",
    "[F] Flee",
};

var g_prev: [MAX_WIDGETS]Widget = undefined;
var g_prev_n: i32 = 0;
var g_have: bool = false;
var g_screen: i32 = -2;
var g_def: i32 = -2;
var g_help: bool = false;
var g_dirty: [MAX_PRESENT]Rect = undefined;
var g_dirty_n: i32 = 0;

pub fn resetFrame() void {
    g_have = false;
    g_prev_n = 0;
    g_screen = -2;
    g_def = -2;
    g_help = false;
    g_dirty_n = 0;
}

pub fn dirtyRects(out: []Rect) i32 {
    var i: i32 = 0;
    while (i < g_dirty_n and i < @intCast(i32, out.len)) : (i += 1) {
        out[@intCast(usize, i)] = g_dirty[i];
    }
    return g_dirty_n;
}

fn catText(out: []u8, start: usize, text: []const u8) usize {
    var p = start;
    var i: usize = 0;
    while (i < text.len and p < out.len) : (i += 1) {
        out[p] = text[i];
        p += 1;
    }
    return p;
}

fn catInt(out: []u8, start: usize, value: i32) usize {
    var p = start;
    var v = value;
    var neg = false;
    if (v < 0) {
        neg = true;
        v = 0 - v;
    }
    var tmp: [12]u8 = undefined;
    var n: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v > 0 and n < tmp.len) {
            tmp[n] = '0' + @intCast(u8, v % 10);
            n += 1;
            v = v / 10;
        }
    }
    if (neg and p < out.len) {
        out[p] = '-';
        p += 1;
    }
    while (n > 0 and p < out.len) {
        n -= 1;
        out[p] = tmp[n];
        p += 1;
    }
    return p;
}

pub fn drawText(sf: *px.Surface, x: i32, y: i32, text: []const u8,
    fg: u16, bg: u16) void {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const bits = font.glyph(text[i]);
        px.pxCoreBlit1bpp(sf, x + @intCast(i32, i) * GLYPH_W, y, bits,
            GLYPH_W, GLYPH_H, fg, bg);
    }
}

pub fn drawDottedRect(sf: *px.Surface, x: i32, y: i32, w: i32, h: i32,
    color: u16) void {
    if (w <= 0 or h <= 0) return;
    var i: i32 = 0;
    while (i < w) : (i += 2) {
        px.pxCoreFill(sf, x + i, y, 1, 1, color);
        px.pxCoreFill(sf, x + i, y + h - 1, 1, 1, color);
    }
    var j: i32 = 0;
    while (j < h) : (j += 2) {
        px.pxCoreFill(sf, x, y + j, 1, 1, color);
        px.pxCoreFill(sf, x + w - 1, y + j, 1, 1, color);
    }
}

pub fn barGeometry(width: i32, value: i32, max: i32, margin: i32) px.Bar {
    if (max <= 0) return px.Bar{ .fill = 0, .red = 0 };
    return px.pxCoreBar(width, value, max, margin);
}

fn phaseName(p: i32) []const u8 {
    if (p == 1) return "night";
    return "day";
}

fn toolSig(s: *const def.GameState) i32 {
    return s.fight.tool + s.fight.tool_charge * 16
        + s.fight.tool_broken * 4096 + s.fight.tool_active * 8192;
}

fn couplingGate(s: *const def.GameState) i32 {
    if (fight.belowPct(s.fight.res, s.fight.max_res, fight.THRASH_GATE_PCT)
        and fight.abovePct(s.fight.hp, s.fight.max_hp, fight.THRASH_GATE_PCT)) {
        return 1;
    }
    if (fight.belowPct(s.fight.hp, s.fight.max_hp, fight.DESPAIR_GATE_PCT)
        and fight.abovePct(s.fight.res, s.fight.max_res,
            fight.DESPAIR_RES_GATE_PCT)) {
        return 2;
    }
    return 0;
}

fn defValid(s: *const def.GameState) bool {
    return s.fight.def_index >= 0
        and s.fight.def_index < creatures.defCount();
}

fn makeWidget(x: i32, y: i32, w: i32, h: i32, kind: i32,
    a: i32, b: i32, c: i32, text_off: i32, sprite: i32) Widget {
    return Widget{
        .x = x, .y = y, .w = w, .h = h,
        .kind = kind, .dirty = 0,
        .a = a, .b = b, .c = c,
        .text_off = text_off, .sprite = sprite,
    };
}

fn logFirst(s: *const def.GameState) i32 {
    if (s.log_n > LOG_LINES) return s.log_n - LOG_LINES;
    return 0;
}

fn logEntry(s: *const def.GameState, slot: i32) def.LogEntry {
    const idx = logFirst(s) + slot;
    if (idx < 0 or idx >= s.log_n) {
        return def.LogEntry{ .class = 0, .msg_id = 0, .a = 0, .b = 0 };
    }
    return s.log[@intCast(usize, idx)];
}

pub fn layoutFight(s: *const def.GameState, out: *[MAX_WIDGETS]Widget) i32 {
    var n: i32 = 0;

    out[@intCast(usize, n)] = makeWidget(0, HUD_Y, def.SCREEN_W, HUD_H, W_HUD,
        s.exp.zone, s.world.phase, s.exp.fight_index,
        toolSig(s), s.world.money);
    n += 1;

    out[@intCast(usize, n)] = makeWidget(0, STAGE_Y, 120, STAGE_H, W_SPRITE,
        s.fight.def_index, s.fight.phase_state, 0, 0, 0);
    n += 1;

    var spd: i32 = -1;
    var role: i32 = 0;
    var cond: i32 = 0;
    if (defValid(s)) {
        var d = creatures.defAt(s.fight.def_index);
        role = d.role;
        cond = s.fight.cond;
        if (render_text.speedRevealed(s)) spd = render.effectiveSpeed(s, &d);
    }
    out[@intCast(usize, n)] = makeWidget(STATS_X, 40, 520, 24, W_STATS,
        spd, role, s.fight.def_index, 0, cond);
    n += 1;

    const gate = couplingGate(s);
    const margin = fight.margin(s);
    out[@intCast(usize, n)] = makeWidget(STATS_X, 72, 520, 36, W_HP,
        s.fight.hp, s.fight.max_hp, margin, 0, gate);
    n += 1;
    out[@intCast(usize, n)] = makeWidget(STATS_X, 112, 520, 36, W_RES,
        s.fight.res, s.fight.max_res, margin, 0, gate);
    n += 1;
    out[@intCast(usize, n)] = makeWidget(STATS_X, 152, 520, 36, W_HULL,
        s.fight.hull, s.fight.max_hull, margin, 0, 0);
    n += 1;

    var slot: i32 = 0;
    while (slot < LOG_LINES) : (slot += 1) {
        const e = logEntry(s, slot);
        out[@intCast(usize, n)] = makeWidget(0, LOG_Y + slot * LINE_H,
            def.SCREEN_W, LINE_H, W_LOG, slot, e.msg_id, e.a, 0, e.b);
        n += 1;
    }

    var b: i32 = 0;
    while (b < 4) : (b += 1) {
        const r = BUTTON_RECTS[@intCast(usize, b)];
        out[@intCast(usize, n)] = makeWidget(r.x, r.y, r.w, r.h, W_BUTTON,
            b, 0, 0, 0, 0);
        n += 1;
    }
    return n;
}

fn rectTouch(a: Rect, b: Rect) bool {
    return a.x <= b.x + b.w and b.x <= a.x + a.w
        and a.y <= b.y + b.h and b.y <= a.y + a.h;
}

fn rectMerge(a: Rect, b: Rect) Rect {
    var x0 = a.x;
    var y0 = a.y;
    var x1 = a.x + a.w;
    var y1 = a.y + a.h;
    if (b.x < x0) x0 = b.x;
    if (b.y < y0) y0 = b.y;
    if (b.x + b.w > x1) x1 = b.x + b.w;
    if (b.y + b.h > y1) y1 = b.y + b.h;
    return Rect{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

fn fullRect() Rect {
    return Rect{ .x = 0, .y = 0, .w = def.SCREEN_W, .h = def.SCREEN_H };
}

pub fn coalesceRects(rects: []const Rect, out: []Rect) i32 {
    if (out.len == 0) return 0;
    var n: i32 = 0;
    var i: usize = 0;
    while (i < rects.len) : (i += 1) {
        if (n < @intCast(i32, out.len)) {
            out[@intCast(usize, n)] = rects[i];
            n += 1;
        } else {
            var merged = false;
            var j: i32 = 0;
            while (j < n) : (j += 1) {
                if (rectTouch(rects[i], out[@intCast(usize, j)])) {
                    out[@intCast(usize, j)] =
                        rectMerge(out[@intCast(usize, j)], rects[i]);
                    merged = true;
                    break;
                }
            }
            if (!merged) {
                out[0] = fullRect();
                return 1;
            }
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        var a: i32 = 0;
        while (a < n) : (a += 1) {
            var b = a + 1;
            while (b < n) {
                if (rectTouch(out[@intCast(usize, a)],
                    out[@intCast(usize, b)])) {
                    out[@intCast(usize, a)] = rectMerge(
                        out[@intCast(usize, a)], out[@intCast(usize, b)]);
                    var k = b;
                    while (k + 1 < n) : (k += 1) {
                        out[@intCast(usize, k)] = out[@intCast(usize, k + 1)];
                    }
                    n -= 1;
                    changed = true;
                } else {
                    b += 1;
                }
            }
        }
    }
    return n;
}

pub fn areaOf(rects: []const Rect) i32 {
    var total: i32 = 0;
    var i: usize = 0;
    while (i < rects.len) : (i += 1) {
        total += rects[i].w * rects[i].h;
    }
    return total;
}

fn sameWidget(a: *const Widget, b: *const Widget) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
        and a.kind == b.kind and a.a == b.a and a.b == b.b and a.c == b.c
        and a.text_off == b.text_off and a.sprite == b.sprite;
}

fn drawScreenBlock(sf: *px.Surface, sc: *const render_text.Screen,
    panel: Rect, center: bool, fg: u16, bg: u16) void {
    var minx: i32 = 10000;
    var maxx: i32 = -1;
    var miny: i32 = 10000;
    var maxy: i32 = -1;
    var y: i32 = 0;
    while (y < @intCast(i32, render.ROWS)) : (y += 1) {
        var x: i32 = 0;
        while (x < @intCast(i32, render.COLS)) : (x += 1) {
            const c = sc.cells[@intCast(usize, y) * render.COLS
                + @intCast(usize, x)];
            if (c != ' ') {
                if (x < minx) minx = x;
                if (x > maxx) maxx = x;
                if (y < miny) miny = y;
                if (y > maxy) maxy = y;
            }
        }
    }
    if (maxx < 0) return;

    var xoff: i32 = panel.x;
    var yoff: i32 = panel.y;
    var first_col: i32 = minx;
    if (center) {
        const text_w = (maxx - minx + 1) * GLYPH_W;
        const text_h = (maxy - miny + 1) * GLYPH_H;
        xoff = panel.x + (panel.w - text_w) / 2 - minx * GLYPH_W;
        yoff = panel.y + (panel.h - text_h) / 2 - miny * GLYPH_H;
    } else {
        first_col = 0;
    }

    y = 0;
    while (y < @intCast(i32, render.ROWS)) : (y += 1) {
        var start: i32 = -1;
        var end: i32 = -1;
        var x: i32 = first_col;
        while (x < @intCast(i32, render.COLS)) : (x += 1) {
            const c = sc.cells[@intCast(usize, y) * render.COLS
                + @intCast(usize, x)];
            if (c != ' ') {
                if (start < 0) start = x;
                end = x;
            }
        }
        if (start >= 0) {
            var line: [80]u8 = undefined;
            var len: usize = 0;
            x = start;
            while (x <= end and len < line.len) : (x += 1) {
                line[len] = sc.cells[@intCast(usize, y) * render.COLS
                    + @intCast(usize, x)];
                len += 1;
            }
            drawText(sf, xoff + start * GLYPH_W, yoff + y * GLYPH_H,
                line[0..len], fg, bg);
        }
    }
}

fn drawHud(sf: *px.Surface, w: *const Widget, s: *const def.GameState) void {
    px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_PANEL);
    var buf: [128]u8 = undefined;
    var p: usize = 0;
    p = catText(buf[0..], p, "UNDERSANDED  FIGHT  ");
    p = catText(buf[0..], p, render.zoneName(s.exp.zone));
    p = catText(buf[0..], p, "  ");
    p = catText(buf[0..], p, phaseName(s.world.phase));
    p = catText(buf[0..], p, "  FIGHT ");
    p = catInt(buf[0..], p, s.exp.fight_index + 1);
    p = catText(buf[0..], p, "  COINS ");
    p = catInt(buf[0..], p, s.world.money);
    drawText(sf, w.x + 4, w.y, buf[0..p], C_TITLE, C_PANEL);

    var sc: render_text.Screen = undefined;
    render.clear(&sc);
    render.renderToolStatus(&sc, s, 0);
    drawScreenBlock(sf, &sc, Rect{ .x = 4, .y = 16, .w = 632, .h = 16 },
        false, C_TEXT, C_PANEL);
}

fn drawSprite(sf: *px.Surface, w: *const Widget, s: *const def.GameState) void {
    px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_PANEL);
    const box = Rect{
        .x = SPRITE_X, .y = SPRITE_Y, .w = SPRITE_W, .h = SPRITE_H,
    };
    px.pxCoreFill(sf, box.x, box.y, box.w, box.h, C_PANEL2);
    drawDottedRect(sf, box.x, box.y, box.w, box.h, C_DOT);

    if (!defValid(s)) return;
    var d = creatures.defAt(s.fight.def_index);
    const name = render.creatureName(&d);
    if (name.len == 0) return;
    var letter: [1]u8 = undefined;
    letter[0] = name[0];
    drawText(sf, box.x + 44, box.y + 40, letter[0..1], C_TEXT, C_PANEL2);
}

fn drawStats(sf: *px.Surface, w: *const Widget, s: *const def.GameState) void {
    px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_PANEL);
    if (!defValid(s)) return;
    var d = creatures.defAt(s.fight.def_index);
    var buf: [128]u8 = undefined;
    var p: usize = 0;
    p = catText(buf[0..], p, render.creatureName(&d));
    p = catText(buf[0..], p, "  ");
    p = catText(buf[0..], p, render.roleName(d.role));
    p = catText(buf[0..], p, "  SPD ");
    if (w.a >= 0) {
        p = catInt(buf[0..], p, w.a);
    } else {
        p = catText(buf[0..], p, "??");
    }
    drawText(sf, w.x + 4, w.y + 4, buf[0..p], C_TEXT, C_PANEL);
}

fn drawBar(sf: *px.Surface, w: *const Widget, label: []const u8,
    color: u16) void {
    px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_PANEL);
    const bw = w.w;
    const bh = BAR_H;
    px.pxCoreFill(sf, w.x, w.y, bw, bh, C_TRACK);
    const g = barGeometry(bw - 2, w.a, w.b, w.c);
    if (g.red > 0) {
        px.pxCoreFill(sf, w.x + 1 + (bw - 2) - g.red, w.y + 1,
            g.red, bh - 2, C_RED);
    }
    if (g.fill > 0) {
        px.pxCoreFill(sf, w.x + 1, w.y + 1, g.fill, bh - 2, color);
    }
    drawDottedRect(sf, w.x, w.y, bw, bh, C_DOT);

    var buf: [64]u8 = undefined;
    var p: usize = 0;
    p = catText(buf[0..], p, label);
    p = catText(buf[0..], p, " ");
    p = catInt(buf[0..], p, w.a);
    p = catText(buf[0..], p, "/");
    p = catInt(buf[0..], p, w.b);
    drawText(sf, w.x + 6, w.y + 4, buf[0..p], C_TEXT, C_TRACK);

    if (w.sprite != 0 and bw > 140) {
        var tag: []const u8 = "THRASH";
        if (w.sprite == 2) tag = "DESPAIR";
        drawText(sf, w.x + bw - @intCast(i32, tag.len) * GLYPH_W - 6,
            w.y + 4, tag, C_TAG, C_TRACK);
    }
}

fn drawLogLine(sf: *px.Surface, w: *const Widget, s: *const def.GameState) void {
    px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_LOG);
    if (!defValid(s)) return;
    const e = logEntry(s, w.a);
    if (e.msg_id == 0) return;
    var d = creatures.defAt(s.fight.def_index);
    var buf: [128]u8 = undefined;
    const line = logLine(e, &d, buf[0..]);
    drawText(sf, w.x + 4, w.y, line, C_TEXT, C_LOG);
}

pub fn logLine(e: def.LogEntry, d: *const def.CreatureDef, out: []u8) []const u8 {
    return render_text.msgLine(e, d, out);
}

fn drawButton(sf: *px.Surface, w: *const Widget, s: *const def.GameState) void {
    _ = s;
    px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_PANEL);
    px.pxCoreFill(sf, w.x + 1, w.y + 1, w.w - 2, w.h - 2, C_PANEL2);
    drawDottedRect(sf, w.x, w.y, w.w, w.h, C_BORDER);
    const idx: usize = @intCast(usize, w.a);
    var label: []const u8 = "";
    if (idx < BUTTON_LABELS.len) label = BUTTON_LABELS[idx];
    const tw = @intCast(i32, label.len) * GLYPH_W;
    const x = w.x + (w.w - tw) / 2;
    const y = w.y + (w.h - GLYPH_H) / 2;
    drawText(sf, x, y, label, C_TEXT, C_PANEL2);
}

fn drawWidget(sf: *px.Surface, w: *const Widget, s: *const def.GameState) void {
    switch (w.kind) {
        W_HUD => drawHud(sf, w, s),
        W_SPRITE => drawSprite(sf, w, s),
        W_STATS => drawStats(sf, w, s),
        W_HP => drawBar(sf, w, "HP", C_HP),
        W_RES => drawBar(sf, w, "RES", C_RES),
        W_HULL => drawBar(sf, w, "HULL", C_HULL),
        W_LOG => drawLogLine(sf, w, s),
        W_BUTTON => drawButton(sf, w, s),
        else => px.pxCoreFill(sf, w.x, w.y, w.w, w.h, C_BG),
    }
}

fn widgetRect(w: *const Widget) Rect {
    return Rect{ .x = w.x, .y = w.y, .w = w.w, .h = w.h };
}

fn drawModal(sf: *px.Surface, s: *const def.GameState) void {
    px.pxCoreFill(sf, 0, 0, def.SCREEN_W, def.SCREEN_H, C_BG);
    const panel = Rect{ .x = 80, .y = 96, .w = 480, .h = 280 };
    px.pxCoreFill(sf, panel.x, panel.y, panel.w, panel.h, C_PANEL);
    drawDottedRect(sf, panel.x, panel.y, panel.w, panel.h, C_BORDER);

    var sc: render_text.Screen = undefined;
    render.clear(&sc);
    var d: def.CreatureDef = undefined;
    if (defValid(s)) {
        d = creatures.defAt(s.fight.def_index);
    } else {
        d = creatures.defAt(0);
    }
    render_text.renderModal(&sc, s, &d);
    drawScreenBlock(sf, &sc, panel, true, C_TEXT, C_PANEL);
}

fn drawHelp(sf: *px.Surface, help_text: []const u8) void {
    px.pxCoreFill(sf, 0, 0, def.SCREEN_W, def.SCREEN_H, C_BG);
    var sc: render_text.Screen = undefined;
    render_text.renderHelp(help_text, &sc);
    drawScreenBlock(sf, &sc,
        Rect{ .x = 0, .y = 0, .w = def.SCREEN_W, .h = def.SCREEN_H },
        false, C_TEXT, C_BG);
}

fn markFull() void {
    g_dirty[0] = fullRect();
    g_dirty_n = 1;
}

pub fn renderScreen(sf: *px.Surface, s: *const def.GameState,
    help_text: []const u8, full: bool) void {
    const modal = s.screen == def.SCREEN_SUBDUE
        or s.screen == def.SCREEN_SUBDUE_POST;
    const help = help_text.len > 0;

    if (help) {
        drawHelp(sf, help_text);
        markFull();
        g_have = true;
        g_screen = s.screen;
        g_def = s.fight.def_index;
        g_help = true;
        return;
    }

    if (modal) {
        drawModal(sf, s);
        markFull();
        g_have = true;
        g_screen = s.screen;
        g_def = s.fight.def_index;
        g_help = false;
        return;
    }

    const mode_changed = !g_have or full or s.screen != g_screen
        or s.fight.def_index != g_def or g_help;

    var next: [MAX_WIDGETS]Widget = undefined;
    const n = layoutFight(s, &next);
    var rects: [MAX_WIDGETS]Rect = undefined;
    var rn: i32 = 0;

    if (mode_changed) {
        px.pxCoreFill(sf, 0, 0, def.SCREEN_W, def.SCREEN_H, C_BG);
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            drawWidget(sf, &next[@intCast(usize, i)], s);
        }
        markFull();
    } else {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const cur = &next[@intCast(usize, i)];
            if (i < g_prev_n and sameWidget(cur, &g_prev[@intCast(usize, i)])) {
                cur.dirty = 0;
            } else {
                cur.dirty = 1;
                drawWidget(sf, cur, s);
                rects[@intCast(usize, rn)] = widgetRect(cur);
                rn += 1;
            }
        }
        const count = coalesceRects(rects[0..@intCast(usize, rn)],
            g_dirty[0..]);
        g_dirty_n = count;
    }

    var i: i32 = 0;
    while (i < n) : (i += 1) {
        g_prev[@intCast(usize, i)] = next[@intCast(usize, i)];
    }
    g_prev_n = n;
    g_have = true;
    g_screen = s.screen;
    g_def = s.fight.def_index;
    g_help = false;
}

pub fn hitButton(x: i32, y: i32) i32 {
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const r = BUTTON_RECTS[@intCast(usize, i)];
        if (x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h) {
            return i;
        }
    }
    return -1;
}
