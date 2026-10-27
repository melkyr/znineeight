// main.zig — z9edit (Phase 2 P4-M3): single-file Z98 source editor.
//
// Usage:
//   z9edit <path>                 open (or create on save) one file
//   z9edit --smoke <in> <out>     load <in>, feed a scripted Event sequence
//                                 through the SAME uiStep the pump uses,
//                                 Ctrl+S writes <out>, exit 0
//
// Z98 subset only; direct imports (no std barrel). The 12 MB arena backs the
// gap buffer, undo log, ident table, and clipboard fallback; GUI compile and
// runtime stay under the 16 MB target.

const gfx = @import("std_gfx.zig");
const arena_mod = @import("std_arena.zig");
const buffer = @import("buffer.zig");
const ui = @import("ui.zig");
const io = @import("std_io.zig");
const os = @import("std_os.zig");

const COLS: u32 = 80;
const ROWS: u32 = 25;
const ARENA_SIZE: usize = 12 * 1024 * 1024;
const TITLE_MAX: usize = 200;

var g_arena_buf: [ARENA_SIZE]u8 = undefined;

fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn argAt(argv: [*][*]u8, i: i32) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[@intCast(usize, i)]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn putBytes(out: []u8, pos_in: usize, s: []const u8) usize {
    var pos = pos_in;
    var i: usize = 0;
    while (i < s.len and pos < out.len) : (i += 1) {
        out[pos] = s[i];
        pos += 1;
    }
    return pos;
}

fn basenameOf(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path[i + 1 ..];
    }
    return path;
}

fn buildTitle(buf: []u8, path: []const u8) []const u8 {
    var p: usize = 0;
    p = putBytes(buf, p, "z9edit \xe2\x80\x94 ");
    p = putBytes(buf, p, basenameOf(path));
    return buf[0..p];
}

fn evBase(kind: gfx.EventKind) gfx.Event {
    return gfx.Event{
        .kind = kind,
        .ch = 0,
        .code = 0,
        .x = 0,
        .y = 0,
        .button = 0,
        .wheel = 0,
        .cols = 0,
        .rows = 0,
        .mods = 0,
    };
}

fn paintFrame(g: *gfx.Gfx, st: *ui.UiState) bool {
    if (!gfx.gfxBeginFrame(g)) return false;
    ui.uiPaint(st) catch {
        return false;
    };
    if (!gfx.gfxEndFrame(g)) return false;
    return true;
}

fn stepFrame(g: *gfx.Gfx, st: *ui.UiState, ev: *const gfx.Event) bool {
    if (!ui.uiStep(st, ev)) return false;
    return paintFrame(g, st);
}

fn feedKey(g: *gfx.Gfx, st: *ui.UiState, code: u16, ch: u8, mods: u8) bool {
    var ev = evBase(.key_down);
    ev.code = code;
    ev.ch = ch;
    ev.mods = mods;
    return stepFrame(g, st, &ev);
}

fn feedText(g: *gfx.Gfx, st: *ui.UiState, s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        var ev = evBase(.key_down);
        ev.ch = s[i];
        if (s[i] == '\n') ev.ch = 13;
        if (!stepFrame(g, st, &ev)) return false;
    }
    return true;
}

fn feedMouse(g: *gfx.Gfx, st: *ui.UiState, kind: gfx.EventKind, x: u32, y: u32) bool {
    var ev = evBase(kind);
    ev.x = x;
    ev.y = y;
    ev.button = 0;
    return stepFrame(g, st, &ev);
}

fn fail(msg: []const u8) void {
    io.write(msg);
    io.write("\n");
    os.exit(1);
}

