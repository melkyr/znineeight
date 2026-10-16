// console_test.zig — pty unit test for the complete Linux console backend (M5b T2).
//
// Run under a pty (`script`) with the harness feeding bytes after the backend
// has entered raw mode. Asserts, in order:
//   1. `enterRaw` disabled echo/canonical mode (ECHO and ICANON cleared,
//      VMIN=VTIME=0) as read back from the live termios;
//   2. `width`/`height` equal the real `ioctl(TIOCGWINSZ)` size *and* the
//      harness-configured pty window (30x100), so the 80x24 fallback cannot
//      make a broken ioctl path pass;
//   3. a key written through the pty is read back by `readKey` (non-blocking,
//      no echo — the harness also asserts the byte never appeared in the pty
//      output, i.e. it was not echoed);
//   4. escape decode: contiguous `ESC[A/B/C/D` -> up/down/right/left; a SPLIT
//      `ESC` ... `[A` (250 ms gap) still resolves to `.up`; `ESC` `CR` yields
//      `.esc` then the preserved `.enter`; a lone `ESC` resolves to `.esc`
//      after the bounded window;
//   5. an external SIGINT is surfaced as `Key.sigint` by the handler;
//   6. the output operations (`clear`, `setCursor`, `writeStr`, `cursorShow`)
//      run without crashing (their emitted escapes are asserted end-to-end by
//      the pty harness);
//   7. `leaveRaw` restored the original termios (c_iflag/c_lflag/c_cc).
//
// `readKey` returns `Key` (`.`none` when nothing is pending) rather than
// `?Key` — compiler defect D1; the in-band sentinel is the workaround.
//
// The test assembles the `Console` vtable literal and drives every operation
// through it, exactly as the CLI does (compiler defect D8: no function here
// *returns* `Console`). This is also a compile-time proof that the backend free
// functions match the contract field signatures exactly.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed_v98/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/console_test.zig
//   sh out/build_target.sh linux out/prog
// The full gate is tests/tier_console.sh: it pins the pty window (`stty rows 30
// cols 100`), exports Z9PLAY_CONSOLE_COLS/ROWS, feeds the byte sequence, and
// asserts the emitted escapes. Running the program manually also needs those
// env vars plus a windowed pty, or the size check fails by design.

const std = @import("std");
const filemod = @import("std_file");
const con = @import("../platform/console_linux.zig");
const contract = @import("../platform/console.zig");

@cInclude("<termios.h>");
@cInclude("<signal.h>");
@cInclude("<sys/ioctl.h>");

// The test reads the live termios itself to prove raw mode was applied and
// restored (independent of the backend's private saved copy).
const Termios = struct {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [32]u8,
    c_ispeed: u32,
    c_ospeed: u32,
};

extern "c" fn tcgetattr(fd: i32, termios_p: *void) i32;
extern "c" fn raise(sig: i32) i32;
extern "c" fn ioctl(fd: i32, request: u32, arg: *void) i32;

// Linux `struct winsize` mirror so the test can read the pty size directly
// (independent of the backend) via TIOCGWINSZ.
const Winsize = struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

const TIOCGWINSZ: u32 = 0x5413;

const ECHO: u32 = 0x00000008;
const ICANON: u32 = 0x00000002;
const VMIN: usize = 6;
const VTIME: usize = 5;
const SIGINT: i32 = 2;

// Injected by the harness; ASCII '@' (decimal 64) never appears in this
// program's own output, so an '@' in the pty log would prove echo leaked.
const EXPECT_CHAR: u8 = 64;
const DEFAULT_MARKER: []const u8 = "/tmp/z9play_console.ready";
const ARENA_BUF: usize = 4096;

var g_arena_buf: [ARENA_BUF]u8 = undefined;
var g_arena: std.arena.Arena = undefined;

// Marker path: the harness may point Z9PLAY_CONSOLE_MARKER at its scratch dir
// so parallel runs never share a stale file.
fn markerPath() []const u8 {
    var name: []const u8 = "Z9PLAY_CONSOLE_MARKER";
    if (std.os.env(name)) |e| {
        if (e.len != 0) return e;
    }
    return DEFAULT_MARKER;
}

// Read an unsigned 16-bit env var (0 when unset/empty/non-numeric). The pty
// harness sets these to the window it configured, so the size assertion cannot
// be satisfied by the 80x24 fallback.
fn envU16(name: []const u8) u16 {
    var e: []const u8 = "";
    if (std.os.env(name)) |v| {
        e = v;
    }
    if (e.len == 0) return 0;
    var acc: u32 = 0;
    var i: usize = 0;
    while (i < e.len) : (i += 1) {
        var c: u8 = e[i];
        if (c < '0' or c > '9') return 0;
        acc = acc * 10 + @intCast(u32, c - '0');
        if (acc > 65535) return 0;
    }
    return @intCast(u16, acc);
}

