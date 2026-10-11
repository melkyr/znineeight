// audio_test.zig — deterministic hermetic test for the z9play WAV audio sink
// (M4 Task 1).
//
// Exercises the blueprint §2.2 `AudioOut` vtable through audio_wavfile.zig:
//   1. setOutputPath + open(44100, 2)
//   2. write N interleaved s16 via the vtable `write_fn`
//   3. drain + close via the vtable
//   4. read the file back and assert: exactly 44 header bytes + N*2 payload
//      bytes; canonical RIFF/WAVE/fmt/data fields for 16-bit stereo 44100;
//      riff size = 36 + payload; data size = payload; and the payload matches
//      the written samples byte-for-byte (little-endian s16).
//   5. a second open/write to a second path must be byte-identical (the global
//      sink re-initialises cleanly).
//   6. negative: an unsupported sample rate is ConfigUnsupported.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/audio_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const audio = @import("../platform/audio.zig");
const wav = @import("../platform/audio_wavfile.zig");

const NSAMP: usize = 1000;

var arena1_buf: [4 * 1024 * 1024]u8 = undefined;
var arena2_buf: [4 * 1024 * 1024]u8 = undefined;
var samples: [NSAMP]i16 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "audio_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn readLe16(b: []const u8, off: usize) u32 {
    return @intCast(u32, b[off]) | (@intCast(u32, b[off + 1]) << 8);
}

fn readLe32(b: []const u8, off: usize) u32 {
    return @intCast(u32, b[off]) | (@intCast(u32, b[off + 1]) << 8) |
        (@intCast(u32, b[off + 2]) << 16) | (@intCast(u32, b[off + 3]) << 24);
}

fn eqAt(b: []const u8, off: usize, s: []const u8) bool {
    if (off + s.len > b.len) return false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (b[off + i] != s[i]) return false;
    }
    return true;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// Write the shared deterministic sample block to `path` through the vtable.
// The vtable is assembled here from the backend's public free functions (the
// backend cannot return an `AudioOut`; compiler defect D8 — see
// examples/torrent_example_defects.md).
fn writeSink(path: []const u8) void {
    wav.setOutputPath(path);
    var ctx: *void = wav.open(44100, 2) catch {
        fail("open(44100,2) failed");
        return;
    };
    var ao: audio.AudioOut = audio.AudioOut{
        .open_fn = wav.open,
        .write_fn = wav.write,
        .close_fn = wav.close,
        .drain_fn = wav.drain,
        .state = ctx,
    };
    var got: usize = ao.write_fn(ao.state, samples[0..]) catch {
        fail("write_fn failed");
        return;
    };
    if (got != NSAMP) fail("write_fn short write");
    ao.drain_fn(ao.state) catch {
        fail("drain_fn failed");
        return;
    };
    ao.close_fn(ao.state);
}

// Read `path` back and assert the canonical header + payload for NSAMP s16.
fn checkSink(arena: *std.arena.Arena, path: []const u8) []u8 {
    var data: []u8 = filemod.readAll(arena, path) catch {
        fail("read back failed");
        return undefined;
    };
    var want: usize = 44 + NSAMP * 2;
    if (data.len != want) fail("file size wrong");
    if (!eqAt(data, 0, "RIFF")) fail("missing RIFF");
    if (!eqAt(data, 8, "WAVE")) fail("missing WAVE");
    if (!eqAt(data, 12, "fmt ")) fail("missing fmt ");
    if (!eqAt(data, 36, "data")) fail("missing data");
    if (readLe32(data, 4) != @intCast(u32, 36 + NSAMP * 2)) fail("bad riff size");
    if (readLe32(data, 16) != 16) fail("bad fmt chunk size");
    if (readLe16(data, 20) != 1) fail("bad audio format");
    if (readLe16(data, 22) != 2) fail("bad channel count");
    if (readLe32(data, 24) != 44100) fail("bad sample rate");
    if (readLe32(data, 28) != 176400) fail("bad byte rate");
    if (readLe16(data, 32) != 4) fail("bad block align");
    if (readLe16(data, 34) != 16) fail("bad bits per sample");
    if (readLe32(data, 40) != @intCast(u32, NSAMP * 2)) fail("bad data size");
    var k: usize = 0;
    while (k < NSAMP) : (k += 1) {
        var u: u16 = @bitCast(u16, samples[k]);
        if (readLe16(data, 44 + k * 2) != @intCast(u32, u)) fail("payload not LE s16");
    }
    return data;
}

// True iff opening `rate` reports exactly ConfigUnsupported.
fn openUnsupported(rate: u32) bool {
    var ctx: *void = wav.open(rate, 2) catch |e| {
        return e == error.ConfigUnsupported;
    };
    _ = ctx;
    return false;
}

pub fn main() void {
    var path1: []const u8 = "/tmp/z9play_audio_test.wav";
    var path2: []const u8 = "/tmp/z9play_audio_test2.wav";

    var k: usize = 0;
    while (k < NSAMP) : (k += 1) {
        var v: i32 = @intCast(i32, k * 37 % 2000) - 1000;
        samples[k] = @intCast(i16, v);
    }

    writeSink(path1);
    writeSink(path2);

    var arena1 = std.arena.init(arena1_buf[0..]);
    var arena2 = std.arena.init(arena2_buf[0..]);
    var d1: []u8 = checkSink(&arena1, path1);
    var d2: []u8 = checkSink(&arena2, path2);

    // Determinism: two independent opens produce byte-identical files.
    if (!eql(d1, d2)) fail("two sink runs differ");

    // Negative: an unsupported sample rate must be ConfigUnsupported.
    if (!openUnsupported(22050)) fail("open(22050) did not report ConfigUnsupported");

    var p: []const u8 = "audio_test: PASS bytes=";
    std.io.write(p);
    std.io.printInt(@intCast(i32, d1.len));
    var nl: []const u8 = " deterministic=2x config_check=ok\n";
    std.io.write(nl);
    std.os.exit(0);
}
