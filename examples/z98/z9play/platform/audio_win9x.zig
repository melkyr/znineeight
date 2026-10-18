// audio_win9x.zig — Win9x waveOut audio backend for z9play (M6 Task 1).
//
// Implements the M4 `AudioOut` vtable (platform/audio.zig) on Windows 9x
// through the winmm `waveOut*` API: waveOutOpen / waveOutPrepareHeader /
// waveOutWrite / waveOutUnprepareHeader / waveOutClose (+ waveOutReset),
// driving signed 16-bit little-endian PCM through a `WAVEFORMATEX` and one
// `WAVEHDR` per buffer. Rates 44100/48000 and 1/2 channels only (spec §5);
// anything else is `ConfigUnsupported`.
//
// Blocking semantics: `waveOutWrite` is asynchronous, so the backend copies
// samples into fixed NBUF = 2 buffers of 500 ms each (`buf_bytes =
// rate * channels` bytes = 0.5 s of s16 at this rate/channel count) and, once
// every buffer is queued, blocks (polls the driver's WHDR_DONE bit) before
// handing the oldest buffer back. That reproduces the M4 contract's
// "write blocks until consumed" behaviour, and the 500 ms buffer size is the
// plan's starvation mitigation. `drain` submits the final partial buffer, then
// waits for every queued buffer; `close` resets the device and closes it.
//
// Host dependence (blueprint §2.2, spec §5): Win9x-only and best-effort. When
// the device cannot be opened or a waveOut call fails, `open` returns
// `error.OpenFailed` cleanly (never crashes); when the device cannot honour the
// requested format/rate/channels it returns `error.ConfigUnsupported`. The
// hermetic WAV sink (audio_wavfile.zig) remains the gate backend and is still
// selected ahead of this one when `Z9PLAY_WAV_OUT` is set (main.zig).
//
// Assembly note (compiler defect D8): a backend must NOT expose a function that
// *returns* `AudioOut` (the vtable struct) in a multi-module build. This module
// exposes the four vtable operations as public free functions (`open`/`write`/
// `close`/`drain`); the caller assembles the `AudioOut` literal and sets
// `state` to the context `open` returned. See examples/torrent_example_defects.md
// (D8). The C externs live in audio_win9x_pal.zig (see there for the split
// rationale).
//
// Pure Z98: free functions only, strict `@intCast`, numeric winmm constants
// (the emitted C does not depend on the Zig level seeing the header macros).

const std = @import("std");
const pal = @import("audio_win9x_pal.zig");
const audio = @import("audio.zig");

pub const AudioError = audio.AudioError;
pub const AudioOut = audio.AudioOut;

// C prototypes for the externs in audio_win9x_pal.zig. Z98 emits no extern
// prototypes, so gcc sees the `waveOut*` declarations only through these
// headers. windows.h must precede mmsystem.h (the latter relies on the base
// win32 types). The `@isWindows()` module selection in main.zig keeps this
// module out of the Linux dump entirely, so no mingw-only header is ever
// visible to the Linux gcc.
@cInclude("<windows.h>");
@cInclude("<mmsystem.h>");

// winmm constants (hardcoded numerically; the protocol is frozen at Win9x).
const WAVE_FORMAT_PCM: u16 = 1;
const WAVE_MAPPER: u32 = 0xFFFFFFFF; // (UINT)-1
const CALLBACK_NULL: u32 = 0;
const MMSYSERR_NOERROR: u32 = 0;

// WAVEHDR.dwFlags bits (mmsystem.h). WHDR_DONE is set by the driver once the
// buffer has finished playing.
const WHDR_DONE: u32 = 0x00000001;

// Buffering: NBUF buffers of 500 ms each. `buf_bytes` is computed at open as
// 0.5 s * rate frames/s * channels samples/frame * 2 bytes = rate * channels
// bytes; the backing array is sized for the maximum supported configuration
// (48000 Hz stereo -> 96000 bytes).
const NBUF: usize = 2;
const BUF_CAP: usize = 96000;

// WAVEFORMATEX mirror (mingw <mmsystem.h>): WORD wFormatTag, WORD nChannels,
// DWORD nSamplesPerSec, DWORD nAvgBytesPerSec, WORD nBlockAlign,
// WORD wBitsPerSample, WORD cbSize. Natural 32-bit layout: offsets 0/2/4/8/12/
// 14/16, size 18 padded to 20.
const WaveFormatEx = struct {
    wFormatTag: u16,
    nChannels: u16,
    nSamplesPerSec: u32,
    nAvgBytesPerSec: u32,
    nBlockAlign: u16,
    wBitsPerSample: u16,
    cbSize: u16,
};

