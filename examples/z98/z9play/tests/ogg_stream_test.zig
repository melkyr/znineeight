// ogg_stream_test.zig — unit gate for z9play M9 Task 2.
//
// For every committed OGG fixture, every packet returned by
// ogg_stream.oggStreamNextPacket is compared byte-for-byte with the
// ogg.reassemble oracle, and oggStreamLastGranule is compared with
// ogg.lastGranule. Synthetic files exercise CRC failure, legal cross-page
// continuation, both illegal continuation transitions, PacketTooLarge, serial
// mismatch, EOF in the middle of a page, and the empty-file tail case.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/m7_t5_seed2/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/ogg_stream_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const ogg_stream = @import("../ogg_stream.zig");

var arena_buf: [4 * 1024 * 1024]u8 = undefined;
var synth_buf: [200000]u8 = undefined;
var page_buf: [ogg_stream.OGG_PAGE_MAX]u8 = undefined;
var body_full: [65025]u8 = undefined;
var laces_full: [255]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "ogg_stream_test: FAIL: ";
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

fn sameBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn wrU32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @intCast(u8, v & 0xff);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xff);
    buf[off + 2] = @intCast(u8, (v >> 16) & 0xff);
    buf[off + 3] = @intCast(u8, (v >> 24) & 0xff);
}

fn wrU64(buf: []u8, off: usize, v: u64) void {
    wrU32(buf, off, @intCast(u32, v & 0xffffffff));
    wrU32(buf, off + 4, @intCast(u32, v >> 32));
}

fn oggCrcRaw(data: []const u8, start: usize, end: usize) u32 {
    var crc: u32 = 0;
    var i: usize = start;
    while (i < end) : (i += 1) {
        var b: u8 = data[i];
        if (i >= start + 22 and i < start + 26) b = 0;
        crc = crc ^ (@intCast(u32, b) << 24);
        var j: u32 = 0;
        while (j < 8) : (j += 1) {
            if ((crc & 0x80000000) != 0) {
                crc = (crc *% 2) ^ 0x04c11db7;
            } else {
                crc = crc *% 2;
            }
        }
    }
    return crc;
}

fn putCrc(buf: []u8, start: usize, end: usize) void {
    var crc: u32 = oggCrcRaw(buf[0..], start, end);
    wrU32(buf, start + 22, crc);
}

fn buildPage(
    buf: []u8,
    off: usize,
    header_type: u8,
    serial: u32,
    seq: u32,
    granule: u64,
    laces: []const u8,
    body: []const u8,
) usize {
    var nseg: usize = laces.len;
    buf[off] = 'O';
    buf[off + 1] = 'g';
    buf[off + 2] = 'g';
    buf[off + 3] = 'S';
    buf[off + 4] = 0;
    buf[off + 5] = header_type;
    wrU64(buf, off + 6, granule);
    wrU32(buf, off + 14, serial);
    wrU32(buf, off + 18, seq);
    wrU32(buf, off + 22, 0);
    buf[off + 26] = @intCast(u8, nseg);
    var i: usize = 0;
    while (i < nseg) : (i += 1) {
        buf[off + 27 + i] = laces[i];
    }
    var body_off: usize = off + 27 + nseg;
    i = 0;
    while (i < body.len) : (i += 1) {
        buf[body_off + i] = body[i];
    }
    var total: usize = 27 + nseg + body.len;
    putCrc(buf, off, off + total);
    return off + total;
}

fn writeBytes(path: []const u8, data: []const u8) void {
    var io = std.arena.init(arena_buf[0..]);
    std.arena.reset(&io);
    var f = filemod.open(&io, path, .Write) catch {
        fail("cannot create synthetic file");
        return;
    };
    var w: usize = 0;
    while (w < data.len) {
        var got: usize = filemod.write(&f, data[w..]) catch {
            fail("cannot write synthetic file");
            return;
        };
        if (got == 0) fail("synthetic write returned 0");
        w += got;
    }
    filemod.close(&f);
}

fn removeFile(path: []const u8) void {
    filemod.remove(path) catch {};
}

fn checkFixture(path: []const u8) void {
    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read committed fixture");
        return;
    };
    var oracle: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("oracle reassemble failed");
        return;
    };
    var want_granule: u64 = ogg.lastGranule(&arena, data) catch {
        fail("oracle lastGranule failed");
        return;
    };
    var first = ogg.pageAt(data, 0) catch {
        fail("oracle pageAt failed");
        return;
    };
    var serial: u32 = first.serial;

    var s = ogg_stream.oggStreamOpen(&arena, path) catch {
        fail("oggStreamOpen failed");
        return;
    };
    var count: usize = 0;
    while (true) {
        var maybe: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch {
            fail("streamed nextPacket failed");
            return;
        };
        if (maybe) |pkt| {
            if (count >= oracle.len) fail("stream returned too many packets");
            if (!sameBytes(pkt, oracle[count].bytes)) fail("streamed packet mismatch");
            count += 1;
        } else {
            break;
        }
    }
    if (count != oracle.len) fail("streamed packet count mismatch");
    ogg_stream.oggStreamClose(&s);

    var got_granule: u64 = ogg_stream.oggStreamLastGranule(&arena, path, serial) catch {
        fail("oggStreamLastGranule failed");
        return;
    };
    if (got_granule != want_granule) fail("last granule mismatch");
}

