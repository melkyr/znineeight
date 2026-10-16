// console_linux.zig — complete Linux console backend for z9play (M5b Task 2).
//
// Implements the `Console` contract (platform/console.zig) on Linux: raw-mode
// enter/leave (termios), non-blocking key decode (a small ESC-introduced arrow
// state machine plus a sticky SIGINT flag), ANSI clear/setCursor/cursorShow/
// writeStr, and window size via `ioctl(TIOCGWINSZ)`. It is Linux-only; the
// Win9x backend lands in M6.
//
// Raw mode (enterRaw): the caller's original termios is saved in the state
// struct and the working copy clears ECHO/ECHONL, ICANON and IEXTEN (so keys
// arrive one at a time, un-echoed, with no extended processing) and clears
// ICRNL/IXON (so CR stays CR and Ctrl-S/Q are ordinary bytes). ISIG is
// deliberately kept, so Ctrl-C is delivered as SIGINT (see below), matching the
// player's "q / Ctrl-C quit". VMIN=0, VTIME=0 makes `read(2)` return
// immediately — the non-blocking contract of `readKey`. OPOST/`c_oflag` is
// deliberately left unchanged: the CLI only uses `\r` for the status line and
// `\n` elsewhere, and can rely on the default ONLCR mapping.
//
// SIGINT handling: `signal(SIGINT, onSigint)` installs a handler that only sets
// a sticky module flag (`g_sigint`). `readKey` checks the flag and returns
// `.sigint`; this is why ISIG stays enabled — Ctrl-C must surface as SIGINT,
// not as the literal byte 0x03.
//
// leaveRaw: `tcsetattr` writes back the saved termios byte-for-byte, undoing
// every change above; it is a no-op when raw mode is not active, so the caller
// can call it unconditionally on every exit path.
//
// Output conventions: clear/setCursor/cursorShow and writeStr all write to
// stdout (fd 1). setCursor takes 0-based row/col and emits the 1-based ANSI
// `ESC[<row+1>;<col+1>H`. width/height read the window via
// `ioctl(0, TIOCGWINSZ)` and fall back to 80x24 when it fails or reports zero.
//
// Assembly note (compiler defect D8): a backend must NOT expose a function that
// *returns* `Console` in a multi-module build. This module exposes the nine
// vtable operations as public free functions whose signatures match the
// contract fields exactly; the caller assembles the `Console` literal and sets
// `state` to its own `ConsoleLinState`. The C externs live in
// console_linux_pal.zig (see there for the split rationale).
//
// D1 note: `readKey` returns `Key` directly (`.none` when nothing is pending)
// rather than `?Key`; seed v98 rejects the optional-of-aggregate
// function-pointer return and mis-emits its C89 typedef order. See D1 in
// examples/torrent_example_defects.md.
//
// Pure Z98: free functions only, strict `@intCast`, numeric termios constants
// (no dependence on the termios.h macros at the Zig level).

const std = @import("std");
const pal = @import("console_linux_pal.zig");
const con = @import("console.zig");

// Prototypes for the externs in console_linux_pal.zig. Z98 emits no extern
// prototypes, so gcc sees only these headers' declarations.
@cInclude("<termios.h>");
@cInclude("<unistd.h>");
@cInclude("<signal.h>");
@cInclude("<sys/ioctl.h>");

// Re-export the contract types so consumers can name them through the backend.
pub const Key = con.Key;
pub const Console = con.Console;

// Linux glibc `struct termios` (same layout on i386/x86_64 and musl): four
// tcflag_t, the line-discipline byte, NCCS=32 control characters, then the two
// speed_t. 60 bytes total; the fields are only accessed through the Zig names,
// and gcc fills the real struct through the `*void` externs.
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

// Caller-owned Linux console state: the original termios plus whether raw mode
// is currently in effect (so `leaveRaw` is safe to call unconditionally), and
// the persistent escape-parse state. The escape state is carried here (not in a
// `readKey` local) so a sequence split across separate `readKey` calls still
// resolves: `esc_phase` is 0 (idle), 1 (ESC seen, awaiting `[`) or 2 (ESC `[`
// seen, awaiting the final byte), and `pending_byte` holds a byte already
// consumed as the tail of a non-arrow escape so it can be returned as its own
// key on the next call (e.g. `ESC` `CR` -> `.esc`, then `.enter`).
pub const ConsoleLinState = struct {
    saved: Termios,
    entered: bool,
    esc_phase: u8,
    esc_start: u32,
    pending_byte: u8,
    pending_valid: bool,
};

// termios(3) constants (linux x86 numeric values; deliberately not the macros).
const TCSANOW: i32 = 0;
const SIGINT: i32 = 2;

// c_cc index of VMIN/VTIME (asm-generic/termbits.h: VMIN=6, VTIME=5).
const VMIN: usize = 6;
const VTIME: usize = 5;

