// gfx_demo/main.zig — Phase 2 P4-M1 standalone proof for std_gfx.
//
// Windowed mode: title `z98 gfx demo`, a cell grid painted with gfxClear /
// gfxFillRect / gfxDrawText + a software mouse cursor, events through the real
// gfxPollEvent pump. `--smoke N` feeds the scripted sequence (click at a cell,
// wheel +3, resize, key q) through the SAME handleEvent the pump uses, paints
// N frames (paced ~100 ms in a real window so Xvfb can screenshot), prints a
// flushed READY once, then gfxClose + exit 0.
//
// Headless mode: `--smoke N --dump-grid` uses gfxOpenMemory (no window, no X),
// paints the same frames, and writes `grid.txt` (row-major ASCII) for the
// byte-for-byte golden gate.
//
// Direct imports only (no std barrel): the compile graph stays small (<16 MB).

const gfx = @import("std_gfx");
const io = @import("std_io");

const COLS: u32 = 64;
const ROWS: u32 = 20;
const TITLE: []const u8 = "z98 gfx demo | DirectDraw7 + GDI";

const App = struct {
    cx: u32,
    cy: u32,
    clicks: u32,
    wheel: i32,
    frames: u32,
    quit: bool,
    resized: bool,
    disp_cols: u32,
    disp_rows: u32,
    last_ch: u8,
};

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

// The app-side event handler. The real pump and --smoke both call this.
fn handleEvent(app: *App, ev: *const gfx.Event) bool {
    if (ev.kind == .close) {
        app.quit = true;
        return false;
    }
    if (ev.kind == .key_down) {
        app.last_ch = ev.ch;
        if (ev.ch == 'q' or ev.ch == 'Q') {
            app.quit = true;
        }
    }
    if (ev.kind == .mouse_move or ev.kind == .mouse_down or ev.kind == .mouse_up) {
        app.cx = ev.x;
        app.cy = ev.y;
        if (ev.kind == .mouse_down) app.clicks += 1;
    }
    if (ev.kind == .wheel) {
        app.wheel += ev.wheel;
    }
    if (ev.kind == .resize) {
        app.resized = true;
        app.disp_cols = ev.cols;
        app.disp_rows = ev.rows;
        io.write("RESIZE ");
        io.printInt(@intCast(i32, ev.cols));
        io.write("x");
        io.printInt(@intCast(i32, ev.rows));
        io.write(" px=");
        io.printInt(@intCast(i32, ev.x));
        io.write("x");
        io.printInt(@intCast(i32, ev.y));
        io.write("\n");
    }
    return true;
}

fn putStr(buf: []u8, pos_in: usize, s: []const u8) usize {
    var pos = pos_in;
    var i: usize = 0;
    while (i < s.len and pos < buf.len) : (i += 1) {
        buf[pos] = s[i];
        pos += 1;
    }
    return pos;
}

fn putInt(buf: []u8, pos_in: usize, v_in: i32) usize {
    var pos = pos_in;
    var v = v_in;
    if (v < 0) {
        if (pos < buf.len) buf[pos] = '-';
        pos += 1;
        v = 0 - v;
    }
    var tmp: [12]u8 = undefined;
    var n: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        var u: u32 = @intCast(u32, v);
        while (u > 0) : (u = u / 10) {
            tmp[n] = @intCast(u8, 48 + (u % 10));
            n += 1;
        }
    }
    while (n > 0) {
        n -= 1;
        if (pos < buf.len) buf[pos] = tmp[n];
        pos += 1;
    }
    return pos;
}

