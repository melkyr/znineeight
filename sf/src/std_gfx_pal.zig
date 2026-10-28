// std_gfx_pal.zig — Z98 std_gfx std-side PAL: Win9x window + DirectDraw7
// windowed present path + hand-written COM vtables + clipboard.
//
// Contract (P4-M1): window class + PeekMessageA pump; DirectDrawCreate ->
// QueryInterface(IID_IDirectDraw7) -> SetCooperativeLevel(DDSCL_NORMAL) ->
// primary + 640x480 offscreen DDSCAPS_OFFSCREENPLAIN (+ best-effort clipper);
// GDI GetDC/SYSTEM_FIXED_FONT/TextOutA into the offscreen; Blt(primary <- back,
// DDBLT_WAIT). No Flip, no back buffer, no CoInitialize.
//
// Every COM call goes through a hand-written vtable struct whose fields are
// `extern "stdcall"` fn-pointer TYPES (the QUICK_REF convention rule). The
// unused slots are also `extern "stdcall" fn() void` so the field indices
// match ddraw.h exactly AND a future caller keeps the Win32 convention; a
// wrong slot would silently call another method. Slot order was taken from
// /usr/i686-w64-mingw32/include/ddraw.h (IDirectDraw7 at :1798,
// IDirectDrawSurface7 at :2503, IDirectDrawClipper at :1335).
//
// The C prototypes for the Win32/GDI/DDraw symbols come from <windows.h> and
// <ddraw.h>; Z98 emits no extern prototypes. The GUID is a local 16-byte value
// (the same bytes DEFINE_GUID(IID_IDirectDraw7) expands to) so the exe does not
// need the dxguid data library.

const arena_mod = @import("std_arena.zig");
const io = @import("std_io.zig");

@cInclude("<windows.h>");
@cInclude("<ddraw.h>");

// --- constants (winuser.h / wingdi.h / ddraw.h numeric values) --------------
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const CW_USEDEFAULT: i32 = -2147483648;
const SW_SHOW: i32 = 5;
const SW_MINIMIZE: i32 = 6;
const SW_RESTORE: i32 = 9;
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOACTIVATE: u32 = 0x0010;
const WM_DESTROY: u32 = 0x0002;
const WM_CLOSE: u32 = 0x0010;
const WM_QUIT: u32 = 0x0012;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_CHAR: u32 = 0x0102;
const WM_MOUSEMOVE: u32 = 0x0200;
const WM_LBUTTONDOWN: u32 = 0x0201;
const WM_LBUTTONUP: u32 = 0x0202;
const WM_MOUSEWHEEL: u32 = 0x020A;
const PM_REMOVE: u32 = 0x0001;
const VK_SHIFT: i32 = 0x10;
const VK_CONTROL: i32 = 0x11;
const IDC_ARROW: u32 = 32512;
const SYSTEM_FIXED_FONT: i32 = 16;
const BLACK_BRUSH: i32 = 4;
const TRANSPARENT: i32 = 1;
const SRCAND: u32 = 0x008800C6;
const SRCPAINT: u32 = 0x00EE0086;
const CF_TEXT: u32 = 1;
const GMEM_MOVEABLE: u32 = 0x0002;
const DDSCL_NORMAL: u32 = 0x00000008;
const DDSCAPS_PRIMARYSURFACE: u32 = 0x00000200;
const DDSCAPS_OFFSCREENPLAIN: u32 = 0x00000040;
const DDSD_CAPS: u32 = 0x00000001;
const DDSD_HEIGHT: u32 = 0x00000002;
const DDSD_WIDTH: u32 = 0x00000004;
const DDBLT_WAIT: u32 = 0x01000000;
const OFFSCREEN_W: u32 = 640;
const OFFSCREEN_H: u32 = 480;
const WHEEL_DELTA: i32 = 120;
const WHEEL_LINES: i32 = 3;
const GLYPH_FIRST: u32 = 32;
const GLYPH_LAST: u32 = 126;
const GLYPH_COUNT: u32 = GLYPH_LAST - GLYPH_FIRST + 1;
const ATLAS_COLORS: u32 = 16;
const S_OK: u32 = 0;

// Event kinds, matching std_gfx.EventKind's declaration order.
const EK_KEY_DOWN: u8 = 0;
const EK_KEY_UP: u8 = 1;
const EK_MOUSE_MOVE: u8 = 2;
const EK_MOUSE_DOWN: u8 = 3;
const EK_MOUSE_UP: u8 = 4;
const EK_WHEEL: u8 = 5;
const EK_RESIZE: u8 = 6;
const EK_CLOSE: u8 = 7;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn isNull(p: *void) bool {
    return @ptrToInt(p) == 0;
}

fn rgb(r: u32, g: u32, b: u32) u32 {
    return (r & 255) | ((g & 255) << 8) | ((b & 255) << 16);
}

// Editor 16-color palette (dark theme). The DirectDraw surfaces are 32-bit;
// these 16 RGB values are the app's whole color vocabulary (the glyph atlas
// bakes them once at open). Index roles are stable for z9edit: 0 bg, 1 panel
// bg, 2 fg, 3 comment, 4 fill bg, 5 green, 6 brown, 7 status bg, 8 alt bg,
// 9-12 syntax accents, 13 accent/selection, 14 warning/gold, 15 bright.
// Unknown indices wrap (idx & 15).
fn paletteRgb(idx: u8) u32 {
    const PAL: [16]u32 = [16]u32{
        rgb(0x0b, 0x0f, 0x14),
        rgb(0x1f, 0x3a, 0x5f),
        rgb(0xc9, 0xd1, 0xd9),
        rgb(0x6e, 0x76, 0x81),
        rgb(0x3a, 0x1f, 0x2b),
        rgb(0x2d, 0x5a, 0x3d),
        rgb(0x5a, 0x3d, 0x1f),
        rgb(0x8b, 0x94, 0x9e),
        rgb(0x16, 0x1b, 0x22),
        rgb(0x79, 0xc0, 0xff),
        rgb(0x56, 0xd3, 0x64),
        rgb(0x7e, 0xe7, 0x87),
        rgb(0xff, 0x7b, 0x72),
        rgb(0x38, 0x8b, 0xfd),
        rgb(0xe3, 0xb3, 0x41),
        rgb(0xff, 0xff, 0xff),
    };
    return PAL[@intCast(usize, idx & 15)];
}

// Raw wheel delta (WM_MOUSEWHEEL high word) -> app lines. Spec §7.1 says the
// event delta is in lines; §7.2 fixes the editor at 3 lines/notch.
pub fn wheelLines(raw_delta: i32) i32 {
    // Z98's signed `/` lowers the divisor through an unsigned cast; do the
    // negative case on the positive magnitude so -240 -> -6 is exact.
    if (raw_delta >= 0) {
        return (raw_delta / WHEEL_DELTA) * WHEEL_LINES;
    }
    return 0 - (((0 - raw_delta) / WHEEL_DELTA) * WHEEL_LINES);
}

// --- HRESULT logging (stdout via std_io/PAL, no printf) --------------------
fn logHr(label: []const u8, hr: u32) void {
    io.write(label);
    io.write(" hr=0x");
    const shifts: [8]u32 = [8]u32{ 28, 24, 20, 16, 12, 8, 4, 0 };
    var buf: [8]u8 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const nib: u32 = (hr >> shifts[i]) & 15;
        if (nib < 10) {
            buf[i] = @intCast(u8, 48 + nib);
        } else {
            buf[i] = @intCast(u8, 87 + nib);
        }
    }
    io.write(buf[0..8]);
    io.write("\n");
}