// WAVEHDR mirror (mingw <mmsystem.h>, 32-bit): eight four-byte fields
// (lpData, dwBufferLength, dwBytesRecorded, dwUser, dwFlags, dwLoops, lpNext,
// reserved) -> 32 bytes, natural layout.
const WaveHdr = struct {
    lpData: [*]u8,
    dwBufferLength: u32,
    dwBytesRecorded: u32,
    dwUser: u32,
    dwFlags: u32,
    dwLoops: u32,
    lpNext: *void,
    reserved: u32,
};

// One open device. Only one is open at a time (a global), matching the v1
// player, which drives a single output device. `bufs` is a flat array indexed
// as `fill_idx * BUF_CAP + offset`.
const Win9xDev = struct {
    hwo: *void, // HWAVEOUT
    rate: u32,
    channels: u8,
    buf_bytes: usize,
    bufs: [NBUF * BUF_CAP]u8,
    hdrs: [NBUF]WaveHdr,
    queued: [NBUF]bool,
    fill_idx: usize,
    fill_len: usize,
};

var g_dev: Win9xDev = undefined;

// --- internal helpers ------------------------------------------------------

// True once the driver has finished the buffer. Read through a volatile pointer
// (the driver writes dwFlags asynchronously); `@ptrCast` adds the qualifier,
// which C89 emission renders as `volatile unsigned int *`.
fn hdrDone(h: *WaveHdr) bool {
    var f: *volatile u32 = @ptrCast(*volatile u32, &h.dwFlags);
    return (f.* & WHDR_DONE) != 0;
}

// Block until the buffer at `fill_idx` is free for reuse: if it is queued, poll
// WHDR_DONE (sleeping 1 ms between reads), then unprepare it. Returns
// immediately when the buffer is not queued.
fn waitFree(ctx: *Win9xDev) void {
    while (ctx.queued[ctx.fill_idx]) {
        var h: *WaveHdr = &ctx.hdrs[ctx.fill_idx];
        if (hdrDone(h)) {
            _ = pal.waveOutUnprepareHeader(ctx.hwo, @ptrCast(*void, h), @intCast(u32, @sizeOf(WaveHdr)));
            ctx.queued[ctx.fill_idx] = false;
            break;
        }
        std.time.sleepMs(1);
    }
}

// Prepare and queue the current buffer (`fill_idx`, `fill_len` bytes), then
// advance to the next and make sure it is free before the caller fills it. A
// failed prepare/write is reported as `WriteFailed` (the buffer is left
// unprepared / not queued).
fn submit(ctx: *Win9xDev) AudioError!void {
    var h: *WaveHdr = &ctx.hdrs[ctx.fill_idx];
    h.dwBufferLength = @intCast(u32, ctx.fill_len);
    // waveOutPrepareHeader requires dwFlags to be zero on entry; the driver
    // sets WHDR_PREPARED/WHDR_DONE on the header while it owns the buffer.
    h.dwFlags = 0;

    var hdr_size: u32 = @intCast(u32, @sizeOf(WaveHdr));
    var rc: u32 = pal.waveOutPrepareHeader(ctx.hwo, @ptrCast(*void, h), hdr_size);
    if (rc != MMSYSERR_NOERROR) return error.WriteFailed;

    rc = pal.waveOutWrite(ctx.hwo, @ptrCast(*void, h), hdr_size);
    if (rc != MMSYSERR_NOERROR) {
        _ = pal.waveOutUnprepareHeader(ctx.hwo, @ptrCast(*void, h), hdr_size);
        return error.WriteFailed;
    }

    ctx.queued[ctx.fill_idx] = true;
    ctx.fill_idx = (ctx.fill_idx + 1) % NBUF;
    ctx.fill_len = 0;

    // Ensure the buffer the next write will target is not still playing.
    waitFree(ctx);
}

// --- vtable implementation -------------------------------------------------

