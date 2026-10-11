// main.zig — z9play entry point (z9play M0/M1: `--info` metadata query and
// `--dump-setup` setup summary).
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
// Exit codes (design spec §5): 0 ok / 1 args (cli.zig) / 2 open / 3 decoder
// (malformed container, header, setup, or a non-Vorbis stream). No audio, no
// playback — that is M4/M5.
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

// Backing store for the read/reassembly/comment arena; module-global so it does
// not sit on the 32-bit stack (~11 KiB fixtures need a small fraction of this).
var arena_buf: [4 * 1024 * 1024]u8 = undefined;

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