fn nextExpectError(s: *ogg_stream.OggStream, want: ogg_stream.OggStreamError) bool {
    var maybe: ?[]const u8 = ogg_stream.oggStreamNextPacket(s) catch |err| {
        return err == want;
    };
    _ = maybe;
    return false;
}

fn expectNextError(path: []const u8, want: ogg_stream.OggStreamError) void {
    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var s = ogg_stream.oggStreamOpen(&arena, path) catch {
        fail("synthetic open failed");
        return;
    };
    var maybe: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch |err| {
        ogg_stream.oggStreamClose(&s);
        if (err != want) fail("wrong nextPacket error");
        return;
    };
    _ = maybe;
    ogg_stream.oggStreamClose(&s);
    fail("expected nextPacket error");
}

fn expectTailError(path: []const u8, serial: u32, want: ogg_stream.OggStreamError) void {
    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var g: u64 = ogg_stream.oggStreamLastGranule(&arena, path, serial) catch |err| {
        if (err != want) fail("wrong lastGranule error");
        return;
    };
    _ = g;
    fail("expected lastGranule error");
}

fn testCrcFailure() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_crc.ogg";
    var laces: [1]u8 = undefined;
    laces[0] = 3;
    var end: usize = buildPage(synth_buf[0..], 0, 0x02, 7, 0, 0, laces[0..], "abc");
    synth_buf[28] = 'X';
    writeBytes(path, synth_buf[0..end]);
    expectNextError(path, error.Crc);
    removeFile(path);
}

fn testContinuation() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_cont.ogg";
    var laces_a: [1]u8 = undefined;
    laces_a[0] = 255;
    var body_a: [255]u8 = undefined;
    var i: usize = 0;
    while (i < 255) : (i += 1) body_a[i] = 0xAA;
    var end: usize = buildPage(synth_buf[0..], 0, 0x02, 42, 0, 0, laces_a[0..], body_a[0..]);

    var laces_b: [2]u8 = undefined;
    laces_b[0] = 45;
    laces_b[1] = 3;
    var body_b: [48]u8 = undefined;
    i = 0;
    while (i < 45) : (i += 1) body_b[i] = 0xBB;
    body_b[45] = 'x';
    body_b[46] = 'y';
    body_b[47] = 'z';
    end = buildPage(synth_buf[0..], end, 0x01, 42, 1, 12345, laces_b[0..], body_b[0..]);
    writeBytes(path, synth_buf[0..end]);

    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var s = ogg_stream.oggStreamOpen(&arena, path) catch {
        fail("continuation open failed");
        return;
    };
    var p0: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch {
        fail("continuation packet 0 errored");
        return;
    };
    if (p0) |pkt| {
        if (pkt.len != 300) fail("continuation packet 0 length != 300");
        if (pkt[0] != 0xAA) fail("continuation packet 0 byte 0 wrong");
        if (pkt[254] != 0xAA) fail("continuation packet 0 byte 254 wrong");
        if (pkt[255] != 0xBB) fail("continuation packet 0 byte 255 wrong");
        if (pkt[299] != 0xBB) fail("continuation packet 0 byte 299 wrong");
    } else {
        fail("continuation packet 0 missing");
    }
    var p1: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch {
        fail("continuation packet 1 errored");
        return;
    };
    if (p1) |pkt| {
        if (pkt.len != 3) fail("continuation packet 1 length != 3");
        if (pkt[0] != 'x' or pkt[1] != 'y' or pkt[2] != 'z') fail("continuation packet 1 bytes wrong");
    } else {
        fail("continuation packet 1 missing");
    }
    var p2: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch {
        fail("continuation EOF errored");
        return;
    };
    if (p2) |pkt| {
        _ = pkt;
        fail("continuation returned an extra packet");
    }
    ogg_stream.oggStreamClose(&s);

    var g: u64 = ogg_stream.oggStreamLastGranule(&arena, path, 42) catch {
        fail("continuation lastGranule errored");
        return;
    };
    if (g != 12345) fail("continuation lastGranule != 12345");
    removeFile(path);
}

fn testContinuationWithoutPending() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_cont_no_pending.ogg";
    var laces: [1]u8 = undefined;
    laces[0] = 3;
    var end: usize = buildPage(synth_buf[0..], 0, 0x01, 9, 0, 0, laces[0..], "abc");
    writeBytes(path, synth_buf[0..end]);
    expectNextError(path, error.Truncated);
    removeFile(path);
}

