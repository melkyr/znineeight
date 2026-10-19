// player_test.zig — deterministic unit test for the z9play Player core +
// double-buffer ring (M4 Task 3).
//
// Drives the WHOLE testdata/sine_stereo_44100.ogg through `player.zig` (the M3
// Vorbis backend behind the `Decoder` vtable) into the hermetic WAV sink
// (platform/audio_wavfile.zig), and asserts:
//
//   1. completion: `playerPump` advances `playing` -> `ended` with no error;
//   2. BYTE-IDENTITY: the produced WAV payload is byte-for-byte equal to the M3
//      `z9play --pcm` output for the same file. That reference is reproduced
//      in-test exactly as main.zig's `--pcm` path does it (decode every audio
//      packet with one `DecoderState`, then trim to `ogg.lastGranule`).
//      (NB: the M3 `--pcm` output is NOT byte-identical to the committed
//      libvorbis golden `expected/*.pcm` — it differs by <= 1 LSB — so the
//      golden is checked by TOLERANCE below, as in tier_decode.sh.)
//   3. tolerance: max |delta| vs testdata/expected/sine_stereo_44100.pcm <= 2
//      LSB (the M3 decode tolerance);
//   4. determinism: two independent Player runs produce byte-identical WAVs.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/player_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const ogg_stream = @import("../ogg_stream.zig");
const vi = @import("../vorbis_info.zig");
const vs = @import("../vorbis_setup.zig");
const dec = @import("../decode.zig");
const audio = @import("../platform/audio.zig");
const wav = @import("../platform/audio_wavfile.zig");
const player = @import("../player.zig");

const FIXTURE: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
const GOLDEN: []const u8 = "examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm";

const MAX_DELTA_BOUND: i32 = 2;

// Arenas. parse/scratch back the Vorbis decoder (persistent state + per-packet
// scratch); player backs the ring + block scratch; ref reproduces the M3 --pcm
// path (single arena, no per-packet reset); io/gold read files back.
var parse_buf: [12 * 1024 * 1024]u8 = undefined;
var scratch_buf: [8 * 1024 * 1024]u8 = undefined;
var player_buf: [2 * 1024 * 1024]u8 = undefined;
var ref_buf: [24 * 1024 * 1024]u8 = undefined;
var io1_buf: [1 * 1024 * 1024]u8 = undefined;
var io2_buf: [1 * 1024 * 1024]u8 = undefined;
var gold_buf: [1 * 1024 * 1024]u8 = undefined;

// Decoded streams: the M3 reference (trimmed to the granule) and one-block
// scratch for the reference decoder.
var ref_pcm: [200000]i16 = undefined;
var tmp_ref: [4096]i16 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "player_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn bytesEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn readLe16(b: []const u8, off: usize) u32 {
    return @intCast(u32, b[off]) | (@intCast(u32, b[off + 1]) << 8);
}

