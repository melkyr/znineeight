// audio_wavfile.zig — hermetic WAV-file audio sink for z9play (M4 Task 1).
//
// Implements the blueprint §2.2 `AudioOut` vtable (audio.zig) by writing the
// decoded interleaved s16 PCM to a canonical 44-byte-header RIFF/WAVE file.
// It is the device-free gate backend: the OSS `/dev/dsp` backend (Task 2) is
// host-dependent, but this sink is deterministic and needs no audio hardware.
//
// Output path mechanism (plan Task 1 left this to the implementer): the vtable
// `open_fn(rate, channels)` carries no path, so the sink resolves it from a
// module-global, set by `setOutputPath`, with a `Z9PLAY_WAV_OUT` environment
// fallback. The explicit setter wins; when neither is set `open` fails with
// `OpenFailed`. The hermetic test calls `setOutputPath` before `open`.
//
// Header strategy: `open` writes the full 44-byte header with the two size
// fields zeroed, then each `write` appends raw little-endian s16. `close`
// seeks back and patches the RIFF size (offset 4 = 36 + data bytes) and the
// `data` chunk size (offset 40 = data bytes). `drain` flushes to disk.
//
// Pure Z98: free functions only, strict `@intCast`, string literals via typed
// `var` (AGENTS.md X.5), no `[]synthetic` types (D2), single global sink.

const std = @import("std");
const filemod = @import("std_file");
const audio = @import("audio.zig");

pub const AudioError = audio.AudioError;
pub const AudioOut = audio.AudioOut;

const PATH_BUF: usize = 4096;
const ARENA_BUF: usize = 64 * 1024;
const CHUNK_SAMPLES: usize = 1024;

// One WAV sink. Only one is open at a time (a global), matching the v1 player,
// which drives a single output device.
const WavSink = struct {
    file: filemod.File,
    rate: u32,
    channels: u8,
    data_bytes: u32,
};

var g_arena_buf: [ARENA_BUF]u8 = undefined;
var g_arena: std.arena.Arena = undefined;
var g_path_buf: [PATH_BUF]u8 = undefined;
var g_path_len: usize = 0;
var g_ctx: WavSink = undefined;

// --- output path ----------------------------------------------------------

// Set the destination WAV path (copied into a fixed buffer, so the caller's
// memory need not outlive the call). Overrides the Z9PLAY_WAV_OUT fallback.
pub fn setOutputPath(path: []const u8) void {
    var n: usize = path.len;
    if (n > PATH_BUF) n = PATH_BUF;
    var i: usize = 0;
    while (i < n) : (i += 1) g_path_buf[i] = path[i];
    g_path_len = n;
}

fn outputPath() []const u8 {
    return g_path_buf[0..g_path_len];
}

// --- little-endian header helpers -----------------------------------------

fn putLe16(buf: []u8, off: usize, v: u16) void {
    buf[off] = @intCast(u8, v & 0xff);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xff);
}

fn putLe32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @intCast(u8, v & 0xff);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xff);
    buf[off + 2] = @intCast(u8, (v >> 16) & 0xff);
    buf[off + 3] = @intCast(u8, (v >> 24) & 0xff);
}

// Canonical 44-byte PCM WAV header for `data_bytes` bytes of interleaved s16.
fn writeWavHeader(buf: []u8, data_bytes: u32, channels: u16, sample_rate: u32) void {
    buf[0] = 'R';
    buf[1] = 'I';
    buf[2] = 'F';
    buf[3] = 'F';
    putLe32(buf, 4, 36 + data_bytes);
    buf[8] = 'W';
    buf[9] = 'A';
    buf[10] = 'V';
    buf[11] = 'E';
    buf[12] = 'f';
    buf[13] = 'm';
    buf[14] = 't';
    buf[15] = ' ';
    putLe32(buf, 16, 16);
    putLe16(buf, 20, 1);
    putLe16(buf, 22, channels);
    putLe32(buf, 24, sample_rate);
    putLe32(buf, 28, sample_rate * @intCast(u32, channels) * 2);
    putLe16(buf, 32, channels * 2);
    putLe16(buf, 34, 16);
    buf[36] = 'd';
    buf[37] = 'a';
    buf[38] = 't';
    buf[39] = 'a';
    putLe32(buf, 40, data_bytes);
}

