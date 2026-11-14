// std_ddraw_pal.zig — Z98 std-side PAL for the raw DirectDraw7 pixel surface.
//
// Windowed DDSCL_NORMAL only: dynamic ddraw.dll load -> DirectDrawCreate ->
// QueryInterface(IID_IDirectDraw7) -> SetCooperativeLevel -> primary +
// 160x144 32-bit system-memory source offscreen (+ clipper). ddrawPresent
// locks the source offscreen with DDLOCK_WAIT, copies the 0x00RRGGBB pixels
// row by row honoring lPitch, unlocks, then does one hardware stretch Blt to
// the primary at the window client rect. Only if that stretch Blt fails does
// it fall back once to a 640x576 staging offscreen (nearest-neighbour, 4-byte
// writes) plus a 1:1 Blt. No fullscreen, no Flip, no SetDisplayMode, no
// BltFast.
//
// The COM vtables are hand-written with the exact MinGW ddraw.h slot order
// (IDirectDraw7 at :1798, IDirectDrawSurface7 at :2503, IDirectDrawClipper at
// :1335). The C prototypes for the Win32/DDraw symbols come from <windows.h>
// and <ddraw.h>; Z98 emits no extern prototypes. GUID bytes are local so the
// exe needs no dxguid data library.
//
// State lives only in std_ddraw.zig's one module-scope DdrawState; this PAL is
// stateless and every function receives the state pointer.

@cInclude("<windows.h>");
@cInclude("<ddraw.h>");

// --- constants (winuser.h / ddraw.h numeric values) ------------------------
const WINDOW_STYLE: u32 = 0x00CA0000; // WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
const CW_USEDEFAULT: i32 = -2147483648;
const SW_SHOW: i32 = 5;
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOACTIVATE: u32 = 0x0010;
const WM_DESTROY: u32 = 0x0002;
const WM_CLOSE: u32 = 0x0010;
const WM_QUIT: u32 = 0x0012;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_SYSKEYDOWN: u32 = 0x0104;
const WM_SYSKEYUP: u32 = 0x0105;
const WM_ACTIVATE: u32 = 0x0006;
const WM_SETFOCUS: u32 = 0x0007;
const WM_KILLFOCUS: u32 = 0x0008;
const PM_REMOVE: u32 = 0x0001;
const IDC_ARROW: u32 = 32512;
const DDSCL_NORMAL: u32 = 0x00000008;
const DDSCAPS_PRIMARYSURFACE: u32 = 0x00000200;
const DDSCAPS_OFFSCREENPLAIN: u32 = 0x00000040;
const DDSCAPS_SYSTEMMEMORY: u32 = 0x00000800;
const DDSD_CAPS: u32 = 0x00000001;
const DDSD_HEIGHT: u32 = 0x00000002;
const DDSD_WIDTH: u32 = 0x00000004;
const DDSD_PIXELFORMAT: u32 = 0x00001000;
const DDPF_RGB: u32 = 0x00000040;
const DDBLT_WAIT: u32 = 0x01000000;
const DDLOCK_WAIT: u32 = 0x00000001;
const DDLOCK_WRITEONLY: u32 = 0x00000020;
const S_OK: u32 = 0;
const E_FAIL: u32 = 0x80004005;
const DDERR_SURFACELOST: u32 = 0x887601C2;
const STAGING_W: u32 = 640;
const STAGING_H: u32 = 576;
const MAX_SRC_W: u32 = 640;
const MAX_SRC_H: u32 = 576;
const EVENT_KEY_DOWN: u8 = 0;
const EVENT_KEY_UP: u8 = 1;
const EVENT_CLOSE: u8 = 2;
const EVENT_FOCUS: u8 = 3;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn isNull(p: *void) bool {
    return @ptrToInt(p) == 0;
}

