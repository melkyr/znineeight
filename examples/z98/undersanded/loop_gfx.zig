// loop_gfx.zig — UNDERSANDED M9 playable window loop (Windows-only, spec §26/§27/§28).
//
// One std_gfx cell window for the whole session. Dock/map/node/journal/help are
// cell-rendered through nav.drawScreen; while a fight (or its subdue modal) is
// live the same window presents the 640x480 px art frame. M10 supplies decoded
// creature sprites and one resident zone background from assets.zig; a missing
// or malformed installed asset set falls back to the M9 placeholder deterministically.
// All game decisions still flow through nav.navStep / nav.bootKey, so keys, the
// help overlay, the dock save/quit prompt and the boot machine are byte-identical
// to the console loops. Rendering never initialises RNG or advances a phase.

const gfx = @import("std_gfx.zig");
const px = @import("std_gfx_px.zig");
const time = @import("std_time.zig");
const def = @import("def.zig");
const nav = @import("nav.zig");
const input = @import("input.zig");
const render = @import("render_term.zig");
const art = @import("render_art.zig");
const assets = @import("assets.zig");
const creatures = @import("creatures_t1.zig");
const journal = @import("journal.zig");
const expedition = @import("expedition.zig");
const fight = @import("fight.zig");
const paths = @import("paths.zig");
const perf = @import("perf.zig");

const IDLE_WAIT_MS: u32 = 250;

var g_perf: perf.Perf = undefined;
var g_perf_buf: [256]u8 = undefined;
var g_win: ?*gfx.Gfx = null;

pub fn perfReset() void {
    perf.reset(&g_perf);
}

pub fn perfLine() []const u8 {
    return perf.format(&g_perf, g_perf_buf[0..]);
}

// gfx key event -> the same input.Key the stdin loops see: printable ASCII,
// Esc = 27, Enter = 13. Other keys are ignored (no game action).
pub fn keyFromEvent(ev: *gfx.Event) ?input.Key {
    if (ev.kind != .key_down) return null;
    if (ev.ch == input.KEY_ESC or ev.code == input.VK_ESC) {
        return input.Key{ .ch = input.KEY_ESC, .code = ev.code };
    }
    if (ev.ch == 13 or ev.ch == 10 or ev.code == 13) {
        return input.Key{ .ch = 13, .code = ev.code };
    }
    if (ev.ch >= 32 and ev.ch <= 126) {
        return input.Key{ .ch = ev.ch, .code = ev.code };
    }
    return null;
}

// Draw one 80x30 cell Screen into the cell window (bg 0, fg 15).
pub fn blitScreen(g: *gfx.Gfx, sc: *render.Screen) void {
    _ = gfx.gfxBeginFrame(g);
    gfx.gfxClear(g, 0);
    var row: [render.COLS]u8 = undefined;
    var y: usize = 0;
    while (y < render.ROWS) : (y += 1) {
        var x: usize = 0;
        while (x < render.COLS) : (x += 1) {
            row[x] = sc.cells[y * render.COLS + x];
        }
        gfx.gfxDrawText(g, 0, @intCast(u32, y), row[0..], 15, 0);
    }
    _ = gfx.gfxEndFrame(g);
}

// Replace cell row 29 with one status/confirmation line (80-column clip).
fn setRow29(sc: *render.Screen, text: []const u8) void {
    const y: usize = render.ROWS - 1;
    var x: usize = 0;
    while (x < render.COLS) : (x += 1) {
        sc.cells[y * render.COLS + x] = ' ';
    }
    x = 0;
    while (x < render.COLS and x < text.len) : (x += 1) {
        sc.cells[y * render.COLS + x] = text[x];
    }
}

fn copyInto(dst: []u8, src: []const u8) usize {
    var i: usize = 0;
    while (i < src.len and i < dst.len) : (i += 1) dst[i] = src[i];
    return i;
}

fn copyNotice(dst: []u8, src: []const u8) usize {
    return copyInto(dst, src);
}

