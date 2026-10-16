// console_test.zig — pty unit test for the Linux raw-console backend (M5 T2).
//
// Run under a pty (`script`) with the harness feeding one key after the backend
// has entered raw mode. Asserts, in order:
//   1. `termEnterRaw` really disabled echo/canonical mode (ECHO and ICANON
//      cleared, VMIN=VTIME=0) as read back from the live termios;
//   2. a key written through the pty is read back by `readKey` (non-blocking,
//      no echo — the harness also asserts the byte never appeared in the pty
//      output, i.e. it was not echoed);
//   3. an external SIGINT is surfaced as `Key.sigint` by the handler;
//   4. `termLeaveRaw` restored the original termios (c_iflag/c_lflag/c_cc).
//
// The harness sends the key only after the program creates a ready marker, so
// the key is written after raw mode is active — no startup/timing race.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed_v98/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/console_test.zig
//   sh out/build_target.sh linux out/prog
//   rm -f /tmp/z9play_console.ready
//   ( while [ ! -e /tmp/z9play_console.ready ]; do sleep 0.01; done; printf '@'; sleep 5 ) \
//       | script -qec out/prog /dev/null
// The full gate is tests/tier_console.sh.

const std = @import("std");
const filemod = @import("std_file");
const con = @import("../platform/console_linux.zig");

@cInclude("<termios.h>");
@cInclude("<signal.h>");

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

pub fn main() void {
    var orig: Termios = undefined;
    _ = tcgetattr(0, @ptrCast(*void, &orig));

    var st: con.TermState = undefined;
    con.termEnterRaw(&st);

    // 1. Raw mode is live: echo and canonical processing are off, reads poll.
    var raw: Termios = undefined;
    _ = tcgetattr(0, @ptrCast(*void, &raw));
    if ((raw.c_lflag & ECHO) != 0) fail("echo not disabled");
    if ((raw.c_lflag & ICANON) != 0) fail("icanon not disabled");
    if (raw.c_cc[VMIN] != 0) fail("vmin not 0");
    if (raw.c_cc[VTIME] != 0) fail("vtime not 0");

    touchMarker();

    // 2. Read the key the harness writes after the marker (non-blocking poll).
    var got_key: i32 = 0;
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        if (con.readKey()) |k| {
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
        }
        std.io.sleepMs(1);
    }
    if (got_key == 0) fail("key not read back");

    // 3. External SIGINT is surfaced as Key.sigint by the handler.
    _ = raise(SIGINT);
    var got_sig: i32 = 0;
    i = 0;
    while (i < 2000) : (i += 1) {
        if (con.readKey()) |k| {
            switch (k) {
                .sigint => {
                    got_sig = 1;
                    break;
                },
                else => {},
            }
        }
        std.io.sleepMs(1);
    }
    if (got_sig == 0) fail("sigint not surfaced");

    // 4. Termios restored byte-for-byte on the fields raw mode touched.
    con.termLeaveRaw(&st);
    var back: Termios = undefined;
    _ = tcgetattr(0, @ptrCast(*void, &back));
    if (back.c_lflag != orig.c_lflag) fail("c_lflag not restored");
    if (back.c_iflag != orig.c_iflag) fail("c_iflag not restored");
    if (back.c_cc[VMIN] != orig.c_cc[VMIN]) fail("vmin not restored");
    if (back.c_cc[VTIME] != orig.c_cc[VTIME]) fail("vtime not restored");

    var p: []const u8 = "console_test: PASS echo=off key=64 sigint=1 restored=1\n";
    std.io.write(p);
    std.os.exit(0);
}
