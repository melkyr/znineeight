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

// Write the 27-byte OGG page header for a page with `nseg` segments and
// `header_type` into `buf` at `off`; returns the segment-table offset. Granule,
// serial, sequence and CRC are left zero — reassemble does not consult them.
fn wrPageHdr(buf: []u8, off: usize, header_type: u8, nseg: u8) usize {
    buf[off] = 'O';
    buf[off + 1] = 'g';
    buf[off + 2] = 'g';
    buf[off + 3] = 'S';
    buf[off + 4] = 0;
    buf[off + 5] = header_type;
    var z: usize = 6;
    while (z < 26) : (z += 1) {
        buf[off + z] = 0;
    }
    buf[off + 26] = nseg;
    return off + 27;
}

// (e) A packet whose segments span two pages (page A ends in a 255 lace with
// the continuation flag; page B closes it) must reassemble to the exact 300
// concatenated bytes, with a following short packet intact. This exercises the
// cross-page-carry path the fixtures do not hit.
fn testContinuationReassembly() void {
    var buf: [1024]u8 = undefined;
    var off: usize = 0;
    // Page A (BOS): a single 255-byte segment -> packet continues.
    var st: usize = wrPageHdr(buf[0..], off, 0x02, 1);
    buf[st] = 255;
    var body: usize = st + 1;
    var i: usize = 0;
    while (i < 255) : (i += 1) {
        buf[body + i] = 0xAA;
    }
    off = body + 255;
    // Page B (continued): laces [45, 3] -> closes the 255+45=300-byte packet,
    // then a second 3-byte packet.
    st = wrPageHdr(buf[0..], off, 0x01, 2);
    buf[st] = 45;
    buf[st + 1] = 3;
    body = st + 2;
    i = 0;
    while (i < 45) : (i += 1) {
        buf[body + i] = 0xBB;
    }
    buf[body + 45] = 'x';
    buf[body + 46] = 'y';
    buf[body + 47] = 'z';
    off = body + 48;

    var arena = std.arena.init(arena_buf[0..]);
    var data: []const u8 = buf[0..off];
    var pk: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("continuation reassemble errored");
        return;
    };
    if (pk.len != 2) fail("continuation: packet count != 2");
    if (pk[0].bytes.len != 300) fail("continuation: packet 0 length != 300");
    if (pk[0].bytes[0] != 0xAA) fail("continuation: byte 0 != 0xAA");
    if (pk[0].bytes[254] != 0xAA) fail("continuation: byte 254 != 0xAA");
    if (pk[0].bytes[255] != 0xBB) fail("continuation: byte 255 != 0xBB");
    if (pk[0].bytes[299] != 0xBB) fail("continuation: byte 299 != 0xBB");
    if (pk[1].bytes.len != 3) fail("continuation: packet 1 length != 3");
    if (pk[1].bytes[0] != 'x') fail("continuation: packet 1 byte 0 != 'x'");
}

// (f) A stream whose final packet is never terminated (ends on a 255 lace at
// EOF) is malformed: reassemble must return a clean OggError (Truncated), never
// write past the terminated-packet allocation. The single page below closes one
// 3-byte packet and then leaves a 255-byte tail open.
fn testUnterminatedReassembly() void {
    var buf: [512]u8 = undefined;
    var st: usize = wrPageHdr(buf[0..], 0, 0x04, 2);
    buf[st] = 3;
    buf[st + 1] = 255;
    var body: usize = st + 2;
    buf[body] = 'a';
    buf[body + 1] = 'b';
    buf[body + 2] = 'c';
    var i: usize = 0;
    while (i < 255) : (i += 1) {
        buf[body + 3 + i] = 0xDD;
    }
    var end: usize = body + 3 + 255;

    var arena = std.arena.init(arena_buf[0..]);
    var data: []const u8 = buf[0..end];
    var saw_err: bool = false;
    ogg.reassemble(&arena, data) catch |err| {
        if (err == error.Truncated) saw_err = true;
    };
    if (!saw_err) fail("unterminated trailing packet did not return Truncated");
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

    // (e) cross-page continuation packet reassembles exactly.
    testContinuationReassembly();
    // (f) an unterminated trailing packet is a clean error, never an OOB write.
    testUnterminatedReassembly();

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