fn logLine(s: []const u8) void {
    io.write(s);
    io.write("\n");
}

fn logPresent(w: u32, h: u32, bw: u32, bh: u32, x: i32, y: i32) void {
    io.write("present 1:1 client=");
    io.printInt(@intCast(i32, w));
    io.write("x");
    io.printInt(@intCast(i32, h));
    io.write(" back=");
    io.printInt(@intCast(i32, bw));
    io.write("x");
    io.printInt(@intCast(i32, bh));
    io.write(" dest=(");
    io.printInt(x);
    io.write(",");
    io.printInt(y);
    io.write(")\n");
}

// --- Win32 / COM struct mirrors (i386, natural layout) ---------------------
const Guid = struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

// IID_IDirectDraw7 = {15e65ec0-3b9c-11d2-b92f-00609797ea5b}
const IID_DD7: Guid = Guid{
    .data1 = 0x15e65ec0,
    .data2 = 0x3b9c,
    .data3 = 0x11d2,
    .data4 = [8]u8{ 0xb9, 0x2f, 0x00, 0x60, 0x97, 0x97, 0xea, 0x5b },
};

const WndProc = extern "stdcall" fn(hwnd: *void, msg: u32, wparam: u32, lparam: i32) i32;

const WndClassA = struct {
    style: u32,
    lpfnWndProc: WndProc,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: *void,
    hIcon: *void,
    hCursor: *void,
    hbrBackground: *void,
    lpszMenuName: *void,
    lpszClassName: *void,
};

const Point = struct { x: i32, y: i32 };
const Msg = struct {
    hwnd: *void,
    message: u32,
    wParam: u32,
    lParam: u32,
    time: u32,
    pt: Point,
};

const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };

// TEXTMETRICA (i386 mingw): 11 LONGs then 9 BYTEs.
const TextMetricA = struct {
    tmHeight: i32,
    tmAscent: i32,
    tmDescent: i32,
    tmInternalLeading: i32,
    tmExternalLeading: i32,
    tmAveCharWidth: i32,
    tmMaxCharWidth: i32,
    tmWeight: i32,
    tmOverhang: i32,
    tmDigitizedAspectX: i32,
    tmDigitizedAspectY: i32,
    tmFirstChar: u8,
    tmLastChar: u8,
    tmDefaultChar: u8,
    tmBreakChar: u8,
    tmItalic: u8,
    tmUnderlined: u8,
    tmStruckOut: u8,
    tmPitchAndFamily: u8,
    tmCharSet: u8,
};

// DDSURFACEDESC2 (i386 mingw, 124 bytes; offsets in ddraw.h comments).
const DdCaps2 = struct {
    dwCaps: u32,
    dwCaps2: u32,
    dwCaps3: u32,
    dwCaps4: u32,
};

const DdSurfaceDesc2 = struct {
    dwSize: u32,
    dwFlags: u32,
    dwHeight: u32,
    dwWidth: u32,
    lPitch: u32,
    dwBackBufferCount: u32,
    dwMipMapCount: u32,
    dwAlphaBitDepth: u32,
    dwReserved: u32,
    lpSurface: *void,
    ckDestOverlayLow: u32,
    ckDestOverlayHigh: u32,
    ckDestBltLow: u32,
    ckDestBltHigh: u32,
    ckSrcOverlayLow: u32,
    ckSrcOverlayHigh: u32,
    ckSrcBltLow: u32,
    ckSrcBltHigh: u32,
    pfSize: u32,
    pfFlags: u32,
    pfFourCC: u32,
    pfBitCount: u32,
    pfRMask: u32,
    pfGMask: u32,
    pfBMask: u32,
    pfAMask: u32,
    ddsCaps: DdCaps2,
    dwTextureStage: u32,
};

fn zeroDesc() DdSurfaceDesc2 {
    return DdSurfaceDesc2{
        .dwSize = 124,
        .dwFlags = 0,
        .dwHeight = 0,
        .dwWidth = 0,
        .lPitch = 0,
        .dwBackBufferCount = 0,
        .dwMipMapCount = 0,
        .dwAlphaBitDepth = 0,
        .dwReserved = 0,
        .lpSurface = nullVoid(),
        .ckDestOverlayLow = 0,
        .ckDestOverlayHigh = 0,
        .ckDestBltLow = 0,
        .ckDestBltHigh = 0,
        .ckSrcOverlayLow = 0,
        .ckSrcOverlayHigh = 0,
        .ckSrcBltLow = 0,
        .ckSrcBltHigh = 0,
        .pfSize = 0,
        .pfFlags = 0,
        .pfFourCC = 0,
        .pfBitCount = 0,
        .pfRMask = 0,
        .pfGMask = 0,
        .pfBMask = 0,
        .pfAMask = 0,
        .ddsCaps = DdCaps2{ .dwCaps = 0, .dwCaps2 = 0, .dwCaps3 = 0, .dwCaps4 = 0 },
        .dwTextureStage = 0,
    };
}

// --- COM vtables -----------------------------------------------------------
// A COM interface pointer is a pointer to { lpVtbl }. The structs below are
// the vtables themselves (arrays of stdcall fn pointers). Unused slots keep
// the index correct and are never called.

const DdVtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
};

const Dd7Vtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    Compact: extern "stdcall" fn() void,
    CreateClipper: extern "stdcall" fn(iface: *void, flags: u32, out: **void, outer: *void) u32,
    CreatePalette: extern "stdcall" fn() void,
    CreateSurface: extern "stdcall" fn(iface: *void, desc: *void, out: **void, outer: *void) u32,
    DuplicateSurface: extern "stdcall" fn() void,
    EnumDisplayModes: extern "stdcall" fn() void,
    EnumSurfaces: extern "stdcall" fn() void,
    FlipToGDISurface: extern "stdcall" fn() void,
    GetCaps: extern "stdcall" fn() void,
    GetDisplayMode: extern "stdcall" fn() void,
    GetFourCCCodes: extern "stdcall" fn() void,
    GetGDISurface: extern "stdcall" fn() void,
    GetMonitorFrequency: extern "stdcall" fn() void,
    GetScanLine: extern "stdcall" fn() void,
    GetVerticalBlankStatus: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    RestoreDisplayMode: extern "stdcall" fn() void,
    SetCooperativeLevel: extern "stdcall" fn(iface: *void, hwnd: *void, flags: u32) u32,
    SetDisplayMode: extern "stdcall" fn() void,
    WaitForVerticalBlank: extern "stdcall" fn() void,
    GetAvailableVidMem: extern "stdcall" fn() void,
    GetSurfaceFromDC: extern "stdcall" fn() void,
    RestoreAllSurfaces: extern "stdcall" fn() void,
    TestCooperativeLevel: extern "stdcall" fn() void,
    GetDeviceIdentifier: extern "stdcall" fn() void,
    StartModeTest: extern "stdcall" fn() void,
    EvaluateMode: extern "stdcall" fn() void,
};

const ClipperVtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    GetClipList: extern "stdcall" fn() void,
    GetHWnd: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    IsClipListChanged: extern "stdcall" fn() void,
    SetClipList: extern "stdcall" fn() void,
    SetHWnd: extern "stdcall" fn(iface: *void, flags: u32, hwnd: *void) u32,
};

