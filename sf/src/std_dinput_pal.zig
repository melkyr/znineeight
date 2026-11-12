// std_dinput_pal.zig — Z98 std-side PAL for DirectInput8 keyboard + gamepad.
//
// Dynamic dinput8.dll load -> DirectInput8Create(IID_IDirectInput8A). The
// keyboard device uses GUID_SysKeyboard with a local c_dfDIKeyboard-equivalent
// data format, DISCL_FOREGROUND|DISCL_NONEXCLUSIVE, and Acquire. The gamepad is
// the first attached DI8DEVCLASS_GAMECTRL device, with a local c_dfDIJoystick
// data format, DISCL_BACKGROUND|DISCL_NONEXCLUSIVE, and Acquire. If the DLL,
// the create function, or the keyboard device is unavailable, the PAL reports
// the GetAsyncKeyState fallback instead.
//
// The COM vtables are hand-written with the exact MinGW dinput.h slot order
// (IDirectInput8A 11 slots at :2376, IDirectInputDevice8A 32 slots at :1944).
// Unused slots are `extern "stdcall" fn() void` placeholders so field indices
// stay exact. The data formats and GUID bytes are local, so the exe needs
// neither dxguid nor a static DINPUT8.DLL import.
//
// This PAL is stateless: the one module-scope DinputState lives in
// std_dinput.zig and every function (including the EnumDevices callback via its
// pvRef) receives that pointer.

@cInclude("<windows.h>");

// --- constants (dinput.h / winuser.h numeric values) -----------------------
const DIRECTINPUT_VERSION: u32 = 0x0800;
const S_OK: u32 = 0;
const DIERR_INPUTLOST: u32 = 0x8007001E;
const DIERR_NOTACQUIRED: u32 = 0x8007000C;
const DI8DEVCLASS_GAMECTRL: u32 = 4;
const DIEDFL_ATTACHEDONLY: u32 = 0x00000001;
const DIENUM_STOP: i32 = 0;
const DISCL_NONEXCLUSIVE: u32 = 0x00000002;
const DISCL_FOREGROUND: u32 = 0x00000004;
const DISCL_BACKGROUND: u32 = 0x00000008;

const DIK_ESCAPE: usize = 0x01;
const DIK_BACK: usize = 0x0E;
const DIK_RETURN: usize = 0x1C;
const DIK_Z: usize = 0x2C;
const DIK_X: usize = 0x2D;
const DIK_UP: usize = 0xC8;
const DIK_LEFT: usize = 0xCB;
const DIK_RIGHT: usize = 0xCD;
const DIK_DOWN: usize = 0xD0;

const VK_BACK: i32 = 0x08;
const VK_RETURN: i32 = 0x0D;
const VK_ESCAPE: i32 = 0x1B;
const VK_LEFT: i32 = 0x25;
const VK_UP: i32 = 0x26;
const VK_RIGHT: i32 = 0x27;
const VK_DOWN: i32 = 0x28;
const VK_Z: i32 = 0x5A;
const VK_X: i32 = 0x58;

const DIDF_ABSAXIS: u32 = 0x00000001;
const DIDF_RELAXIS: u32 = 0x00000002;
const DIOBJ_AXIS: u32 = 0x80FFFF03;
const DIOBJ_POV: u32 = 0x80FFFF10;
const DIOBJ_BUTTON: u32 = 0x80FFFF0C;
const DIOBJ_KBD_BUTTON: u32 = 0x8000000C;
const DIOBJ_AXIS_FLAGS: u32 = 0x00000100;

const KEYBOARD_STATE_BYTES: u32 = 256;
const JOYSTICK_STATE_BYTES: u32 = 80;
const JOY_DEADZONE: i32 = 250;

const BACKEND_DINPUT8: u8 = 1;
const BACKEND_FALLBACK: u8 = 2;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn isNull(p: *void) bool {
    return @ptrToInt(p) == 0;
}

