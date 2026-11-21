// std_dsound.zig — Z98 std lib L2: DirectSound output with a WinMM waveOut
// fallback.
//
// Public API (P3 Task 3): DsoundError, Dsound plus dsoundOpen, dsoundWrite,
// dsoundQueued, dsoundBackendKind, dsoundClose. Dsound is opaque: the public
// type holds one pointer to the private module-scope DsoundState, so no HWND,
// COM pointer, or GUID is reachable through the app-facing type. There is
// exactly one static DsoundState and one static Dsound; dsoundOpen fails if
// either is already open. No heap and no stack-backed device state.
//
// dsoundWrite is nonblocking: it returns the number of i16 elements accepted,
// which may be fewer than offered, and never sleeps. dsoundBackendKind returns
// 1 for DirectSound and 2 for the waveOut fallback. The Win32/COM
// implementation lives in std_dsound_pal.zig.

const pal = @import("std_dsound_pal.zig");

pub const DsoundError = error{ OpenFailed, BufferFailed, Lost };

const DsoundState = struct {
    st: pal.State,
};

pub const Dsound = struct { opaque: *DsoundState };

var g_state: DsoundState = undefined;
var g_dsound: Dsound = undefined;
var g_opened: bool = false;

pub fn dsoundOpen(window: *void, sample_rate: u32, channels: u16) DsoundError!*Dsound {
    if (g_opened) return error.OpenFailed;
    const s = &g_state;
    const rc = pal.open(window, sample_rate, channels, &s.st);
    if (rc == 1) return error.OpenFailed;
    if (rc == 2) return error.BufferFailed;
    if (rc == 3) return error.Lost;
    if (rc != 0) return error.OpenFailed;
    g_opened = true;
    g_dsound.opaque = s;
    return &g_dsound;
}

pub fn dsoundWrite(d: *Dsound, samples: []const i16) usize {
    if (!g_opened) return 0;
    return pal.write(&d.opaque.st, samples);
}

pub fn dsoundQueued(d: *const Dsound) usize {
    if (!g_opened) return 0;
    return pal.queued(&d.opaque.st);
}

pub fn dsoundBackendKind(d: *const Dsound) u8 {
    if (!g_opened) return 0;
    return d.opaque.st.backend;
}

pub fn dsoundClose(d: *Dsound) void {
    if (!g_opened) return;
    pal.close(&d.opaque.st);
    g_opened = false;
}
