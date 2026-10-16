// console_linux_pal.zig — z9play M5 Task 2: Linux raw-console C externs.
//
// Split out of console_linux.zig for the same Z98 reasons as
// audio_oss_pal.zig: an `extern "c" fn` may be declared at module scope but NOT
// inside a struct, and a same-named extern cannot coexist with the backend's
// public function in one module. The backend therefore owns the public console
// API (`termEnterRaw`/`termLeaveRaw`/`readKey`) and calls the C library through
// this PAL module.
//
// The prototypes are made visible to gcc by the headers console_linux.zig
// @cIncludes (Z98 emits no extern prototypes; C declarations come only from the
// headers it @cIncludes). POSIX tcgetattr/tcsetattr/read come from
// <termios.h>/<unistd.h>; signal(2) from <signal.h> takes and returns a
// `void (*)(int)`. The termios buffer is passed as `*void`: the caller owns the
// struct and gcc converts the void pointer to `struct termios *` implicitly at
// the call site (no incompatible-pointer warning). The `optional_actions` value
// (TCSANOW) is hardcoded numerically by the caller.
//
// Pure Z98: free functions only.

pub extern "c" fn tcgetattr(fd: i32, termios_p: *void) i32;
pub extern "c" fn tcsetattr(fd: i32, optional_actions: i32, termios_p: *void) i32;
pub extern "c" fn read(fd: i32, buf: [*]u8, count: u32) i32;
pub extern "c" fn signal(signum: i32, handler: fn (i32) void) fn (i32) void;