fn testMissingContinuation() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_missing_cont.ogg";
    var laces_a: [1]u8 = undefined;
    laces_a[0] = 255;
    var body_a: [255]u8 = undefined;
    var i: usize = 0;
    while (i < 255) : (i += 1) body_a[i] = 0xCC;
    var end: usize = buildPage(synth_buf[0..], 0, 0x02, 9, 0, 0, laces_a[0..], body_a[0..]);
    var laces_b: [1]u8 = undefined;
    laces_b[0] = 3;
    end = buildPage(synth_buf[0..], end, 0x00, 9, 1, 0, laces_b[0..], "abc");
    writeBytes(path, synth_buf[0..end]);
    expectNextError(path, error.Truncated);
    removeFile(path);
}

fn testSerialMismatch() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_serial.ogg";
    var laces: [1]u8 = undefined;
    laces[0] = 3;
    var end: usize = buildPage(synth_buf[0..], 0, 0x02, 100, 0, 0, laces[0..], "abc");
    end = buildPage(synth_buf[0..], end, 0x00, 200, 1, 0, laces[0..], "def");
    writeBytes(path, synth_buf[0..end]);

    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var s = ogg_stream.oggStreamOpen(&arena, path) catch {
        fail("serial open failed");
        return;
    };
    var p0: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch {
        fail("serial first packet errored");
        return;
    };
    if (p0) |pkt| {
        if (!sameBytes(pkt, "abc")) fail("serial first packet wrong");
    } else {
        fail("serial first packet missing");
    }
    var saw: bool = nextExpectError(&s, error.SerialMismatch);
    ogg_stream.oggStreamClose(&s);
    if (!saw) fail("serial mismatch was not reported");
    removeFile(path);
}

fn testPacketTooLarge() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_large.ogg";
    var i: usize = 0;
    while (i < 255) : (i += 1) laces_full[i] = 255;
    i = 0;
    while (i < 65025) : (i += 1) body_full[i] = @intCast(u8, i & 255);

    var io = std.arena.init(arena_buf[0..]);
    std.arena.reset(&io);
    var f = filemod.open(&io, path, .Write) catch {
        fail("cannot create oversize fixture");
        return;
    };
    var page_no: u32 = 0;
    while (page_no < 17) : (page_no += 1) {
        var header_type: u8 = 0x00;
        if (page_no == 0) header_type = 0x02;
        if (page_no != 0) header_type = 0x01;
        var end: usize = buildPage(
            page_buf[0..],
            0,
            header_type,
            77,
            page_no,
            0,
            laces_full[0..],
            body_full[0..],
        );
        var w: usize = 0;
        while (w < end) {
            var got: usize = filemod.write(&f, page_buf[w..end]) catch {
                fail("cannot write oversize fixture");
                return;
            };
            if (got == 0) fail("oversize write returned 0");
            w += got;
        }
    }
    filemod.close(&f);

    expectNextError(path, error.PacketTooLarge);
    removeFile(path);
}

fn testEofMidPage() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_eof.ogg";
    var laces: [1]u8 = undefined;
    laces[0] = 3;
    var end: usize = buildPage(synth_buf[0..], 0, 0x02, 5, 0, 0, laces[0..], "abc");
    writeBytes(path, synth_buf[0 .. end - 10]);
    expectNextError(path, error.Truncated);
    expectTailError(path, 5, error.Truncated);
    removeFile(path);
}

fn testEmptyFile() void {
    var path: []const u8 = "/tmp/z9play_ogg_stream_empty.ogg";
    writeBytes(path, "");
    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var s = ogg_stream.oggStreamOpen(&arena, path) catch {
        fail("empty open failed");
        return;
    };
    var maybe: ?[]const u8 = ogg_stream.oggStreamNextPacket(&s) catch {
        fail("empty nextPacket errored");
        return;
    };
    if (maybe) |pkt| {
        _ = pkt;
        fail("empty file returned a packet");
    }
    ogg_stream.oggStreamClose(&s);
    var g: u64 = ogg_stream.oggStreamLastGranule(&arena, path, 0) catch {
        fail("empty lastGranule errored");
        return;
    };
    if (g != 0) fail("empty lastGranule != 0");
    removeFile(path);
}

pub fn main() void {
    checkFixture("examples/z98/z9play/testdata/sine_stereo_44100.ogg");
    checkFixture("examples/z98/z9play/testdata/sine_mono_44100.ogg");
    checkFixture("examples/z98/z9play/testdata/sine_stereo_48000.ogg");
    checkFixture("examples/z98/z9play/testdata/tagged_unicode.ogg");
    checkFixture("examples/z98/z9play/testdata/short.ogg");

    testCrcFailure();
    testContinuation();
    testContinuationWithoutPending();
    testMissingContinuation();
    testSerialMismatch();
    testPacketTooLarge();
    testEofMidPage();
    testEmptyFile();

    var ok: []const u8 = "ogg_stream_test: PASS fixtures=5 synthetic=8\n";
    std.io.write(ok);
    std.os.exit(0);
}
