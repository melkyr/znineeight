// std_ddraw.zig — Z98 std lib L2: raw 32-bit DirectDraw pixel surface.
//
// Public API (P3 Task 1): DdrawError/DdrawEvent/Ddraw plus ddrawOpen,
// ddrawPresent, ddrawPoll, ddrawSetScale, ddrawWindow, ddrawClose. Pixels are
// 0x00RRGGBB u32 lane values for a fixed src_w x src_h source; integer scales
// 1..4 only. The Win32 window/COM/DirectDraw7 implementation lives in
// std_ddraw_pal.zig.
//
// Ddraw is opaque: the public type holds one pointer to the private
// module-scope DdrawState, so no HWND, COM pointer, or GUID is reachable
// through the app-facing type. There is exactly one static DdrawState and one
// static Ddraw; ddrawOpen fails if either is already open. No heap and no
// stack-backed surface state.

const pal = @import("std_ddraw_pal.zig");

pub const DdrawError = error{ OpenFailed, SurfaceFailed, NotSupported };

pub const DdrawEvent = struct {
    kind: u8,
    key: u16,
    close: bool,
};

const DdrawState = struct {
    st: pal.State,
    src_w: u32,
    src_h: u32,
    scale: u32,
};

pub const Ddraw = struct { opaque: *DdrawState };

var g_state: DdrawState = undefined;
var g_ddraw: Ddraw = undefined;
var g_opened: bool = false;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

pub fn ddrawOpen(title: []const u8, src_w: u32, src_h: u32, scale: u32) DdrawError!*Ddraw {
    if (g_opened) return error.OpenFailed;
    if (src_w == 0 or src_h == 0) return error.NotSupported;
    if (src_w > pal.max_src_w or src_h > pal.max_src_h) return error.NotSupported;
    if (scale < 1 or scale > 4) return error.NotSupported;

    const s = &g_state;
    s.src_w = src_w;
    s.src_h = src_h;
    s.scale = scale;
    const rc = pal.open(title, src_w, src_h, scale, &s.st);
    if (rc == 2) return error.SurfaceFailed;
    if (rc != 0) return error.OpenFailed;

    g_opened = true;
    g_ddraw.opaque = s;
    return &g_ddraw;
}

pub fn ddrawPresent(d: *Ddraw, pixels: []const u32) bool {
    if (!g_opened) return false;
    const s = d.opaque;
    const need: usize = @intCast(usize, s.src_w) * @intCast(usize, s.src_h);
    if (pixels.len < need) return false;
    return pal.present(&s.st, pixels, s.scale);
}

pub fn ddrawPoll(d: *Ddraw, ev: *DdrawEvent) bool {
    if (!g_opened) return false;
    const s = d.opaque;
    var raw: pal.Event = undefined;
    if (!pal.poll(&s.st, &raw)) return false;
    ev.kind = raw.kind;
    ev.key = raw.key;
    ev.close = raw.close;
    return true;
}

pub fn ddrawSetScale(d: *Ddraw, scale: u32) bool {
    if (!g_opened) return false;
    if (scale < 1 or scale > 4) return false;
    const s = d.opaque;
    if (!pal.setScale(&s.st, scale)) return false;
    s.scale = scale;
    return true;
}

pub fn ddrawWindow(d: *Ddraw) *void {
    if (!g_opened) return nullVoid();
    return pal.window(&d.opaque.st);
}

pub fn ddrawClose(d: *Ddraw) void {
    if (!g_opened) return;
    const s = d.opaque;
    pal.close(&s.st);
    g_opened = false;
}