fn nullGuid() *const Guid {
    return @ptrCast(*const Guid, @intToPtr(*const Guid, 0));
}

fn copyCstr(s: []const u8, out: []u8) void {
    var n: usize = s.len;
    if (n >= out.len) n = out.len - 1;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = s[i];
    out[n] = 0;
}

// --- GUID / data-format mirrors (i386, natural layout) ---------------------
const Guid = struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

// IID_IDirectInput8A = {bf798030-483a-4da2-aa99-5d64ed369700}
const IID_DI8: Guid = Guid{
    .data1 = 0xBF798030,
    .data2 = 0x483A,
    .data3 = 0x4DA2,
    .data4 = [8]u8{ 0xAA, 0x99, 0x5D, 0x64, 0xED, 0x36, 0x97, 0x00 },
};

// GUID_SysKeyboard = {6f1d2b61-d5a0-11cf-bfc7-444553540000}
const GUID_SYS_KEYBOARD: Guid = Guid{
    .data1 = 0x6F1D2B61,
    .data2 = 0xD5A0,
    .data3 = 0x11CF,
    .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 },
};

// GUID_Key = {55728220-d33c-11cf-bfc7-444553540000}
const GUID_KEY: Guid = Guid{
    .data1 = 0x55728220,
    .data2 = 0xD33C,
    .data3 = 0x11CF,
    .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 },
};

