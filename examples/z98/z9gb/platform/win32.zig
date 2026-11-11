// win32.zig — windowed Win32 platform backend (P3 Task 5).
//
// Wires the P3 std modules into the P1 five-field Platform table: DirectDraw
// presentation, DirectInput polling (keyboard fallback included), and
// DirectSound output at 44,100 Hz stereo. Every Win32/COM handle stays behind
// the opaque `state` pointer; this file exports only `platformWin32`.
//
// Pacing lives in main.zig; this backend owns the `timeBeginPeriod(1)` /
// `timeEndPeriod(1)` pairing around the platform lifetime so the Win9x
// scheduler tick is reduced while the frame loop sleeps.
//
// Pure Z98 free functions only; no heap and no stack-backed platform state
// (one module-scope Win32State).

@cInclude("<windows.h>");
@cInclude("<mmsystem.h>");

const std = @import("std");
const backend = @import("backend.zig");
const ddraw = @import("std_ddraw");
const dinput = @import("std_dinput");
const dsound = @import("std_dsound");

const FRAME_W: u32 = 160;
const FRAME_H: u32 = 144;
const AUDIO_RATE: u32 = 44100;
const AUDIO_CHANNELS: u16 = 2;
const TIMER_PERIOD_MS: u32 = 1;

// winmm, statically pinned (Win9x supplies both in winmm.dll). The return code
// is TIMERR_NOERROR (0) on success; failure is ignored and the bounded spin
// tail alone keeps the frame loop honest.
extern "stdcall" fn timeBeginPeriod(uPeriod: u32) u32;
extern "stdcall" fn timeEndPeriod(uPeriod: u32) u32;

const Win32State = struct {
    ddraw: *ddraw.Ddraw,
    dinput: *dinput.Dinput,
    dsound: *dsound.Dsound,
    timer_started: bool,
};

// Open flag lives outside the state (same pattern as std_ddraw/std_dinput/
// std_dsound): it is explicitly false before any callback reads it, so the
// undefined state storage is never consulted before win32Open fills it.
var g_state: Win32State = undefined;
var g_opened: bool = false;

fn win32Open(state: *void, width: u32, height: u32, scale: u32) bool {
    var s = @ptrCast(*Win32State, state);
    if (g_opened) return false;
    if (width != FRAME_W or height != FRAME_H) return false;
    if (scale < 1 or scale > 4) return false;

    const d = ddraw.ddrawOpen("z9gb", width, height, scale) catch return false;
    const window = ddraw.ddrawWindow(d);
    const di = dinput.dinputOpen(window) catch {
        ddraw.ddrawClose(d);
        return false;
    };
    const ds = dsound.dsoundOpen(window, AUDIO_RATE, AUDIO_CHANNELS) catch {
        dinput.dinputClose(di);
        ddraw.ddrawClose(d);
        return false;
    };

    s.ddraw = d;
    s.dinput = di;
    s.dsound = ds;
    s.timer_started = timeBeginPeriod(TIMER_PERIOD_MS) == 0;
    g_opened = true;

    const dkind: u8 = dinput.dinputBackendKind(di);
    const skind: u8 = dsound.dsoundBackendKind(ds);
    std.io.write("z9gb: input=");
    if (dkind == 1) {
        std.io.write("dinput8");
    } else {
        std.io.write("fallback");
    }
    std.io.write(" audio=");
    if (skind == 1) {
        std.io.write("dsound");
    } else {
        std.io.write("waveout");
    }
    std.io.write("\n");
    return true;
}

fn win32Present(state: *void, frame: []const u32) void {
    var s = @ptrCast(*Win32State, state);
    if (!g_opened) return;
    _ = ddraw.ddrawPresent(s.ddraw, frame);
}

fn win32Poll(state: *void, input: *backend.InputState) bool {
    var s = @ptrCast(*Win32State, state);
    input.buttons = 0;
    input.quit = false;
    if (!g_opened) return false;

    var consumed: bool = false;
    var ev: ddraw.DdrawEvent = undefined;
    while (ddraw.ddrawPoll(s.ddraw, &ev)) {
        consumed = true;
        if (ev.close) input.quit = true;
    }

    var b: dinput.Buttons = undefined;
    dinput.dinputPoll(s.dinput, &b);
    var bits: u8 = 0;
    if (b.right) bits |= 0x01;
    if (b.left) bits |= 0x02;
    if (b.up) bits |= 0x04;
    if (b.down) bits |= 0x08;
    if (b.a) bits |= 0x10;
    if (b.b) bits |= 0x20;
    if (b.select) bits |= 0x40;
    if (b.start) bits |= 0x80;
    input.buttons = bits;
    if (b.quit) input.quit = true;
    return consumed;
}

fn win32Audio(state: *void, samples: []const i16) void {
    var s = @ptrCast(*Win32State, state);
    if (!g_opened) return;
    _ = dsound.dsoundWrite(s.dsound, samples);
}

fn win32Close(state: *void) void {
    var s = @ptrCast(*Win32State, state);
    if (!g_opened) return;
    dsound.dsoundClose(s.dsound);
    dinput.dinputClose(s.dinput);
    ddraw.ddrawClose(s.ddraw);
    if (s.timer_started) _ = timeEndPeriod(TIMER_PERIOD_MS);
    g_opened = false;
}

var g_platform: backend.Platform = backend.Platform{
    .state = @ptrCast(*void, &g_state),
    .open_fn = win32Open,
    .present_fn = win32Present,
    .poll_fn = win32Poll,
    .audio_fn = win32Audio,
    .close_fn = win32Close,
};

pub fn platformWin32() *backend.Platform {
    return &g_platform;
}
