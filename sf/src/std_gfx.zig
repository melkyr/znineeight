// std_gfx.zig — Z98 std lib L2: minimal DirectDraw GUI layer.
//
// Contract (P4-M1): backend-free Color/EventKind/Event/GfxError/Gfx + the
// drawing surface: gfxOpen/gfxOpenMemory/gfxPollEvent/gfxBeginFrame/
// gfxEndFrame/gfxClear/gfxFillRect/gfxDrawText/gfxCharSize/gfxBufferSize/
// gfxDumpGrid/gfxClipboardSet/gfxClipboardGet/gfxClose. All coordinates are
// CELLS. Colors are VGA palette indices 0..15.
//
// The Win9x backend (window class/pump, DirectDraw7, GDI text, clipboard) lives
// in std_gfx_pal.zig; this module owns the cell grid (the glyph/cell cache), the
// font metrics, the ASCII sanitisation (32..126, otherwise '?'), and the
// headless gfxOpenMemory path. A memory Gfx never creates a window and its
// grid is the deterministic `--dump-grid` payload; a windowed Gfx mirrors the
// same cells while painting the real offscreen surface.
//
// Single instance by design (the v1 layer drives one window): the opaque Gfx is
// a module-global static returned by pointer, so no CRT allocator is needed.

const pal = @import("std_gfx_pal.zig");
const arena_mod = @import("std_arena.zig");

pub const Color = u8;

pub const EventKind = enum {
    key_down,
    key_up,
    mouse_move,
    mouse_down,
    mouse_up,
    wheel,
    resize,
    close,
};

pub const Event = struct {
    kind: EventKind,
    ch: u8,
    code: u16,
    x: u32,
    y: u32,
    button: u8,
    wheel: i32,
    cols: u32,
    rows: u32,
    mods: u8,
};

pub const GfxError = error{ OpenFailed, OutOfMemory, SurfaceFailed, ClipboardFailed };

const MAX_COLS: u32 = 200;
const MAX_ROWS: u32 = 100;
const MAX_CELLS: usize = 200 * 100;
const MAX_DUMP: usize = MAX_CELLS + 100 + 2;
const MEM_CW: u32 = 8;
const MEM_CH: u32 = 16;
const TEXT_CHUNK: usize = 256;

pub const Gfx = struct {
    cells: [MAX_CELLS]u8,
    dump: [MAX_DUMP]u8,
    cols: u32,
    rows: u32,
    cw: u32,
    ch: u32,
    mem_only: bool,
    st: pal.State,
};

var g_gfx: Gfx = undefined;

fn initGrid(g: *Gfx, cols: u32, rows: u32) void {
    g.cols = cols;
    g.rows = rows;
    var i: usize = 0;
    while (i < MAX_CELLS) : (i += 1) {
        g.cells[i] = 32;
    }
}

fn sanitize(b: u8) u8 {
    if (b < 32 or b > 126) return 63; // '?'
    return b;
}

pub fn gfxOpen(title: []const u8, cols: u32, rows: u32) GfxError!*Gfx {
    if (cols == 0 or rows == 0 or cols > MAX_COLS or rows > MAX_ROWS) {
        return error.OpenFailed;
    }
    const g = &g_gfx;
    initGrid(g, cols, rows);
    g.cw = MEM_CW;
    g.ch = MEM_CH;
    g.mem_only = false;
    if (!pal.open(title, cols, rows, &g.st)) {
        return error.OpenFailed;
    }
    g.cw = g.st.cw;
    g.ch = g.st.ch;
    return g;
}

pub fn gfxOpenMemory(cols: u32, rows: u32) GfxError!*Gfx {
    if (cols == 0 or rows == 0 or cols > MAX_COLS or rows > MAX_ROWS) {
        return error.OpenFailed;
    }
    const g = &g_gfx;
    initGrid(g, cols, rows);
    g.cw = MEM_CW;
    g.ch = MEM_CH;
    g.mem_only = true;
    return g;
}

fn kindFromU8(k: u8) EventKind {
    if (k == 0) return .key_down;
    if (k == 1) return .key_up;
    if (k == 2) return .mouse_move;
    if (k == 3) return .mouse_down;
    if (k == 4) return .mouse_up;
    if (k == 5) return .wheel;
    if (k == 6) return .resize;
    return .close;
}

pub fn gfxPollEvent(g: *Gfx, ev: *Event) bool {
    if (g.mem_only) return false;
    var raw: pal.RawEvent = undefined;
    if (!pal.pollEvent(&g.st, &raw)) return false;
    ev.kind = kindFromU8(raw.kind);
    ev.ch = raw.ch;
    ev.code = raw.code;
    ev.x = raw.x;
    ev.y = raw.y;
    ev.button = raw.button;
    ev.wheel = raw.wheel;
    ev.cols = raw.cols;
    ev.rows = raw.rows;
    ev.mods = raw.mods;
    return true;
}