fn copyCstr(s: []const u8, out: []u8) void {
    var n: usize = s.len;
    if (n >= out.len) n = out.len - 1;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = s[i];
    out[n] = 0;
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

// DDSURFACEDESC2 (i386 mingw, 124 bytes).
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

// --- COM vtables (exact ddraw.h slot order) --------------------------------
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
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
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
    GetDC: extern "stdcall" fn() void,
    GetFlipStatus: extern "stdcall" fn() void,
    GetOverlayPosition: extern "stdcall" fn() void,
    GetPalette: extern "stdcall" fn() void,
    GetPixelFormat: extern "stdcall" fn() void,
    GetSurfaceDesc: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    IsLost: extern "stdcall" fn() void,
    Lock: extern "stdcall" fn(iface: *void, dest: *void, desc: *void, flags: u32, event: *void) u32,
    ReleaseDC: extern "stdcall" fn() void,
    Restore: extern "stdcall" fn(iface: *void) u32,
    SetClipper: extern "stdcall" fn(iface: *void, clipper: *void) u32,
    SetColorKey: extern "stdcall" fn() void,
    SetOverlayPosition: extern "stdcall" fn() void,
    SetPalette: extern "stdcall" fn() void,
    Unlock: extern "stdcall" fn(iface: *void, surface: *void) u32,
    UpdateOverlay: extern "stdcall" fn() void,
    UpdateOverlayDisplay: extern "stdcall" fn() void,
    UpdateOverlayZOrder: extern "stdcall" fn() void,
    GetDDInterface: extern "stdcall" fn() void,
    PageLock: extern "stdcall" fn() void,
    PageUnlock: extern "stdcall" fn() void,
    SetSurfaceDesc: extern "stdcall" fn() void,
    SetPrivateData: extern "stdcall" fn() void,
    GetPrivateData: extern "stdcall" fn() void,
    FreePrivateData: extern "stdcall" fn() void,
    GetUniquenessValue: extern "stdcall" fn() void,
    ChangeUniquenessValue: extern "stdcall" fn() void,
    SetPriority: extern "stdcall" fn() void,
    GetPriority: extern "stdcall" fn() void,
    SetLOD: extern "stdcall" fn() void,
    GetLOD: extern "stdcall" fn() void,
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

// --- external Win32 / DDraw symbols ----------------------------------------
const DirectDrawCreateFn = extern "stdcall" fn(lpGuid: *void, out: **void, outer: *void) u32;
pub extern "stdcall" fn GetModuleHandleA(name: *void) *void;
pub extern "stdcall" fn LoadLibraryA(name: [*]const u8) *void;
pub extern "stdcall" fn GetProcAddress(mod: *void, name: [*]const u8) *void;
pub extern "stdcall" fn FreeLibrary(mod: *void) i32;
pub extern "stdcall" fn IsWindow(hwnd: *void) i32;
pub extern "stdcall" fn RegisterClassA(wc: *void) u16;
pub extern "stdcall" fn CreateWindowExA(ex_style: u32, cls: *void, title: *void, style: u32, x: i32, y: i32, w: i32, h: i32, parent: *void, menu: *void, inst: *void, param: *void) *void;
pub extern "stdcall" fn DefWindowProcA(hwnd: *void, msg: u32, wparam: u32, lparam: i32) i32;
pub extern "stdcall" fn ShowWindow(hwnd: *void, cmd: i32) i32;
pub extern "stdcall" fn UpdateWindow(hwnd: *void) i32;
pub extern "stdcall" fn SetForegroundWindow(hwnd: *void) i32;
pub extern "stdcall" fn DestroyWindow(hwnd: *void) i32;
pub extern "stdcall" fn UnregisterClassA(name: [*]const u8, inst: *void) i32;
pub extern "stdcall" fn LoadCursorA(inst: *void, name: *void) *void;
pub extern "stdcall" fn PeekMessageA(msg: *void, hwnd: *void, min: u32, max: u32, remove: u32) i32;
pub extern "stdcall" fn TranslateMessage(msg: *const void) i32;
pub extern "stdcall" fn DispatchMessageA(msg: *const void) i32;
pub extern "stdcall" fn PostQuitMessage(code: i32) void;
pub extern "stdcall" fn GetClientRect(hwnd: *void, rc: *void) i32;
pub extern "stdcall" fn ClientToScreen(hwnd: *void, pt: *void) i32;
pub extern "stdcall" fn AdjustWindowRect(rc: *void, style: u32, menu: i32) i32;
pub extern "stdcall" fn SetWindowPos(hwnd: *void, after: *void, x: i32, y: i32, w: i32, h: i32, flags: u32) i32;

// --- state -----------------------------------------------------------------
pub const State = struct {
    hwnd: *void,
    hinst: *void,
    dd: *void,
    dd7: *void,
    dd_lib: *void,
    dd_create: *void,
    primary: *void,
    src: *void,
    staging: *void,
    clipper: *void,
    src_w: u32,
    src_h: u32,
    scale: u32,
    staging_tried: bool,
    window_gone: bool,
    title: [128]u8,
    class_name: [32]u8,
};

pub const Event = struct {
    kind: u8,
    key: u16,
    close: bool,
};

fn zeroEvent(ev: *Event) void {
    ev.kind = 0;
    ev.key = 0;
    ev.close = false;
}

// --- resource helpers ------------------------------------------------------
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

fn releaseDdrawLib(st: *State) void {
    if (!isNull(st.dd_lib)) {
        _ = FreeLibrary(st.dd_lib);
    }
    st.dd_lib = nullVoid();
    st.dd_create = nullVoid();
}

fn makeSurface(st: *State, w: u32, h: u32, primary: bool) *void {
    var ddsd = zeroDesc();
    if (primary) {
        ddsd.dwFlags = DDSD_CAPS;
        ddsd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    } else {
        ddsd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT | DDSD_PIXELFORMAT;
        ddsd.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN | DDSCAPS_SYSTEMMEMORY;
        ddsd.dwWidth = w;
        ddsd.dwHeight = h;
        ddsd.pfSize = 32;
        ddsd.pfFlags = DDPF_RGB;
        ddsd.pfBitCount = 32;
        ddsd.pfRMask = 0x00FF0000;
        ddsd.pfGMask = 0x0000FF00;
        ddsd.pfBMask = 0x000000FF;
        ddsd.pfAMask = 0;
    }
    var raw: *void = nullVoid();
    const hr = dd7Vtbl(st.dd7).CreateSurface(st.dd7, @ptrCast(*void, &ddsd), &raw, nullVoid());
    if (hr != S_OK) return nullVoid();
    return raw;
}

fn createClipper(st: *State) bool {
    var clip_raw: *void = nullVoid();
    var hr = dd7Vtbl(st.dd7).CreateClipper(st.dd7, 0, &clip_raw, nullVoid());
    if (hr != S_OK or isNull(clip_raw)) return false;
    st.clipper = clip_raw;
    hr = clipperVtbl(st.clipper).SetHWnd(st.clipper, 0, st.hwnd);
    if (hr != S_OK) {
        releaseClipper(st.clipper);
        st.clipper = nullVoid();
        return false;
    }
    hr = surfaceVtbl(st.primary).SetClipper(st.primary, st.clipper);
    if (hr != S_OK) {
        releaseClipper(st.clipper);
        st.clipper = nullVoid();
        return false;
    }
    return true;
}

fn rebuildClipper(st: *State) bool {
    releaseClipper(st.clipper);
    st.clipper = nullVoid();
    return createClipper(st);
}

fn loadDdraw(st: *State) bool {
    var dll_name: [32]u8 = undefined;
    copyCstr("ddraw.dll", dll_name[0..]);
    const lib = LoadLibraryA(@ptrCast([*]const u8, &dll_name[0]));
    if (isNull(lib)) return false;
    st.dd_lib = lib;
    var fn_name: [32]u8 = undefined;
    copyCstr("DirectDrawCreate", fn_name[0..]);
    const proc = GetProcAddress(lib, @ptrCast([*]const u8, &fn_name[0]));
    if (isNull(proc)) {
        releaseDdrawLib(st);
        return false;
    }
    st.dd_create = proc;
    return true;
}

// --- open/close ------------------------------------------------------------
pub fn open(title: []const u8, src_w: u32, src_h: u32, scale: u32, st: *State) u8 {
    st.hwnd = nullVoid();
    st.hinst = nullVoid();
    st.dd = nullVoid();
    st.dd7 = nullVoid();
    st.dd_lib = nullVoid();
    st.dd_create = nullVoid();
    st.primary = nullVoid();
    st.src = nullVoid();
    st.staging = nullVoid();
    st.clipper = nullVoid();
    st.src_w = src_w;
    st.src_h = src_h;
    st.scale = scale;
    st.staging_tried = false;
    st.window_gone = false;
    copyCstr(title, st.title[0..]);
    copyCstr("z98ddrawwnd", st.class_name[0..]);

    const hinst = GetModuleHandleA(nullVoid());
    st.hinst = hinst;

    const wnd_void: *void = @ptrCast(*void, DefWindowProcA);
    const wnd_proc: WndProc = @ptrCast(WndProc, wnd_void);
    var wc: WndClassA = WndClassA{
        .style = 0,
        .lpfnWndProc = wnd_proc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hinst,
        .hIcon = nullVoid(),
        .hCursor = LoadCursorA(nullVoid(), @intToPtr(*void, @intCast(usize, IDC_ARROW))),
        .hbrBackground = nullVoid(),
        .lpszMenuName = nullVoid(),
        .lpszClassName = @ptrCast(*void, &st.class_name[0]),
    };
    _ = RegisterClassA(@ptrCast(*void, &wc));

    const cw: i32 = @intCast(i32, src_w * scale);
    const ch: i32 = @intCast(i32, src_h * scale);
    var rc = Rect{ .left = 0, .top = 0, .right = cw, .bottom = ch };
    var ow: i32 = cw;
    var oh: i32 = ch;
    if (AdjustWindowRect(@ptrCast(*void, &rc), WINDOW_STYLE, 0) != 0) {
        ow = rc.right - rc.left;
        oh = rc.bottom - rc.top;
    }
    st.hwnd = CreateWindowExA(0, @ptrCast(*void, &st.class_name[0]),
        @ptrCast(*void, &st.title[0]), WINDOW_STYLE,
        CW_USEDEFAULT, CW_USEDEFAULT, ow, oh,
        nullVoid(), nullVoid(), hinst, nullVoid());
    if (isNull(st.hwnd)) {
        close(st);
        return 1;
    }
    _ = ShowWindow(st.hwnd, SW_SHOW);
    _ = UpdateWindow(st.hwnd);
    _ = SetForegroundWindow(st.hwnd);

    if (!loadDdraw(st)) {
        close(st);
        return 1;
    }
    const create: DirectDrawCreateFn = @ptrCast(DirectDrawCreateFn, st.dd_create);
    var dd_raw: *void = nullVoid();
    var hr = create(nullVoid(), &dd_raw, nullVoid());
    if (hr != S_OK or isNull(dd_raw)) {
        close(st);
        return 1;
    }
    st.dd = dd_raw;
    var dd7_raw: *void = nullVoid();
    hr = ddVtbl(st.dd).QueryInterface(st.dd, @ptrCast(*const void, &IID_DD7), &dd7_raw);
    if (hr != S_OK or isNull(dd7_raw)) {
        close(st);
        return 1;
    }
    st.dd7 = dd7_raw;
    hr = dd7Vtbl(st.dd7).SetCooperativeLevel(st.dd7, st.hwnd, DDSCL_NORMAL);
    if (hr != S_OK) {
        close(st);
        return 1;
    }

    st.primary = makeSurface(st, src_w, src_h, true);
    if (isNull(st.primary)) {
        close(st);
        return 2;
    }
    st.src = makeSurface(st, src_w, src_h, false);
    if (isNull(st.src)) {
        close(st);
        return 2;
    }
    if (!createClipper(st)) {
        close(st);
        return 1;
    }
    return 0;
}

pub fn close(st: *State) void {
    releaseSurface(st.staging);
    releaseSurface(st.src);
    releaseSurface(st.primary);
    releaseClipper(st.clipper);
    releaseDd7(st.dd7);
    releaseDd(st.dd);
    releaseDdrawLib(st);
    st.staging = nullVoid();
    st.src = nullVoid();
    st.primary = nullVoid();
    st.clipper = nullVoid();
    st.dd7 = nullVoid();
    st.dd = nullVoid();
    st.scale = 0;
    st.staging_tried = false;
    st.window_gone = false;
    if (!isNull(st.hwnd)) {
        _ = DestroyWindow(st.hwnd);
        st.hwnd = nullVoid();
    }
    if (!isNull(st.hinst)) {
        _ = UnregisterClassA(@ptrCast([*]const u8, &st.class_name[0]), st.hinst);
        st.hinst = nullVoid();
    }
}

pub fn window(st: *State) *void {
    return st.hwnd;
}

pub fn setScale(st: *State, scale_in: u32) bool {
    if (isNull(st.hwnd)) return false;
    if (scale_in < 1 or scale_in > 4) return false;
    const cw: i32 = @intCast(i32, st.src_w * scale_in);
    const ch: i32 = @intCast(i32, st.src_h * scale_in);
    if (cw <= 0 or ch <= 0) return false;
    var rc = Rect{ .left = 0, .top = 0, .right = cw, .bottom = ch };
    var ow: i32 = cw;
    var oh: i32 = ch;
    if (AdjustWindowRect(@ptrCast(*void, &rc), WINDOW_STYLE, 0) != 0) {
        ow = rc.right - rc.left;
        oh = rc.bottom - rc.top;
    }
    const flags: u32 = SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE;
    if (SetWindowPos(st.hwnd, nullVoid(), 0, 0, ow, oh, flags) == 0) return false;
    st.scale = scale_in;
    return rebuildClipper(st);
}

// --- presentation ----------------------------------------------------------
fn clientDest(st: *State, dest: *Rect) bool {
    var crc: Rect = undefined;
    if (GetClientRect(st.hwnd, @ptrCast(*void, &crc)) == 0) return false;
    const cw: i32 = crc.right - crc.left;
    const ch: i32 = crc.bottom - crc.top;
    if (cw <= 0 or ch <= 0) {
        dest.* = Rect{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
        return true;
    }
    var origin = Point{ .x = crc.left, .y = crc.top };
    if (ClientToScreen(st.hwnd, @ptrCast(*void, &origin)) == 0) return false;
    dest.* = Rect{
        .left = origin.x,
        .top = origin.y,
        .right = origin.x + cw,
        .bottom = origin.y + ch,
    };
    return true;
}

fn copyPixels(st: *State, pixels: []const u32) u32 {
    var lockdesc = zeroDesc();
    const hr = surfaceVtbl(st.src).Lock(st.src, nullVoid(), @ptrCast(*void, &lockdesc),
        DDLOCK_WAIT | DDLOCK_WRITEONLY, nullVoid());
    if (hr != S_OK) return hr;
    if (isNull(lockdesc.lpSurface)) {
        _ = surfaceVtbl(st.src).Unlock(st.src, nullVoid());
        return E_FAIL;
    }
    const base: [*]u8 = @ptrCast([*]u8, lockdesc.lpSurface);
    const pitch: usize = @intCast(usize, lockdesc.lPitch);
    const rows: usize = @intCast(usize, st.src_h);
    const row_px: usize = @intCast(usize, st.src_w);
    const sp: [*]const u32 = pixels.ptr;
    var y: usize = 0;
    while (y < rows) : (y += 1) {
        const dp: [*]u32 = @ptrCast([*]u32, base + y * pitch);
        const srow: [*]const u32 = sp + y * row_px;
        var x: usize = 0;
        while (x < row_px) : (x += 1) dp[x] = srow[x];
    }
    return surfaceVtbl(st.src).Unlock(st.src, nullVoid());
}

fn bltStretch(st: *State, dest: *Rect, src_rect: *Rect) u32 {
    return surfaceVtbl(st.primary).Blt(st.primary, @ptrCast(*void, dest),
        st.src, @ptrCast(*void, src_rect), DDBLT_WAIT, nullVoid());
}

fn ensureStaging(st: *State) bool {
    if (!isNull(st.staging)) return true;
    if (st.staging_tried) return false;
    st.staging_tried = true;
    st.staging = makeSurface(st, STAGING_W, STAGING_H, false);
    return !isNull(st.staging);
}

// Software nearest-neighbour fallback: one Lock of the 640x576 staging
// offscreen, 4-byte writes per destination pixel block, one Unlock, then a
// 1:1 Blt to the primary. Never software-scales the primary by default.
fn softwareScale(st: *State, pixels: []const u32, scale: u32, dest: *Rect) u32 {
    const sw: u32 = st.src_w * scale;
    const sh: u32 = st.src_h * scale;
    if (sw > STAGING_W or sh > STAGING_H) return E_FAIL;
    if (!ensureStaging(st)) return E_FAIL;
    var lockdesc = zeroDesc();
    var hr = surfaceVtbl(st.staging).Lock(st.staging, nullVoid(), @ptrCast(*void, &lockdesc),
        DDLOCK_WAIT | DDLOCK_WRITEONLY, nullVoid());
    if (hr != S_OK) return hr;
    if (isNull(lockdesc.lpSurface)) {
        _ = surfaceVtbl(st.staging).Unlock(st.staging, nullVoid());
        return E_FAIL;
    }
    const base: [*]u8 = @ptrCast([*]u8, lockdesc.lpSurface);
    const pitch: usize = @intCast(usize, lockdesc.lPitch);
    const sp: [*]const u32 = pixels.ptr;
    const rows: usize = @intCast(usize, st.src_h);
    const cols: usize = @intCast(usize, st.src_w);
    var sy: usize = 0;
    while (sy < rows) : (sy += 1) {
        var fy: u32 = 0;
        while (fy < scale) : (fy += 1) {
            const dy: usize = sy * @intCast(usize, scale) + @intCast(usize, fy);
            const dp: [*]u32 = @ptrCast([*]u32, base + dy * pitch);
            const srow: [*]const u32 = sp + sy * cols;
            var sx: usize = 0;
            while (sx < cols) : (sx += 1) {
                const c: u32 = srow[sx];
                const dx0: usize = sx * @intCast(usize, scale);
                var fx: u32 = 0;
                while (fx < scale) : (fx += 1) {
                    dp[dx0 + @intCast(usize, fx)] = c;
                }
            }
        }
    }
    hr = surfaceVtbl(st.staging).Unlock(st.staging, nullVoid());
    if (hr != S_OK) return hr;
    var src_rect = Rect{
        .left = 0,
        .top = 0,
        .right = @intCast(i32, sw),
        .bottom = @intCast(i32, sh),
    };
    return surfaceVtbl(st.primary).Blt(st.primary, @ptrCast(*void, dest),
        st.staging, @ptrCast(*void, &src_rect), DDBLT_WAIT, nullVoid());
}

fn restoreAll(st: *State) void {
    if (!isNull(st.primary)) _ = surfaceVtbl(st.primary).Restore(st.primary);
    if (!isNull(st.src)) _ = surfaceVtbl(st.src).Restore(st.src);
    if (!isNull(st.staging)) _ = surfaceVtbl(st.staging).Restore(st.staging);
}

fn attemptPresent(st: *State, pixels: []const u32, scale: u32, dest: *Rect) u32 {
    var hr = copyPixels(st, pixels);
    if (hr != S_OK) return hr;
    var src_rect = Rect{
        .left = 0,
        .top = 0,
        .right = @intCast(i32, st.src_w),
        .bottom = @intCast(i32, st.src_h),
    };
    hr = bltStretch(st, dest, &src_rect);
    if (hr == S_OK) return S_OK;
    if (hr == DDERR_SURFACELOST) return hr;
    return softwareScale(st, pixels, scale, dest);
}

pub fn present(st: *State, pixels: []const u32, scale: u32) bool {
    if (isNull(st.primary) or isNull(st.src) or isNull(st.hwnd)) return false;
    const need: usize = @intCast(usize, st.src_w) * @intCast(usize, st.src_h);
    if (pixels.len < need) return false;
    var dest: Rect = undefined;
    if (!clientDest(st, &dest)) return false;
    // Minimized/0x0 client: nothing to present, but this is not an error.
    if (dest.right <= dest.left or dest.bottom <= dest.top) return true;
    var hr = attemptPresent(st, pixels, scale, &dest);
    if (hr == DDERR_SURFACELOST) {
        restoreAll(st);
        hr = attemptPresent(st, pixels, scale, &dest);
    }
    return hr == S_OK;
}

// --- event pump ------------------------------------------------------------
pub fn poll(st: *State, ev: *Event) bool {
    zeroEvent(ev);
    if (isNull(st.hwnd)) return false;
    if (IsWindow(st.hwnd) == 0) {
        if (st.window_gone) return false;
        st.window_gone = true;
        ev.kind = EVENT_CLOSE;
        ev.close = true;
        return true;
    }
    var msg: Msg = undefined;
    while (PeekMessageA(@ptrCast(*void, &msg), nullVoid(), 0, 0, PM_REMOVE) != 0) {
        const m = msg.message;
        zeroEvent(ev);
        if (m == WM_QUIT or m == WM_CLOSE or m == WM_DESTROY) {
            ev.kind = EVENT_CLOSE;
            ev.close = true;
            if (m == WM_CLOSE) _ = PostQuitMessage(0);
            return true;
        }
        if (m == WM_KEYDOWN or m == WM_SYSKEYDOWN) {
            ev.kind = EVENT_KEY_DOWN;
            ev.key = @intCast(u16, msg.wParam & 0xFFFF);
            _ = TranslateMessage(@ptrCast(*const void, &msg));
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        if (m == WM_KEYUP or m == WM_SYSKEYUP) {
            ev.kind = EVENT_KEY_UP;
            ev.key = @intCast(u16, msg.wParam & 0xFFFF);
            _ = TranslateMessage(@ptrCast(*const void, &msg));
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        if (m == WM_ACTIVATE or m == WM_SETFOCUS or m == WM_KILLFOCUS) {
            ev.kind = EVENT_FOCUS;
            _ = DispatchMessageA(@ptrCast(*const void, &msg));
            return true;
        }
        _ = TranslateMessage(@ptrCast(*const void, &msg));
        _ = DispatchMessageA(@ptrCast(*const void, &msg));
    }
    return false;
}

pub const max_src_w: u32 = MAX_SRC_W;
pub const max_src_h: u32 = MAX_SRC_H;