const Surface7Vtbl = struct {
    QueryInterface: extern "stdcall" fn() void,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    AddAttachedSurface: extern "stdcall" fn() void,
    AddOverlayDirtyRect: extern "stdcall" fn() void,
    Blt: extern "stdcall" fn(iface: *void, dest: *void, src: *void, src_rect: *void, flags: u32, fx: *void) u32,
    BltBatch: extern "stdcall" fn() void,
    BltFast: extern "stdcall" fn() void,
    DeleteAttachedSurface: extern "stdcall" fn() void,
    EnumAttachedSurfaces: extern "stdcall" fn() void,
    EnumOverlayZOrders: extern "stdcall" fn() void,
    Flip: extern "stdcall" fn() void,
    GetAttachedSurface: extern "stdcall" fn() void,
    GetBltStatus: extern "stdcall" fn() void,
    GetCaps: extern "stdcall" fn() void,
    GetClipper: extern "stdcall" fn() void,
    GetColorKey: extern "stdcall" fn() void,
    GetDC: extern "stdcall" fn(iface: *void, out: **void) u32,
    GetFlipStatus: extern "stdcall" fn() void,
    GetOverlayPosition: extern "stdcall" fn() void,
    GetPalette: extern "stdcall" fn() void,
    GetPixelFormat: extern "stdcall" fn() void,
    GetSurfaceDesc: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    IsLost: extern "stdcall" fn() void,
    Lock: extern "stdcall" fn() void,
    ReleaseDC: extern "stdcall" fn(iface: *void, hdc: *void) u32,
    Restore: extern "stdcall" fn(iface: *void) u32,
    SetClipper: extern "stdcall" fn(iface: *void, clipper: *void) u32,
    SetColorKey: extern "stdcall" fn(iface: *void, flags: u32, key: *void) u32,
    SetOverlayPosition: extern "stdcall" fn() void,
    SetPalette: extern "stdcall" fn() void,
    Unlock: extern "stdcall" fn() void,
    UpdateOverlay: extern "stdcall" fn() void,
    UpdateOverlayDisplay: extern "stdcall" fn() void,
    UpdateOverlayZOrder: extern "stdcall" fn() void,
};

const DdObj = struct { vtbl: *const DdVtbl };
const Dd7Obj = struct { vtbl: *const Dd7Vtbl };
const ClipperObj = struct { vtbl: *const ClipperVtbl };
const Surface7Obj = struct { vtbl: *const Surface7Vtbl };

fn ddVtbl(p: *void) *const DdVtbl {
    const o: *const DdObj = @ptrCast(*const DdObj, p);
    return o.vtbl;
}
fn dd7Vtbl(p: *void) *const Dd7Vtbl {
    const o: *const Dd7Obj = @ptrCast(*const Dd7Obj, p);
    return o.vtbl;
}
fn clipperVtbl(p: *void) *const ClipperVtbl {
    const o: *const ClipperObj = @ptrCast(*const ClipperObj, p);
    return o.vtbl;
}
fn surfaceVtbl(p: *void) *const Surface7Vtbl {
    const o: *const Surface7Obj = @ptrCast(*const Surface7Obj, p);
    return o.vtbl;
}

// --- external Win32 / GDI / DDraw symbols ----------------------------------
pub extern "stdcall" fn DirectDrawCreate(lpGuid: *void, out: **void, outer: *void) u32;
pub extern "stdcall" fn GetModuleHandleA(name: *void) *void;
pub extern "stdcall" fn RegisterClassA(wc: *void) u16;
pub extern "stdcall" fn CreateWindowExA(ex_style: u32, cls: *void, title: *void, style: u32, x: i32, y: i32, w: i32, h: i32, parent: *void, menu: *void, inst: *void, param: *void) *void;
pub extern "stdcall" fn DefWindowProcA(hwnd: *void, msg: u32, wparam: u32, lparam: i32) i32;
pub extern "stdcall" fn ShowWindow(hwnd: *void, cmd: i32) i32;
pub extern "stdcall" fn UpdateWindow(hwnd: *void) i32;
pub extern "stdcall" fn SetForegroundWindow(hwnd: *void) i32;
pub extern "stdcall" fn SetWindowTextA(hwnd: *void, s: [*]const u8) i32;
pub extern "stdcall" fn DestroyWindow(hwnd: *void) i32;
pub extern "stdcall" fn UnregisterClassA(name: [*]const u8, inst: *void) i32;
pub extern "stdcall" fn LoadCursorA(inst: *void, name: *void) *void;
pub extern "stdcall" fn PeekMessageA(msg: *void, hwnd: *void, min: u32, max: u32, remove: u32) i32;
pub extern "stdcall" fn TranslateMessage(msg: *const void) i32;
pub extern "stdcall" fn DispatchMessageA(msg: *const void) i32;
pub extern "stdcall" fn PostQuitMessage(code: i32) void;
pub extern "stdcall" fn PostMessageA(hwnd: *void, msg: u32, wparam: u32, lparam: i32) i32;
pub extern "stdcall" fn GetKeyState(vk: i32) i16;
pub extern "stdcall" fn GetClientRect(hwnd: *void, rc: *void) i32;
pub extern "stdcall" fn ClientToScreen(hwnd: *void, pt: *void) i32;
pub extern "stdcall" fn AdjustWindowRect(rc: *void, style: u32, menu: i32) i32;
pub extern "stdcall" fn SetWindowPos(hwnd: *void, after: *void, x: i32, y: i32, w: i32, h: i32, flags: u32) i32;
pub extern "stdcall" fn GetDC(hwnd: *void) *void;
pub extern "stdcall" fn ReleaseDC(hwnd: *void, hdc: *void) i32;
pub extern "stdcall" fn FillRect(hdc: *void, rc: *const void, brush: *void) i32;
pub extern "stdcall" fn CreateSolidBrush(color: u32) *void;
pub extern "stdcall" fn DeleteObject(obj: *void) i32;
pub extern "stdcall" fn GetStockObject(kind: i32) *void;
pub extern "stdcall" fn SelectObject(hdc: *void, obj: *void) *void;
pub extern "stdcall" fn SetBkMode(hdc: *void, mode: i32) i32;
pub extern "stdcall" fn SetTextColor(hdc: *void, color: u32) u32;
pub extern "stdcall" fn GetTextMetricsA(hdc: *void, tm: *void) i32;
pub extern "stdcall" fn TextOutA(hdc: *void, x: i32, y: i32, s: [*]const u8, len: i32) i32;
pub extern "stdcall" fn CreateCompatibleDC(hdc: *void) *void;
pub extern "stdcall" fn CreateCompatibleBitmap(hdc: *void, w: i32, h: i32) *void;
pub extern "stdcall" fn CreateBitmap(w: i32, h: i32, planes: u32, bits: u32, data: *void) *void;
pub extern "stdcall" fn BitBlt(dest: *void, x: i32, y: i32, w: i32, h: i32, src: *void, sx: i32, sy: i32, rop: u32) i32;
pub extern "stdcall" fn DeleteDC(dc: *void) i32;
pub extern "stdcall" fn OpenClipboard(hwnd: *void) i32;
pub extern "stdcall" fn EmptyClipboard() i32;
pub extern "stdcall" fn CloseClipboard() i32;
pub extern "stdcall" fn SetClipboardData(fmt: u32, data: *void) *void;
pub extern "stdcall" fn GetClipboardData(fmt: u32) *void;
pub extern "stdcall" fn GlobalAlloc(flags: u32, bytes: u32) *void;
pub extern "stdcall" fn GlobalLock(mem: *void) *void;
pub extern "stdcall" fn GlobalUnlock(mem: *void) i32;
pub extern "stdcall" fn GlobalFree(mem: *void) *void;
pub extern "stdcall" fn GlobalSize(mem: *void) u32;

