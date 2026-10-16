// main.zig — z9play entry point (z9play M0/M1/M3: `--info` metadata query,
// `--dump-setup` setup summary, and `--pcm` decode-to-WAV; M4: `--wav` Player
// playback into the hermetic WAV sink; M5: interactive CLI playback).
//
// Pure Z98: free functions, no generics, no @cImport, strict @intCast, string
// literals via `var s: []const u8 = "..."`. Reads one OGG file and reassembles
// its packets (ogg.zig), then dispatches on the cli mode:
//
//   --info        parse the Vorbis identification + comment headers
//                 (vorbis_info.zig), derive the duration from the last audio
//                 granule, and print a FIXED info block in the same `key=value`
//                 line format as the committed goldens
//                 (testdata/expected/*.meta):
//
//                   channels=<n>
//                   sample_rate=<rate>
//                   duration_s=<sec>.<mmm>       (3 decimal places)
//                   TITLE=<raw bytes>            (only when the tag is present)
//                   ARTIST=<raw bytes>           (only when the tag is present)
//                   ALBUM=<raw bytes>            (only when the tag is present)
//
//   --dump-setup  parse the setup header (vorbis_setup.zig, forwarding the
//                 identification header's channel count) and print one FIXED
//                 summary line in the same format as the committed goldens
//                 (testdata/expected/*.setup):
//
//                   codebooks=<n> floors=<n> residues=<n> mappings=<n> modes=<n>
//
//   --pcm <in> <out>  decode every audio packet to a canonical 44-byte-header
//                 PCM WAV (the M3 decode reference).
//
//   --wav <in> <out>  drive the M4 Player core (decode -> double-buffer ring ->
//                 the platform `AudioOut` vtable) into the hermetic WAV sink
//                 (platform/audio_wavfile.zig). No audio device is used. On
//                 success it prints `wav: ended frames=<n> pos_ms=<n>
//                 monotonic=<0|1>`; this is the path tests/tier_audio.sh gates.
//
//   <file.ogg> [--volume N] [--start SEC] [--loop] [--quiet]
//                 interactive M5 playback: drive the Player into the WAV sink
//                 when `Z9PLAY_WAV_OUT` is set, else the OSS `/dev/dsp` backend,
//                 with a startup metadata line, a per-second `\r` status line
//                 (fmt.statusLine) unless `--quiet`, keys space / `+` / `-` / `q`
//                 / Ctrl-C, and a final `Stopped at mm:ss.` line.
//
// Exit codes (design spec §5): 0 ok / 1 args (cli.zig) / 2 open / 3 decoder /
// 4 audio / 5 internal (M5 playback); the request modes retain their M0–M4
// codes (2 open / 3 decoder).
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/main.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog --info examples/z98/z9play/testdata/tagged_unicode.ogg

const std = @import("std");
const cli = @import("cli.zig");
const filemod = @import("std_file");
const ogg = @import("ogg.zig");
const vi = @import("vorbis_info.zig");
const vs = @import("vorbis_setup.zig");
const dec = @import("decode.zig");
const audio = @import("platform/audio.zig");
const wav = @import("platform/audio_wavfile.zig");
const oss = @import("platform/audio_oss.zig");
const con = @import("platform/console_linux.zig");
const contract = @import("platform/console.zig");
const fmt = @import("fmt.zig");
const player = @import("player.zig");

// Backing store for the read/reassembly/comment arena; module-global so it does
// not sit on the 32-bit stack (~11 KiB fixtures need a small fraction of this).
var arena_buf: [4 * 1024 * 1024]u8 = undefined;

// Separate arena for `--pcm` decode scratch. Decoding a whole file builds the
// codebook decode tables and the residue decoder's per-codeword vectors, which
// accumulate over the stream; the read/reassembly arena above is reused for the
// container and must stay intact. Module-global so it is off the 32-bit stack.
var dec_arena_buf: [16 * 1024 * 1024]u8 = undefined;

