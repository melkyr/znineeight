// decode_test.zig — deterministic unit/gate harness for z9play decode.zig
// (M3 Task 4).
//
// Decodes EVERY audio packet of testdata/sine_stereo_44100.ogg, in stream
// order, through ogg.reassemble -> parseId / parseSetup -> decode.zig into one
// interleaved s16 stream, and compares it against the libvorbis (oggdec) golden
// testdata/expected/sine_stereo_44100.pcm.
//
//   1. sample count: the decoder emits at least the golden frame count and no
//      more than one long block of padding beyond it. The golden is the first
//      `golden_frames` frames of the decoded stream (Vorbis discards the
//      priming frame's output and the final page's granule trims the last
//      frame's tail; the encoder's padding samples are the excess).
//   2. tolerance: max |delta| <= 2 LSB and the reported RMS.
//   3. determinism: three independent full decodes (arena reset between runs)
//      produce byte-identical PCM (SHA-1).
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/decode_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const crypto = @import("std_crypto");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const vi = @import("../vorbis_info.zig");
const vs = @import("../vorbis_setup.zig");
const dec = @import("../decode.zig");

const FIXTURE: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
const GOLDEN: []const u8 = "examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm";

// 16 MiB is ample for one decode pass (parser + decode tables + the residue
// decoder's per-codeword arena scratch); the arena is reset between the three
// determinism runs so the total stays bounded.
var arena_buf: [16 * 1024 * 1024]u8 = undefined;
var out_buf: [400000]i16 = undefined;
var tmp_buf: [4096]i16 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "decode_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn writeU(uint: u64) void {
    if (uint == 0) {
        var z: []const u8 = "0";
        std.io.write(z);
        return;
    }
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var v: u64 = uint;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = tmp[n - 1 - i];
    std.io.write(buf[0..n]);
}

fn hexByte(b: u8) void {
    var d: []const u8 = "0123456789abcdef";
    var hi: u8 = (b >> 4) & 0x0f;
    var lo: u8 = b & 0x0f;
    var s: [1]u8 = undefined;
    s[0] = d[@intCast(usize, hi)];
    std.io.write(s[0..1]);
    s[0] = d[@intCast(usize, lo)];
    std.io.write(s[0..1]);
}

fn sha1Of(data: []const u8, out: *[20]u8) void {
    var s: crypto.Sha1 = crypto.sha1Init();
    crypto.sha1Update(&s, data);
    crypto.sha1Final(&s, out);
}

const RunResult = struct {
    frames: usize,
    golden_frames: usize,
    max_delta: i32,
    rms_milli: i32,
    hash: [20]u8,
};

// One complete decode pass from a reset arena. Returns the decoded frame
// count, the golden frame count, the max absolute difference over the golden
// range, the RMS (in 1/1000 LSB), and the SHA-1 of the decoded golden range.
fn decodeOnce(arena: *std.arena.Arena, ch: usize) RunResult {
    var data: []u8 = filemod.readAll(arena, FIXTURE) catch {
        fail("cannot read fixture");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
    };
    var golden: []u8 = filemod.readAll(arena, GOLDEN) catch {
        fail("cannot read golden PCM");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
    };
    var packets: []ogg.Packet = ogg.reassemble(arena, data) catch {
        fail("reassemble failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
    };
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("parseId failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
    };
    var setup: vs.Setup = vs.parseSetup(arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
        fail("parseSetup failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
    };
    var state: dec.DecoderState = dec.initDecoderState(arena, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
        fail("initDecoderState failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
    };

    var total: usize = 0;
    var p: usize = 3;
    while (p < packets.len) : (p += 1) {
        var f: usize = dec.decodePacket(arena, setup, &state, packets[p].bytes, tmp_buf[0..4096]) catch |e| {
            if (e == error.UnsupportedFloor) {
                fail("decodePacket: unsupported floor (floor0) in fixture");
            } else if (e == error.OutOfMemory) {
                fail("decodePacket: arena OutOfMemory");
            } else {
                fail("decodePacket returned an error");
            }
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .rms_milli = 0, .hash = undefined };
        };
        var base: usize = total * ch;
        var q: usize = 0;
        while (q < f * ch) : (q += 1) {
            out_buf[base + q] = tmp_buf[q];
        }
        total += f;
    }

    var golden_frames: usize = golden.len / (2 * ch);
    if (total < golden_frames) fail("decoded fewer frames than the golden");
    var max_pad: u32 = 4096;
    if (total > golden_frames + @intCast(usize, max_pad)) fail("decoded far more frames than the golden");

    var gv: []i16 = @ptrCast([*]i16, golden.ptr)[0..golden_frames * ch];
    var count: usize = golden_frames * ch;
    var maxd: i32 = 0;
    var sumsq: f64 = 0.0;
    var k: usize = 0;
    while (k < count) : (k += 1) {
        var d: i32 = @intCast(i32, out_buf[k]) - @intCast(i32, gv[k]);
        var ad: i32 = d;
        if (ad < 0) ad = -ad;
        if (ad > maxd) maxd = ad;
        var df: f64 = @intToFloat(f64, d);
        sumsq = sumsq + df * df;
    }
    var rms: f64 = std.math.sqrt(sumsq / @intToFloat(f64, count));
    var rms_milli: i32 = @intCast(i32, rms * 1000.0 + 0.5);

    var hash: [20]u8 = undefined;
    var bytes: []const u8 = @ptrCast([*]const u8, out_buf[0..].ptr)[0 .. count * 2];
    sha1Of(bytes, &hash);

    return RunResult{ .frames = total, .golden_frames = golden_frames, .max_delta = maxd, .rms_milli = rms_milli, .hash = hash };
}

pub fn main() void {
    var arena = std.arena.init(arena_buf[0..]);

    std.arena.reset(&arena);
    var r1: RunResult = decodeOnce(&arena, 2);
    std.arena.reset(&arena);
    var r2: RunResult = decodeOnce(&arena, 2);
    std.arena.reset(&arena);
    var r3: RunResult = decodeOnce(&arena, 2);

    // sample count: the golden range must exist and the excess is bounded.
    if (r1.golden_frames == 0) fail("golden frame count is zero");
    if (r1.frames < r1.golden_frames) fail("r1 too few frames");
    if (r2.frames != r1.frames or r3.frames != r1.frames) fail("frame count not deterministic");
    if (r1.max_delta > 2) fail("max |delta| exceeds 2 LSB");

    // determinism: byte-identical PCM across three runs
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (r1.hash[i] != r2.hash[i] or r1.hash[i] != r3.hash[i]) fail("decoded PCM not deterministic");
    }

    var p1: []const u8 = "decode_test: PASS frames=";
    std.io.write(p1);
    writeU(@intCast(u64, r1.frames));
    var p2: []const u8 = " golden_frames=";
    std.io.write(p2);
    writeU(@intCast(u64, r1.golden_frames));
    var p3: []const u8 = " max_delta=";
    std.io.write(p3);
    std.io.printInt(r1.max_delta);
    var p4: []const u8 = " rms_milli=";
    std.io.write(p4);
    std.io.printInt(r1.rms_milli);
    var p5: []const u8 = " sha1=";
    std.io.write(p5);
    i = 0;
    while (i < 20) : (i += 1) hexByte(r1.hash[i]);
    var nl: []const u8 = " deterministic=3x\n";
    std.io.write(nl);
    std.os.exit(0);
}
