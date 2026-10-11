// audio_oss.zig — Linux OSS `/dev/dsp` audio backend for z9play (M4 Task 2).
//
// Implements the blueprint §2.2 `AudioOut` vtable (platform/audio.zig) on Linux
// through the OSS digitised-voice device `/dev/dsp`, using `extern "c"`
// open(2)/ioctl(2)/write(2)/close(2) and the OSS `SNDCTL_DSP_*` ioctls. The
// device is configured for signed 16-bit little-endian PCM at the requested
// rate / channel count; `write` blocks until the kernel accepts the data (OSS
// blocking-write semantics), and `drain` uses `SNDCTL_DSP_SYNC` to block until
// everything queued has played.
//
// Host dependence (blueprint §2.2, spec §5): the backend is Linux-only and
// best-effort. When the device is absent, cannot be opened, or a required ioctl
// fails, `open` returns `error.OpenFailed` cleanly (never crashes); when the
// device cannot honour the requested format/rate/channels it returns
// `error.ConfigUnsupported`. The hermetic WAV sink (audio_wavfile.zig) remains
// the gate backend.
//
// Assembly note (compiler defect D8): a backend must NOT expose a function that
// *returns* `AudioOut` (the vtable struct) in a multi-module build. This module
// exposes the four vtable operations as public free functions (`open`/`write`/
// `close`/`drain`); the caller assembles the `AudioOut` literal and sets
// `state` to the context `open` returned. See examples/torrent_example_defects.md
// (D8). The C externs live in audio_oss_pal.zig because an `extern "c" fn open`
// cannot share a module with the required `pub fn open` (same-name collision).
//
// Pure Z98: free functions only, strict `@intCast`, numeric OSS ioctl constants
// (the emitted C does not depend on <sys/soundcard.h> having been installed).

const std = @import("std");
const pal = @import("audio_oss_pal.zig");
const audio = @import("audio.zig");

pub const AudioError = audio.AudioError;
pub const AudioOut = audio.AudioOut;

// C prototypes for the externs in audio_oss_pal.zig. Z98 emits no extern
// prototypes, so gcc sees only these headers' declarations; POSIX open flags are
// hardcoded numerically below (matching sf/src/std_file.zig), never the macros.
@cInclude("<unistd.h>");
@cInclude("<fcntl.h>");
@cInclude("<sys/ioctl.h>");

// POSIX open(2) (linux x86 numeric values; deliberately not the fcntl.h macros).
const O_WRONLY: i32 = 1;
const OPEN_MODE: i32 = 0;

// OSS ioctl request numbers (from <linux/soundcard.h>), computed for the pinned
// i386 target from the kernel's _IOC macro: dir<<30 | size<<16 | type<<8 | nr,
// with type 'P' = 0x50 and `int` = 4 bytes. Hardcoded so the emitted C does not
// require <sys/soundcard.h> to be installed at all.
//   _SIOWR('P',5,int) = 0xC0045005  SNDCTL_DSP_SETFMT  (get/set sample format)
//   _SIOWR('P',6,int) = 0xC0045006  SNDCTL_DSP_CHANNELS
//   _SIOWR('P',2,int) = 0xC0045002  SNDCTL_DSP_SPEED
//   _SIO  ('P',1)     = 0x00005001  SNDCTL_DSP_SYNC    (block until played out)
const SNDCTL_DSP_SETFMT: u32 = 0xC0045005;
const SNDCTL_DSP_CHANNELS: u32 = 0xC0045006;
const SNDCTL_DSP_SPEED: u32 = 0xC0045002;
const SNDCTL_DSP_SYNC: u32 = 0x00005001;

// AFMT_S16_LE: OSS sample-format mask bit for signed 16-bit little-endian.
const AFMT_S16_LE: i32 = 0x00000010;

// One open device. Only one is open at a time (a global), matching the v1 player,
// which drives a single output device.
const OssDev = struct {
    fd: i32,
    rate: u32,
    channels: u8,
};

const DEV_PATH_BUF: usize = 16;

var g_dev: OssDev = undefined;

// Copy `s` into `out` and NUL-terminate. Returns false when it does not fit.
fn cstr(s: []const u8, out: []u8) bool {
    if (s.len >= out.len) return false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) out[i] = s[i];
    out[s.len] = 0;
    return true;
}