// Decimal u16 to stdout (evidence line for the harness).
fn writeDec(v_in: u16) void {
    var v: u32 = @intCast(u32, v_in);
    if (v == 0) {
        var z: []const u8 = "0";
        std.io.write(z);
        return;
    }
    var tmp: [5]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var out: [5]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = tmp[n - 1 - i];
    std.io.write(out[0..n]);
}

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn fail(msg: []const u8) void {
    var p: []const u8 = "console_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// Create the ready marker so the harness knows raw mode is active and can send
// the key without racing startup.
fn touchMarker() void {
    g_arena = std.arena.init(g_arena_buf[0..]);
    var f = filemod.open(&g_arena, markerPath(), filemod.Mode.Write) catch {
        fail("marker open");
        return;
    };
    var one: []const u8 = "1";
    _ = filemod.write(&f, one) catch {};
    filemod.close(&f);
}

// Key discriminants for the lookup helpers below (a tagged union cannot be
// compared directly in Z98).
const TAG_NONE: u8 = 0;
const TAG_CHAR: u8 = 1;
const TAG_SIGINT: u8 = 2;
const TAG_UP: u8 = 3;
const TAG_DOWN: u8 = 4;
const TAG_LEFT: u8 = 5;
const TAG_RIGHT: u8 = 6;
const TAG_ENTER: u8 = 7;
const TAG_ESC: u8 = 8;

fn keyTag(k: contract.Key) u8 {
    switch (k) {
        .none => return TAG_NONE,
        .char => return TAG_CHAR,
        .sigint => return TAG_SIGINT,
        .up => return TAG_UP,
        .down => return TAG_DOWN,
        .left => return TAG_LEFT,
        .right => return TAG_RIGHT,
        .enter => return TAG_ENTER,
        .esc => return TAG_ESC,
        else => return 255,
    }
}

// Poll `readKey` until `want` arrives. `.none` (nothing pending) is skipped; a
// different non-`.none` key is a failure. Returns false on timeout.
fn waitTag(cs: contract.Console, want: u8, timeout_ms: u32) bool {
    var i: u32 = 0;
    while (i < timeout_ms) : (i += 1) {
        var k: contract.Key = cs.readKey_fn(cs.state);
        var t: u8 = keyTag(k);
        if (t == want) return true;
        if (t != TAG_NONE) return false;
        std.io.sleepMs(1);
    }
    return false;
}

pub fn main() void {
    var orig: Termios = undefined;
    _ = tcgetattr(0, @ptrCast(*void, &orig));

    // Assemble the contract vtable from the backend's public free functions,
    // exactly as the CLI does. This is a compile-time proof that each backend
    // signature matches its `Console` field.
    var st: con.ConsoleLinState = undefined;
    var cs: contract.Console = contract.Console{
        .clear_fn = con.clear,
        .setCursor_fn = con.setCursor,
        .writeStr_fn = con.writeStr,
        .readKey_fn = con.readKey,
        .enterRaw_fn = con.enterRaw,
        .leaveRaw_fn = con.leaveRaw,
        .width_fn = con.width,
        .height_fn = con.height,
        .cursorShow_fn = con.cursorShow,
        .state = @ptrCast(*void, &st),
    };

    cs.enterRaw_fn(cs.state);

    // 1. Raw mode is live: echo and canonical processing are off, reads poll.
    var raw: Termios = undefined;
    _ = tcgetattr(0, @ptrCast(*void, &raw));
    if ((raw.c_lflag & ECHO) != 0) fail("echo not disabled");
    if ((raw.c_lflag & ICANON) != 0) fail("icanon not disabled");
    if (raw.c_cc[VMIN] != 0) fail("vmin not 0");
    if (raw.c_cc[VTIME] != 0) fail("vtime not 0");

    // 2. Window size: the harness sets the pty to 30x100 via `stty`; the backend
    //    must report the real ioctl(TIOCGWINSZ) size, not the 80x24 fallback.
    //    The test reads the size directly too and requires agreement, so a
    //    broken ioctl path cannot pass on the fallback.
    var wsz: Winsize = undefined;
    if (ioctl(0, TIOCGWINSZ, @ptrCast(*void, &wsz)) != 0) fail("test ioctl TIOCGWINSZ failed");
    if (wsz.ws_col == 0 or wsz.ws_row == 0) fail("pty reported 0x0 size");
    var w: u16 = cs.width_fn(cs.state);
    var h: u16 = cs.height_fn(cs.state);
    if (w != wsz.ws_col) fail("width does not match ioctl");
    if (h != wsz.ws_row) fail("height does not match ioctl");
    var cols: u16 = envU16("Z9PLAY_CONSOLE_COLS");
    var rows: u16 = envU16("Z9PLAY_CONSOLE_ROWS");
    if (cols == 0 or rows == 0) fail("size env not set");
    if (w != cols) fail("width does not match pty window");
    if (h != rows) fail("height does not match pty window");
    writeText("console_test: SIZE w=");
    writeDec(w);
    writeText(" h=");
    writeDec(h);
    writeText("\n");

    touchMarker();

    // 3. Read the char the harness writes after the marker (non-blocking poll;
    //    `readKey` returns `.none` until the byte arrives).
    var got_key: i32 = 0;
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        var k: contract.Key = cs.readKey_fn(cs.state);
        switch (k) {
            .char => |c| {
                if (c == EXPECT_CHAR) {
                    got_key = 1;
                    break;
                }
                fail("wrong key byte");
                return;
            },
            else => {},
        }
        std.io.sleepMs(1);
    }
    if (got_key == 0) fail("key not read back");

    // 3a. Contiguous arrows: `ESC[A/B/C/D` -> `.up/.down/.right/.left`.
    if (!waitTag(cs, TAG_UP, 3000)) fail("contiguous ESC[A not decoded to .up");
    if (!waitTag(cs, TAG_DOWN, 3000)) fail("contiguous ESC[B not decoded to .down");
    if (!waitTag(cs, TAG_RIGHT, 3000)) fail("contiguous ESC[C not decoded to .right");
    if (!waitTag(cs, TAG_LEFT, 3000)) fail("contiguous ESC[D not decoded to .left");

    // 3b. Split escape sequence: the harness writes ESC now and `[A` ~250 ms
    //     later. The persistent parse state must still resolve it to `.up`; a
    //     one-shot decode would return `.esc` and leak the `[`/`A` as chars.
    if (!waitTag(cs, TAG_UP, 3000)) fail("split ESC [A not decoded to .up");

    // 3c. ESC immediately followed by CR: `.esc`, then the preserved CR as its
    //     own `.enter` (the non-'[' byte must not be swallowed).
    if (!waitTag(cs, TAG_ESC, 3000)) fail("ESC CR not decoded to .esc");
    if (!waitTag(cs, TAG_ENTER, 3000)) fail("ESC CR did not preserve .enter");

    // 3d. A truly lone ESC (no tail ever arrives) resolves to `.esc` once the
    //     bounded disambiguation window elapses.
    if (!waitTag(cs, TAG_ESC, 3000)) fail("lone ESC not decoded to .esc");

    // 4. External SIGINT is surfaced as Key.sigint by the handler.
    _ = raise(SIGINT);
    if (!waitTag(cs, TAG_SIGINT, 2000)) fail("sigint not surfaced");

    // 5. Output operations: exercise every remaining op through the vtable.
    // Their emitted ANSI escapes are asserted end-to-end by the pty harness.
    cs.clear_fn(cs.state);
    cs.setCursor_fn(cs.state, 2, 3);
    cs.cursorShow_fn(cs.state, false);
    var msg: []const u8 = "z9play console backend\n";
    cs.writeStr_fn(cs.state, msg);
    cs.cursorShow_fn(cs.state, true);

    // 6. Termios restored byte-for-byte on the fields raw mode touched.
    cs.leaveRaw_fn(cs.state);
    var back: Termios = undefined;
    _ = tcgetattr(0, @ptrCast(*void, &back));
    if (back.c_lflag != orig.c_lflag) fail("c_lflag not restored");
    if (back.c_iflag != orig.c_iflag) fail("c_iflag not restored");
    if (back.c_cc[VMIN] != orig.c_cc[VMIN]) fail("vmin not restored");
    if (back.c_cc[VTIME] != orig.c_cc[VTIME]) fail("vtime not restored");

    var p: []const u8 = "console_test: PASS echo=off key=64 sigint=1 restored=1\n";
    std.io.write(p);
    var e: []const u8 = "console_test: ESC contig=udrl split=up preserve=enter lone=esc\n";
    std.io.write(e);
    var q: []const u8 = "console_test: OPS clear=1 setcursor=1 writestr=1 cursor=1 size=ok\n";
    std.io.write(q);
    std.os.exit(0);
}