fn sampleFrame(perf_on: bool, t0: u64, freq: u64) void {
    if (!perf_on) return;
    const t1 = time.highRes();
    perf.addTicks(&g_perf, t1 - t0, freq);
}

// Wait for one usable key/close. Close returns null. Mouse clicks in the live
// art fight hit-test the exported button rects and synthesize S/R/E/F. This
// loop owns no tween; a future tween would poll at 16 ms instead of the idle
// 250 ms.
fn readWindowKey(g: *gfx.Gfx, fight_art: bool) ?input.Key {
    while (true) {
        if (!gfx.gfxWaitEvent(g, IDLE_WAIT_MS)) continue;
        var ev: gfx.Event = undefined;
        if (!gfx.gfxPollEvent(g, &ev)) continue;
        if (ev.kind == .close) return null;
        if (ev.kind == .key_down) {
            if (keyFromEvent(&ev)) |k| return k;
            continue;
        }
        if (ev.kind == .mouse_down and fight_art) {
            const idx = art.hitButton(@intCast(i32, ev.px), @intCast(i32, ev.py));
            if (idx == 0) return input.Key{ .ch = 's', .code = 0 };
            if (idx == 1) return input.Key{ .ch = 'r', .code = 0 };
            if (idx == 2) return input.Key{ .ch = 'e', .code = 0 };
            if (idx == 3) return input.Key{ .ch = 'f', .code = 0 };
            continue;
        }
        // resize/focus and non-left mouse are ignored (M12 owns windowing).
    }
    return null;
}

fn artMode(g: *def.GameState, p: ?*px.Gfx) bool {
    if (p == null) return false;
    if (expedition.isInFight(g)) return true;
    if (g.screen == def.NAV_SUBDUE_INTRO) return true;
    if (g.screen == def.SCREEN_SUBDUE or g.screen == def.SCREEN_SUBDUE_POST) return true;
    if (g.screen == def.NAV_SCORE or g.screen == def.NAV_CREDITS) return true;
    return false;
}

// Decoded art pointers for the current screen. A failed/missing asset load
// leaves them null, so render_art uses its deterministic placeholder.
fn artView(g: *def.GameState) art.ArtAssets {
    var view = art.emptyAssets();
    const a = assets.current() orelse return view;
    view.bg = assets.ensureBackgroundZone(g.exp.zone);
    if (g.fight.def_index >= 0 and g.fight.def_index < creatures.defCount()) {
        const d = creatures.defAt(g.fight.def_index);
        if ((d.flags & def.F_BOSS) != 0) {
            view.sprite = assets.bossSpriteForPhase(
                a, g.fight.boss_variant, g.fight.boss_phase);
        } else {
            view.sprite = assets.spriteForDef(a, d.id);
        }
    }

    view.boat = assets.boatSprite(a);
    view.paints = assets.boatPaints(a);
    view.overlays = assets.overlays(a);
    return view;
}

fn drawArtFrame(g: *def.GameState, p: *px.Gfx, st: *const nav.NavState,
    notice: []const u8) bool {
    const sf = px.gfxPxLock(p) catch return false;

    var help_text: []const u8 = "";
    if (st.help_page != nav.HELP_PAGE_NONE) {
        help_text = journal.helpPage(g.screen) orelse "(manual text unavailable)";
    }
    art.shakeUpdate(g, time.highRes(), time.highResFreq());
    art.renderScreen(&sf, g, help_text, true, artView(g));

    art.drawNotice(&sf, g, notice);

    px.gfxPxUnlock(p);
    px.gfxPxPresent(p, 0, 0, 640, 480);
    return true;
}

// Presentation step for one rendered frame. Returns the (possibly disabled) px
// handle: a failed lock+restore falls back to cell mode for the rest of the
// session.
fn drawScene(win: *gfx.Gfx, g: *def.GameState, p_in: ?*px.Gfx,
    st: *const nav.NavState, notice: []const u8, perf_on: bool) ?*px.Gfx {
    var p_opt = p_in;
    const freq = time.highResFreq();
    var t0: u64 = 0;
    if (perf_on) t0 = time.highRes();

    if (p_opt) |p| {
        if (artMode(g, p_opt)) {
            if (drawArtFrame(g, p, st, notice)) {
                sampleFrame(perf_on, t0, freq);
                return p_opt;
            }
            if (!px.gfxPxRestore(p)) p_opt = null;
        }
    }

    var sc: render.Screen = undefined;
    nav.drawScreen(g, st, &sc);
    if (notice.len > 0) setRow29(&sc, notice);
    blitScreen(win, &sc);
    sampleFrame(perf_on, t0, freq);
    return p_opt;
}

