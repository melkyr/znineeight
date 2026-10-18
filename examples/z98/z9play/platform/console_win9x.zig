// console_win9x.zig — complete Win9x console backend for z9play (M6 Task 2).
//
// Implements the complete M5b `Console` contract (platform/console.zig) on
// Windows 9x through the Win32 console API: raw mode via Get/SetConsoleMode,
// non-blocking key decode via GetNumberOfConsoleInputEvents/ReadConsoleInputA
// (KEY_EVENT records, VK_* -> the shared `Key` variants), output via
// FillConsoleOutputCharacterA/SetConsoleCursorPosition/WriteConsoleA, size via
// GetConsoleScreenBufferInfo, and cursor visibility via Get/SetConsoleCursorInfo.
//
// Raw mode (enterRaw): the input handle's original mode is saved in the
// caller's state and ENABLE_LINE_INPUT/ENABLE_ECHO_INPUT are cleared. Unlike the
// Linux backend, ENABLE_PROCESSED_INPUT is deliberately KEPT ON: Ctrl-C is then
// delivered to the console-control handler (matching Linux ISIG) instead of
// arriving as the literal byte 0x03. A non-console input handle (GetConsoleMode
// fails, e.g. redirected input) is a safe no-op, so a bogus mode is never
// written back.
//
// Ctrl-C: `onCtrl` is a console-control handler that sets a sticky module flag
// (`g_sigint`) for CTRL_C_EVENT/CTRL_BREAK_EVENT and returns TRUE (handled, the
// process keeps running). `readKey` checks the flag first and returns `.sigint`,
// exactly like the Linux signal handler's sticky flag.
//
// Crash backstop (plan: SetConsoleCtrlHandler/atexit; `defer` alone is
// insufficient because Z98's std.os.exit runs no defer): the control handler
// also restores the saved input mode on CTRL_CLOSE/LOGOFF/SHUTDOWN events, and
// an `atexit` handler restores it on any normal CRT exit that skipped the
// caller's explicit `leaveRaw`. The caller is still expected to call `leaveRaw`
// before every `std.os.exit` path (main.zig, Task 3); `leaveRaw` is cheap and
// idempotent so that is always safe.
//
// `readKey` is non-blocking: GetNumberOfConsoleInputEvents first, and when no
// events are pending it returns `.none` (the contract's in-band sentinel, D1).
// Non-KEY_EVENT records (mouse/resize/focus) and key-up transitions are
// consumed and skipped. A pending Ctrl-C flag takes priority over keys. VK_UP/
// DOWN/LEFT/RIGHT (0x26/0x28/0x25/0x27) map to the arrow variants, VK_RETURN
// (0x0D) to `.enter`, VK_ESCAPE (0x1B) to `.esc`; any other key with a non-zero
// character yields `.char` (low byte of the AsciiChar/UnicodeChar union).
//
// Output/size conventions: `setCursor` takes 0-based row/col and passes them as
// the 0-based COORD {x=col, y=row} (the Win32 convention). `width`/`height` use
// the screen buffer size (`dwSize.X/Y`), the plan's GetConsoleScreenBufferInfo
// mapping, and fall back to 80x24 when the query fails or reports zero.
// `clear` blanks every cell with FillConsoleOutputCharacterA and homes the
// cursor. All output goes through the STD_OUTPUT_HANDLE with WriteConsoleA; a
// redirected stdout handle makes the Win32 output calls fail harmlessly (the
// player's Win9x path is console-oriented).
//
// Assembly note (compiler defect D8): a backend must NOT expose a function that
// *returns* `Console` in a multi-module build. This module exposes the nine
// vtable operations as public free functions whose signatures match the
// contract fields exactly; the caller assembles the `Console` literal and sets
// `state` to its own `ConsoleWinState`. The C externs and the Win32 struct
// mirrors live in console_win9x_pal.zig (see there for the split rationale).
//
// Pure Z98: free functions only, strict `@intCast`, numeric Win32 constants.

const pal = @import("console_win9x_pal.zig");
const con = @import("console.zig");

// Re-export the contract types so consumers can name them through the backend.
pub const Key = con.Key;
pub const Console = con.Console;

// STD_INPUT_HANDLE / STD_OUTPUT_HANDLE (winbase.h: (DWORD)-10 / (DWORD)-11).
const STD_INPUT_HANDLE: i32 = -10;
const STD_OUTPUT_HANDLE: i32 = -11;

// Console input mode bits (wincon.h).
const ENABLE_PROCESSED_INPUT: u32 = 0x0001; // kept ON (Ctrl-C -> control handler)
const ENABLE_LINE_INPUT: u32 = 0x0002;
const ENABLE_ECHO_INPUT: u32 = 0x0004;

// INPUT_RECORD.EventType.
const KEY_EVENT: u16 = 0x0001;

// Virtual-key codes (winuser.h).
const VK_UP: u16 = 0x26;
const VK_DOWN: u16 = 0x28;
const VK_LEFT: u16 = 0x25;
const VK_RIGHT: u16 = 0x27;
const VK_RETURN: u16 = 0x0D;
const VK_ESCAPE: u16 = 0x1B;

