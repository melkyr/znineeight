// audio_win9x_pal.zig — z9play M6 Task 1: Win9x waveOut C externs.
//
// Split out of audio_win9x.zig for the same Z98 reason as audio_oss_pal.zig: an
// `extern "stdcall" fn` may be declared at module scope but NOT inside a struct
// (a namespaced declaration is rejected), and the backend owns the public
// vtable free functions (`open`/`write`/`close`/`drain`). Keeping the platform
// binding in its own module mirrors audio_oss_pal.zig / console_linux_pal.zig
// and keeps the backend body free of extern noise.
//
// The prototypes are made visible to gcc by the headers audio_win9x.zig
// @cIncludes (<windows.h> then <mmsystem.h>); Z98 emits no extern prototypes.
// The `waveOut*` API is WINAPI (__stdcall on i686 mingw), hence
// `extern "stdcall"`. The WAVEFORMATEX / WAVEHDR mirrors live in the backend
// and are passed through as `*void` (gcc converts the void pointer to the
// concrete `*WAVEFORMATEX` / `*WAVEHDR` at the call site, exactly as
// audio_oss_pal passes its ioctl argument).
//
// Pure Z98: free functions only.

// MMRESULT waveOutOpen(LPHWAVEOUT, UINT, LPCWAVEFORMATEX, DWORD_PTR, DWORD_PTR, DWORD);
pub extern "stdcall" fn waveOutOpen(phwo: *void, uDeviceID: u32, pwfx: *void, dwCallback: u32, dwInstance: u32, fdwOpen: u32) u32;

// MMRESULT waveOutPrepareHeader(HWAVEOUT, LPWAVEHDR, UINT);
pub extern "stdcall" fn waveOutPrepareHeader(hwo: *void, pwh: *void, cbwh: u32) u32;

// MMRESULT waveOutWrite(HWAVEOUT, LPWAVEHDR, UINT);
pub extern "stdcall" fn waveOutWrite(hwo: *void, pwh: *void, cbwh: u32) u32;

// MMRESULT waveOutUnprepareHeader(HWAVEOUT, LPWAVEHDR, UINT);
pub extern "stdcall" fn waveOutUnprepareHeader(hwo: *void, pwh: *void, cbwh: u32) u32;

// MMRESULT waveOutReset(HWAVEOUT);
pub extern "stdcall" fn waveOutReset(hwo: *void) u32;

// MMRESULT waveOutClose(HWAVEOUT);
pub extern "stdcall" fn waveOutClose(hwo: *void) u32;