// Boot driver over the shared pure machine. Returns true when the dock is
// reached; false on quit/close (app then skips navRunGfx).
pub fn bootGfx(win: *gfx.Gfx, gs: *def.GameState, dir: []const u8,
    perf_on: bool) bool {
    g_win = win;
    var screen = nav.bootReset(gs, dir);
    var st = nav.initState();
    var sc: render.Screen = undefined;
    var msg: [256]u8 = undefined;
    var msg_len: usize = 0;
    const freq = time.highResFreq();

    while (true) {
        gs.screen = screen;
        nav.bootDraw(gs, &st, screen, &sc);
        if (msg_len > 0) setRow29(&sc, msg[0..msg_len]);

        var t0: u64 = 0;
        if (perf_on) t0 = time.highRes();
        blitScreen(win, &sc);
        sampleFrame(perf_on, t0, freq);
        msg_len = 0;

        const key = readWindowKey(win, false) orelse return false;
        const out = nav.bootKey(gs, &st, dir, screen, key, msg[0..]);
        msg_len = out.msg_len;
        screen = out.screen;
        if (out.done) return true;
        if (out.quit) return false;
    }
    return false;
}

// Playable navigation loop with cell screens and the art fight.
pub fn navRunGfx(g: *def.GameState, px0: ?*px.Gfx, perf_on: bool) void {
    const win = g_win orelse return;
    if (!nav.screenAllowed(g.screen)) {
        g.screen = def.NAV_DOCK;
    }

    var p_opt = px0;
    var dir_buf: [4096]u8 = undefined;
    const dir = paths.dataDirOrFallback(dir_buf[0..]);
    var st = nav.initState();
    var notice_buf: [256]u8 = undefined;
    var line_buf: [256]u8 = undefined;
    var notice_len: usize = 0;
    var quit_armed = false;
    var quit_key = input.Key{ .ch = 0, .code = 0 };

    while (true) {
        p_opt = drawScene(win, g, p_opt, &st, notice_buf[0..notice_len], perf_on);
        notice_len = 0;

        const fight_art = g.screen == def.SCREEN_FIGHT;
        const raw_key = readWindowKey(win, fight_art) orelse return;
        var key: input.Key = undefined;
        const filtered = input.filterKey(raw_key);
        if (filtered) |k| {
            key = k;
        } else {
            continue;
        }

        if (quit_armed) {
            quit_armed = false;
            const it = nav.navIntercept(g, &st, dir, quit_key, key);
            if (it.msg.len > 0) notice_len = copyNotice(notice_buf[0..], it.msg);
            if (it.quit) return;
            continue;
        }

        if (nav.navQuitKey(g, &st, key)) {
            quit_armed = true;
            quit_key = key;
            const probe = nav.navIntercept(g, &st, dir, key, null);
            notice_len = copyNotice(notice_buf[0..], probe.msg);
            continue;
        }

        const it = nav.navIntercept(g, &st, dir, key, null);
        if (it.handled) {
            if (it.msg.len > 0) notice_len = copyNotice(notice_buf[0..], it.msg);
            if (it.quit) return;
            continue;
        }

        const next = nav.navStep(g, &st, key);
        if (next == def.NAV_QUIT) return;
        const tip = nav.navTipLine(&st);
        if (tip.len > 0) {
            notice_len = copyNotice(notice_buf[0..], tip);
        } else {
            const line = nav.navResultLine(g, &st, line_buf[0..]);
            if (line.len > 0) notice_len = copyNotice(notice_buf[0..], line);
        }
    }
}