// Write every byte of `data` (loop over partial writes).
fn writeExact(f: *filemod.File, data: []const u8) AudioError!void {
    var off: usize = 0;
    while (off < data.len) {
        var w: usize = filemod.write(f, data[off..]) catch return error.WriteFailed;
        if (w == 0) return error.WriteFailed;
        off += w;
    }
}

// --- vtable implementation -------------------------------------------------

// `AudioOut.open_fn`: open the sink for `rate`/`channels` and return its opaque
// context. v1 accepts only 44100 and 48000 (spec §1); anything else is
// ConfigUnsupported.
pub fn open(rate: u32, channels: u8) AudioError!*void {
    if (rate != 44100 and rate != 48000) return error.ConfigUnsupported;
    if (channels == 0) return error.ConfigUnsupported;

    var path: []const u8 = outputPath();
    if (path.len == 0) {
        var envname: []const u8 = "Z9PLAY_WAV_OUT";
        if (std.os.env(envname)) |e| {
            setOutputPath(e);
            path = outputPath();
        }
    }
    if (path.len == 0) return error.OpenFailed;

    g_arena = std.arena.init(g_arena_buf[0..]);
    var f: filemod.File = filemod.open(&g_arena, path, filemod.Mode.Write) catch return error.OpenFailed;

    var hdr: [44]u8 = undefined;
    writeWavHeader(hdr[0..], 0, @intCast(u16, channels), rate);
    writeExact(&f, hdr[0..]) catch {
        filemod.close(&f);
        return error.WriteFailed;
    };

    g_ctx = WavSink{ .file = f, .rate = rate, .channels = channels, .data_bytes = 0 };
    return @ptrCast(*void, &g_ctx);
}

// `AudioOut.write_fn`: append interleaved s16 samples as little-endian bytes.
// Returns the number of samples accepted (all of them, on success).
pub fn write(state: *void, samples: []const i16) AudioError!usize {
    var ctx: *WavSink = @ptrCast(*WavSink, state);
    var chunk: [CHUNK_SAMPLES * 2]u8 = undefined;
    var i: usize = 0;
    while (i < samples.len) {
        var n: usize = samples.len - i;
        if (n > CHUNK_SAMPLES) n = CHUNK_SAMPLES;
        var j: usize = 0;
        while (j < n) : (j += 1) {
            var u: u16 = @bitCast(u16, samples[i + j]);
            chunk[j * 2] = @intCast(u8, u & 0xff);
            chunk[j * 2 + 1] = @intCast(u8, (u >> 8) & 0xff);
        }
        writeExact(&ctx.file, chunk[0 .. n * 2]) catch return error.WriteFailed;
        ctx.data_bytes += @intCast(u32, n * 2);
        i += n;
    }
    return samples.len;
}

// `AudioOut.drain_fn`: block until buffered audio is consumed; for a file sink,
// flush to disk.
pub fn drain(state: *void) AudioError!void {
    var ctx: *WavSink = @ptrCast(*WavSink, state);
    filemod.flush(&ctx.file) catch return error.DeviceError;
}

// `AudioOut.close_fn`: patch the two size fields, then close. void per blueprint
// §2.2; a seek/write failure here still closes the file (best effort).
pub fn close(state: *void) void {
    var ctx: *WavSink = @ptrCast(*WavSink, state);
    var b: [4]u8 = undefined;
    putLe32(b[0..], 0, 36 + ctx.data_bytes);
    _ = filemod.seek(&ctx.file, 4, filemod.SeekWhence.Set) catch {};
    writeExact(&ctx.file, b[0..]) catch {};
    putLe32(b[0..], 0, ctx.data_bytes);
    _ = filemod.seek(&ctx.file, 40, filemod.SeekWhence.Set) catch {};
    writeExact(&ctx.file, b[0..]) catch {};
    filemod.close(&ctx.file);
}

// This backend exposes its vtable entries as the public free functions above;
// the caller assembles the `audio.AudioOut` literal (with `state` set to the
// context `open` returned). No function here *returns* `AudioOut`: a function
// returning the vtable struct trips compiler defect D8 in multi-module builds
// (see examples/torrent_example_defects.md).