// c_lflag bits: ECHO/ECHONL (no echo), ICANON (byte-at-a-time), IEXTEN
// (disable extended processing). ISIG is intentionally NOT cleared.
const ECHO: u32 = 0x00000008;
const ECHONL: u32 = 0x00000040;
const ICANON: u32 = 0x00000002;
const IEXTEN: u32 = 0x00008000;

// c_iflag bits: ICRNL (CR -> NL), IXON (flow control).
const ICRNL: u32 = 0x00000100;
const IXON: u32 = 0x00000400;

// TIOCGWINSZ (asm-generic/ioctls.h: _IOR('T', 0x13, struct winsize)).
const TIOCGWINSZ: u32 = 0x5413;

// ASCII ESC and the arrow-sequence tail bytes.
const ESC: u8 = 0x1b;

// Inter-byte disambiguation window for the escape state machine. After an ESC
// (or an ESC `[`) the parser keeps the sequence "open" for this many ms; if no
// next byte arrives the pending ESC resolves to `.esc`. The machine is
// non-blocking (each `readKey` still returns `.none` when idle), so this window
// is not a stall — it only bounds how long a lone ESC waits before it is
// reported. Splits observed under a pty at 200 ms must resolve, hence 1000 ms.
const ESC_WINDOW_MS: u32 = 1000;

// Set by the SIGINT handler; sticky until the next `enterRaw`. A byte is enough
// (the handler is async-signal-safe: one store).
var g_sigint: u8 = 0;

fn onSigint(sig: i32) void {
    _ = sig;
    g_sigint = 1;
}

// --- vtable implementation: raw mode --------------------------------------

// `Console.enterRaw_fn`: enter raw mode on stdin (fd 0), saving the original
// settings into the caller's state. A second call re-saves the (already raw)
// termios, so `leaveRaw` still restores whatever termios was current. When
// stdin is not a tty (tcgetattr fails, e.g. a redirected run) raw mode is not
// entered and `leaveRaw` becomes a no-op, so a bogus termios is never written
// back.
pub fn enterRaw(state: *void) void {
    var st: *ConsoleLinState = @ptrCast(*ConsoleLinState, state);
    g_sigint = 0;
    st.entered = false;
    st.esc_phase = 0;
    st.esc_start = 0;
    st.pending_valid = false;
    if (pal.tcgetattr(0, @ptrCast(*void, &st.saved)) != 0) return;

    var raw: Termios = st.saved;
    raw.c_lflag = raw.c_lflag & ~(ECHO | ECHONL | ICANON | IEXTEN);
    raw.c_iflag = raw.c_iflag & ~(ICRNL | IXON);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    _ = pal.tcsetattr(0, TCSANOW, @ptrCast(*void, &raw));

    _ = pal.signal(SIGINT, onSigint);
    st.entered = true;
}

// `Console.leaveRaw_fn`: restore the termios saved by `enterRaw`. A no-op when
// raw mode is not active, so the caller can call it unconditionally.
pub fn leaveRaw(state: *void) void {
    var st: *ConsoleLinState = @ptrCast(*ConsoleLinState, state);
    if (!st.entered) return;
    _ = pal.tcsetattr(0, TCSANOW, @ptrCast(*void, &st.saved));
    st.entered = false;
}

// --- vtable implementation: key input -------------------------------------

// One byte from stdin, or -1 when none is ready (read is non-blocking, VMIN=0).
fn pullByte() i32 {
    var b: [1]u8 = undefined;
    var n: i32 = pal.read(0, @ptrCast([*]u8, &b[0]), 1);
    if (n == 1) return @intCast(i32, b[0]);
    return -1;
}

