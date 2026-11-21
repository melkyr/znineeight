// audio_oss_pal.zig — z9play M4 Task 2: Linux OSS `/dev/dsp` C externs.
//
// Split out of audio_oss.zig for one Z98 reason only: an `extern "c" fn` may be
// declared at module scope but NOT inside a struct (a namespaced declaration is
// rejected with `error[2000]`), and an `extern "c" fn open` cannot coexist with
// the backend's required `pub fn open` in the same module (the two declarations
// collide / the extern shadows the public function). The backend therefore owns
// the public vtable free functions (`open`/`write`/`close`/`drain`) and calls
// the C symbols through this PAL module — the same split `std_file.zig` /
// `std_file_pal.zig` uses in the std lib.
//
// The prototypes are made visible to gcc by the headers audio_oss.zig
// @cIncludes (Z98 emits no extern prototypes; C declarations come only from the
// headers it @cIncludes). POSIX open/read/write/close; ioctl(2) is declared
// with a fixed pointer third argument (every request this backend issues takes
// a pointer, and ioctl SYNC/POST ignore it).
//
// Pure Z98: free functions only.

// POSIX open(2) flags are hardcoded numerically by the caller (no dependence on
// the fcntl.h macro values), matching sf/src/std_file.zig.
pub extern "c" fn open(path: [*]const u8, flags: i32, mode: i32) i32;
pub extern "c" fn write(fd: i32, buf: [*]const u8, count: u32) i32;
pub extern "c" fn close(fd: i32) i32;
// int ioctl(int fd, unsigned long request, ...) — always called with a pointer.
pub extern "c" fn ioctl(fd: i32, request: u32, arg: *void) i32;
