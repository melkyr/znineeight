// std_gfx.zig — Z98 std lib L2: minimal DirectDraw GUI layer.
//
// Contract (P4-M1): backend-free Color/EventKind/Event/GfxError/Gfx + the
// drawing surface: gfxOpen/gfxOpenMemory/gfxPollEvent/gfxBeginFrame/
// gfxEndFrame/gfxClear/gfxFillRect/gfxDrawText/gfxCharSize/gfxBufferSize/
// gfxDumpGrid/gfxClipboardSet/gfxClipboardGet/gfxClose. All coordinates are
// CELLS. Colors are 16-color palette indices 0..15 (see
// std_gfx_pal.paletteRgb; the DirectDraw surface itself is 32-bit).
//
// The Win9x backend (window class/pump, glyph atlas, DirectDraw7, clipboard)
// lives in std_gfx_pal.zig; this module owns the cell grid, the font metrics,
// the ASCII sanitisation (32..126, otherwise '?'), resize bookkeeping, and the
// headless gfxOpenMemory path. A memory Gfx never creates a window and its
// grid is the deterministic `--dump-grid` payload; a windowed Gfx mirrors the
// same cells while painting the real offscreen surface.
//
// Gfx is opaque: the public type is one pointer to the private GfxState, so no
// cell buffer or raw COM pointer is reachable through the app-facing type.

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
const EK_RESIZE: u8 = 6;

const GfxState = struct {
    cells: [MAX_CELLS]u8,
    dump: [MAX_DUMP]u8,
    cols: u32,
    rows: u32,
    cw: u32,
    ch: u32,
    mem_only: bool,
    st: pal.State,
};

pub const Gfx = struct { opaque: *GfxState };

var g_state: GfxState = undefined;
var g_gfx: Gfx = undefined;

fn initGrid(s: *GfxState, cols: u32, rows: u32) void {
    s.cols = cols;
    s.rows = rows;
    var i: usize = 0;
    while (i < MAX_CELLS) : (i += 1) {
        s.cells[i] = 32;
    }
}

fn resizeGrid(s: *GfxState, cols: u32, rows: u32) void {
    if (cols == 0 or rows == 0 or cols > MAX_COLS or rows > MAX_ROWS) return;
    initGrid(s, cols, rows);
}

fn sanitize(b: u8) u8 {
    if (b < 32 or b > 126) return 63; // '?'
    return b;
}

pub fn gfxOpen(title: []const u8, cols: u32, rows: u32) GfxError!*Gfx {
    if (cols == 0 or rows == 0 or cols > MAX_COLS or rows > MAX_ROWS) {
        return error.OpenFailed;
    }
    const s = &g_state;
    initGrid(s, cols, rows);
    s.cw = MEM_CW;
    s.ch = MEM_CH;
    s.mem_only = false;
    if (!pal.open(title, cols, rows, &s.st)) {
        return error.OpenFailed;
    }
    s.cw = s.st.cw;
    s.ch = s.st.ch;
    g_gfx.opaque = s;
    return &g_gfx;
}

pub fn gfxOpenMemory(cols: u32, rows: u32) GfxError!*Gfx {
    if (cols == 0 or rows == 0 or cols > MAX_COLS or rows > MAX_ROWS) {
        return error.OpenFailed;
    }
    const s = &g_state;
    initGrid(s, cols, rows);
    s.cw = MEM_CW;
    s.ch = MEM_CH;
    s.mem_only = true;
    g_gfx.opaque = s;
    return &g_gfx;
}