// Run the Player once over FIXTURE into `wav_path`. Resets the codec arenas at
// entry so two runs are independent.
fn playOnce(parse: *std.arena.Arena, scratch: *std.arena.Arena, par: *std.arena.Arena, wav_path: []const u8) void {
    std.arena.reset(parse);
    std.arena.reset(scratch);
    std.arena.reset(par);

    var id: vi.IdHeader = undefined;
    var setup: vs.Setup = undefined;
    var os: ogg_stream.OggStream = ogg_stream.oggStreamOpen(parse, FIXTURE) catch {
        fail("oggStreamOpen failed");
        return;
    };
    var m0: ?[]const u8 = ogg_stream.oggStreamNextPacket(&os) catch {
        fail("packet 0 failed");
        return;
    };
    if (m0) |p0| {
        id = vi.parseId(p0) catch {
            fail("parseId failed");
            return;
        };
    } else {
        fail("missing Vorbis headers");
        return;
    }
    var m1: ?[]const u8 = ogg_stream.oggStreamNextPacket(&os) catch {
        fail("packet 1 failed");
        return;
    };
    if (m1) |p1| {
        _ = p1;
    } else {
        fail("missing Vorbis headers");
        return;
    }
    var m2: ?[]const u8 = ogg_stream.oggStreamNextPacket(&os) catch {
        fail("packet 2 failed");
        return;
    };
    if (m2) |p2| {
        setup = vs.parseSetup(parse, p2, @intCast(u32, id.channels)) catch {
            fail("parseSetup failed");
            return;
        };
    } else {
        fail("missing Vorbis setup header");
        return;
    }
    var st: dec.DecoderState = dec.initDecoderState(parse, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
        fail("initDecoderState failed");
        return;
    };
    var last: u64 = ogg_stream.oggStreamLastGranule(parse, FIXTURE, os.serial) catch {
        fail("lastGranule failed");
        return;
    };

    var vc: *player.VorbisCtx = player.vorbisCreate(parse, scratch, &os, setup, st, id.sample_rate, id.channels, last) catch {
        fail("vorbisCreate failed");
        return;
    };
    var decv: player.Decoder = player.Decoder{
        .ctx = @ptrCast(*void, vc),
        .next_fn = player.vorbisNext,
        .max_frames = vc.max_frames,
        .sample_rate = vc.sample_rate,
        .channels = vc.channels,
        .total_frames = vc.total_frames,
    };

    wav.setOutputPath(wav_path);
    var ctx: *void = wav.open(id.sample_rate, id.channels) catch {
        fail("wav open failed");
        return;
    };
    var ao: audio.AudioOut = audio.AudioOut{
        .open_fn = wav.open,
        .write_fn = wav.write,
        .close_fn = wav.close,
        .drain_fn = wav.drain,
        .state = ctx,
    };
    var meta: player.Meta = player.Meta{ .title = null, .artist = null, .album = null };

    var pl: player.Player = undefined;
    player.playerInit(&pl, par, &decv, &ao, meta) catch {
        fail("playerInit failed");
        return;
    };

    if (pl.state != player.PlayerState.playing) {
        fail("player did not start in playing");
        return;
    }
    while (pl.state == player.PlayerState.playing) {
        player.playerPump(&pl) catch |e| {
            if (e == error.DecodeFailed) fail("playerPump: DecodeFailed");
            if (e == error.AudioFailed) fail("playerPump: AudioFailed");
            if (e == error.OutOfMemory) fail("playerPump: OutOfMemory");
            if (e == error.BadConfig) fail("playerPump: BadConfig");
            fail("playerPump: other");
            return;
        };
    }
    if (pl.state != player.PlayerState.ended) {
        fail("player did not end cleanly");
        return;
    }
    pl.audio.drain_fn(pl.audio.state) catch {
        fail("audio drain failed");
        return;
    };
    pl.audio.close_fn(pl.audio.state);
    ogg_stream.oggStreamClose(&os);
}

// Reproduce the M3 `--pcm` reference: decode every audio packet with one
// `DecoderState` (no per-packet reset, matching main.zig), then trim to
// `ogg.lastGranule`. Fills `ref_pcm`; stores the frame count in `frames_out`.
fn buildReference(ref: *std.arena.Arena, frames_out: *usize) void {
    std.arena.reset(ref);
    var data: []u8 = filemod.readAll(ref, FIXTURE) catch {
        fail("ref: cannot read fixture");
        return;
    };
    var packets: []ogg.Packet = ogg.reassemble(ref, data) catch {
        fail("ref: reassemble failed");
        return;
    };
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("ref: parseId failed");
        return;
    };
    var setup: vs.Setup = vs.parseSetup(ref, packets[2].bytes, @intCast(u32, id.channels)) catch {
        fail("ref: parseSetup failed");
        return;
    };
    var st: dec.DecoderState = dec.initDecoderState(ref, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
        fail("ref: initDecoderState failed");
        return;
    };
    var ch: usize = @intCast(usize, id.channels);
    var total: usize = 0;
    var p: usize = 3;
    while (p < packets.len) : (p += 1) {
        var f: usize = dec.decodePacket(ref, setup, &st, packets[p].bytes, tmp_ref[0..4096]) catch {
            fail("ref: decodePacket failed");
            return;
        };
        var q: usize = 0;
        while (q < f * ch) : (q += 1) {
            ref_pcm[(total * ch) + q] = tmp_ref[q];
        }
        total += f;
    }
    var last: u64 = ogg.lastGranule(ref, data) catch 0;
    var frames: usize = total;
    if (last > 0 and last <= @intCast(u64, total)) frames = @intCast(usize, last);
    frames_out.* = frames;
}

