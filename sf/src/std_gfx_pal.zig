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
// unused slots are `fn() void` so the field indices match ddraw.h
// exactly; a wrong slot would silently call another method. Slot order was
// taken from /usr/i686-w64-mingw32/include/ddraw.h (IDirectDraw7 at :1798,
// IDirectDrawSurface7 at :2503, IDirectDrawClipper at :1335).
//
// The C prototypes for the Win32/GDI/DDraw symbols come from <windows.h> and
// <ddraw.h>; Z98 emits no extern prototypes. The GUID is a local 16-byte value
// (the same bytes DEFINE_GUID(IID_IDirectDraw7) expands to) so the exe does not
// need the dxguid data library.

const arena_mod = @import("std_arena.zig");

@cInclude("<windows.h>");
@cInclude("<ddraw.h>");

// --- constants (winuser.h / wingdi.h / ddraw.h numeric values) --------------
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const CW_USEDEFAULT: i32 = -2147483648;
const SW_SHOW: i32 = 5;
const WM_DESTROY: u32 = 0x0002;
const WM_SIZE: u32 = 0x0005;
const WM_CLOSE: u32 = 0x0010;
const WM_QUIT: u32 = 0x0012;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
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

// Standard VGA 16-color palette (0..15). Unknown indices wrap (idx & 15).
fn paletteRgb(idx: u8) u32 {
    const PAL: [16]u32 = [16]u32{
        rgb(0, 0, 0),
        rgb(0, 0, 170),
        rgb(0, 170, 0),
        rgb(0, 170, 170),
        rgb(170, 0, 0),
        rgb(170, 0, 170),
        rgb(170, 85, 0),
        rgb(170, 170, 170),
        rgb(85, 85, 85),
        rgb(85, 85, 255),
        rgb(85, 255, 85),
        rgb(85, 255, 255),
        rgb(255, 85, 85),
        rgb(255, 85, 255),
        rgb(255, 255, 85),
        rgb(255, 255, 255),
    };
    return PAL[@intCast(usize, idx & 15)];
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
    AddRef: fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
};

const Dd7Vtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    Compact: fn() void,
    CreateClipper: extern "stdcall" fn(iface: *void, flags: u32, out: **void, outer: *void) u32,
    CreatePalette: fn() void,
    CreateSurface: extern "stdcall" fn(iface: *void, desc: *void, out: **void, outer: *void) u32,
    DuplicateSurface: fn() void,
    EnumDisplayModes: fn() void,
    EnumSurfaces: fn() void,
    FlipToGDISurface: fn() void,
    GetCaps: fn() void,
    GetDisplayMode: fn() void,
    GetFourCCCodes: fn() void,
    GetGDISurface: fn() void,
    GetMonitorFrequency: fn() void,
    GetScanLine: fn() void,
    GetVerticalBlankStatus: fn() void,
    Initialize: fn() void,
    RestoreDisplayMode: fn() void,
    SetCooperativeLevel: extern "stdcall" fn(iface: *void, hwnd: *void, flags: u32) u32,
    SetDisplayMode: fn() void,
    WaitForVerticalBlank: fn() void,
    GetAvailableVidMem: fn() void,
    GetSurfaceFromDC: fn() void,
    RestoreAllSurfaces: fn() void,
    TestCooperativeLevel: fn() void,
    GetDeviceIdentifier: fn() void,
    StartModeTest: fn() void,
    EvaluateMode: fn() void,
};

const ClipperVtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    GetClipList: fn() void,
    GetHWnd: fn() void,
    Initialize: fn() void,
    IsClipListChanged: fn() void,
    SetClipList: fn() void,
    SetHWnd: extern "stdcall" fn(iface: *void, flags: u32, hwnd: *void) u32,
};

