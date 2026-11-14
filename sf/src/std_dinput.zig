// std_dinput.zig — Z98 std lib L2: DirectInput8 keyboard + gamepad with a
// GetAsyncKeyState keyboard fallback.
//
// Public API (P3 Task 2): DinputError, Buttons, Dinput plus dinputOpen,
// dinputPoll, dinputClose, dinputMapKeys, dinputBackendKind. Dinput is opaque:
// the public type holds one pointer to the private module-scope DinputState, so
// no HWND, COM pointer, or GUID is reachable through the app-facing type. There
// is exactly one static DinputState and one static Dinput; dinputOpen fails if
// either is already open. No heap and no stack-backed device state.
//
// dinputMapKeys is the no-Win32 test seam: it maps a synthetic 256-byte key
// array (DInput keyboard state layout) into Buttons. dinputBackendKind returns
// 1 for the DInput8 backend and 2 for the GetAsyncKeyState fallback. The
// Win32/COM implementation lives in std_dinput_pal.zig.

const pal = @import("std_dinput_pal.zig");

pub const DinputError = error{ OpenFailed, NotSupported };

pub const Buttons = struct {
    right: bool,
    left: bool,
    up: bool,
    down: bool,
    a: bool,
    b: bool,
    select: bool,
    start: bool,
    quit: bool,
};

const DinputState = struct {
    st: pal.State,
};

pub const Dinput = struct { opaque: *DinputState };

var g_state: DinputState = undefined;
var g_dinput: Dinput = undefined;
var g_opened: bool = false;

fn zeroButtons(b: *Buttons) void {
    b.right = false;
    b.left = false;
    b.up = false;
    b.down = false;
    b.a = false;
    b.b = false;
    b.select = false;
    b.start = false;
    b.quit = false;
}

fn copyButtons(out: *Buttons, raw: *const pal.Buttons) void {
    out.right = raw.right;
    out.left = raw.left;
    out.up = raw.up;
    out.down = raw.down;
    out.a = raw.a;
    out.b = raw.b;
    out.select = raw.select;
    out.start = raw.start;
    out.quit = raw.quit;
}

pub fn dinputOpen(window: *void) DinputError!*Dinput {
    if (g_opened) return error.OpenFailed;
    const s = &g_state;
    const kind = pal.open(window, &s.st);
    if (kind != pal.backend_dinput8 and kind != pal.backend_fallback) {
        return error.OpenFailed;
    }
    g_opened = true;
    g_dinput.opaque = s;
    return &g_dinput;
}

pub fn dinputPoll(d: *Dinput, out: *Buttons) void {
    if (!g_opened) {
        zeroButtons(out);
        return;
    }
    const s = d.opaque;
    var raw: pal.Buttons = undefined;
    pal.poll(&s.st, &raw);
    copyButtons(out, &raw);
}

pub fn dinputClose(d: *Dinput) void {
    if (!g_opened) return;
    const s = d.opaque;
    pal.close(&s.st);
    g_opened = false;
}

pub fn dinputMapKeys(keys: []const u8, out: *Buttons) void {
    var raw: pal.Buttons = undefined;
    pal.mapKeys(keys, &raw);
    copyButtons(out, &raw);
}

pub fn dinputPollRaw(d: *Dinput, out: []u8) bool {
    if (!g_opened) return false;
    const s = d.opaque;
    return pal.pollRaw(&s.st, out);
}

pub fn dinputBackendKind(d: *const Dinput) u8 {
    if (!g_opened) return 0;
    return d.opaque.st.backend;
}