// C runtime trampoline (zig_nocrt.c): owns the stdcall WndProc and records
// SENT WM_SIZE/WM_CLOSE messages for this poll loop. cdecl; the emitted C uses
// C89 implicit declarations for these helpers (32-bit pointer/int compatible).
extern "c" fn z98_gfx_set_defproc(p: *void) void;
extern "c" fn z98_gfx_wndproc_addr() usize;
extern "c" fn z98_gfx_reset() void;
extern "c" fn z98_gfx_resize_take(w: *u32, h: *u32) i32;
extern "c" fn z98_gfx_close_take() i32;

// --- PAL state -------------------------------------------------------------
pub const State = struct {
    hwnd: *void,
    hinst: *void,
    dd: *void,
    dd7: *void,
    primary: *void,
    back: *void,
    atlas_color_dc: *void,
    atlas_mask_dc: *void,
    atlas_color_bmp: *void,
    atlas_mask_bmp: *void,
    atlas_old_color: *void,
    atlas_old_mask: *void,
    atlas_used: bool,
    clipper: *void,
    hdc: *void,
    font: *void,
    brushes: [16]*void,
    cols: u32,
    rows: u32,
    cw: u32,
    ch: u32,
    bufw: u32,
    bufh: u32,
    present_w: u32,
    present_h: u32,
    blt_logged: bool,
    blt_failed: bool,
    pending: bool,
    pend_code: u16,
    pend_mods: u8,
    deferred: bool,
    def_kind: u8,
    def_ch: u8,
    def_code: u16,
    def_mods: u8,
    title: [128]u8,
    class_name: [32]u8,
};

pub const RawEvent = struct {
    kind: u8,
    ch: u8,
    code: u16,
    x: u32,
    y: u32,
    button: u8,
    wheel: i32,
    cols: u32,
    rows: u32,
    mods: u8,
};

fn copyCstr(s: []const u8, out: []u8) void {
    var n: usize = s.len;
    if (n >= out.len) n = out.len - 1;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = s[i];
    out[n] = 0;
}

// Update the top-level window title (z9edit keeps its dirty `*` current).
pub fn setTitle(st: *State, title: []const u8) bool {
    if (isNull(st.hwnd)) return false;
    var buf: [128]u8 = undefined;
    copyCstr(title, buf[0..]);
    return SetWindowTextA(st.hwnd, @ptrCast([*]const u8, &buf[0])) != 0;
}

fn releaseSurface(p: *void) void {
    if (!isNull(p)) {
        _ = surfaceVtbl(p).Release(p);
    }
}

fn releaseClipper(p: *void) void {
    if (!isNull(p)) {
        _ = clipperVtbl(p).Release(p);
    }
}

fn releaseDd7(p: *void) void {
    if (!isNull(p)) {
        _ = dd7Vtbl(p).Release(p);
    }
}

fn releaseDd(p: *void) void {
    if (!isNull(p)) {
        _ = ddVtbl(p).Release(p);
    }
}

fn makeSurface(st: *State, w: u32, h: u32, primary: bool, label: []const u8) *void {
    var ddsd = zeroDesc();
    if (primary) {
        ddsd.dwFlags = DDSD_CAPS;
        ddsd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    } else {
        ddsd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT;
        ddsd.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN;
        ddsd.dwWidth = w;
        ddsd.dwHeight = h;
    }
    var raw: *void = nullVoid();
    const hr = dd7Vtbl(st.dd7).CreateSurface(st.dd7, @ptrCast(*void, &ddsd), &raw, nullVoid());
    logHr(label, hr);
    if (hr != S_OK) return nullVoid();
    return raw;
}

fn resizeBack(st: *State, w: u32, h: u32) bool {
    if (w == 0 or h == 0) return false;
    releaseSurface(st.back);
    st.back = nullVoid();
    const nb = makeSurface(st, w, h, false, "CreateSurface(resize)");
    if (isNull(nb)) return false;
    st.back = nb;
    st.bufw = w;
    st.bufh = h;
    return true;
}

fn releaseAtlas(st: *State) void {
    if (!isNull(st.atlas_color_dc)) {
        if (!isNull(st.atlas_old_color)) {
            _ = SelectObject(st.atlas_color_dc, st.atlas_old_color);
        }
        _ = DeleteDC(st.atlas_color_dc);
        st.atlas_color_dc = nullVoid();
    }
    if (!isNull(st.atlas_mask_dc)) {
        if (!isNull(st.atlas_old_mask)) {
            _ = SelectObject(st.atlas_mask_dc, st.atlas_old_mask);
        }
        _ = DeleteDC(st.atlas_mask_dc);
        st.atlas_mask_dc = nullVoid();
    }
    if (!isNull(st.atlas_color_bmp)) {
        _ = DeleteObject(st.atlas_color_bmp);
        st.atlas_color_bmp = nullVoid();
    }
    if (!isNull(st.atlas_mask_bmp)) {
        _ = DeleteObject(st.atlas_mask_bmp);
        st.atlas_mask_bmp = nullVoid();
    }
    st.atlas_old_color = nullVoid();
    st.atlas_old_mask = nullVoid();
    st.atlas_used = false;
}

fn buildAtlas(st: *State) bool {
    const aw: u32 = GLYPH_COUNT * st.cw;
    const ah: u32 = ATLAS_COLORS * st.ch;
    const wdc = GetDC(st.hwnd);
    if (isNull(wdc)) {
        logLine("GetDC(window) for glyph-atlas failed");
        return false;
    }
    st.atlas_color_bmp = CreateCompatibleBitmap(wdc, @intCast(i32, aw), @intCast(i32, ah));
    st.atlas_mask_bmp = CreateBitmap(@intCast(i32, aw), @intCast(i32, ah), 1, 1, nullVoid());
    st.atlas_color_dc = CreateCompatibleDC(wdc);
    st.atlas_mask_dc = CreateCompatibleDC(wdc);
    _ = ReleaseDC(st.hwnd, wdc);
    if (isNull(st.atlas_color_bmp) or isNull(st.atlas_mask_bmp)
        or isNull(st.atlas_color_dc) or isNull(st.atlas_mask_dc)) {
        logLine("glyph-atlas allocation failed");
        releaseAtlas(st);
        return false;
    }
    st.atlas_old_color = SelectObject(st.atlas_color_dc, st.atlas_color_bmp);
    st.atlas_old_mask = SelectObject(st.atlas_mask_dc, st.atlas_mask_bmp);

    var full = Rect{ .left = 0, .top = 0, .right = @intCast(i32, aw), .bottom = @intCast(i32, ah) };
    _ = FillRect(st.atlas_color_dc, @ptrCast(*const void, &full), brushFor(st, 0));
    _ = FillRect(st.atlas_mask_dc, @ptrCast(*const void, &full), brushFor(st, 15));
    _ = SelectObject(st.atlas_color_dc, st.font);
    _ = SelectObject(st.atlas_mask_dc, st.font);
    _ = SetBkMode(st.atlas_color_dc, TRANSPARENT);
    _ = SetBkMode(st.atlas_mask_dc, TRANSPARENT);

    var fg: u32 = 0;
    while (fg < ATLAS_COLORS) : (fg += 1) {
        _ = SetTextColor(st.atlas_color_dc, paletteRgb(@intCast(u8, fg)));
        // Mask: black glyph on white -> SRCAND clears glyph pixels, keeps bg.
        _ = SetTextColor(st.atlas_mask_dc, 0);
        var idx: u32 = 0;
        while (idx < GLYPH_COUNT) : (idx += 1) {
            var ch: [1]u8 = undefined;
            ch[0] = @intCast(u8, GLYPH_FIRST + idx);
            _ = TextOutA(st.atlas_color_dc,
                @intCast(i32, idx * st.cw), @intCast(i32, fg * st.ch),
                @ptrCast([*]const u8, &ch[0]), 1);
            _ = TextOutA(st.atlas_mask_dc,
                @intCast(i32, idx * st.cw), @intCast(i32, fg * st.ch),
                @ptrCast([*]const u8, &ch[0]), 1);
        }
    }
    logLine("glyph-atlas built (95x16 GDI color+mask)");
    return true;
}