pub fn main() void {
    var parse = std.arena.init(parse_buf[0..]);
    var scratch = std.arena.init(scratch_buf[0..]);
    var par = std.arena.init(player_buf[0..]);
    var ref = std.arena.init(ref_buf[0..]);
    var io1 = std.arena.init(io1_buf[0..]);
    var io2 = std.arena.init(io2_buf[0..]);
    var gold = std.arena.init(gold_buf[0..]);

    var path1: []const u8 = "/tmp/z9play_player_test.wav";
    var path2: []const u8 = "/tmp/z9play_player_test2.wav";

    playOnce(&parse, &scratch, &par, path1);
    playOnce(&parse, &scratch, &par, path2);

    var d1: []u8 = filemod.readAll(&io1, path1) catch {
        fail("cannot read back wav1");
        return;
    };
    var d2: []u8 = filemod.readAll(&io2, path2) catch {
        fail("cannot read back wav2");
        return;
    };
    if (!bytesEq(d1, d2)) fail("player output not deterministic");
    if (d1.len < 44) fail("wav too short");

    // Canonical header: 16-bit PCM, the fixture's channels/rate.
    if (readLe16(d1, 20) != 1) fail("wav: not PCM");
    var ch: usize = @intCast(usize, readLe16(d1, 22));
    if (ch == 0) fail("wav: zero channels");
    if (readLe16(d1, 34) != 16) fail("wav: not 16-bit");

    // Reference (M3 --pcm) and byte-identity.
    var ref_frames: usize = 0;
    buildReference(&ref, &ref_frames);
    if (ref_frames == 0) fail("reference produced no frames");
    var ref_bytes: usize = ref_frames * ch * 2;
    if (d1.len != 44 + ref_bytes) fail("payload size differs from M3 --pcm");
    var i: usize = 0;
    while (i < ref_bytes) : (i += 1) {
        var s: i16 = ref_pcm[@intCast(usize, i / 2)];
        var u: u16 = @bitCast(u16, s);
        var lo: u8 = @intCast(u8, u & 0xff);
        var hi: u8 = @intCast(u8, (u >> 8) & 0xff);
        var want: u8 = lo;
        if ((i % 2) == 1) want = hi;
        if (d1[44 + i] != want) fail("payload byte differs from M3 --pcm");
    }

    // Tolerance vs the libvorbis golden (M3 gate: <= 2 LSB).
    var gold_bytes: []u8 = filemod.readAll(&gold, GOLDEN) catch {
        fail("cannot read golden pcm");
        return;
    };
    var nsamp: usize = ref_frames * ch;
    var gn: usize = gold_bytes.len / 2;
    if (gn < nsamp) nsamp = gn;
    var gv: []i16 = @ptrCast([*]i16, gold_bytes.ptr)[0..gn];
    var maxd: i32 = 0;
    var k: usize = 0;
    while (k < nsamp) : (k += 1) {
        var d: i32 = @intCast(i32, ref_pcm[k]) - @intCast(i32, gv[k]);
        if (d < 0) d = -d;
        if (d > maxd) maxd = d;
    }
    if (maxd > MAX_DELTA_BOUND) fail("max delta vs golden exceeds 2 LSB");

    var p1: []const u8 = "player_test: PASS frames=";
    std.io.write(p1);
    std.io.printInt(@intCast(i32, ref_frames));
    var p2: []const u8 = " wav_bytes=";
    std.io.write(p2);
    std.io.printInt(@intCast(i32, d1.len));
    var p3: []const u8 = " max_delta=";
    std.io.write(p3);
    std.io.printInt(maxd);
    var p4: []const u8 = " m3_pcm=byte_identical deterministic=2x\n";
    std.io.write(p4);
    std.os.exit(0);
}