fn paint(g: *gfx.Gfx, app: *App) void {
    gfx.gfxClear(g, 8);

    gfx.gfxFillRect(g, 0, 0, COLS, 1, 15, 1);
    gfx.gfxDrawText(g, 1, 0, TITLE, 15, 1);

    gfx.gfxFillRect(g, 0, 1, COLS, 1, 8, 7);
    gfx.gfxDrawText(g, 1, 1, "ESC quit | wheel=3 lines | click moves cursor", 0, 7);

    gfx.gfxDrawText(g, 2, 3, "std_gfx: cell grid + GDI text + DDraw7 Blt", 14, 0);
    gfx.gfxDrawText(g, 2, 4, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10, 0);
    gfx.gfxDrawText(g, 2, 5, "abcdefghijklmnopqrstuvwxyz", 11, 0);
    gfx.gfxDrawText(g, 2, 6, "0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", 12, 0);

    gfx.gfxFillRect(g, 2, 8, 26, 3, 14, 4);
    gfx.gfxDrawText(g, 3, 9, "fill-rect exercised", 15, 4);

    gfx.gfxDrawText(g, 2, 12, "scripted: click, wheel +3, resize, q", 13, 0);

    var status: [80]u8 = undefined;
    var p: usize = 0;
    p = putStr(status[0..], p, "click=(");
    p = putInt(status[0..], p, @intCast(i32, app.cx));
    p = putStr(status[0..], p, ",");
    p = putInt(status[0..], p, @intCast(i32, app.cy));
    p = putStr(status[0..], p, ") clicks=");
    p = putInt(status[0..], p, @intCast(i32, app.clicks));
    p = putStr(status[0..], p, " wheel=");
    p = putInt(status[0..], p, app.wheel);
    p = putStr(status[0..], p, " frame=");
    p = putInt(status[0..], p, @intCast(i32, app.frames));
    if (app.resized) {
        p = putStr(status[0..], p, " resize=");
        p = putInt(status[0..], p, @intCast(i32, app.disp_cols));
        p = putStr(status[0..], p, "x");
        p = putInt(status[0..], p, @intCast(i32, app.disp_rows));
    }
    gfx.gfxFillRect(g, 0, ROWS - 1, COLS, 1, 0, 7);
    gfx.gfxDrawText(g, 1, ROWS - 1, status[0..p], 0, 7);

    var cx = app.cx;
    var cy = app.cy;
    if (cx >= COLS) cx = COLS - 1;
    if (cy > ROWS - 3) cy = ROWS - 3;
    gfx.gfxFillRect(g, cx, cy, 1, 1, 15, 13);
    gfx.gfxDrawText(g, cx, cy, "X", 0, 13);
}

fn scripted(app: *App, g: *gfx.Gfx, idx: u32, total: u32, mem_only: bool) void {
    if (idx == 1) {
        var ev = evBase(.mouse_down);
        ev.x = 20;
        ev.y = 8;
        ev.button = 0;
        _ = handleEvent(app, &ev);
        return;
    }
    if (idx == 2) {
        var ev = evBase(.wheel);
        ev.wheel = gfx.gfxWheelLines(120);
        _ = handleEvent(app, &ev);
        return;
    }
    if (idx == 3) {
        if (mem_only) {
            var ev = evBase(.resize);
            ev.cols = COLS;
            ev.rows = ROWS;
            ev.x = COLS * 8;
            ev.y = ROWS * 16;
            _ = handleEvent(app, &ev);
        } else {
            // Real window resize: Windows SENDs WM_SIZE to the WndProc; the
            // PAL poll loop then resizes the offscreen surface and grid.
            _ = gfx.gfxTestResize(g, 70, 22);
        }
        return;
    }
    if (idx == 8) {
        if (!mem_only) {
            _ = gfx.gfxTestResize(g, 100, 37);
        }
        return;
    }
    if (total > 4 and idx + 1 == total) {
        var ev = evBase(.key_down);
        ev.ch = 'q';
        ev.code = 0x51;
        _ = handleEvent(app, &ev);
    }
}

fn parseU32(s: []const u8) u32 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return v;
        v = v * 10 + @intCast(u32, s[i] - '0');
    }
    return v;
}

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