pub fn open(title: []const u8, cols: u32, rows: u32, st: *State) bool {
    st.hwnd = nullVoid();
    st.hinst = nullVoid();
    st.dd = nullVoid();
    st.dd7 = nullVoid();
    st.primary = nullVoid();
    st.back = nullVoid();
    st.atlas_color_dc = nullVoid();
    st.atlas_mask_dc = nullVoid();
    st.atlas_color_bmp = nullVoid();
    st.atlas_mask_bmp = nullVoid();
    st.atlas_old_color = nullVoid();
    st.atlas_old_mask = nullVoid();
    st.atlas_used = false;
    st.clipper = nullVoid();
    st.hdc = nullVoid();
    st.font = nullVoid();
    st.cols = cols;
    st.rows = rows;
    st.cw = 8;
    st.ch = 16;
    st.bufw = OFFSCREEN_W;
    st.bufh = OFFSCREEN_H;
    st.present_w = 0;
    st.present_h = 0;
    st.blt_logged = false;
    st.blt_failed = false;
    st.pending = false;
    st.pend_code = 0;
    st.pend_mods = 0;
    st.deferred = false;
    st.def_kind = 0;
    st.def_ch = 0;
    st.def_code = 0;
    st.def_mods = 0;
    var bi: usize = 0;
    while (bi < 16) : (bi += 1) st.brushes[bi] = nullVoid();
    copyCstr(title, st.title[0..]);
    var cls: []const u8 = "z98gfxwnd";
    copyCstr(cls, st.class_name[0..]);

    const hinst = GetModuleHandleA(nullVoid());
    st.hinst = hinst;

    // The WndProc is the C trampoline (Z98 cannot define a stdcall function).
    // It records SENT WM_SIZE/WM_CLOSE messages for this poll loop and forwards
    // everything to DefWindowProcA (address supplied here, no user32 import in
    // the runtime shim itself).
    z98_gfx_reset();
    z98_gfx_set_defproc(@ptrCast(*void, DefWindowProcA));
    const wnd_addr = z98_gfx_wndproc_addr();
    const wnd_void: *void = @intToPtr(*void, wnd_addr);
    const wnd_proc: WndProc = @ptrCast(WndProc, wnd_void);

    var wc: WndClassA = WndClassA{
        .style = 0,
        .lpfnWndProc = wnd_proc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hinst,
        .hIcon = nullVoid(),
        .hCursor = LoadCursorA(nullVoid(), @intToPtr(*void, @intCast(usize, IDC_ARROW))),
        .hbrBackground = GetStockObject(BLACK_BRUSH),
        .lpszMenuName = nullVoid(),
        .lpszClassName = @ptrCast(*void, &st.class_name[0]),
    };
    _ = RegisterClassA(@ptrCast(*void, &wc));

    var title_ptr: *void = @ptrCast(*void, &st.title[0]);
    st.hwnd = CreateWindowExA(0, @ptrCast(*void, &st.class_name[0]), title_ptr,
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
        @intCast(i32, OFFSCREEN_W), @intCast(i32, OFFSCREEN_H),
        nullVoid(), nullVoid(), hinst, nullVoid());
    if (isNull(st.hwnd)) {
        close(st);
        return false;
    }
    _ = ShowWindow(st.hwnd, SW_SHOW);
    _ = UpdateWindow(st.hwnd);
    _ = SetForegroundWindow(st.hwnd);

    // Glyph metrics from the real fixed font (self-consistent per machine).
    st.font = GetStockObject(SYSTEM_FIXED_FONT);
    const mdc = GetDC(st.hwnd);
    if (!isNull(mdc)) {
        const old = SelectObject(mdc, st.font);
        var tm: TextMetricA = undefined;
        if (GetTextMetricsA(mdc, @ptrCast(*void, &tm)) == 0) {
            logLine("GetTextMetricsA failed; using 8x16 fallback");
        } else {
            if (tm.tmAveCharWidth > 0) st.cw = @intCast(u32, tm.tmAveCharWidth);
            if (tm.tmHeight > 0) st.ch = @intCast(u32, tm.tmHeight);
        }
        _ = SelectObject(mdc, old);
        _ = ReleaseDC(st.hwnd, mdc);
    } else {
        logLine("GetDC(window) failed; using 8x16 fallback");
    }

    var i: usize = 0;
    while (i < 16) : (i += 1) {
        st.brushes[i] = CreateSolidBrush(paletteRgb(@intCast(u8, i)));
        if (isNull(st.brushes[i])) {
            logLine("CreateSolidBrush failed");
            close(st);
            return false;
        }
    }

    // DirectDraw: v1 create, then upgrade to v7 (the T0-pre gotcha).
    var dd_raw: *void = nullVoid();
    var hr = DirectDrawCreate(nullVoid(), &dd_raw, nullVoid());
    logHr("DirectDrawCreate", hr);
    if (hr != S_OK) {
        close(st);
        return false;
    }
    if (isNull(dd_raw)) {
        logLine("DirectDrawCreate returned null v1 interface");
        close(st);
        return false;
    }
    st.dd = dd_raw;
    var dd7_raw: *void = nullVoid();
    hr = ddVtbl(st.dd).QueryInterface(st.dd, @ptrCast(*const void, &IID_DD7), &dd7_raw);
    logHr("QueryInterface(IID_IDirectDraw7)", hr);
    if (hr != S_OK) {
        close(st);
        return false;
    }
    if (isNull(dd7_raw)) {
        logLine("QueryInterface(IID_IDirectDraw7) returned null");
        close(st);
        return false;
    }
    st.dd7 = dd7_raw;
    hr = dd7Vtbl(st.dd7).SetCooperativeLevel(st.dd7, st.hwnd, DDSCL_NORMAL);
    logHr("SetCooperativeLevel(DDSCL_NORMAL)", hr);
    if (hr != S_OK) {
        close(st);
        return false;
    }

    st.primary = makeSurface(st, OFFSCREEN_W, OFFSCREEN_H, true, "CreateSurface(primary)");
    if (isNull(st.primary)) {
        close(st);
        return false;
    }
    st.back = makeSurface(st, OFFSCREEN_W, OFFSCREEN_H, false, "CreateSurface(offscreen)");
    if (isNull(st.back)) {
        close(st);
        return false;
    }

    // Binding glyph cache: one offscreen color+mask atlas of ASCII 32..126 x
    // 16 palette colors, built once at open with SYSTEM_FIXED_FONT. Per-cell
    // drawText then GDI-BitBlts the atlas cell (mask SRCAND + color SRCPAINT).
    if (!buildAtlas(st)) {
        logLine("glyph atlas build failed");
        close(st);
        return false;
    }

    // Best-effort clipper (windowed Blt still works without it; T0-pre proved
    // the primary<-offscreen path under DDSCL_NORMAL).
    var clip_raw: *void = nullVoid();
    hr = dd7Vtbl(st.dd7).CreateClipper(st.dd7, 0, &clip_raw, nullVoid());
    logHr("CreateClipper", hr);
    if (hr == S_OK and !isNull(clip_raw)) {
        st.clipper = clip_raw;
        hr = clipperVtbl(st.clipper).SetHWnd(st.clipper, 0, st.hwnd);
        logHr("SetHWnd(clipper)", hr);
        if (hr == S_OK) {
            hr = surfaceVtbl(st.primary).SetClipper(st.primary, st.clipper);
            logHr("SetClipper(primary)", hr);
        }
        if (hr != S_OK) {
            releaseClipper(st.clipper);
            st.clipper = nullVoid();
        }
    }
    return true;
}