// `Console.readKey_fn`: return the next key. Non-blocking (VMIN=0): a
// `read(2)` returning no byte yields `.none`. A pending SIGINT takes priority
// and yields `.sigint` (sticky).
//
// ESC handling is a persistent parse state machine carried in `st` (not a
// one-shot local), so a sequence split across separate `readKey` calls still
// resolves. `esc_phase` 1 = ESC seen (awaiting `[`), 2 = ESC `[` seen
// (awaiting the final byte). If the final byte is `A/B/C/D` the arrow is
// returned; a byte that follows ESC but is not part of an arrow is preserved in
// `pending_byte` and returned as its own key on the next call (so `ESC` `CR`
// yields `.esc` then `.enter`, never swallowing the CR). A lone/incomplete ESC
// resolves to `.esc` once `ESC_WINDOW_MS` elapses with no further byte; while
// the sequence is open, `readKey` still returns `.none` when idle (no stall).
// A fresh CR/LF -> `.enter`; any other fresh byte -> `.char`.
pub fn readKey(state: *void) Key {
    var st: *ConsoleLinState = @ptrCast(*ConsoleLinState, state);
    if (g_sigint != 0) return Key{ .sigint = {} };

    while (true) {
        // A preserved escape tail is returned first, as its own key (it may
        // itself be an ESC, starting a new sequence).
        if (st.pending_valid) {
            var pb: u8 = st.pending_byte;
            st.pending_valid = false;
            if (pb == ESC) {
                st.esc_phase = 1;
                st.esc_start = std.time.ticksMs();
                continue;
            }
            if (pb == '\r' or pb == '\n') return Key{ .enter = {} };
            return Key{ .char = pb };
        }

        // Continue an open escape sequence.
        if (st.esc_phase != 0) {
            var b: i32 = pullByte();
            if (b < 0) {
                if (std.time.ticksMs() - st.esc_start >= ESC_WINDOW_MS) {
                    st.esc_phase = 0;
                    return Key{ .esc = {} };
                }
                return Key{ .none = {} };
            }
            var c: u8 = @intCast(u8, b);
            if (st.esc_phase == 1) {
                if (c == 91) { // '['
                    st.esc_phase = 2;
                    st.esc_start = std.time.ticksMs();
                    continue;
                }
                st.esc_phase = 0;
                st.pending_byte = c;
                st.pending_valid = true;
                return Key{ .esc = {} };
            }
            // esc_phase == 2: the final byte of an `ESC [ x` sequence.
            st.esc_phase = 0;
            if (c == 65) return Key{ .up = {} };    // 'A'
            if (c == 66) return Key{ .down = {} };  // 'B'
            if (c == 67) return Key{ .right = {} }; // 'C'
            if (c == 68) return Key{ .left = {} };  // 'D'
            st.pending_byte = c;
            st.pending_valid = true;
            return Key{ .esc = {} };
        }

        // Idle: pull a fresh byte. ESC arms the sequence and the loop advances
        // immediately (contiguous `ESC [ A` resolves in one call).
        var b2: i32 = pullByte();
        if (b2 < 0) return Key{ .none = {} };
        var c2: u8 = @intCast(u8, b2);
        if (c2 == ESC) {
            st.esc_phase = 1;
            st.esc_start = std.time.ticksMs();
            continue;
        }
        if (c2 == '\r' or c2 == '\n') return Key{ .enter = {} };
        return Key{ .char = c2 };
    }
}

// --- vtable implementation: output ----------------------------------------

// `Console.writeStr_fn`: write the bytes to stdout (fd 1). The CLI uses this
// for the startup metadata line and the CR-Prefixed status line.
pub fn writeStr(state: *void, s: []const u8) void {
    _ = state;
    std.io.write(s);
}

// `Console.clear_fn`: ANSI clear + cursor home `\033[2J\033[H` to stdout.
pub fn clear(state: *void) void {
    _ = state;
    var s: []const u8 = "\x1b[2J\x1b[H";
    std.io.write(s);
}

// Decimal digits of `v` (0..65535), no sign. Returns the digit count.
fn writeDec(buf: []u8, v_in: u32) usize {
    var v: u32 = v_in;
    if (v == 0) {
        buf[0] = '0';
        return 1;
    }
    var tmp: [10]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = tmp[n - 1 - i];
    }
    return n;
}

// `Console.setCursor_fn`: ANSI cursor position `\033[<row+1>;<col+1>H` to
// stdout. `row`/`col` are 0-based; the ANSI sequence is 1-based, so both are
// incremented.
pub fn setCursor(state: *void, row: u16, col: u16) void {
    _ = state;
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    buf[n] = ESC;
    n += 1;
    buf[n] = '[';
    n += 1;
    n += writeDec(buf[n..], @intCast(u32, row) + 1);
    buf[n] = ';';
    n += 1;
    n += writeDec(buf[n..], @intCast(u32, col) + 1);
    buf[n] = 'H';
    n += 1;
    std.io.write(buf[0..n]);
}

// `Console.cursorShow_fn`: ANSI cursor show/hide `\033[?25h` / `\033[?25l`.
pub fn cursorShow(state: *void, show: bool) void {
    _ = state;
    if (show) {
        var s: []const u8 = "\x1b[?25h";
        std.io.write(s);
    } else {
        var s: []const u8 = "\x1b[?25l";
        std.io.write(s);
    }
}

// `Console.width_fn`: terminal columns from ioctl(TIOCGWINSZ); 80 when the
// ioctl fails or reports zero.
pub fn width(state: *void) u16 {
    _ = state;
    var ws: pal.Winsize = undefined;
    if (pal.ioctl(0, TIOCGWINSZ, @ptrCast(*void, &ws)) != 0) return 80;
    if (ws.ws_col == 0) return 80;
    return ws.ws_col;
}

// `Console.height_fn`: terminal rows from ioctl(TIOCGWINSZ); 24 when the ioctl
// fails or reports zero.
pub fn height(state: *void) u16 {
    _ = state;
    var ws: pal.Winsize = undefined;
    if (pal.ioctl(0, TIOCGWINSZ, @ptrCast(*void, &ws)) != 0) return 24;
    if (ws.ws_row == 0) return 24;
    return ws.ws_row;
}