const GUID_XAXIS: Guid = Guid{ .data1 = 0xA36D02E0, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_YAXIS: Guid = Guid{ .data1 = 0xA36D02E1, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_ZAXIS: Guid = Guid{ .data1 = 0xA36D02E2, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_RXAXIS: Guid = Guid{ .data1 = 0xA36D02F4, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_RYAXIS: Guid = Guid{ .data1 = 0xA36D02F5, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_RZAXIS: Guid = Guid{ .data1 = 0xA36D02E3, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_SLIDER: Guid = Guid{ .data1 = 0xA36D02E4, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_POV: Guid = Guid{ .data1 = 0xA36D02F2, .data2 = 0xC9F3, .data3 = 0x11CF, .data4 = [8]u8{ 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };

const ObjFormat = struct {
    pguid: *const Guid,
    dwOfs: u32,
    dwType: u32,
    dwFlags: u32,
};

const DataFormat = struct {
    dwSize: u32,
    dwObjSize: u32,
    dwFlags: u32,
    dwDataSize: u32,
    dwNumObjs: u32,
    rgodf: *ObjFormat,
};

const JoyState = struct {
    lX: i32,
    lY: i32,
    lZ: i32,
    lRx: i32,
    lRy: i32,
    lRz: i32,
    rglSlider: [2]i32,
    rgdwPOV: [4]u32,
    rgbButtons: [32]u8,
};

// --- COM vtables (exact MinGW dinput.h slot order) -------------------------
const Di8Vtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    CreateDevice: extern "stdcall" fn(iface: *void, rguid: *const void, out: **void, outer: *void) u32,
    EnumDevices: extern "stdcall" fn(iface: *void, dev_type: u32, cb: *const void, ref: *void, flags: u32) u32,
    GetDeviceStatus: extern "stdcall" fn() void,
    RunControlPanel: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    FindDevice: extern "stdcall" fn() void,
    EnumDevicesBySemantics: extern "stdcall" fn() void,
    ConfigureDevices: extern "stdcall" fn() void,
};

const Dev8Vtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    GetCapabilities: extern "stdcall" fn() void,
    EnumObjects: extern "stdcall" fn() void,
    GetProperty: extern "stdcall" fn() void,
    SetProperty: extern "stdcall" fn() void,
    Acquire: extern "stdcall" fn(iface: *void) u32,
    Unacquire: extern "stdcall" fn(iface: *void) u32,
    GetDeviceState: extern "stdcall" fn(iface: *void, cb: u32, data: *void) u32,
    GetDeviceData: extern "stdcall" fn() void,
    SetDataFormat: extern "stdcall" fn(iface: *void, format: *const void) u32,
    SetEventNotification: extern "stdcall" fn() void,
    SetCooperativeLevel: extern "stdcall" fn(iface: *void, hwnd: *void, flags: u32) u32,
    GetObjectInfo: extern "stdcall" fn() void,
    GetDeviceInfo: extern "stdcall" fn() void,
    RunControlPanel: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    CreateEffect: extern "stdcall" fn() void,
    EnumEffects: extern "stdcall" fn() void,
    GetEffectInfo: extern "stdcall" fn() void,
    GetForceFeedbackState: extern "stdcall" fn() void,
    SendForceFeedbackCommand: extern "stdcall" fn() void,
    EnumCreatedEffectObjects: extern "stdcall" fn() void,
    Escape: extern "stdcall" fn() void,
    Poll: extern "stdcall" fn(iface: *void) u32,
    SendDeviceData: extern "stdcall" fn() void,
    EnumEffectsInFile: extern "stdcall" fn() void,
    WriteEffectToFile: extern "stdcall" fn() void,
    BuildActionMap: extern "stdcall" fn() void,
    SetActionMap: extern "stdcall" fn() void,
    GetImageInfo: extern "stdcall" fn() void,
};

const Di8Obj = struct { vtbl: *const Di8Vtbl };
const Dev8Obj = struct { vtbl: *const Dev8Vtbl };

fn di8Vtbl(p: *void) *const Di8Vtbl {
    const o: *const Di8Obj = @ptrCast(*const Di8Obj, p);
    return o.vtbl;
}

fn devVtbl(p: *void) *const Dev8Vtbl {
    const o: *const Dev8Obj = @ptrCast(*const Dev8Obj, p);
    return o.vtbl;
}

// --- external Win32 symbols ------------------------------------------------
const DirectInput8CreateFn = extern "stdcall" fn(hinst: *void, version: u32, riid: *const void, out: **void, outer: *void) u32;

pub extern "stdcall" fn GetModuleHandleA(name: *void) *void;
pub extern "stdcall" fn LoadLibraryA(name: [*]const u8) *void;
pub extern "stdcall" fn GetProcAddress(mod: *void, name: [*]const u8) *void;
pub extern "stdcall" fn FreeLibrary(mod: *void) i32;
pub extern "stdcall" fn GetAsyncKeyState(vk: i32) i16;

// --- state -----------------------------------------------------------------
pub const State = struct {
    backend: u8,
    lib: *void,
    di8: *void,
    kbd: *void,
    joy: *void,
    kbd_keys: [256]u8,
    joy_state: JoyState,
    kbd_format: DataFormat,
    kbd_objects: [256]ObjFormat,
    joy_format: DataFormat,
    joy_objects: [44]ObjFormat,
    joy_guid: Guid,
    joy_found: bool,
};

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

// --- data-format setup -----------------------------------------------------
fn axisObj(g: *const Guid, ofs: u32) ObjFormat {
    return ObjFormat{ .pguid = g, .dwOfs = ofs, .dwType = DIOBJ_AXIS, .dwFlags = DIOBJ_AXIS_FLAGS };
}

fn povObj(ofs: u32) ObjFormat {
    return ObjFormat{ .pguid = &GUID_POV, .dwOfs = ofs, .dwType = DIOBJ_POV, .dwFlags = 0 };
}

fn buttonObj(ofs: u32) ObjFormat {
    return ObjFormat{ .pguid = nullGuid(), .dwOfs = ofs, .dwType = DIOBJ_BUTTON, .dwFlags = 0 };
}

fn initKeyboardFormat(st: *State) void {
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        st.kbd_objects[@intCast(usize, i)] = ObjFormat{
            .pguid = &GUID_KEY,
            .dwOfs = i,
            .dwType = DIOBJ_KBD_BUTTON | (i << 8),
            .dwFlags = 0,
        };
    }
    st.kbd_format = DataFormat{
        .dwSize = 24,
        .dwObjSize = 16,
        .dwFlags = DIDF_RELAXIS,
        .dwDataSize = 256,
        .dwNumObjs = 256,
        .rgodf = @ptrCast(*ObjFormat, &st.kbd_objects[0]),
    };
}

fn initJoystickFormat(st: *State) void {
    st.joy_objects[0] = axisObj(&GUID_XAXIS, 0);
    st.joy_objects[1] = axisObj(&GUID_YAXIS, 4);
    st.joy_objects[2] = axisObj(&GUID_ZAXIS, 8);
    st.joy_objects[3] = axisObj(&GUID_RXAXIS, 12);
    st.joy_objects[4] = axisObj(&GUID_RYAXIS, 16);
    st.joy_objects[5] = axisObj(&GUID_RZAXIS, 20);
    st.joy_objects[6] = axisObj(&GUID_SLIDER, 24);
    st.joy_objects[7] = axisObj(&GUID_SLIDER, 28);
    st.joy_objects[8] = povObj(32);
    st.joy_objects[9] = povObj(36);
    st.joy_objects[10] = povObj(40);
    st.joy_objects[11] = povObj(44);
    var i: u32 = 0;
    while (i < 32) : (i += 1) {
        st.joy_objects[12 + @intCast(usize, i)] = buttonObj(48 + i);
    }
    st.joy_format = DataFormat{
        .dwSize = 24,
        .dwObjSize = 16,
        .dwFlags = DIDF_ABSAXIS,
        .dwDataSize = 80,
        .dwNumObjs = 44,
        .rgodf = @ptrCast(*ObjFormat, &st.joy_objects[0]),
    };
}

// --- EnumDevices callback (stdcall definition, original C symbol) ----------
extern "stdcall" fn enumDeviceCallback(instance: *void, ref: *void) i32 {
    const st: *State = @ptrCast(*State, ref);
    const base: [*]const u8 = @ptrCast([*]const u8, instance);
    const g: *const Guid = @ptrCast(*const Guid, base + 4);
    st.joy_guid = g.*;
    st.joy_found = true;
    return DIENUM_STOP;
}

// --- release helpers -------------------------------------------------------
fn releaseDevice(p: *void) void {
    if (!isNull(p)) {
        _ = devVtbl(p).Release(p);
    }
}

fn releaseDi8(p: *void) void {
    if (!isNull(p)) {
        _ = di8Vtbl(p).Release(p);
    }
}

fn releaseLibrary(st: *State) void {
    if (!isNull(st.lib)) {
        _ = FreeLibrary(st.lib);
    }
    st.lib = nullVoid();
}

// --- keyboard/gamepad map --------------------------------------------------
pub fn mapKeys(keys: []const u8, out: *Buttons) void {
    zeroButtons(out);
    if (keys.len < 256) return;
    const MASK: u8 = 0x80;
    out.left = (keys[DIK_LEFT] & MASK) != 0;
    out.right = (keys[DIK_RIGHT] & MASK) != 0;
    out.up = (keys[DIK_UP] & MASK) != 0;
    out.down = (keys[DIK_DOWN] & MASK) != 0;
    out.a = (keys[DIK_Z] & MASK) != 0;
    out.b = (keys[DIK_X] & MASK) != 0;
    out.select = (keys[DIK_BACK] & MASK) != 0;
    out.start = (keys[DIK_RETURN] & MASK) != 0;
    out.quit = (keys[DIK_ESCAPE] & MASK) != 0;
}

fn mapJoystick(st: *State, out: *Buttons) void {
    const MASK: u8 = 0x80;
    const x = st.joy_state.lX;
    const y = st.joy_state.lY;
    if (x < -JOY_DEADZONE) out.left = true;
    if (x > JOY_DEADZONE) out.right = true;
    if (y < -JOY_DEADZONE) out.up = true;
    if (y > JOY_DEADZONE) out.down = true;
    if ((st.joy_state.rgbButtons[0] & MASK) != 0) out.a = true;
    if ((st.joy_state.rgbButtons[1] & MASK) != 0) out.b = true;
    if ((st.joy_state.rgbButtons[8] & MASK) != 0) out.select = true;
    if ((st.joy_state.rgbButtons[9] & MASK) != 0) out.start = true;
}

fn keyDown(vk: i32) bool {
    return GetAsyncKeyState(vk) < 0;
}

fn pollFallback(out: *Buttons) void {
    zeroButtons(out);
    out.left = keyDown(VK_LEFT);
    out.right = keyDown(VK_RIGHT);
    out.up = keyDown(VK_UP);
    out.down = keyDown(VK_DOWN);
    out.a = keyDown(VK_Z);
    out.b = keyDown(VK_X);
    out.select = keyDown(VK_BACK);
    out.start = keyDown(VK_RETURN);
    out.quit = keyDown(VK_ESCAPE);
}

// --- open/close ------------------------------------------------------------
pub fn open(window: *void, st: *State) u8 {
    st.backend = BACKEND_FALLBACK;
    st.lib = nullVoid();
    st.di8 = nullVoid();
    st.kbd = nullVoid();
    st.joy = nullVoid();
    st.joy_found = false;
    initKeyboardFormat(st);
    initJoystickFormat(st);

    var dll_name: [24]u8 = undefined;
    copyCstr("dinput8.dll", dll_name[0..]);
    const lib = LoadLibraryA(@ptrCast([*]const u8, &dll_name[0]));
    if (isNull(lib)) return BACKEND_FALLBACK;

    var fn_name: [32]u8 = undefined;
    copyCstr("DirectInput8Create", fn_name[0..]);
    const proc = GetProcAddress(lib, @ptrCast([*]const u8, &fn_name[0]));
    if (isNull(proc)) {
        _ = FreeLibrary(lib);
        return BACKEND_FALLBACK;
    }
    st.lib = lib;

    const create: DirectInput8CreateFn = @ptrCast(DirectInput8CreateFn, proc);
    var di_raw: *void = nullVoid();
    var hr = create(GetModuleHandleA(nullVoid()), DIRECTINPUT_VERSION,
        @ptrCast(*const void, &IID_DI8), &di_raw, nullVoid());
    if (hr != S_OK or isNull(di_raw)) {
        releaseLibrary(st);
        return BACKEND_FALLBACK;
    }
    st.di8 = di_raw;

    var kbd_raw: *void = nullVoid();
    hr = di8Vtbl(st.di8).CreateDevice(st.di8, @ptrCast(*const void, &GUID_SYS_KEYBOARD),
        &kbd_raw, nullVoid());
    if (hr != S_OK or isNull(kbd_raw)) {
        releaseDi8(st.di8);
        st.di8 = nullVoid();
        releaseLibrary(st);
        return BACKEND_FALLBACK;
    }
    st.kbd = kbd_raw;
    hr = devVtbl(st.kbd).SetDataFormat(st.kbd, @ptrCast(*const void, &st.kbd_format));
    if (hr != S_OK) {
        releaseDevice(st.kbd);
        st.kbd = nullVoid();
        releaseDi8(st.di8);
        st.di8 = nullVoid();
        releaseLibrary(st);
        return BACKEND_FALLBACK;
    }
    _ = devVtbl(st.kbd).SetCooperativeLevel(st.kbd, window,
        DISCL_FOREGROUND | DISCL_NONEXCLUSIVE);
    _ = devVtbl(st.kbd).Acquire(st.kbd);

    st.joy_found = false;
    _ = di8Vtbl(st.di8).EnumDevices(st.di8, DI8DEVCLASS_GAMECTRL,
        @ptrCast(*const void, enumDeviceCallback), @ptrCast(*void, st),
        DIEDFL_ATTACHEDONLY);
    if (st.joy_found) {
        var joy_raw: *void = nullVoid();
        hr = di8Vtbl(st.di8).CreateDevice(st.di8, @ptrCast(*const void, &st.joy_guid),
            &joy_raw, nullVoid());
        if (hr == S_OK and !isNull(joy_raw)) {
            st.joy = joy_raw;
            hr = devVtbl(st.joy).SetDataFormat(st.joy, @ptrCast(*const void, &st.joy_format));
            if (hr == S_OK) {
                _ = devVtbl(st.joy).SetCooperativeLevel(st.joy, window,
                    DISCL_BACKGROUND | DISCL_NONEXCLUSIVE);
                _ = devVtbl(st.joy).Acquire(st.joy);
            } else {
                releaseDevice(st.joy);
                st.joy = nullVoid();
            }
        }
    }

    st.backend = BACKEND_DINPUT8;
    return BACKEND_DINPUT8;
}

pub fn close(st: *State) void {
    releaseDevice(st.joy);
    st.joy = nullVoid();
    releaseDevice(st.kbd);
    st.kbd = nullVoid();
    releaseDi8(st.di8);
    st.di8 = nullVoid();
    releaseLibrary(st);
    st.backend = 0;
    st.joy_found = false;
}

// Additive raw accessor: the same 256-byte keyboard image poll() reads. The
// DirectInput8 path copies st.kbd_keys after one GetDeviceState; the fallback
// path builds a VK-indexed view with 0x80 for each down key. Existing poll()
// behavior is unchanged.
pub fn pollRaw(st: *State, out: []u8) bool {
    if (out.len < 256) return false;
    if (st.backend == BACKEND_FALLBACK) {
        var vk: i32 = 0;
        while (vk < 256) : (vk += 1) {
            const ui: usize = @intCast(usize, vk);
            if (keyDown(vk)) {
                out[ui] = 0x80;
            } else {
                out[ui] = 0;
            }
        }
        return true;
    }

    const hr = devVtbl(st.kbd).GetDeviceState(st.kbd, KEYBOARD_STATE_BYTES,
        @ptrCast(*void, &st.kbd_keys[0]));
    if (hr == S_OK) {
        var i: usize = 0;
        while (i < 256) : (i += 1) out[i] = st.kbd_keys[i];
        return true;
    }
    if (hr == DIERR_INPUTLOST or hr == DIERR_NOTACQUIRED) {
        _ = devVtbl(st.kbd).Acquire(st.kbd);
    }
    return false;
}

// --- poll ------------------------------------------------------------------
pub fn poll(st: *State, out: *Buttons) void {
    if (st.backend == BACKEND_FALLBACK) {
        pollFallback(out);
        return;
    }
    zeroButtons(out);

    var kbd_ok = false;
    var hr = devVtbl(st.kbd).GetDeviceState(st.kbd, KEYBOARD_STATE_BYTES,
        @ptrCast(*void, &st.kbd_keys[0]));
    if (hr == S_OK) {
        kbd_ok = true;
    } else if (hr == DIERR_INPUTLOST or hr == DIERR_NOTACQUIRED) {
        _ = devVtbl(st.kbd).Acquire(st.kbd);
    }
    if (kbd_ok) {
        mapKeys(st.kbd_keys[0..256], out);
    }

    if (isNull(st.joy)) return;
    var jhr = devVtbl(st.joy).Poll(st.joy);
    if (jhr == DIERR_INPUTLOST or jhr == DIERR_NOTACQUIRED) {
        _ = devVtbl(st.joy).Acquire(st.joy);
        return;
    }
    jhr = devVtbl(st.joy).GetDeviceState(st.joy, JOYSTICK_STATE_BYTES,
        @ptrCast(*void, &st.joy_state));
    if (jhr == DIERR_INPUTLOST or jhr == DIERR_NOTACQUIRED) {
        _ = devVtbl(st.joy).Acquire(st.joy);
        return;
    }
    if (jhr == S_OK) {
        mapJoystick(st, out);
    }
}

pub const backend_dinput8: u8 = BACKEND_DINPUT8;
pub const backend_fallback: u8 = BACKEND_FALLBACK;