pub fn close(st: *State) void {
    if (!isNull(st.hdc)) {
        if (!isNull(st.back)) {
            _ = surfaceVtbl(st.back).ReleaseDC(st.back, st.hdc);
        }
        st.hdc = nullVoid();
    }
    releaseAtlas(st);
    releaseSurface(st.back);
    releaseSurface(st.primary);
    releaseClipper(st.clipper);
    releaseDd7(st.dd7);
    releaseDd(st.dd);
    st.back = nullVoid();
    st.primary = nullVoid();
    st.clipper = nullVoid();
    st.dd7 = nullVoid();
    st.dd = nullVoid();
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        if (!isNull(st.brushes[i])) {
            _ = DeleteObject(st.brushes[i]);
            st.brushes[i] = nullVoid();
        }
    }
    if (!isNull(st.hwnd)) {
        _ = DestroyWindow(st.hwnd);
        st.hwnd = nullVoid();
    }
    if (!isNull(st.hinst)) {
        _ = UnregisterClassA(@ptrCast([*]const u8, &st.class_name[0]), st.hinst);
        st.hinst = nullVoid();
    }
}

pub fn beginFrame(st: *State) bool {
    if (isNull(st.back)) return false;
    var dc_raw: *void = nullVoid();
    const hr = surfaceVtbl(st.back).GetDC(st.back, &dc_raw);
    if (hr != S_OK) return false;
    if (isNull(dc_raw)) return false;
    st.hdc = dc_raw;
    _ = SelectObject(st.hdc, st.font);
    _ = SetBkMode(st.hdc, TRANSPARENT);
    return true;
}

pub fn endFrame(st: *State) bool {
    if (!isNull(st.hdc)) {
        _ = surfaceVtbl(st.back).ReleaseDC(st.back, st.hdc);
        st.hdc = nullVoid();
    }
    if (isNull(st.primary) or isNull(st.back) or isNull(st.hwnd)) return false;

    var crc: Rect = undefined;
    if (GetClientRect(st.hwnd, @ptrCast(*void, &crc)) == 0) return false;
    var origin = Point{ .x = crc.left, .y = crc.top };
    if (ClientToScreen(st.hwnd, @ptrCast(*void, &origin)) == 0) return false;

    var cw: i32 = crc.right - crc.left;
    var ch: i32 = crc.bottom - crc.top;
    const bw: i32 = @intCast(i32, st.bufw);
    const bh: i32 = @intCast(i32, st.bufh);
    if (cw > bw) cw = bw;
    if (ch > bh) ch = bh;
    // Minimized/0x0 client: there is nothing to present, but this is not an
    // error. The next restore produces a normal WM_SIZE and frame.
    if (cw <= 0 or ch <= 0) return true;

    var dest = Rect{
        .left = origin.x,
        .top = origin.y,
        .right = origin.x + cw,
        .bottom = origin.y + ch,
    };
    var src = Rect{ .left = 0, .top = 0, .right = cw, .bottom = ch };
    const uw: u32 = @intCast(u32, cw);
    const uh: u32 = @intCast(u32, ch);
    var geom_changed = false;
    if (st.present_w != uw or st.present_h != uh or st.bufw != uw or st.bufh != uh) {
        st.present_w = uw;
        st.present_h = uh;
        geom_changed = true;
        logPresent(uw, uh, st.bufw, st.bufh, origin.x, origin.y);
    }
    const hr = surfaceVtbl(st.primary).Blt(st.primary, @ptrCast(*void, &dest),
        st.back, @ptrCast(*void, &src), DDBLT_WAIT, nullVoid());
    // Keep the evidence useful without per-frame stdout spam: log the first
    // success and every geometry change, plus failures once per failure run.
    if (hr != S_OK) {
        if (!st.blt_failed) {
            logHr("Blt(primary<-offscreen)", hr);
            st.blt_failed = true;
        }
    } else {
        st.blt_failed = false;
        if (!st.blt_logged or geom_changed) {
            logHr("Blt(primary<-offscreen)", hr);
            st.blt_logged = true;
        }
    }
    return hr == S_OK;
}

fn brushFor(st: *State, idx: u8) *void {
    return st.brushes[@intCast(usize, idx & 15)];
}

pub fn fillRect(st: *State, px: i32, py: i32, pw: i32, ph: i32, fg: u8, bg: u8) void {
    if (isNull(st.hdc)) return;
    if (pw <= 0 or ph <= 0) return;
    var rc = Rect{ .left = px, .top = py, .right = px + pw, .bottom = py + ph };
    _ = FillRect(st.hdc, @ptrCast(*const void, &rc), brushFor(st, bg));
    // A one-pixel frame in fg makes the fg argument observable without a
    // general line primitive (v1 primitives stay clear/fill/text).
    if (pw > 2 and ph > 2) {
        var top = Rect{ .left = px, .top = py, .right = px + pw, .bottom = py + 1 };
        var bot = Rect{ .left = px, .top = py + ph - 1, .right = px + pw, .bottom = py + ph };
        var lft = Rect{ .left = px, .top = py, .right = px + 1, .bottom = py + ph };
        var rgt = Rect{ .left = px + pw - 1, .top = py, .right = px + pw, .bottom = py + ph };
        _ = FillRect(st.hdc, @ptrCast(*const void, &top), brushFor(st, fg));
        _ = FillRect(st.hdc, @ptrCast(*const void, &bot), brushFor(st, fg));
        _ = FillRect(st.hdc, @ptrCast(*const void, &lft), brushFor(st, fg));
        _ = FillRect(st.hdc, @ptrCast(*const void, &rgt), brushFor(st, fg));
    }
}