// Console control event types (wincon.h).
const CTRL_C_EVENT: u32 = 0;
const CTRL_BREAK_EVENT: u32 = 1;

// Caller-owned Win9x console state: the input handle and original mode saved by
// `enterRaw`, plus whether raw mode is currently in effect (so `leaveRaw` is
// safe to call unconditionally). The module globals below mirror the active
// values for the asynchronously-invoked control/atexit handlers, which receive
// no state pointer.
pub const ConsoleWinState = struct {
    in_handle: *void,
    saved_in_mode: u32,
    entered: bool,
};

// Handler-visible copy of the live raw-mode state.
var g_in_handle: *void = undefined;
var g_saved_in_mode: u32 = 0;
var g_raw_active: bool = false;
var g_sigint: u8 = 0;

// Registration guards (SetConsoleCtrlHandler would otherwise add duplicate
// handlers if enterRaw is called more than once; atexit cannot be removed).
var g_ctrl_installed: bool = false;
var g_atexit_installed: bool = false;

// Restore the saved input mode if raw mode is active. Shared by the control
// handler (close/logoff/shutdown) and the atexit backstop; safe when inactive.
fn restoreModes() void {
    if (!g_raw_active) return;
    _ = pal.SetConsoleMode(g_in_handle, g_saved_in_mode);
    g_raw_active = false;
}

// atexit backstop: Z98's std.os.exit runs no `defer`, so a caller that exits
// without `leaveRaw` still gets its console mode restored by the CRT at exit.
fn restoreAtExit() void {
    restoreModes();
}

// Console-control handler (PHANDLER_ROUTINE shape). Ctrl-C/Ctrl-Break set the
// sticky flag and are reported as handled so the process continues and
// `readKey` surfaces `.sigint`; the termination events restore the mode first
// and defer to the default action (return FALSE).
fn onCtrl(ctrl_type: u32) i32 {
    if (ctrl_type == CTRL_C_EVENT or ctrl_type == CTRL_BREAK_EVENT) {
        g_sigint = 1;
        return 1;
    }
    restoreModes();
    return 0;
}

// --- vtable implementation: raw mode --------------------------------------

// `Console.enterRaw_fn`: save the input mode and clear ENABLE_LINE_INPUT /
// ENABLE_ECHO_INPUT (ENABLE_PROCESSED_INPUT stays on). A non-console handle is
// a no-op. Re-entry re-saves the current (already raw) mode, like the Linux
// backend; `leaveRaw` still restores whatever mode was current when called.
pub fn enterRaw(state: *void) void {
    var st: *ConsoleWinState = @ptrCast(*ConsoleWinState, state);
    st.entered = false;
    g_sigint = 0;

    var h: *void = pal.GetStdHandle(STD_INPUT_HANDLE);
    var mode: u32 = 0;
    if (pal.GetConsoleMode(h, &mode) == 0) return;

    st.in_handle = h;
    st.saved_in_mode = mode;
    st.entered = true;
    g_in_handle = h;
    g_saved_in_mode = mode;
    g_raw_active = true;

    var raw: u32 = mode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
    _ = pal.SetConsoleMode(h, raw);

    if (!g_ctrl_installed) {
        _ = pal.SetConsoleCtrlHandler(@ptrCast(pal.CtrlHandler, onCtrl), 1);
        g_ctrl_installed = true;
    }
    if (!g_atexit_installed) {
        _ = pal.atexit(restoreAtExit);
        g_atexit_installed = true;
    }
}

// `Console.leaveRaw_fn`: write the saved input mode back byte-for-byte and
// unregister the control handler. A no-op when raw mode is not active, so the
// caller can call it unconditionally on every exit path.
pub fn leaveRaw(state: *void) void {
    var st: *ConsoleWinState = @ptrCast(*ConsoleWinState, state);
    if (!st.entered) return;
    _ = pal.SetConsoleMode(st.in_handle, st.saved_in_mode);
    st.entered = false;
    g_raw_active = false;
    if (g_ctrl_installed) {
        _ = pal.SetConsoleCtrlHandler(@ptrCast(pal.CtrlHandler, onCtrl), 0);
        g_ctrl_installed = false;
    }
}

// --- vtable implementation: key input -------------------------------------

