// win9x_console_probe.zig — honest raw-mode restore probe for the Win9x console
// backend (M6 Task 4 (c)).
//
// Built for `-osw` (mingw) and run under Wine inside a pty (`script`), so Wine
// exposes a real console handle. The probe reads the input console mode with
// GetConsoleMode, drives the backend's `enterRaw` -> `leaveRaw`, and reads the
// mode back. It prints the before/raw/after DWORDs and three booleans:
//
//   entered=1       GetConsoleMode succeeded and enterRaw saved/applied a mode
//   raw_changed=1   line/echo/processed-input bits were actually cleared
//   restored=1      leaveRaw put back the exact original DWORD
//
// The probe reports `nocons=1` and exits 2 when Wine provides no console handle
// (in that case the tier must not fake a pass). The tier asserts the PASS line
// after stripping the ANSI cursor noise Wine emits on a console.
//
// Build (tier does this through scripts/win32_cross/cross_build_run.sh):
//   /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 --output-dir out \
//       examples/z98/z9play/tests/win9x_console_probe.zig
//   i686-w64-mingw32-gcc -std=c89 -m32 ... out/*.o zig_runtime.c zig_pal.c
//   -lwsock32 -o out/probe.exe
// Run under a pty:  script -qec "exec wine out/probe.exe" /dev/null

const std = @import("std");
const cwin = @import("../platform/console_win9x.zig");
const pal = @import("../platform/console_win9x_pal.zig");

const STD_INPUT_HANDLE: i32 = -10;
const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
const ENABLE_LINE_INPUT: u32 = 0x0002;
const ENABLE_ECHO_INPUT: u32 = 0x0004;

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn writeU32(v_in: u32) void {
    var v: u32 = v_in;
    if (v == 0) {
        var z: []const u8 = "0";
        std.io.write(z);
        return;
    }
    var tmp: [10]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var out: [10]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = tmp[n - 1 - i];
    std.io.write(out[0..n]);
}

fn writeBool(on: bool) void {
    if (on) {
        var t: []const u8 = "1";
        std.io.write(t);
    } else {
        var f: []const u8 = "0";
        std.io.write(f);
    }
}

pub fn main() void {
    var h: *void = pal.GetStdHandle(STD_INPUT_HANDLE);
    var before: u32 = 0;
    if (pal.GetConsoleMode(h, &before) == 0) {
        var msg: []const u8 = "win9x_console_probe: nocons=1\n";
        writeText(msg);
        std.os.exit(2);
        return;
    }

    var st: cwin.ConsoleWinState = undefined;
    cwin.enterRaw(@ptrCast(*void, &st));
    var entered: bool = st.entered;

    var raw: u32 = 0;
    var raw_ok: bool = false;
    if (pal.GetConsoleMode(h, &raw) != 0) {
        var cleared: u32 = raw & (ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
        raw_ok = cleared == 0 and raw != before;
    }

    cwin.leaveRaw(@ptrCast(*void, &st));

    var after: u32 = 0;
    var restored: bool = false;
    if (pal.GetConsoleMode(h, &after) != 0) {
        restored = after == before;
    }

    var p: []const u8 = "win9x_console_probe: entered=";
    writeText(p);
    writeBool(entered);
    var c: []const u8 = ",raw_changed=";
    writeText(c);
    writeBool(raw_ok);
    var r: []const u8 = ",restored=";
    writeText(r);
    writeBool(restored);
    var nl: []const u8 = "\n";
    writeText(nl);

    var m: []const u8 = "win9x_console_probe: modes before=";
    writeText(m);
    writeU32(before);
    var q: []const u8 = " raw=";
    writeText(q);
    writeU32(raw);
    var a: []const u8 = " after=";
    writeText(a);
    writeU32(after);
    var nl2: []const u8 = "\n";
    writeText(nl2);

    if (!raw_ok or !restored) {
        std.os.exit(1);
        return;
    }
    std.os.exit(0);
}