// `--wav` (M4 Player) backing stores: `wav_scratch_buf` is the per-packet decode
// scratch (reset by vorbisNext each packet, so it stays small); `wav_player_buf`
// backs the Player's double-buffer ring + one-block scratch. Both are module-
// global to keep them off the 32-bit stack.
var wav_scratch_buf: [8 * 1024 * 1024]u8 = undefined;
var wav_player_buf: [2 * 1024 * 1024]u8 = undefined;

// --- M5 interactive playback: audio wrappers ------------------------------
//
// Playback needs two things the M4 Player does not do itself: apply the CLI
// volume (the Player only stores `volume`) and, for `--start`, run a throwaway
// sink while it seeks. Both are frontend concerns, so M5 supplies `AudioOut`
// wrappers around whichever real backend was opened (WAV sink or OSS), exactly
// as M4 assembles the backend literal (no function here *returns* `AudioOut`;
// compiler defect D8).
//
// `g_real` is the selected backend vtable; `mix*` scales interleaved s16 by
// `g_mix_vol`/100 into `g_mix_buf`, then forwards to `g_real`. `discard*` drops
// samples and just counts them (the Player's position/ring bookkeeping still
// advances, so `--start` seeks by decoding). The Player never calls `open_fn`
// (the CLI opens the backend and sets `state`), but the field is filled for
// completeness.
const MIX_MAX: usize = 88200; // ring capacity (interleaved i16)
var g_mix_buf: [MIX_MAX]i16 = undefined;
var g_mix_vol: u8 = 80;
var g_real: audio.AudioOut = undefined;
var g_discard_ctx: u8 = 0;

fn mixOpen(rate: u32, channels: u8) audio.AudioError!*void {
    return g_real.open_fn(rate, channels);
}

fn mixWrite(state: *void, samples: []const i16) audio.AudioError!usize {
    var off: usize = 0;
    while (off < samples.len) {
        var n: usize = samples.len - off;
        if (n > MIX_MAX) n = MIX_MAX;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var s: i32 = @intCast(i32, samples[off + i]);
            s = s * @intCast(i32, g_mix_vol) / 100;
            g_mix_buf[i] = @intCast(i16, s);
        }
        var w: usize = g_real.write_fn(state, g_mix_buf[0..n]) catch return error.WriteFailed;
        if (w != n) return error.WriteFailed;
        off += n;
    }
    return samples.len;
}

fn mixClose(state: *void) void {
    g_real.close_fn(state);
}

fn mixDrain(state: *void) audio.AudioError!void {
    g_real.drain_fn(state) catch return error.DeviceError;
}

fn discardOpen(rate: u32, channels: u8) audio.AudioError!*void {
    _ = rate;
    _ = channels;
    return @ptrCast(*void, &g_discard_ctx);
}

fn discardWrite(state: *void, samples: []const i16) audio.AudioError!usize {
    _ = state;
    return samples.len;
}

fn discardClose(state: *void) void {
    _ = state;
}

fn discardDrain(state: *void) audio.AudioError!void {
    _ = state;
}

// Print `msg` (if non-empty), restore the terminal, and exit `code`. Used on
// every playback failure path after the `Console` entered raw mode. Restores
// through the contract's `leaveRaw_fn`, so it stays correct if the backend is
// swapped.
fn playFail(cs: *contract.Console, msg: []const u8, code: i32) void {
    cs.leaveRaw_fn(cs.state);
    std.io.write(msg);
    std.os.exit(code);
}

// Write the `\r`-prefixed fixed-width status line (fmt.statusLine) to stdout.
fn writeStatus(pos_ms: u64, dur_ms: u64, vol: u8) void {
    var buf: [fmt.STATUS_LINE_MAX]u8 = undefined;
    var line: []const u8 = fmt.statusLine(buf[0..], pos_ms, dur_ms, vol);
    var cr: []const u8 = "\r";
    std.io.write(cr);
    std.io.write(line);
}

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn writeNl() void {
    var s: []const u8 = "\n";
    std.io.write(s);
}