// `AudioOut.open_fn`: open the waveOut device and configure 16-bit PCM at
// `rate` (44100/48000) and `channels` (1/2). Any other configuration is
// `ConfigUnsupported`; any waveOutOpen failure is `OpenFailed`.
pub fn open(rate: u32, channels: u8) AudioError!*void {
    if (rate != 44100 and rate != 48000) return error.ConfigUnsupported;
    if (channels != 1 and channels != 2) return error.ConfigUnsupported;

    var wfx: WaveFormatEx = undefined;
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = @intCast(u16, channels);
    wfx.nSamplesPerSec = rate;
    wfx.nAvgBytesPerSec = rate * @intCast(u32, channels) * 2;
    wfx.nBlockAlign = @intCast(u16, @intCast(u32, channels) * 2);
    wfx.wBitsPerSample = 16;
    wfx.cbSize = 0;

    g_dev.hwo = @intToPtr(*void, 0);
    var rc: u32 = pal.waveOutOpen(@ptrCast(*void, &g_dev.hwo), WAVE_MAPPER, @ptrCast(*void, &wfx), CALLBACK_NULL, 0, 0);
    if (rc != MMSYSERR_NOERROR) return error.OpenFailed;

    g_dev.rate = rate;
    g_dev.channels = channels;
    g_dev.buf_bytes = @intCast(usize, rate) * @intCast(usize, channels);
    g_dev.fill_idx = 0;
    g_dev.fill_len = 0;

    var i: usize = 0;
    while (i < NBUF) : (i += 1) {
        g_dev.hdrs[i] = WaveHdr{
            .lpData = @ptrCast([*]u8, &g_dev.bufs[i * BUF_CAP]),
            .dwBufferLength = 0,
            .dwBytesRecorded = 0,
            .dwUser = 0,
            .dwFlags = 0,
            .dwLoops = 0,
            .lpNext = @intToPtr(*void, 0),
            .reserved = 0,
        };
        g_dev.queued[i] = false;
    }
    return @ptrCast(*void, &g_dev);
}

// `AudioOut.write_fn`: copy interleaved s16 samples into the 500 ms buffers and
// submit each full one. Blocks (via `submit` -> `waitFree`) once every buffer is
// in flight, so this call does not return until some audio has been consumed.
// Returns the number of samples accepted (all of them, on success).
pub fn write(state: *void, samples: []const i16) AudioError!usize {
    if (samples.len == 0) return 0;
    var ctx: *Win9xDev = @ptrCast(*Win9xDev, state);
    var base: [*]const u8 = @ptrCast([*]const u8, samples.ptr);
    var total: usize = samples.len * 2;
    var off: usize = 0;
    while (off < total) {
        var space: usize = ctx.buf_bytes - ctx.fill_len;
        var take: usize = total - off;
        if (take > space) take = space;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            ctx.bufs[ctx.fill_idx * BUF_CAP + ctx.fill_len + j] = base[off + j];
        }
        ctx.fill_len += take;
        off += take;
        if (ctx.fill_len >= ctx.buf_bytes) {
            submit(ctx) catch return error.WriteFailed;
        }
    }
    return samples.len;
}

// `AudioOut.drain_fn`: submit the final partial buffer (if any), then block
// until every queued buffer has played out.
pub fn drain(state: *void) AudioError!void {
    var ctx: *Win9xDev = @ptrCast(*Win9xDev, state);
    if (ctx.fill_len > 0) {
        submit(ctx) catch return error.DeviceError;
    }

    var i: usize = 0;
    while (i < NBUF) : (i += 1) {
        if (ctx.queued[i]) {
            var h: *WaveHdr = &ctx.hdrs[i];
            while (!hdrDone(h)) std.time.sleepMs(1);
            _ = pal.waveOutUnprepareHeader(ctx.hwo, @ptrCast(*void, h), @intCast(u32, @sizeOf(WaveHdr)));
            ctx.queued[i] = false;
        }
    }
    ctx.fill_idx = 0;
    ctx.fill_len = 0;
}

// `AudioOut.close_fn`: stop playback (waveOutReset marks every queued buffer
// done), unprepare anything still queued, and close the device. void per
// blueprint §2.2 (best effort).
pub fn close(state: *void) void {
    var ctx: *Win9xDev = @ptrCast(*Win9xDev, state);
    _ = pal.waveOutReset(ctx.hwo);
    var i: usize = 0;
    while (i < NBUF) : (i += 1) {
        if (ctx.queued[i]) {
            _ = pal.waveOutUnprepareHeader(ctx.hwo, @ptrCast(*void, &ctx.hdrs[i]), @intCast(u32, @sizeOf(WaveHdr)));
            ctx.queued[i] = false;
        }
    }
    _ = pal.waveOutClose(ctx.hwo);
    ctx.fill_idx = 0;
    ctx.fill_len = 0;
}

// This backend exposes its vtable entries as the public free functions above;
// the caller assembles the `audio.AudioOut` literal (with `state` set to the
// context `open` returned). No function here *returns* `AudioOut`: a function
// returning the vtable struct trips compiler defect D8 in multi-module builds
// (see examples/torrent_example_defects.md).