// Raw wheel delta -> app lines (3 lines/notch, spec §7.1/§7.2). Exposed so the
// demo/tier exercises the real mapping instead of injecting a pre-mapped 3.
pub fn gfxWheelLines(raw_delta: i32) i32 {
    return pal.wheelLines(raw_delta);
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
    const s = g.opaque;
    if (s.mem_only) return false;
    var raw: pal.RawEvent = undefined;
    if (!pal.pollEvent(&s.st, &raw)) return false;
    if (raw.kind == EK_RESIZE) {
        resizeGrid(s, raw.cols, raw.rows);
        if (s.cols != 0 and s.rows != 0) {
            raw.cols = s.cols;
            raw.rows = s.rows;
        }
    }
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

// Test affordance: resize the real window (window mode) so Windows SENDs
// WM_SIZE to the WndProc, or resize the headless grid directly. Used by
// --smoke to exercise the actual WM_SIZE surface+grid resize path.
pub fn gfxTestResize(g: *Gfx, cols: u32, rows: u32) bool {
    const s = g.opaque;
    if (cols == 0 or rows == 0 or cols > MAX_COLS or rows > MAX_ROWS) return false;
    if (s.mem_only) {
        resizeGrid(s, cols, rows);
        return true;
    }
    return pal.testResizeClient(&s.st, cols, rows);
}

pub fn gfxBeginFrame(g: *Gfx) bool {
    const s = g.opaque;
    if (s.mem_only) return true;
    return pal.beginFrame(&s.st);
}

pub fn gfxEndFrame(g: *Gfx) bool {
    const s = g.opaque;
    if (s.mem_only) return true;
    return pal.endFrame(&s.st);
}

pub fn gfxClear(g: *Gfx, bg: Color) void {
    const s = g.opaque;
    var i: usize = 0;
    while (i < MAX_CELLS) : (i += 1) {
        s.cells[i] = 32;
    }
    if (!s.mem_only) {
        pal.fillRect(&s.st, 0, 0,
            @intCast(i32, s.cols * s.cw), @intCast(i32, s.rows * s.ch), bg, bg);
    }
}

pub fn gfxFillRect(g: *Gfx, x: u32, y: u32, w: u32, h: u32, fg: Color, bg: Color) void {
    const s = g.opaque;
    if (x >= s.cols or y >= s.rows) return;
    var x1: u32 = x + w;
    if (x1 > s.cols) x1 = s.cols;
    var y1: u32 = y + h;
    if (y1 > s.rows) y1 = s.rows;
    if (x1 <= x or y1 <= y) return;
    var yy: u32 = y;
    while (yy < y1) : (yy += 1) {
        var xx: u32 = x;
        while (xx < x1) : (xx += 1) {
            s.cells[@intCast(usize, yy * s.cols + xx)] = 32;
        }
    }
    if (!s.mem_only) {
        pal.fillRect(&s.st,
            @intCast(i32, x * s.cw), @intCast(i32, y * s.ch),
            @intCast(i32, (x1 - x) * s.cw), @intCast(i32, (y1 - y) * s.ch),
            fg, bg);
    }
}

pub fn gfxDrawText(g: *Gfx, x: u32, y: u32, s_in: []const u8, fg: Color, bg: Color) void {
    const s = g.opaque;
    if (y >= s.rows or x >= s.cols) return;
    var maxn: usize = s_in.len;
    const room: usize = @intCast(usize, s.cols - x);
    if (maxn > room) maxn = room;
    var i: usize = 0;
    while (i < maxn) : (i += 1) {
        s.cells[@intCast(usize, y * s.cols + x + @intCast(u32, i))] = sanitize(s_in[i]);
    }
    if (s.mem_only) return;
    var off: usize = 0;
    var buf: [TEXT_CHUNK]u8 = undefined;
    while (off < maxn) {
        var n: usize = maxn - off;
        if (n > TEXT_CHUNK) n = TEXT_CHUNK;
        var j: usize = 0;
        while (j < n) : (j += 1) buf[j] = sanitize(s_in[off + j]);
        pal.drawText(&s.st,
            @intCast(i32, (x + @intCast(u32, off)) * s.cw), @intCast(i32, y * s.ch),
            buf[0..n], fg, bg, s.cw, s.ch);
        off += n;
    }
}

// Per-cell pixel size (fixed font metrics on a window, 8x16 in memory mode).
pub fn gfxCharSize(g: *Gfx, w: *u32, h: *u32) void {
    const s = g.opaque;
    w.* = s.cw;
    h.* = s.ch;
}

// Pixel size of the cols x rows cell area.
pub fn gfxBufferSize(g: *Gfx, w: *u32, h: *u32) void {
    const s = g.opaque;
    w.* = s.cols * s.cw;
    h.* = s.rows * s.ch;
}

// Row-major ASCII snapshot: one line per row, '\n' after each row (including
// the last). Trailing padding spaces are trimmed so the golden has no trailing
// whitespace; leading spaces keep cell columns. Non-printable drawn bytes are
// already '?'.
pub fn gfxDumpGrid(g: *Gfx) []u8 {
    const s = g.opaque;
    var p: usize = 0;
    var y: u32 = 0;
    while (y < s.rows) : (y += 1) {
        const row_start = p;
        var x: u32 = 0;
        while (x < s.cols) : (x += 1) {
            s.dump[p] = s.cells[@intCast(usize, y * s.cols + x)];
            p += 1;
        }
        while (p > row_start and s.dump[p - 1] == 32) {
            p -= 1;
        }
        s.dump[p] = 10;
        p += 1;
    }
    return s.dump[0..p];
}

pub fn gfxClipboardSet(g: *Gfx, s_in: []const u8) bool {
    const s = g.opaque;
    if (s.mem_only) return false;
    return pal.clipboardSet(&s.st, s_in);
}

pub fn gfxClipboardGet(g: *Gfx, arena: *arena_mod.Arena) ?[]u8 {
    const s = g.opaque;
    if (s.mem_only) return null;
    return pal.clipboardGet(&s.st, arena);
}

pub fn gfxClose(g: *Gfx) void {
    const s = g.opaque;
    if (!s.mem_only) {
        pal.close(&s.st);
    }
    s.mem_only = true;
}

// Additive P4-M3 helper: refresh the real window title (dirty `*`). A memory
// Gfx has no window, so it returns false and the cell grid is unchanged.
pub fn gfxSetTitle(g: *Gfx, title: []const u8) bool {
    const s = g.opaque;
    if (s.mem_only) return false;
    return pal.setTitle(&s.st, title);
}
