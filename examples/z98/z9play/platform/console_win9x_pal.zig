// console_win9x_pal.zig — z9play M6 Task 2: Win9x console C externs + mirrors.
//
// Split out of console_win9x.zig for the same Z98 reason as audio_win9x_pal.zig:
// an `extern "stdcall" fn` may be declared at module scope but NOT inside a
// struct, and the backend owns the public vtable free functions. The prototypes
// are made visible to gcc by this module's @cInclude (Z98 emits no extern
// prototypes); <windows.h> must be included before any Win32 type is named.
//
// The Win32 structs are mirrored here because `COORD` is passed BY VALUE by
// SetConsoleCursorPosition / FillConsoleOutputCharacterA, so the PAL externs and
// the backend must name the same Z98 type. The mirrors follow the i686 mingw
// layout exactly (normal Z98 structs use natural C alignment): COORD 4 bytes,
// SMALL_RECT 8, CONSOLE_SCREEN_BUFFER_INFO 22, CONSOLE_CURSOR_INFO 8,
// KEY_EVENT_RECORD 16, INPUT_RECORD 20 (WORD event type + 2 bytes tail padding
// before the 4-byte-aligned union member).
//
// Calling convention: the console API is WINAPI (__stdcall on i686 mingw),
// hence `extern "stdcall"`. No console-control handler is bound: Z98 cannot
// define a stdcall function (defect D5), and a cdecl function cast to the
// stdcall handler type would corrupt the i386 stack. The Ctrl-C path is
// processed-input-off KEY_EVENT 0x03 in the backend (M6 Amendment 1).
//
// Pure Z98: free functions only, hardcoded numerically stable Win32 constants
// live in the backend.

@cInclude("<windows.h>");
@cInclude("<stdlib.h>");

// COORD (wincon.h): SHORT x, SHORT y.
pub const Coord = struct {
    x: i16,
    y: i16,
};

// SMALL_RECT (wincon.h): SHORT left, top, right, bottom.
pub const SmallRect = struct {
    left: i16,
    top: i16,
    right: i16,
    bottom: i16,
};

// CONSOLE_SCREEN_BUFFER_INFO (wincon.h).
pub const ConsoleScreenBufferInfo = struct {
    dwSize: Coord,
    dwCursorPosition: Coord,
    wAttributes: u16,
    srWindow: SmallRect,
    dwMaximumWindowSize: Coord,
};

// CONSOLE_CURSOR_INFO (wincon.h): DWORD dwSize, BOOL bVisible.
pub const ConsoleCursorInfo = struct {
    dwSize: u32,
    bVisible: i32,
};

// KEY_EVENT_RECORD (wincon.h): BOOL bKeyDown, WORD wRepeatCount,
// WORD wVirtualKeyCode, WORD wVirtualScanCode, union { WCHAR/CHAR } uChar,
// DWORD dwControlKeyState.
pub const KeyEventRecord = struct {
    bKeyDown: i32,
    wRepeatCount: u16,
    wVirtualKeyCode: u16,
    wVirtualScanCode: u16,
    uChar: u16,
    dwControlKeyState: u32,
};

// INPUT_RECORD (wincon.h): WORD EventType, then the event union. Reaching the
// union member through a complete KEY_EVENT_RECORD mirror keeps the 2-byte
// tail padding that the 4-byte-aligned union member requires on i686.
pub const InputRecord = struct {
    event_type: u16,
    key: KeyEventRecord,
};

// HANDLE GetStdHandle(DWORD nStdHandle);
pub extern "stdcall" fn GetStdHandle(nStdHandle: i32) *void;

// BOOL GetConsoleMode(HANDLE, LPDWORD);
pub extern "stdcall" fn GetConsoleMode(hConsoleHandle: *void, lpMode: *u32) i32;

// BOOL SetConsoleMode(HANDLE, DWORD);
pub extern "stdcall" fn SetConsoleMode(hConsoleHandle: *void, dwMode: u32) i32;

// BOOL GetNumberOfConsoleInputEvents(HANDLE, LPDWORD);
pub extern "stdcall" fn GetNumberOfConsoleInputEvents(hConsoleInput: *void, lpNumberOfEvents: *u32) i32;

// BOOL ReadConsoleInputA(HANDLE, PINPUT_RECORD, DWORD, LPDWORD);
pub extern "stdcall" fn ReadConsoleInputA(hConsoleInput: *void, lpBuffer: *void, nLength: u32, lpNumberOfEventsRead: *u32) i32;

// BOOL WriteConsoleA(HANDLE, const VOID*, DWORD, LPDWORD, LPVOID);
pub extern "stdcall" fn WriteConsoleA(hConsoleOutput: *void, lpBuffer: [*]const u8, nNumberOfCharsToWrite: u32, lpNumberOfCharsWritten: *u32, lpReserved: *void) i32;

// BOOL FillConsoleOutputCharacterA(HANDLE, CHAR, DWORD, COORD, LPDWORD);
pub extern "stdcall" fn FillConsoleOutputCharacterA(hConsoleOutput: *void, cCharacter: i8, nLength: u32, dwWriteCoord: Coord, lpNumberOfCharsWritten: *u32) i32;

// BOOL SetConsoleCursorPosition(HANDLE, COORD);
pub extern "stdcall" fn SetConsoleCursorPosition(hConsoleOutput: *void, dwCursorPosition: Coord) i32;

// BOOL GetConsoleScreenBufferInfo(HANDLE, PCONSOLE_SCREEN_BUFFER_INFO);
pub extern "stdcall" fn GetConsoleScreenBufferInfo(hConsoleOutput: *void, lpConsoleScreenBufferInfo: *void) i32;

// BOOL GetConsoleCursorInfo(HANDLE, PCONSOLE_CURSOR_INFO);
pub extern "stdcall" fn GetConsoleCursorInfo(hConsoleOutput: *void, lpConsoleCursorInfo: *void) i32;

// BOOL SetConsoleCursorInfo(HANDLE, const CONSOLE_CURSOR_INFO*);
pub extern "stdcall" fn SetConsoleCursorInfo(hConsoleOutput: *void, lpConsoleCursorInfo: *void) i32;

// int atexit(void (*)(void)) — CRT cdecl callback, used for the crash backstop.
pub extern "c" fn atexit(func: fn () void) i32;