// `Console.readKey_fn`: return the next key without blocking. A pending Ctrl-C
// flag takes priority (sticky). With no input events ready the result is
// `.none`; non-key records and key-up transitions are skipped.
pub fn readKey(state: *void) Key {
    _ = state;
    if (g_sigint != 0) return Key{ .sigint = {} };

    var h: *void = pal.GetStdHandle(STD_INPUT_HANDLE);
    while (true) {
        var n: u32 = 0;
        if (pal.GetNumberOfConsoleInputEvents(h, &n) == 0) return Key{ .none = {} };
        if (n == 0) return Key{ .none = {} };

        var rec: pal.InputRecord = undefined;
        var got: u32 = 0;
        if (pal.ReadConsoleInputA(h, @ptrCast(*void, &rec), 1, &got) == 0) return Key{ .none = {} };
        if (got == 0) return Key{ .none = {} };

        // The control handler may have fired while ReadConsoleInputA ran.
        if (g_sigint != 0) return Key{ .sigint = {} };

        if (rec.event_type != KEY_EVENT) continue;
        if (rec.key.bKeyDown == 0) continue;

        var vk: u16 = rec.key.wVirtualKeyCode;
        if (vk == VK_UP) return Key{ .up = {} };
        if (vk == VK_DOWN) return Key{ .down = {} };
        if (vk == VK_LEFT) return Key{ .left = {} };
        if (vk == VK_RIGHT) return Key{ .right = {} };
        if (vk == VK_RETURN) return Key{ .enter = {} };
        if (vk == VK_ESCAPE) return Key{ .esc = {} };

        var ch: u16 = rec.key.uChar;
        if (ch != 0) {
            // Defensive: if ENABLE_PROCESSED_INPUT was cleared by the console
            // state, Ctrl-C arrives as byte 0x03; surface it as `.sigint`.
            if (ch == 3) return Key{ .sigint = {} };
            return Key{ .char = @intCast(u8, ch & @intCast(u16, 0xFF)) };
        }
        // A key with no character and no mapped VK (e.g. pure modifier): skip.
    }
    return Key{ .none = {} };
}

// --- vtable implementation: output ----------------------------------------

// `Console.writeStr_fn`: write the bytes to the console with WriteConsoleA.
pub fn writeStr(state: *void, s: []const u8) void {
    _ = state;
    if (s.len == 0) return;
    var h: *void = pal.GetStdHandle(STD_OUTPUT_HANDLE);
    var written: u32 = 0;
    _ = pal.WriteConsoleA(h, s.ptr, @intCast(u32, s.len), &written, @intToPtr(*void, 0));
}

// `Console.clear_fn`: blank every cell of the screen buffer and home the
// cursor (the Win32 FillConsoleOutputCharacter equivalent of ANSI clear).
pub fn clear(state: *void) void {
    _ = state;
    var h: *void = pal.GetStdHandle(STD_OUTPUT_HANDLE);
    var info: pal.ConsoleScreenBufferInfo = undefined;
    if (pal.GetConsoleScreenBufferInfo(h, @ptrCast(*void, &info)) == 0) return;

    var w: i32 = @intCast(i32, info.dwSize.x);
    var ht: i32 = @intCast(i32, info.dwSize.y);
    if (w <= 0 or ht <= 0) return;

    var cells: u32 = @intCast(u32, w * ht);
    var home: pal.Coord = pal.Coord{ .x = 0, .y = 0 };
    var space: i8 = 32;
    var written: u32 = 0;
    _ = pal.FillConsoleOutputCharacterA(h, space, cells, home, &written);
    _ = pal.SetConsoleCursorPosition(h, home);
}

// `Console.setCursor_fn`: 0-based row/col from the caller; Win32 COORD is
// already 0-based, so the fields are {x=col, y=row}.
pub fn setCursor(state: *void, row: u16, col: u16) void {
    _ = state;
    var h: *void = pal.GetStdHandle(STD_OUTPUT_HANDLE);
    var pos: pal.Coord = pal.Coord{ .x = @intCast(i16, col), .y = @intCast(i16, row) };
    _ = pal.SetConsoleCursorPosition(h, pos);
}

// `Console.cursorShow_fn`: flip CONSOLE_CURSOR_INFO.bVisible and write it back.
pub fn cursorShow(state: *void, show: bool) void {
    _ = state;
    var h: *void = pal.GetStdHandle(STD_OUTPUT_HANDLE);
    var info: pal.ConsoleCursorInfo = undefined;
    if (pal.GetConsoleCursorInfo(h, @ptrCast(*void, &info)) == 0) return;
    if (show) {
        info.bVisible = 1;
    } else {
        info.bVisible = 0;
    }
    _ = pal.SetConsoleCursorInfo(h, @ptrCast(*void, &info));
}

// `Console.width_fn`: screen buffer columns from GetConsoleScreenBufferInfo
// (dwSize.X, the plan's mapping); 80 when the query fails or reports zero.
pub fn width(state: *void) u16 {
    _ = state;
    var h: *void = pal.GetStdHandle(STD_OUTPUT_HANDLE);
    var info: pal.ConsoleScreenBufferInfo = undefined;
    if (pal.GetConsoleScreenBufferInfo(h, @ptrCast(*void, &info)) == 0) return 80;
    if (info.dwSize.x <= 0) return 80;
    return @intCast(u16, info.dwSize.x);
}

// `Console.height_fn`: screen buffer rows from GetConsoleScreenBufferInfo
// (dwSize.Y); 24 when the query fails or reports zero.
pub fn height(state: *void) u16 {
    _ = state;
    var h: *void = pal.GetStdHandle(STD_OUTPUT_HANDLE);
    var info: pal.ConsoleScreenBufferInfo = undefined;
    if (pal.GetConsoleScreenBufferInfo(h, @ptrCast(*void, &info)) == 0) return 24;
    if (info.dwSize.y <= 0) return 24;
    return @intCast(u16, info.dwSize.y);
}