pub fn gfxBeginFrame(g: *Gfx) bool {
    if (g.mem_only) return true;
    return pal.beginFrame(&g.st);
}

pub fn gfxEndFrame(g: *Gfx) bool {
    if (g.mem_only) return true;
    return pal.endFrame(&g.st);
}

pub fn gfxClear(g: *Gfx, bg: Color) void {
    var i: usize = 0;
    while (i < MAX_CELLS) : (i += 1) {
        g.cells[i] = 32;
    }
    if (!g.mem_only) {
        pal.fillRect(&g.st, 0, 0,
            @intCast(i32, g.cols * g.cw), @intCast(i32, g.rows * g.ch), bg, bg);
    }
}

pub fn gfxFillRect(g: *Gfx, x: u32, y: u32, w: u32, h: u32, fg: Color, bg: Color) void {
    if (x >= g.cols or y >= g.rows) return;
    var x1: u32 = x + w;
    if (x1 > g.cols) x1 = g.cols;
    var y1: u32 = y + h;
    if (y1 > g.rows) y1 = g.rows;
    if (x1 <= x or y1 <= y) return;
    var yy: u32 = y;
    while (yy < y1) : (yy += 1) {
        var xx: u32 = x;
        while (xx < x1) : (xx += 1) {
            g.cells[@intCast(usize, yy * g.cols + xx)] = 32;
        }
    }
    if (!g.mem_only) {
        pal.fillRect(&g.st,
            @intCast(i32, x * g.cw), @intCast(i32, y * g.ch),
            @intCast(i32, (x1 - x) * g.cw), @intCast(i32, (y1 - y) * g.ch),
            fg, bg);
    }
}

pub fn gfxDrawText(g: *Gfx, x: u32, y: u32, s: []const u8, fg: Color, bg: Color) void {
    if (y >= g.rows or x >= g.cols) return;
    var maxn: usize = s.len;
    const room: usize = @intCast(usize, g.cols - x);
    if (maxn > room) maxn = room;
    var i: usize = 0;
    while (i < maxn) : (i += 1) {
        g.cells[@intCast(usize, y * g.cols + x + @intCast(u32, i))] = sanitize(s[i]);
    }
    if (g.mem_only) return;
    var off: usize = 0;
    var buf: [TEXT_CHUNK]u8 = undefined;
    while (off < maxn) {
        var n: usize = maxn - off;
        if (n > TEXT_CHUNK) n = TEXT_CHUNK;
        var j: usize = 0;
        while (j < n) : (j += 1) buf[j] = sanitize(s[off + j]);
        pal.drawText(&g.st,
            @intCast(i32, (x + @intCast(u32, off)) * g.cw), @intCast(i32, y * g.ch),
            buf[0..n], fg, bg, g.cw, g.ch);
        off += n;
    }
}

// Per-cell pixel size (fixed font metrics on a window, 8x16 in memory mode).
pub fn gfxCharSize(g: *Gfx, w: *u32, h: *u32) void {
    w.* = g.cw;
    h.* = g.ch;
}

// Pixel size of the cols x rows cell area.
pub fn gfxBufferSize(g: *Gfx, w: *u32, h: *u32) void {
    w.* = g.cols * g.cw;
    h.* = g.rows * g.ch;
}

// Row-major ASCII snapshot: one line per row, '\n' after each row (including
// the last). Trailing padding spaces are trimmed so the golden has no trailing
// whitespace; leading spaces keep cell columns. Non-printable drawn bytes are
// already '?'.
pub fn gfxDumpGrid(g: *Gfx) []u8 {
    var p: usize = 0;
    var y: u32 = 0;
    while (y < g.rows) : (y += 1) {
        const row_start = p;
        var x: u32 = 0;
        while (x < g.cols) : (x += 1) {
            g.dump[p] = g.cells[@intCast(usize, y * g.cols + x)];
            p += 1;
        }
        while (p > row_start and g.dump[p - 1] == 32) {
            p -= 1;
        }
        g.dump[p] = 10;
        p += 1;
    }
    return g.dump[0..p];
}

pub fn gfxClipboardSet(g: *Gfx, s: []const u8) bool {
    if (g.mem_only) return false;
    return pal.clipboardSet(&g.st, s);
}

pub fn gfxClipboardGet(g: *Gfx, arena: *arena_mod.Arena) ?[]u8 {
    if (g.mem_only) return null;
    return pal.clipboardGet(&g.st, arena);
}

pub fn gfxClose(g: *Gfx) void {
    if (!g.mem_only) {
        pal.close(&g.st);
    }
    g.mem_only = true;
}