// --- vtable implementation -------------------------------------------------

// `AudioOut.open_fn`: open `/dev/dsp` and configure s16 / `channels` / `rate`.
// v1 accepts only 44100 and 48000, mono or stereo (spec §5); anything else is
// `ConfigUnsupported`. Any device failure (absent, busy, ioctl rejected) closes
// the fd if it was opened and returns `OpenFailed`.
pub fn open(rate: u32, channels: u8) AudioError!*void {
    if (rate != 44100 and rate != 48000) return error.ConfigUnsupported;
    if (channels != 1 and channels != 2) return error.ConfigUnsupported;

    var path: []const u8 = "/dev/dsp";
    var devbuf: [DEV_PATH_BUF]u8 = undefined;
    if (!cstr(path, devbuf[0..])) return error.OpenFailed;

    var fd: i32 = pal.open(@ptrCast([*]const u8, &devbuf[0]), O_WRONLY, OPEN_MODE);
    if (fd < 0) return error.OpenFailed;

    var fmt: i32 = AFMT_S16_LE;
    if (pal.ioctl(fd, SNDCTL_DSP_SETFMT, @ptrCast(*void, &fmt)) < 0) {
        _ = pal.close(fd);
        return error.OpenFailed;
    }
    if (fmt != AFMT_S16_LE) {
        _ = pal.close(fd);
        return error.ConfigUnsupported;
    }

    var chans: i32 = @intCast(i32, channels);
    if (pal.ioctl(fd, SNDCTL_DSP_CHANNELS, @ptrCast(*void, &chans)) < 0) {
        _ = pal.close(fd);
        return error.OpenFailed;
    }
    if (chans != @intCast(i32, channels)) {
        _ = pal.close(fd);
        return error.ConfigUnsupported;
    }

    var speed: i32 = @intCast(i32, rate);
    if (pal.ioctl(fd, SNDCTL_DSP_SPEED, @ptrCast(*void, &speed)) < 0) {
        _ = pal.close(fd);
        return error.OpenFailed;
    }
    if (speed != @intCast(i32, rate)) {
        _ = pal.close(fd);
        return error.ConfigUnsupported;
    }

    g_dev = OssDev{ .fd = fd, .rate = rate, .channels = channels };
    return @ptrCast(*void, &g_dev);
}

// `AudioOut.write_fn`: write interleaved s16 samples as little-endian bytes.
// The OSS blocking write accepts the data before returning (so this call blocks
// until consumed); a short write is looped. Returns the number of samples
// accepted (all of them, on success).
pub fn write(state: *void, samples: []const i16) AudioError!usize {
    if (samples.len == 0) return 0;
    var ctx: *OssDev = @ptrCast(*OssDev, state);
    var base: [*]const u8 = @ptrCast([*]const u8, samples.ptr);
    var bytes: usize = samples.len * 2;
    var off: usize = 0;
    while (off < bytes) {
        var w: i32 = pal.write(ctx.fd, base + off, @intCast(u32, bytes - off));
        if (w <= 0) return error.WriteFailed;
        off += @intCast(usize, w);
    }
    return samples.len;
}

// `AudioOut.drain_fn`: block until queued audio has played out. OSS
// SNDCTL_DSP_SYNC waits for the device to finish the current buffer.
pub fn drain(state: *void) AudioError!void {
    var ctx: *OssDev = @ptrCast(*OssDev, state);
    var dummy: i32 = 0;
    if (pal.ioctl(ctx.fd, SNDCTL_DSP_SYNC, @ptrCast(*void, &dummy)) < 0) {
        return error.DeviceError;
    }
}

// `AudioOut.close_fn`: release the device. void per blueprint §2.2.
pub fn close(state: *void) void {
    var ctx: *OssDev = @ptrCast(*OssDev, state);
    _ = pal.close(ctx.fd);
}

// This backend exposes its vtable entries as the public free functions above;
// the caller assembles the `audio.AudioOut` literal (with `state` set to the
// context `open` returned). No function here *returns* `AudioOut`: a function
// returning the vtable struct trips compiler defect D8 in multi-module builds
// (see examples/torrent_example_defects.md).