pub fn drawText(st: *State, px: i32, py: i32, s: []const u8, fg: u8, bg: u8, cw: u32, ch: u32) void {
    if (s.len == 0) return;
    if (isNull(st.hdc)) return;
    var bgrc = Rect{
        .left = px,
        .top = py,
        .right = px + @intCast(i32, cw) * @intCast(i32, s.len),
        .bottom = py + @intCast(i32, ch),
    };
    _ = FillRect(st.hdc, @ptrCast(*const void, &bgrc), brushFor(st, bg));
    if (isNull(st.atlas_color_dc) or isNull(st.atlas_mask_dc) or cw == 0 or ch == 0) {
        _ = SetTextColor(st.hdc, paletteRgb(fg));
        _ = TextOutA(st.hdc, px, py, s.ptr, @intCast(i32, s.len));
        return;
    }
    const color: u32 = @intCast(u32, fg & 15);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        var code: u32 = @intCast(u32, s[i]);
        if (code < GLYPH_FIRST or code > GLYPH_LAST) code = 63; // '?'
        const gi: u32 = code - GLYPH_FIRST;
        const dx: i32 = px + @intCast(i32, @intCast(u32, i) * cw);
        const sx: i32 = @intCast(i32, gi * cw);
        const sy: i32 = @intCast(i32, color * ch);
        const iw: i32 = @intCast(i32, cw);
        const ih: i32 = @intCast(i32, ch);
        // Clear the glyph pixels (mask is black there), then OR the colored
        // glyph (foreground pixels; black elsewhere). Both come from the one
        // atlas built at gfxOpen.
        if (BitBlt(st.hdc, dx, py, iw, ih, st.atlas_mask_dc, sx, sy, SRCAND) == 0
            or BitBlt(st.hdc, dx, py, iw, ih, st.atlas_color_dc, sx, sy, SRCPAINT) == 0) {
            _ = SetTextColor(st.hdc, paletteRgb(fg));
            _ = TextOutA(st.hdc, px, py, s.ptr, @intCast(i32, s.len));
            return;
        }
        if (!st.atlas_used) {
            st.atlas_used = true;
            logLine("glyph-atlas present active");
        }
    }
}

// Translate a WM_KEYDOWN virtual key to the unmodified character (the
// contract's Ctrl+S -> 's' rule). Non-character keys leave ch = 0; the app
// still gets `code`.
fn virtualToChar(vk: u16) u8 {
    if (vk >= 0x30 and vk <= 0x39) return @intCast(u8, vk);
    if (vk >= 0x41 and vk <= 0x5A) return @intCast(u8, vk + 32);
    if (vk >= 0x60 and vk <= 0x69) return @intCast(u8, vk - 0x60 + 48);
    if (vk == 0x6A) return 42; // '*'
    if (vk == 0x6B) return 43; // '+'
    if (vk == 0x6C) return 45; // separator '-' (kept in the requested set)
    if (vk == 0x6D) return 45; // '-'
    if (vk == 0x6E) return 46; // '.'
    if (vk == 0x6F) return 47; // '/'
    if (vk == 0x20) return 32;
    if (vk == 0x0D) return 13;
    if (vk == 0x09) return 9;
    if (vk == 0x1B) return 27;
    if (vk == 0x08) return 8;
    if (vk == 0x2E) return 127;
    return 0;
}

// Keys whose typed character arrives through WM_CHAR (letters, digits,
// punctuation, numpad, space, enter/tab/backspace/escape). Arrows/F-keys and
// VK_DELETE do not (Win32 emits no WM_CHAR for Delete), so those emit key_down
// immediately with the virtualToChar mapping (Delete -> 127).
fn isCharKey(vk: u16) bool {
    if (vk >= 0x30 and vk <= 0x39) return true;
    if (vk >= 0x41 and vk <= 0x5A) return true;
    if (vk >= 0x60 and vk <= 0x6F) return true;
    if (vk >= 0xBA and vk <= 0xE2) return true;
    if (vk == 0x20 or vk == 0x0D or vk == 0x09) return true;
    if (vk == 0x1B or vk == 0x08) return true;
    return false;
}

fn zeroRaw(raw: *RawEvent) void {
    raw.kind = 0;
    raw.ch = 0;
    raw.code = 0;
    raw.x = 0;
    raw.y = 0;
    raw.button = 0;
    raw.wheel = 0;
    raw.cols = 0;
    raw.rows = 0;
    raw.mods = 0;
}

fn fillDeferred(st: *State, raw: *RawEvent) bool {
    if (!st.deferred) return false;
    zeroRaw(raw);
    raw.kind = st.def_kind;
    raw.ch = st.def_ch;
    raw.code = st.def_code;
    raw.mods = st.def_mods;
    st.deferred = false;
    return true;
}

fn deferKeyUp(st: *State, code: u16, ch: u8, mods: u8) void {
    st.deferred = true;
    st.def_kind = EK_KEY_UP;
    st.def_ch = ch;
    st.def_code = code;
    st.def_mods = mods;
}

// Test-only: resize the real top-level window so Windows sends WM_SIZE to the
// WndProc (the production path). AdjustWindowRect converts the requested
// client size into the outer window size; the poll loop then takes the recorded
// client size and resizes the back buffer/grid.
pub fn testResizeClient(st: *State, cols: u32, rows: u32) bool {
    if (isNull(st.hwnd)) return false;
    if (cols == 0 or rows == 0) return false;
    const w: u32 = cols * st.cw;
    const h: u32 = rows * st.ch;
    if (w == 0 or h == 0 or w > 0x7FFF or h > 0x7FFF) return false;
    var rc = Rect{ .left = 0, .top = 0, .right = @intCast(i32, w), .bottom = @intCast(i32, h) };
    if (AdjustWindowRect(@ptrCast(*void, &rc), WS_OVERLAPPEDWINDOW, 0) == 0) return false;
    const ow: i32 = rc.right - rc.left;
    const oh: i32 = rc.bottom - rc.top;
    const flags: u32 = SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE;
    return SetWindowPos(st.hwnd, nullVoid(), 0, 0, ow, oh, flags) != 0;
}

// Test-only window-state drivers for the live-pump regressions.
pub fn testMinimize(st: *State) bool {
    if (isNull(st.hwnd)) return false;
    _ = ShowWindow(st.hwnd, SW_MINIMIZE);
    // Bare Xvfb/Wine has no window manager, so also drive the client to 0x0
    // explicitly; this is the same GetClientRect path a real minimize takes.
    _ = SetWindowPos(st.hwnd, nullVoid(), 0, 0, 0, 0,
        SWP_NOZORDER | SWP_NOACTIVATE);
    return true;
}

pub fn testRestore(st: *State) bool {
    if (isNull(st.hwnd)) return false;
    _ = ShowWindow(st.hwnd, SW_RESTORE);
    return testResizeClient(st, st.cols, st.rows);
}

pub fn testClose(st: *State) bool {
    if (isNull(st.hwnd)) return false;
    return PostMessageA(st.hwnd, WM_CLOSE, 0, 0) != 0;
}

pub fn testKey(st: *State, vk: u16) bool {
    if (isNull(st.hwnd)) return false;
    return PostMessageA(st.hwnd, WM_KEYDOWN, @intCast(u32, vk), 0) != 0;
}

fn modsNow() u8 {
    var m: u8 = 0;
    if (GetKeyState(VK_SHIFT) < 0) m = m | 1;
    if (GetKeyState(VK_CONTROL) < 0) m = m | 2;
    return m;
}

