// console_linux.zig — Linux raw-console key input for z9play (M5 Task 2).
//
// Provides the raw terminal mode + non-blocking, non-echoing single-key reader
// the M5 CLI playback loop drives (space / '+' / '-' / 'q' / Ctrl-C). It is
// Linux-only (termios via `extern "c"`, SIGINT mapped to a quit key); the Win9x
// backend lands in M6. The CLI restores the terminal in its normal flow via
// `termLeaveRaw`.
//
// Raw mode (enter): the caller's original termios is saved in `TermState.saved`
// and the working copy clears ECHO/ECHONL, ICANON and IEXTEN (so keys arrive one
// at a time, un-echoed, with no extended processing) and clears ICRNL/IXON (so
// CR stays CR and Ctrl-S/Q are ordinary bytes). ISIG is deliberately kept, so
// Ctrl-C is delivered as SIGINT (see below), matching the plan's "keys: q /
// Ctrl-C quit". VMIN=0, VTIME=0 makes `read(2)` return immediately — the
// non-blocking contract of `readKey`. OPOST/`c_oflag` is deliberately left
// unchanged: the M5 CLI only uses `\r` for the status line and `\n` elsewhere,
// and can rely on the default ONLCR mapping.
//
// SIGINT handling: `signal(SIGINT, onSigint)` installs a handler that only sets
// a sticky module flag (`g_sigint`). `readKey` checks the flag and returns
// `.sigint`; the CLI maps that to a clean quit and the terminal is restored via
// `termLeaveRaw`. This is why ISIG stays enabled — Ctrl-C must surface as
// SIGINT, not as the literal byte 0x03.
//
// `leave`: `tcsetattr` writes back the saved termios byte-for-byte, undoing
// every change above.
//
// Pure Z98: free functions only, strict `@intCast`, numeric termios constants
// (no dependence on the termios.h macros at the Zig level); the C externs live
// in console_linux_pal.zig (see there for the split rationale).

const std = @import("std");
const pal = @import("console_linux_pal.zig");

// Prototypes for the externs in console_linux_pal.zig. Z98 emits no extern
// prototypes, so gcc sees only these headers' declarations.
@cInclude("<termios.h>");
@cInclude("<unistd.h>");
@cInclude("<signal.h>");

// One key event. `char` is one raw byte (no UTF-8/escape decoding — the M5 CLI
// only needs ASCII keys); `sigint` is Ctrl-C (or an external SIGINT).
pub const Key = union(enum) {
    char: u8,
    sigint,
};

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

// Caller-owned terminal state: the original termios plus whether raw mode is
// currently in effect (so `termLeaveRaw` is safe to call unconditionally).
pub const TermState = struct {
    saved: Termios,
    entered: bool,
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

// Set by the SIGINT handler; sticky until the next `termEnterRaw`. A byte is
// enough (the handler is async-signal-safe: one store).
var g_sigint: u8 = 0;

fn onSigint(sig: i32) void {
    _ = sig;
    g_sigint = 1;
}

// Enter raw mode on stdin (fd 0), saving the original settings into `state`.
// Idempotent from the caller's viewpoint: a second call re-saves the (already
// raw) termios, so `termLeaveRaw` still restores whatever termios was current.
// When stdin is not a tty (tcgetattr fails, e.g. a redirected run) raw mode is
// not entered and `termLeaveRaw` becomes a no-op, so a bogus termios is never
// written back.
pub fn termEnterRaw(state: *TermState) void {
    g_sigint = 0;
    state.entered = false;
    if (pal.tcgetattr(0, @ptrCast(*void, &state.saved)) != 0) return;

    var raw: Termios = state.saved;
    raw.c_lflag = raw.c_lflag & ~(ECHO | ECHONL | ICANON | IEXTEN);
    raw.c_iflag = raw.c_iflag & ~(ICRNL | IXON);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    _ = pal.tcsetattr(0, TCSANOW, @ptrCast(*void, &raw));

    _ = pal.signal(SIGINT, onSigint);
    state.entered = true;
}

// Restore the termios saved by `termEnterRaw`. A no-op when raw mode is not
// active, so the CLI can call it unconditionally on every exit path.
pub fn termLeaveRaw(state: *TermState) void {
    if (!state.entered) return;
    _ = pal.tcsetattr(0, TCSANOW, @ptrCast(*void, &state.saved));
    state.entered = false;
}

// Return the next key, or null when none is ready yet. Non-blocking (VMIN=0):
// a `read(2)` that returns no byte yields null. A pending SIGINT takes priority
// and yields `.sigint` (sticky); an interrupted read that then observes the
// flag also yields `.sigint`.
pub fn readKey() ?Key {
    if (g_sigint != 0) return Key{ .sigint = {} };
    var b: [1]u8 = undefined;
    var n: i32 = pal.read(0, @ptrCast([*]u8, &b[0]), 1);
    if (n == 1) return Key{ .char = b[0] };
    if (n < 0 and g_sigint != 0) return Key{ .sigint = {} };
    return null;
}
