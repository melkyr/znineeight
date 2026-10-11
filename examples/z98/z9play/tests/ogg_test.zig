// ogg_test.zig — deterministic unit harness for the z9play OGG container.
//
// Asserts, against the committed fixture
// examples/z98/z9play/testdata/sine_stereo_44100.ogg:
//   (a) the page walk yields exactly 4 pages, first granule 0, last granule
//       88200, and crcOk() is true for every page;
//   (b) reassembly yields the three Vorbis headers as the first three packets
//       (packet 0 begins 0x01 "vorbis", packet 1 begins 0x03 "vorbis",
//       packet 2 begins 0x05 "vorbis").
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/ogg_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const vi = @import("../vorbis_info.zig");

// Backing store for the read/reassembly arena; module-global so it does not
// sit on the 32-bit stack. 4 MiB is far above this ~11 KiB fixture's needs.
var arena_buf: [4 * 1024 * 1024]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "ogg_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

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

fn startsWith(pkt: []const u8, prefix: []const u8) bool {
    if (pkt.len < prefix.len) return false;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        if (pkt[i] != prefix[i]) return false;
    }
    return true;
}

// Walk every page of `path` and verify its stored CRC. Uses a fresh arena over
// the module-global backing buffer (the caller has finished with the read
// fixture by the time this runs).
fn crcAllPages(path: []const u8) bool {
    var arena = std.arena.init(arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, path) catch return false;
    var off: usize = 0;
    while (off < data.len) {
        var page = ogg.pageAt(data, off) catch return false;
        if (!ogg.crcOk(data, page)) return false;
        off = ogg.nextPage(data, page);
    }
    return true;
}

// Assert the duration derived from `path`'s last audio granule is within
// `tol_ms` of `want_ms`. The sample rate comes from the Vorbis identification
// header of the reassembled first packet (container + id integration).
fn checkDuration(path: []const u8, want_ms: u64, tol_ms: u64) void {
    var arena = std.arena.init(arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture for duration");
        return;
    };
    var g: u64 = ogg.lastGranule(&arena, data) catch {
        fail("lastGranule failed");
        return;
    };
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble for duration failed");
        return;
    };
    if (packets.len < 1) {
        fail("no reassembled packets for duration");
        return;
    }
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("parseId for duration failed");
        return;
    };
    var d: u64 = ogg.durationMs(g, id.sample_rate);
    var diff: u64 = 0;
    if (d >= want_ms) {
        diff = d - want_ms;
    } else {
        diff = want_ms - d;
    }
    if (diff > tol_ms) {
        var msg: []const u8 = "duration mismatch for ";
        std.io.write(msg);
        std.io.write(path);
        var nl: []const u8 = "\n";
        std.io.write(nl);
        fail("duration out of tolerance");
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    var arena = std.arena.init(arena_buf[0..]);
    var path: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture sine_stereo_44100.ogg");
        return;
    };

    // (a) page walk: count, first/last granule, CRC on every page.
    var off: usize = 0;
    var pages: u64 = 0;
    var first_granule: u64 = 0;
    var last_granule: u64 = 0;
    while (off < data.len) {
        var page = ogg.pageAt(data, off) catch {
            fail("pageAt failed on fixture");
            return;
        };
        if (pages == 0) first_granule = page.granule;
        last_granule = page.granule;
        if (!ogg.crcOk(data, page)) fail("crcOk false on a fixture page");
        pages += 1;
        off = ogg.nextPage(data, page);
    }
    if (pages != 4) fail("page count != 4");
    if (first_granule != 0) fail("first granule != 0");
    if (last_granule != 88200) fail("last granule != 88200");

    // (b) reassembly: the three Vorbis headers are the first three packets.
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble failed");
        return;
    };
    if (packets.len < 3) fail("fewer than 3 reassembled packets");
    var h0: []const u8 = "\x01vorbis";
    var h1: []const u8 = "\x03vorbis";
    var h2: []const u8 = "\x05vorbis";
    if (!startsWith(packets[0].bytes, h0)) fail("packet 0 does not begin 0x01vorbis");
    if (!startsWith(packets[1].bytes, h1)) fail("packet 1 does not begin 0x03vorbis");
    if (!startsWith(packets[2].bytes, h2)) fail("packet 2 does not begin 0x05vorbis");

    // (c) CRC sanity across every page of every committed fixture.
    var f_mono: []const u8 = "examples/z98/z9play/testdata/sine_mono_44100.ogg";
    var f_48000: []const u8 = "examples/z98/z9play/testdata/sine_stereo_48000.ogg";
    var f_tagged: []const u8 = "examples/z98/z9play/testdata/tagged_unicode.ogg";
    var f_short: []const u8 = "examples/z98/z9play/testdata/short.ogg";
    if (!crcAllPages(f_mono)) fail("crcOk failed on sine_mono_44100.ogg");
    if (!crcAllPages(f_48000)) fail("crcOk failed on sine_stereo_48000.ogg");
    if (!crcAllPages(f_tagged)) fail("crcOk failed on tagged_unicode.ogg");
    if (!crcAllPages(f_short)) fail("crcOk failed on short.ogg");

    // (d) duration: last-page granule of the audio logical stream / sample rate.
    // sine_stereo_44100.ogg is asserted exactly (88200 samples @ 44100 Hz =
    // 2000 ms); the others allow +/-1 ms for granule rounding.
    var d_stereo: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
    var d_mono: []const u8 = "examples/z98/z9play/testdata/sine_mono_44100.ogg";
    var d_48000: []const u8 = "examples/z98/z9play/testdata/sine_stereo_48000.ogg";
    var d_tagged: []const u8 = "examples/z98/z9play/testdata/tagged_unicode.ogg";
    var d_short: []const u8 = "examples/z98/z9play/testdata/short.ogg";
    checkDuration(d_stereo, 2000, 0);
    checkDuration(d_mono, 1000, 1);
    checkDuration(d_48000, 1000, 1);
    checkDuration(d_tagged, 1000, 1);
    checkDuration(d_short, 300, 1);
    if (ogg.durationMs(500, 0) != 0) fail("durationMs did not guard a zero sample rate");

    var ok: []const u8 = "ogg_test: PASS pages=";
    std.io.write(ok);
    writeU64(pages);
    var lg: []const u8 = " last_granule=";
    std.io.write(lg);
    writeU64(last_granule);
    var pk: []const u8 = " packets=";
    std.io.write(pk);
    writeU64(@intCast(u64, packets.len));
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(0);
}