// Decimal, unsigned. The zero case prints a single `0` (the loop below would
// otherwise print nothing).
fn writeU64(v_in: u64) void {
    var v: u64 = v_in;
    if (v == 0) {
        var z: []const u8 = "0";
        std.io.write(z);
        return;
    }
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = tmp[n - 1 - i];
    }
    std.io.write(buf[0..n]);
}

// `value` zero-padded to exactly three decimal digits (0..=999).
fn write3digits(value: u64) void {
    var v: u64 = value % 1000;
    var b: [3]u8 = undefined;
    b[0] = @intCast(u8, (v / 100) % 10) + '0';
    b[1] = @intCast(u8, (v / 10) % 10) + '0';
    b[2] = @intCast(u8, v % 10) + '0';
    std.io.write(b[0..3]);
}

// Duration as seconds with three decimal places (`1300 ms` -> `1.300`).
fn writeDurationMs(ms: u64) void {
    writeU64(ms / 1000);
    var dot: []const u8 = ".";
    std.io.write(dot);
    write3digits(ms);
}

// The value for `key` (already uppercase) among `tags`, or "" when absent.
fn tagValue(tags: []vi.Tag, key: []const u8) []const u8 {
    var i: usize = 0;
    while (i < tags.len) : (i += 1) {
        if (std.str.eql(tags[i].key, key)) return tags[i].value;
    }
    var empty: []const u8 = "";
    return empty;
}

// Emit `KEY=<value>` for `key` when present; an empty (absent) or zero-length
// value prints nothing (the goldens omit unset tags).
fn writeTagLine(tags: []vi.Tag, key: []const u8) void {
    var v: []const u8 = tagValue(tags, key);
    if (v.len == 0) return;
    writeText(key);
    var eqs: []const u8 = "=";
    std.io.write(eqs);
    std.io.write(v);
    writeNl();
}

// Little-endian writers for the canonical WAV header (the fixtures' golden PCM
// is raw s16 LE, so the header byte order is fixed regardless of host).
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

// Write the canonical 44-byte PCM WAV header for `data_bytes` bytes of
// interleaved s16 data at `channels`/`sample_rate` into buf[0..44].
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