fn runSmoke(in_path: []const u8, out_path: []const u8) void {
    var arena = arena_mod.init(g_arena_buf[0..]);
    const b = buffer.bufLoad(&arena, in_path) catch {
        fail("z9edit: cannot read smoke input");
        return;
    };
    var tb: [TITLE_MAX]u8 = undefined;
    const title = buildTitle(tb[0..], in_path);
    const g = gfx.gfxOpen(title, COLS, ROWS) catch {
        fail("z9edit: gfxOpen failed");
        return;
    };
    const st = ui.uiInit(&arena, g, b, in_path) catch {
        gfx.gfxClose(g);
        fail("z9edit: uiInit failed");
        return;
    };
    ui.uiSetSavePath(st, out_path);

    if (!paintFrame(g, st)) {
        gfx.gfxClose(g);
        fail("z9edit: initial paint failed");
        return;
    }
    io.write("READY\n");
    // Keep presenting frames before the scripted sequence so the Xvfb/Wine
    // screenshot sees a live window (windowed DDraw needs a few presents).
    var hold: u32 = 0;
    while (hold < 12) : (hold += 1) {
        if (!paintFrame(g, st)) return;
        io.sleepMs(100);
    }

    // click-to-cursor at line 2, col 0 (gutter is 2 cells for this fixture)
    if (!feedMouse(g, st, .mouse_down, 2, 2)) return;
    if (!feedMouse(g, st, .mouse_up, 2, 2)) return;
    // End of line, then type a new declarations/comment/number line.
    if (!feedKey(g, st, 0x23, 0, 0)) return;
    if (!feedText(g, st, "\n    const tmp = error[3000]; // note 7")) return;

    // drag-select "const" on the new line (cols 4..9), delete, undo.
    if (!feedMouse(g, st, .mouse_down, 6, 3)) return;
    if (!feedMouse(g, st, .mouse_move, 11, 3)) return;
    if (!feedMouse(g, st, .mouse_up, 11, 3)) return;
    if (!feedKey(g, st, 0x2E, 127, 0)) return;
    if (!feedKey(g, st, 0, 'z', 2)) return;

    // Shift+arrows extend select, clipboard copy/cut/paste round-trip.
    if (!feedMouse(g, st, .mouse_down, 6, 3)) return;
    if (!feedMouse(g, st, .mouse_up, 6, 3)) return;
    var k: usize = 0;
    while (k < 5) : (k += 1) {
        if (!feedKey(g, st, 0x27, 0, 1)) return;
    }
    if (!feedKey(g, st, 0, 'c', 2)) return;
    if (!feedKey(g, st, 0, 'x', 2)) return;
    if (!feedKey(g, st, 0, 'v', 2)) return;

    // select-all + type-over replaces the whole buffer; undo twice restores.
    if (!feedKey(g, st, 0, 'a', 2)) return;
    if (!feedKey(g, st, 0, 'X', 0)) return;
    if (!feedKey(g, st, 0, 'z', 2)) return;
    if (!feedKey(g, st, 0, 'z', 2)) return;

    // save to <out>, then quit.
    if (!feedKey(g, st, 0, 's', 2)) return;
    _ = feedKey(g, st, 0, 'q', 2);

    io.sleepMs(200);
    gfx.gfxClose(g);
}

fn runInteractive(path: []const u8) void {
    var arena = arena_mod.init(g_arena_buf[0..]);
    const b = buffer.bufLoad(&arena, path) catch |e| {
        if (e == error.OutOfMemory or e == error.TooLarge) {
            fail("z9edit: cannot allocate file buffer");
            return;
        }
        const nb = buffer.bufInit(&arena, 4096) catch {
            fail("z9edit: cannot allocate file buffer");
            return;
        };
        var tb2: [TITLE_MAX]u8 = undefined;
        const t2 = buildTitle(tb2[0..], path);
        const g2 = gfx.gfxOpen(t2, COLS, ROWS) catch {
            fail("z9edit: gfxOpen failed");
            return;
        };
        const st2 = ui.uiInit(&arena, g2, nb, path) catch {
            gfx.gfxClose(g2);
            fail("z9edit: uiInit failed");
            return;
        };
        loop(g2, st2);
        return;
    };
    var tb: [TITLE_MAX]u8 = undefined;
    const title = buildTitle(tb[0..], path);
    const g = gfx.gfxOpen(title, COLS, ROWS) catch {
        fail("z9edit: gfxOpen failed");
        return;
    };
    const st = ui.uiInit(&arena, g, b, path) catch {
        gfx.gfxClose(g);
        fail("z9edit: uiInit failed");
        return;
    };
    loop(g, st);
}

fn loop(g: *gfx.Gfx, st: *ui.UiState) void {
    var quit = false;
    while (!quit) {
        var ev: gfx.Event = undefined;
        while (gfx.gfxPollEvent(g, &ev)) {
            if (!ui.uiStep(st, &ev)) {
                quit = true;
                break;
            }
        }
        if (quit) break;
        if (!paintFrame(g, st)) {
            gfx.gfxClose(g);
            fail("z9edit: paint failed");
            return;
        }
        io.sleepMs(16);
    }
    gfx.gfxClose(g);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    if (argc >= 4 and strEq(argAt(argv, 1), "--smoke")) {
        runSmoke(argAt(argv, 2), argAt(argv, 3));
        return;
    }
    if (argc < 2) {
        io.write("usage: z9edit <path> | z9edit --smoke <in> <out>\n");
        os.exit(2);
        return;
    }
    runInteractive(argAt(argv, 1));
}