fn dumpGrid(g: *gfx.Gfx) bool {
    const grid = gfx.gfxDumpGrid(g);
    const fd = io.fileOpen("grid.txt", true) orelse return false;
    io.fileWrite(fd, grid);
    io.fileClose(fd);
    return true;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var smoke: bool = false;
    var dump: bool = false;
    var selftest: bool = false;
    var smoke_n: u32 = 0;
    var i: i32 = 1;
    while (i < argc) : (i += 1) {
        const a = argAt(argv, i);
        if (strEq(a, "--smoke")) {
            smoke = true;
            if (i + 1 < argc) {
                i += 1;
                smoke_n = parseU32(argAt(argv, i));
            }
            if (smoke_n == 0) smoke_n = 1;
        } else if (strEq(a, "--dump-grid")) {
            dump = true;
        } else if (strEq(a, "--selftest")) {
            selftest = true;
        }
    }

    if (selftest) {
        const w1 = gfx.gfxWheelLines(120);
        const w2 = gfx.gfxWheelLines(-240);
        io.write("WHEELMAP 120=");
        io.printInt(w1);
        io.write(" -240=");
        io.printInt(w2);
        io.write("\n");
        if (w1 == 3 and w2 == -6) {
            io.write("WHEELMAP OK\n");
        } else {
            io.write("WHEELMAP FAIL\n");
            @exit(@intCast(u8, 1));
        }
        return;
    }

    var app = App{
        .cx = 4,
        .cy = 10,
        .clicks = 0,
        .wheel = 0,
        .frames = 0,
        .quit = false,
        .resized = false,
        .disp_cols = COLS,
        .disp_rows = ROWS,
        .last_ch = 0,
    };

    var g: *gfx.Gfx = undefined;
    if (dump) {
        g = gfx.gfxOpenMemory(COLS, ROWS) catch {
            io.write("gfx_demo: gfxOpenMemory failed\n");
            @exit(@intCast(u8, 1));
            return;
        };
    } else {
        var title: []const u8 = "z98 gfx demo";
        g = gfx.gfxOpen(title, COLS, ROWS) catch {
            io.write("gfx_demo: gfxOpen failed\n");
            @exit(@intCast(u8, 1));
            return;
        };
    }

    if (!smoke and !dump) {
        // Interactive window loop: the real pump drives the same handler.
        while (!app.quit) {
            var ev: gfx.Event = undefined;
            while (gfx.gfxPollEvent(g, &ev)) {
                if (!handleEvent(&app, &ev)) break;
            }
            if (app.quit) break;
            if (!gfx.gfxBeginFrame(g)) {
                gfx.gfxClose(g);
                io.write("gfx_demo: begin frame failed\n");
                @exit(@intCast(u8, 1));
                return;
            }
            paint(g, &app);
            if (!gfx.gfxEndFrame(g)) {
                gfx.gfxClose(g);
                io.write("gfx_demo: end frame failed (Blt)\n");
                @exit(@intCast(u8, 1));
                return;
            }
            app.frames += 1;
            io.sleepMs(16);
        }
        gfx.gfxClose(g);
        return;
    }

    var ready: bool = false;
    var f: u32 = 0;
    while (f < smoke_n) : (f += 1) {
        scripted(&app, g, f, smoke_n, dump);
        if (!app.quit) {
            var ev: gfx.Event = undefined;
            while (gfx.gfxPollEvent(g, &ev)) {
                _ = handleEvent(&app, &ev);
            }
        }
        if (!gfx.gfxBeginFrame(g)) {
            gfx.gfxClose(g);
            io.write("gfx_demo: begin frame failed\n");
            @exit(@intCast(u8, 1));
            return;
        }
        paint(g, &app);
        if (!gfx.gfxEndFrame(g)) {
            gfx.gfxClose(g);
            io.write("gfx_demo: end frame failed (Blt)\n");
            @exit(@intCast(u8, 1));
            return;
        }
        app.frames += 1;
        if (!ready) {
            io.write("READY\n");
            ready = true;
        }
        if (!dump) io.sleepMs(100);
    }

    if (dump) {
        if (!dumpGrid(g)) {
            gfx.gfxClose(g);
            io.write("gfx_demo: grid.txt write failed\n");
            @exit(@intCast(u8, 1));
            return;
        }
    }
    gfx.gfxClose(g);
}