pub fn main(argc: i32, argv: [*][*]u8) void {
    var args: cli.Args = cli.parseArgs(argc, argv);

    var arena = std.arena.init(arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, args.path) catch {
        var msg: []const u8 = "z9play: cannot open file\n";
        std.io.write(msg);
        std.os.exit(2);
        return;
    };

    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        var msg: []const u8 = "z9play: not an OGG Vorbis stream\n";
        std.io.write(msg);
        std.os.exit(3);
        return;
    };
    if (packets.len < 2) {
        var msg: []const u8 = "z9play: missing Vorbis headers\n";
        std.io.write(msg);
        std.os.exit(3);
        return;
    }

    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        var msg: []const u8 = "z9play: bad Vorbis identification header\n";
        std.io.write(msg);
        std.os.exit(3);
        return;
    };

    if (args.mode == cli.MODE_DUMP_SETUP) {
        if (packets.len < 3) {
            var msg: []const u8 = "z9play: missing Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        }
        var setup: vs.Setup = vs.parseSetup(&arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
            var msg: []const u8 = "z9play: bad Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var l_cb: []const u8 = "codebooks=";
        std.io.write(l_cb);
        writeU64(@intCast(u64, setup.codebooks.len));
        var l_fl: []const u8 = " floors=";
        std.io.write(l_fl);
        writeU64(@intCast(u64, setup.floors.len));
        var l_rs: []const u8 = " residues=";
        std.io.write(l_rs);
        writeU64(@intCast(u64, setup.residues.len));
        var l_mp: []const u8 = " mappings=";
        std.io.write(l_mp);
        writeU64(@intCast(u64, setup.mappings.len));
        var l_mo: []const u8 = " modes=";
        std.io.write(l_mo);
        writeU64(@intCast(u64, setup.modes.len));
        writeNl();
        std.os.exit(0);
        return;
    }

    if (args.mode == cli.MODE_PCM) {
        if (packets.len < 3) {
            var msg: []const u8 = "z9play: missing Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        }
        var darena = std.arena.init(dec_arena_buf[0..]);
        var setup: vs.Setup = vs.parseSetup(&darena, packets[2].bytes, @intCast(u32, id.channels)) catch {
            var msg: []const u8 = "z9play: bad Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var state: dec.DecoderState = dec.initDecoderState(&darena, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
            var msg: []const u8 = "z9play: cannot initialize the decoder\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var ch: usize = @intCast(usize, id.channels);
        var n1: u32 = @intCast(u32, 1) << @intCast(u32, id.blocksize_1);
        var audio_count: usize = packets.len - 3;
        var frames_cap: usize = audio_count * @intCast(usize, n1 / 2);
        if (frames_cap == 0) frames_cap = 1;

        // Per-packet scratch: a block emits at most n1/2 frames = n1*ch samples.
        var tr: [*]u8 = std.arena.alloc(&darena, @intCast(usize, n1) * ch * @sizeOf(i16)) catch {
            var msg: []const u8 = "z9play: out of memory\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var tmp: []i16 = @ptrCast([*]i16, tr)[0 .. @intCast(usize, n1) * ch];
        var br: [*]u8 = std.arena.alloc(&darena, frames_cap * ch * @sizeOf(i16)) catch {
            var msg: []const u8 = "z9play: out of memory\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var big: []i16 = @ptrCast([*]i16, br)[0 .. frames_cap * ch];

        var total: usize = 0;
        var p: usize = 3;
        while (p < packets.len) : (p += 1) {
            var f: usize = dec.decodePacket(&darena, setup, &state, packets[p].bytes, tmp) catch {
                var msg: []const u8 = "z9play: corrupt or unsupported audio packet\n";
                std.io.write(msg);
                std.os.exit(3);
                return;
            };
            var q: usize = 0;
            while (q < f * ch) : (q += 1) {
                big[total * ch + q] = tmp[q];
            }
            total += f;
        }

        // Trim the last page's granule padding: the golden payload is the first
        // `granule` frames (the priming frame emits nothing).
        var last: u64 = ogg.lastGranule(&arena, data) catch 0;
        var out_frames: usize = total;
        if (last > 0 and last <= @intCast(u64, total)) out_frames = @intCast(usize, last);

        var data_bytes: usize = out_frames * ch * 2;
        var wlen: usize = 44 + data_bytes;
        var wr: [*]u8 = std.arena.alloc(&darena, wlen) catch {
            var msg: []const u8 = "z9play: out of memory\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var wbuf: []u8 = wr[0..wlen];
        writeWavHeader(wbuf[0..44], @intCast(u32, data_bytes), @intCast(u16, ch), id.sample_rate);

        var k: usize = 0;
        while (k < out_frames * ch) : (k += 1) {
            var u: u16 = @bitCast(u16, big[k]);
            wbuf[44 + k * 2] = @intCast(u8, u & 0xff);
            wbuf[44 + k * 2 + 1] = @intCast(u8, (u >> 8) & 0xff);
        }
        filemod.writeAll(args.out_path, wbuf) catch {
            var msg: []const u8 = "z9play: cannot write output file\n";
            std.io.write(msg);
            std.os.exit(2);
            return;
        };
        std.os.exit(0);
        return;
    }

    // --wav <in.ogg> <out.wav>: drive the M4 Player core (decode -> double
    // buffer ring -> audio vtable) into the hermetic WAV sink. This is the M4
    // gate path (tests/tier_audio.sh): it exercises the real Player + audio
    // output layer with no device dependency. Exit codes follow the spec:
    // 3 = malformed stream / decode / audio failure, 2 = sink open failure.
    if (args.mode == cli.MODE_WAV) {
        if (packets.len < 3) {
            var msg: []const u8 = "z9play: missing Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        }

        // Persistent decode state (setup, DecoderState, the VorbisCtx and its
        // one-block scratch) off the 32-bit stack; `scratch` is reset per packet
        // by vorbisNext; `par` backs the Player ring + block buffer. `darena`
        // reuses the --pcm decode arena (mutually exclusive modes).
        var darena = std.arena.init(dec_arena_buf[0..]);
        var scratch = std.arena.init(wav_scratch_buf[0..]);
        var par = std.arena.init(wav_player_buf[0..]);

        var setup: vs.Setup = vs.parseSetup(&darena, packets[2].bytes, @intCast(u32, id.channels)) catch {
            var msg: []const u8 = "z9play: bad Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var state: dec.DecoderState = dec.initDecoderState(&darena, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
            var msg: []const u8 = "z9play: cannot initialize the decoder\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var last: u64 = ogg.lastGranule(&arena, data) catch {
            var msg: []const u8 = "z9play: cannot locate the audio granule\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var vc: *player.VorbisCtx = player.vorbisCreate(&darena, &scratch, packets, setup, state, 3, id.sample_rate, id.channels, last) catch {
            var msg: []const u8 = "z9play: cannot initialize the player decoder\n";
            std.io.write(msg);
            std.os.exit(3);
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

        wav.setOutputPath(args.out_path);
        var actx: *void = wav.open(id.sample_rate, id.channels) catch {
            var msg: []const u8 = "z9play: cannot open the WAV sink\n";
            std.io.write(msg);
            std.os.exit(2);
            return;
        };
        var ao: audio.AudioOut = audio.AudioOut{
            .open_fn = wav.open,
            .write_fn = wav.write,
            .close_fn = wav.close,
            .drain_fn = wav.drain,
            .state = actx,
        };
        var meta: player.Meta = player.Meta{ .title = null, .artist = null, .album = null };

        var pl: player.Player = undefined;
        player.playerInit(&pl, &par, &decv, &ao, meta) catch {
            var msg: []const u8 = "z9play: cannot initialize the player\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };

        // Pump to completion; assert the reported position is monotonic.
        var monotonic: bool = true;
        var prev_ms: u64 = 0;
        while (pl.state == player.PlayerState.playing) {
            player.playerPump(&pl) catch {
                var msg: []const u8 = "z9play: playback failed\n";
                std.io.write(msg);
                std.os.exit(3);
                return;
            };
            var pos_ms: u64 = player.playerPositionMs(&pl);
            if (pos_ms < prev_ms) monotonic = false;
            prev_ms = pos_ms;
        }
        if (pl.state != player.PlayerState.ended) {
            var msg: []const u8 = "z9play: playback did not end cleanly\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        }
        pl.audio.drain_fn(pl.audio.state) catch {
            var msg: []const u8 = "z9play: audio drain failed\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        pl.audio.close_fn(pl.audio.state);

        var l_end: []const u8 = "wav: ended frames=";
        writeText(l_end);
        writeU64(pl.frames_written);
        var l_pos: []const u8 = " pos_ms=";
        writeText(l_pos);
        writeU64(prev_ms);
        var l_mono: []const u8 = " monotonic=";
        writeText(l_mono);
        if (monotonic) {
            var t: []const u8 = "1";
            writeText(t);
        } else {
            var f: []const u8 = "0";
            writeText(f);
        }
        writeNl();
        std.os.exit(0);
        return;
    }

    // Playback (<file.ogg> [--volume/--start/--loop/--quiet], M5): drive the M4
    // Player through the M5 console + formatter. The audio backend is selected
    // by the environment: when `Z9PLAY_WAV_OUT` is set the hermetic WAV sink is
    // used (tests); otherwise the Linux OSS `/dev/dsp` backend, which exits 4
    // when the device is absent. The Player core's `write` does not block for
    // the WAV sink, so the loop paces itself against `std.time.ticksMs()`
    // instead of relying on the device for real time.
    if (args.mode == cli.MODE_PLAY) {
        if (packets.len < 3) {
            var msg: []const u8 = "z9play: missing Vorbis setup header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        }

        // Decode chain backing stores (same as --wav) + the container comment
        // for the startup metadata line.
        var darena = std.arena.init(dec_arena_buf[0..]);
        var scratch = std.arena.init(wav_scratch_buf[0..]);
        var par = std.arena.init(wav_player_buf[0..]);

        var comment: vi.Comment = vi.parseComment(&arena, packets[1].bytes) catch {
            var msg: []const u8 = "z9play: bad Vorbis comment header\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var last: u64 = ogg.lastGranule(&arena, data) catch {
            var msg: []const u8 = "z9play: cannot locate the audio granule\n";
            std.io.write(msg);
            std.os.exit(3);
            return;
        };
        var dur_ms: u64 = ogg.durationMs(last, id.sample_rate);

        var k_title: []const u8 = "TITLE";
        var k_artist: []const u8 = "ARTIST";
        var k_album: []const u8 = "ALBUM";
        var title_val: []const u8 = tagValue(comment.tags, k_title);
        var artist_val: []const u8 = tagValue(comment.tags, k_artist);
        var album_val: []const u8 = tagValue(comment.tags, k_album);
        var title_opt: ?[]const u8 = null;
        if (title_val.len > 0) title_opt = title_val;
        var artist_opt: ?[]const u8 = null;
        if (artist_val.len > 0) artist_opt = artist_val;
        var album_opt: ?[]const u8 = null;
        if (album_val.len > 0) album_opt = album_val;
        var meta: player.Meta = player.Meta{ .title = title_opt, .artist = artist_opt, .album = album_opt };

        // Backend selection: Z9PLAY_WAV_OUT present -> hermetic WAV sink;
        // otherwise OSS /dev/dsp.
        var wav_env: []const u8 = "Z9PLAY_WAV_OUT";
        var use_wav: bool = false;
        var env_path: []const u8 = "";
        if (std.os.env(wav_env)) |e| {
            use_wav = true;
            env_path = e;
        }

        var real_ctx: *void = undefined;
        var real_ao: audio.AudioOut = undefined;
        if (use_wav) {
            wav.setOutputPath(env_path);
            real_ctx = wav.open(id.sample_rate, id.channels) catch {
                var msg: []const u8 = "z9play: cannot open the WAV sink\n";
                std.io.write(msg);
                std.os.exit(4);
                return;
            };
            real_ao = audio.AudioOut{ .open_fn = wav.open, .write_fn = wav.write, .close_fn = wav.close, .drain_fn = wav.drain, .state = real_ctx };
        } else {
            real_ctx = oss.open(id.sample_rate, id.channels) catch {
                var msg: []const u8 = "z9play: cannot open the audio device\n";
                std.io.write(msg);
                std.os.exit(4);
                return;
            };
            real_ao = audio.AudioOut{ .open_fn = oss.open, .write_fn = oss.write, .close_fn = oss.close, .drain_fn = oss.drain, .state = real_ctx };
        }
        g_real = real_ao;

        // Volume-scaling wrapper over the real backend, plus the discard sink
        // `--start` seeks with.
        var mix_ao: audio.AudioOut = audio.AudioOut{ .open_fn = mixOpen, .write_fn = mixWrite, .close_fn = mixClose, .drain_fn = mixDrain, .state = real_ctx };
        var discard_ao: audio.AudioOut = audio.AudioOut{ .open_fn = discardOpen, .write_fn = discardWrite, .close_fn = discardClose, .drain_fn = discardDrain, .state = @ptrCast(*void, &g_discard_ctx) };

        var vol: u8 = args.volume;
        g_mix_vol = vol;

        // Startup metadata line: `z9play: <title-or-path>  <mm:ss>  <ch>ch
        // <rate>Hz`.
        var name: []const u8 = args.path;
        if (title_val.len > 0) name = title_val;
        writeText("z9play: ");
        writeText(name);
        writeText("  ");
        var mbuf: [fmt.MMSS_MAX]u8 = undefined;
        std.io.write(fmt.mmss(mbuf[0..], dur_ms));
        writeText("  ");
        writeU64(@intCast(u64, id.channels));
        writeText("ch ");
        writeU64(@intCast(u64, id.sample_rate));
        writeText("Hz\n");

        // Assemble the Linux `Console` vtable from the backend's public free
        // functions (mirrors the `audio.AudioOut` assembly above). Raw keyboard
        // input is a no-op when stdin is not a tty; keys are then not polled, so
        // a redirected run still completes.
        var st: con.ConsoleLinState = undefined;
        var cs: contract.Console = contract.Console{
            .clear_fn = con.clear,
            .setCursor_fn = con.setCursor,
            .writeStr_fn = con.writeStr,
            .readKey_fn = con.readKey,
            .enterRaw_fn = con.enterRaw,
            .leaveRaw_fn = con.leaveRaw,
            .width_fn = con.width,
            .height_fn = con.height,
            .cursorShow_fn = con.cursorShow,
            .state = @ptrCast(*void, &st),
        };
        cs.enterRaw_fn(cs.state);
        var interactive: bool = st.entered;

        var pl: player.Player = undefined;
        var quit: bool = false;
        var ended_by_start: bool = false;
        while (true) {
            // (Re)build the decode chain for this pass (needed on --loop).
            std.arena.reset(&darena);
            std.arena.reset(&scratch);
            std.arena.reset(&par);

            var setup: vs.Setup = vs.parseSetup(&darena, packets[2].bytes, @intCast(u32, id.channels)) catch {
                playFail(&cs, "z9play: bad Vorbis setup header\n", 3);
                return;
            };
            var state: dec.DecoderState = dec.initDecoderState(&darena, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
                playFail(&cs, "z9play: cannot initialize the decoder\n", 3);
                return;
            };
            var vc: *player.VorbisCtx = player.vorbisCreate(&darena, &scratch, packets, setup, state, 3, id.sample_rate, id.channels, last) catch {
                playFail(&cs, "z9play: cannot initialize the player decoder\n", 3);
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

            g_mix_vol = vol;
            var first_ao: *const audio.AudioOut = &mix_ao;
            if (args.start_ms > 0) first_ao = &discard_ao;
            player.playerInit(&pl, &par, &decv, first_ao, meta) catch {
                playFail(&cs, "z9play: cannot initialize the player\n", 5);
                return;
            };
            pl.volume = vol;

            // `--start`: decode into the discard sink until the reported
            // position reaches the offset, then switch to the real sink. The
            // Player's ring/position state carries over, so the status line
            // shows the absolute position.
            if (args.start_ms > 0) {
                while (pl.state == player.PlayerState.playing and pl.position_ms < args.start_ms) {
                    player.playerPump(&pl) catch {
                        playFail(&cs, "z9play: cannot seek into the file\n", 3);
                        return;
                    };
                }
                pl.audio = &mix_ao;
            }

            if (pl.state == player.PlayerState.playing) {
                var base_ticks: u32 = std.time.ticksMs();
                var last_status: u32 = base_ticks;
                var paused_accum: u64 = 0;
                var pause_began: u32 = 0;
                if (!args.quiet) {
                    writeStatus(player.playerPositionMs(&pl), pl.duration_ms, vol);
                }
                while (true) {
                    if (interactive) {
                        while (true) {
                            var k: contract.Key = cs.readKey_fn(cs.state);
                            var got: bool = true;
                            switch (k) {
                                .char => |c| {
                                    if (c == 'q') {
                                        quit = true;
                                    } else if (c == ' ') {
                                        if (pl.state == player.PlayerState.playing) {
                                            pl.state = player.PlayerState.paused;
                                            pause_began = std.time.ticksMs();
                                        } else if (pl.state == player.PlayerState.paused) {
                                            pl.state = player.PlayerState.playing;
                                            paused_accum += @intCast(u64, std.time.ticksMs() - pause_began);
                                        }
                                    } else if (c == '+' or c == '=') {
                                        if (vol <= 95) {
                                            vol += 5;
                                        } else {
                                            vol = 100;
                                        }
                                        g_mix_vol = vol;
                                        pl.volume = vol;
                                    } else if (c == '-') {
                                        if (vol >= 5) {
                                            vol -= 5;
                                        } else {
                                            vol = 0;
                                        }
                                        g_mix_vol = vol;
                                        pl.volume = vol;
                                    }
                                },
                                .sigint => {
                                    quit = true;
                                },
                                .none => {
                                    got = false;
                                },
                                else => {},
                            }
                            if (quit) break;
                            if (!got) break;
                        }
                    }
                    if (quit) break;
                    if (pl.state == player.PlayerState.ended) break;

                    if (pl.state == player.PlayerState.playing) {
                        var now: u32 = std.time.ticksMs();
                        var elapsed: u64 = @intCast(u64, now - base_ticks) - paused_accum;
                        // Pace on *played* time, not the absolute position: after
                        // a `--start` seek the position already equals start_ms
                        // while the wall clock has just restarted, so comparing
                        // the absolute position would idle for start_ms. The
                        // content is unchanged (status still shows the absolute
                        // position).
                        var played: u64 = 0;
                        if (pl.position_ms > args.start_ms) played = pl.position_ms - args.start_ms;
                        if (played <= elapsed + 200) {
                            player.playerPump(&pl) catch |e| {
                                if (e == error.DecodeFailed) {
                                    playFail(&cs, "z9play: playback decode error\n", 3);
                                } else if (e == error.AudioFailed) {
                                    playFail(&cs, "z9play: audio output failed\n", 4);
                                } else {
                                    playFail(&cs, "z9play: internal playback error\n", 5);
                                }
                                return;
                            };
                        } else {
                            std.time.sleepMs(10);
                        }
                    } else {
                        std.time.sleepMs(10);
                    }

                    if (!args.quiet) {
                        var now2: u32 = std.time.ticksMs();
                        if (now2 - last_status >= 1000) {
                            writeStatus(player.playerPositionMs(&pl), pl.duration_ms, vol);
                            last_status = now2;
                        }
                    }
                }
            } else if (args.start_ms > 0) {
                ended_by_start = true;
            }

            if (quit) break;
            if (ended_by_start) break;
            if (!args.loop) break;
        }

        // Drain + close the real sink (via the wrapper), restore the terminal,
        // then print the final position.
        pl.audio.drain_fn(pl.audio.state) catch {
            playFail(&cs, "z9play: audio drain failed\n", 4);
            return;
        };
        pl.audio.close_fn(pl.audio.state);
        cs.leaveRaw_fn(cs.state);

        var fpos: u64 = player.playerPositionMs(&pl);
        var nl: []const u8 = "\n";
        std.io.write(nl);
        writeText("Stopped at ");
        var sbuf: [fmt.MMSS_MAX]u8 = undefined;
        std.io.write(fmt.mmss(sbuf[0..], fpos));
        writeText(".\n");
        std.os.exit(0);
        return;
    }

    var comment: vi.Comment = vi.parseComment(&arena, packets[1].bytes) catch {
        var msg: []const u8 = "z9play: bad Vorbis comment header\n";
        std.io.write(msg);
        std.os.exit(3);
        return;
    };
    var last: u64 = ogg.lastGranule(&arena, data) catch {
        var msg: []const u8 = "z9play: cannot locate the audio granule\n";
        std.io.write(msg);
        std.os.exit(3);
        return;
    };
    var dur_ms: u64 = ogg.durationMs(last, id.sample_rate);

    var l_ch: []const u8 = "channels=";
    writeText(l_ch);
    writeU64(@intCast(u64, id.channels));
    writeNl();

    var l_sr: []const u8 = "sample_rate=";
    writeText(l_sr);
    writeU64(@intCast(u64, id.sample_rate));
    writeNl();

    var l_ds: []const u8 = "duration_s=";
    writeText(l_ds);
    writeDurationMs(dur_ms);
    writeNl();

    var k_title: []const u8 = "TITLE";
    var k_artist: []const u8 = "ARTIST";
    var k_album: []const u8 = "ALBUM";
    writeTagLine(comment.tags, k_title);
    writeTagLine(comment.tags, k_artist);
    writeTagLine(comment.tags, k_album);

    std.os.exit(0);
}