const Surface7Vtbl = struct {
    QueryInterface: fn() void,
    AddRef: fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    AddAttachedSurface: fn() void,
    AddOverlayDirtyRect: fn() void,
    Blt: extern "stdcall" fn(iface: *void, dest: *void, src: *void, src_rect: *void, flags: u32, fx: *void) u32,
    BltBatch: fn() void,
    BltFast: fn() void,
    DeleteAttachedSurface: fn() void,
    EnumAttachedSurfaces: fn() void,
    EnumOverlayZOrders: fn() void,
    Flip: fn() void,
    GetAttachedSurface: fn() void,
    GetBltStatus: fn() void,
    GetCaps: fn() void,
    GetClipper: fn() void,
    GetColorKey: fn() void,
    GetDC: extern "stdcall" fn(iface: *void, out: **void) u32,
    GetFlipStatus: fn() void,
    GetOverlayPosition: fn() void,
    GetPalette: fn() void,
    GetPixelFormat: fn() void,
    GetSurfaceDesc: fn() void,
    Initialize: fn() void,
    IsLost: fn() void,
    Lock: fn() void,
    ReleaseDC: extern "stdcall" fn(iface: *void, hdc: *void) u32,
    Restore: extern "stdcall" fn(iface: *void) u32,
    SetClipper: extern "stdcall" fn(iface: *void, clipper: *void) u32,
    SetColorKey: fn() void,
    SetOverlayPosition: fn() void,
    SetPalette: fn() void,
    Unlock: fn() void,
    UpdateOverlay: fn() void,
    UpdateOverlayDisplay: fn() void,
    UpdateOverlayZOrder: fn() void,
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
pub extern "stdcall" fn LoadCursorA(inst: *void, name: *void) *void;
pub extern "stdcall" fn PeekMessageA(msg: *void, hwnd: *void, min: u32, max: u32, remove: u32) i32;
pub extern "stdcall" fn TranslateMessage(msg: *const void) i32;
pub extern "stdcall" fn DispatchMessageA(msg: *const void) i32;
pub extern "stdcall" fn PostMessageA(hwnd: *void, msg: u32, wparam: u32, lparam: i32) i32;
pub extern "stdcall" fn PostQuitMessage(code: i32) void;
pub extern "stdcall" fn GetKeyState(vk: i32) i16;
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
pub extern "stdcall" fn OpenClipboard(hwnd: *void) i32;
pub extern "stdcall" fn EmptyClipboard() i32;
pub extern "stdcall" fn CloseClipboard() i32;
pub extern "stdcall" fn SetClipboardData(fmt: u32, data: *void) *void;
pub extern "stdcall" fn GetClipboardData(fmt: u32) *void;
pub extern "stdcall" fn GlobalAlloc(flags: u32, bytes: u32) *void;
pub extern "stdcall" fn GlobalLock(mem: *void) *void;
pub extern "stdcall" fn GlobalUnlock(mem: *void) i32;
pub extern "stdcall" fn GlobalFree(mem: *void) *void;

// --- PAL state -------------------------------------------------------------
pub const State = struct {
    hwnd: *void,
    dd: *void,
    dd7: *void,
    primary: *void,
    back: *void,
    clipper: *void,
    hdc: *void,
    font: *void,
    brushes: [16]*void,
    cols: u32,
    rows: u32,
    cw: u32,
    ch: u32,
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

pub fn open(title: []const u8, cols: u32, rows: u32, st: *State) bool {
    st.hwnd = nullVoid();
    st.dd = nullVoid();
    st.dd7 = nullVoid();
    st.primary = nullVoid();
    st.back = nullVoid();
    st.clipper = nullVoid();
    st.hdc = nullVoid();
    st.font = nullVoid();
    st.cols = cols;
    st.rows = rows;
    st.cw = 8;
    st.ch = 16;
    copyCstr(title, st.title[0..]);
    var cls: []const u8 = "z98gfxwnd";
    copyCstr(cls, st.class_name[0..]);

    const hinst = GetModuleHandleA(nullVoid());

    var wc: WndClassA = WndClassA{
        .style = 0,
        .lpfnWndProc = DefWindowProcA,
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
        _ = GetTextMetricsA(mdc, @ptrCast(*void, &tm));
        _ = SelectObject(mdc, old);
        _ = ReleaseDC(st.hwnd, mdc);
        if (tm.tmAveCharWidth > 0) st.cw = @intCast(u32, tm.tmAveCharWidth);
        if (tm.tmHeight > 0) st.ch = @intCast(u32, tm.tmHeight);
    }

    var i: usize = 0;
    while (i < 16) : (i += 1) {
        st.brushes[i] = CreateSolidBrush(paletteRgb(@intCast(u8, i)));
    }

    // DirectDraw: v1 create, then upgrade to v7 (the T0-pre gotcha).
    var dd_raw: *void = nullVoid();
    var hr = DirectDrawCreate(nullVoid(), &dd_raw, nullVoid());
    if (hr != S_OK) {
        close(st);
        return false;
    }
    if (isNull(dd_raw)) {
        close(st);
        return false;
    }
    st.dd = dd_raw;
    var dd7_raw: *void = nullVoid();
    hr = ddVtbl(st.dd).QueryInterface(st.dd, @ptrCast(*const void, &IID_DD7), &dd7_raw);
    if (hr != S_OK) {
        close(st);
        return false;
    }
    if (isNull(dd7_raw)) {
        close(st);
        return false;
    }
    st.dd7 = dd7_raw;
    _ = dd7Vtbl(st.dd7).SetCooperativeLevel(st.dd7, st.hwnd, DDSCL_NORMAL);

    var ddsd = zeroDesc();
    ddsd.dwFlags = DDSD_CAPS;
    ddsd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    var prim_raw: *void = nullVoid();
    hr = dd7Vtbl(st.dd7).CreateSurface(st.dd7, @ptrCast(*void, &ddsd), &prim_raw, nullVoid());
    if (hr != S_OK) {
        close(st);
        return false;
    }
    if (isNull(prim_raw)) {
        close(st);
        return false;
    }
    st.primary = prim_raw;

    ddsd = zeroDesc();
    ddsd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT;
    ddsd.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN;
    ddsd.dwWidth = OFFSCREEN_W;
    ddsd.dwHeight = OFFSCREEN_H;
    var back_raw: *void = nullVoid();
    hr = dd7Vtbl(st.dd7).CreateSurface(st.dd7, @ptrCast(*void, &ddsd), &back_raw, nullVoid());
    if (hr != S_OK) {
        close(st);
        return false;
    }
    if (isNull(back_raw)) {
        close(st);
        return false;
    }
    st.back = back_raw;

    // Best-effort clipper (windowed Blt still works without it; T0-pre proved
    // the primary<-offscreen path under DDSCL_NORMAL).
    var clip_raw: *void = nullVoid();
    hr = dd7Vtbl(st.dd7).CreateClipper(st.dd7, 0, &clip_raw, nullVoid());
    if (hr == S_OK and !isNull(clip_raw)) {
        st.clipper = clip_raw;
        _ = clipperVtbl(st.clipper).SetHWnd(st.clipper, 0, st.hwnd);
        _ = surfaceVtbl(st.primary).SetClipper(st.primary, st.clipper);
    }
    return true;
}

pub fn close(st: *State) void {
    if (!isNull(st.hdc)) {
        _ = ReleaseDC(st.back, st.hdc);
        st.hdc = nullVoid();
    }
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
        _ = PostMessageA(st.hwnd, WM_CLOSE, 0, 0);
        st.hwnd = nullVoid();
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
    if (isNull(st.primary) or isNull(st.back)) return false;
    const hr = surfaceVtbl(st.primary).Blt(st.primary, nullVoid(), st.back,
        nullVoid(), DDBLT_WAIT, nullVoid());
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
    if (!isNull(st.hdc)) {
        var bgrc = Rect{
            .left = px,
            .top = py,
            .right = px + @intCast(i32, cw) * @intCast(i32, s.len),
            .bottom = py + @intCast(i32, ch),
        };
        _ = FillRect(st.hdc, @ptrCast(*const void, &bgrc), brushFor(st, bg));
        _ = SetTextColor(st.hdc, paletteRgb(fg));
        _ = TextOutA(st.hdc, px, py, s.ptr, @intCast(i32, s.len));
    }
}

// Translate a WM_KEYDOWN virtual key to the unmodified character (the
// contract's Ctrl+S -> 's' rule). Non-character keys leave ch = 0; the app
// still gets `code`.
fn virtualToChar(vk: u16) u8 {
    if (vk >= 0x30 and vk <= 0x39) return @intCast(u8, vk);
    if (vk >= 0x41 and vk <= 0x5A) return @intCast(u8, vk + 32);
    if (vk == 0x20) return 32;
    if (vk == 0x0D) return 13;
    if (vk == 0x09) return 9;
    if (vk == 0x1B) return 27;
    if (vk == 0x08) return 8;
    if (vk == 0x2E) return 127;
    return 0;
}

fn modsNow() u8 {
    var m: u8 = 0;
    if (GetKeyState(VK_SHIFT) < 0) m = m | 1;
    if (GetKeyState(VK_CONTROL) < 0) m = m | 2;
    return m;
}

pub fn pollEvent(st: *State, raw: *RawEvent) bool {
    if (isNull(st.hwnd)) return false;
    var msg: Msg = undefined;
    while (PeekMessageA(@ptrCast(*void, &msg), nullVoid(), 0, 0, PM_REMOVE) != 0) {
        const m = msg.message;
        if (m == WM_QUIT) {
            raw.kind = EK_CLOSE;
            return true;
        }
        if (m == WM_CLOSE or m == WM_DESTROY) {
            raw.kind = EK_CLOSE;
            _ = PostQuitMessage(0);
            return true;
        }
        if (m == WM_SIZE) {
            const wp = @intCast(u32, msg.lParam & 0xFFFF);
            const hp = @intCast(u32, (msg.lParam >> 16) & 0xFFFF);
            raw.kind = EK_RESIZE;
            raw.x = wp;
            raw.y = hp;
            raw.cols = if (st.cw == 0) 1 else wp / st.cw;
            raw.rows = if (st.ch == 0) 1 else hp / st.ch;
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        if (m == WM_KEYDOWN or m == WM_KEYUP) {
            const vk = @intCast(u16, msg.wParam & 0xFFFF);
            raw.kind = if (m == WM_KEYDOWN) EK_KEY_DOWN else EK_KEY_UP;
            raw.code = vk;
            raw.ch = virtualToChar(vk);
            raw.mods = modsNow();
            _ = TranslateMessage(@ptrCast(*const void, &msg));
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
            raw.wheel = delta / WHEEL_DELTA;
            raw.mods = modsNow();
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        _ = TranslateMessage(@ptrCast(*const void, &msg));
        _ = DispatchMessageA(@ptrCast(*const void, &msg));
    }
    return false;
}

pub fn clipboardSet(st: *State, s: []const u8) bool {
    if (isNull(st.hwnd)) return false;
    if (OpenClipboard(st.hwnd) == 0) return false;
    _ = EmptyClipboard();
    const n: u32 = @intCast(u32, s.len + 1);
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
    var i: usize = 0;
    while (i < s.len) : (i += 1) dp[i] = s[i];
    dp[s.len] = 0;
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
    var n: usize = 0;
    while (sp[n] != 0) : (n += 1) {}
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