pub fn pollEvent(st: *State, raw: *RawEvent) bool {
    if (isNull(st.hwnd)) return false;
    if (fillDeferred(st, raw)) return true;
    if (z98_gfx_close_take() != 0) {
        zeroRaw(raw);
        raw.kind = EK_CLOSE;
        return true;
    }
    var rw: u32 = 0;
    var rh: u32 = 0;
    if (z98_gfx_resize_take(&rw, &rh) != 0) {
        zeroRaw(raw);
        var cols: u32 = st.cols;
        var rows: u32 = st.rows;
        var pw: u32 = st.bufw;
        var ph: u32 = st.bufh;
        if (rw > 0 and rh > 0) {
            if (resizeBack(st, rw, rh)) {
                pw = rw;
                ph = rh;
                cols = if (st.cw == 0) 1 else rw / st.cw;
                rows = if (st.ch == 0) 1 else rh / st.ch;
                st.cols = cols;
                st.rows = rows;
            }
        }
        raw.kind = EK_RESIZE;
        raw.x = pw;
        raw.y = ph;
        raw.cols = cols;
        raw.rows = rows;
        return true;
    }
    zeroRaw(raw);
    var msg: Msg = undefined;
    while (PeekMessageA(@ptrCast(*void, &msg), nullVoid(), 0, 0, PM_REMOVE) != 0) {
        const m = msg.message;
        if (m == WM_CHAR) {
            if (st.pending) {
                zeroRaw(raw);
                raw.kind = EK_KEY_DOWN;
                raw.code = st.pend_code;
                raw.ch = @intCast(u8, msg.wParam & 0xFF);
                raw.mods = st.pend_mods;
                st.pending = false;
                return true;
            }
            continue;
        }
        zeroRaw(raw);
        if (m == WM_QUIT) {
            raw.kind = EK_CLOSE;
            return true;
        }
        if (m == WM_CLOSE or m == WM_DESTROY) {
            raw.kind = EK_CLOSE;
            _ = PostQuitMessage(0);
            return true;
        }
        if (m == WM_KEYDOWN) {
            const vk = @intCast(u16, msg.wParam & 0xFFFF);
            const mods = modsNow();
            const ctrl = (mods & 2) != 0;
            if (ctrl) {
                raw.kind = EK_KEY_DOWN;
                raw.code = vk;
                raw.ch = virtualToChar(vk);
                raw.mods = mods;
                _ = TranslateMessage(@ptrCast(*const void, &msg));
                _ = DispatchMessageA(@ptrCast(*const void, &msg));
                return true;
            }
            if (isCharKey(vk)) {
                st.pending = true;
                st.pend_code = vk;
                st.pend_mods = mods;
                _ = TranslateMessage(@ptrCast(*const void, &msg));
                _ = DispatchMessageA(@ptrCast(*const void, &msg));
                continue;
            }
            raw.kind = EK_KEY_DOWN;
            raw.code = vk;
            raw.ch = virtualToChar(vk);
            raw.mods = mods;
            _ = TranslateMessage(@ptrCast(*const void, &msg));
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        if (m == WM_KEYUP) {
            const vk = @intCast(u16, msg.wParam & 0xFFFF);
            const mods = modsNow();
            if (st.pending and st.pend_code == vk) {
                deferKeyUp(st, vk, virtualToChar(vk), mods);
                raw.kind = EK_KEY_DOWN;
                raw.code = st.pend_code;
                raw.ch = 0;
                raw.mods = st.pend_mods;
                st.pending = false;
                _ = DispatchMessageA(@ptrCast(*const void, &msg));
                return true;
            }
            raw.kind = EK_KEY_UP;
            raw.code = vk;
            raw.ch = virtualToChar(vk);
            raw.mods = mods;
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        if (m == WM_MOUSEMOVE or m == WM_LBUTTONDOWN or m == WM_LBUTTONUP) {
            const mx = @intCast(u32, msg.lParam & 0xFFFF);
            const my = @intCast(u32, (msg.lParam >> 16) & 0xFFFF);
            if (m == WM_MOUSEMOVE) raw.kind = EK_MOUSE_MOVE;
            if (m == WM_LBUTTONDOWN) raw.kind = EK_MOUSE_DOWN;
            if (m == WM_LBUTTONUP) raw.kind = EK_MOUSE_UP;
            raw.button = 0;
            raw.x = if (st.cw == 0) 0 else mx / st.cw;
            raw.y = if (st.ch == 0) 0 else my / st.ch;
            raw.mods = modsNow();
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        if (m == WM_MOUSEWHEEL) {
            var delta: i32 = @intCast(i32, (msg.wParam >> 16) & 0xFFFF);
            if (delta > 32767) delta = delta - 65536;
            raw.kind = EK_WHEEL;
            raw.wheel = wheelLines(delta);
            raw.mods = modsNow();
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        _ = TranslateMessage(@ptrCast(*const void, &msg));
        _ = DispatchMessageA(@ptrCast(*const void, &msg));
    }
    if (st.pending) {
        zeroRaw(raw);
        raw.kind = EK_KEY_DOWN;
        raw.code = st.pend_code;
        raw.ch = 0;
        raw.mods = st.pend_mods;
        st.pending = false;
        return true;
    }
    return false;
}

pub fn clipboardSet(st: *State, s: []const u8) bool {
    if (isNull(st.hwnd)) return false;
    if (OpenClipboard(st.hwnd) == 0) return false;
    _ = EmptyClipboard();
    // CF_TEXT is CRLF text: expand canonical LF here while the editor's
    // internal copy stays LF (so --smoke save bytes are unchanged).
    var extra: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\n' and (i == 0 or s[i - 1] != '\r')) extra += 1;
    }
    const n: u32 = @intCast(u32, s.len + extra + 1);
    const mem = GlobalAlloc(GMEM_MOVEABLE, n);
    if (isNull(mem)) {
        _ = CloseClipboard();
        return false;
    }
    const dst = GlobalLock(mem);
    if (isNull(dst)) {
        _ = GlobalFree(mem);
        _ = CloseClipboard();
        return false;
    }
    const dp: [*]u8 = @ptrCast([*]u8, dst);
    var di: usize = 0;
    i = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\n' and (i == 0 or s[i - 1] != '\r')) {
            dp[di] = '\r';
            di += 1;
        }
        dp[di] = s[i];
        di += 1;
    }
    dp[di] = 0;
    _ = GlobalUnlock(mem);
    const owned = SetClipboardData(CF_TEXT, mem);
    if (isNull(owned)) {
        _ = GlobalFree(mem);
        _ = CloseClipboard();
        return false;
    }
    _ = CloseClipboard();
    return true;
}

pub fn clipboardGet(st: *State, arena: *arena_mod.Arena) ?[]u8 {
    if (isNull(st.hwnd)) return null;
    if (OpenClipboard(st.hwnd) == 0) return null;
    const mem = GetClipboardData(CF_TEXT);
    if (isNull(mem)) {
        _ = CloseClipboard();
        return null;
    }
    const src = GlobalLock(mem);
    if (isNull(src)) {
        _ = CloseClipboard();
        return null;
    }
    const sp: [*]const u8 = @ptrCast([*]const u8, src);
    const cap: usize = @intCast(usize, GlobalSize(mem));
    var n: usize = 0;
    while (n < cap and sp[n] != 0) : (n += 1) {}
    var out = arena_mod.alloc(arena, n) catch {
        _ = GlobalUnlock(mem);
        _ = CloseClipboard();
        return null;
    };
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = sp[i];
    _ = GlobalUnlock(mem);
    _ = CloseClipboard();
    return out[0..n];
}
