// flac_test.zig — deterministic unit/gate harness for z9play flac.zig (M8 T2).
//
// Decodes the generated FLAC fixture through flac.open + flac.decode into one
// interleaved s16 stream and compares it against the raw PCM golden used to
// generate it. FLAC is lossless, so the match is exact (max |delta| = 0); the
// harness still reports the tolerance-style numbers for the T2 gate.
//
// Determinism: three independent full decodes (arena reset between runs)
// produce byte-identical decoded PCM (SHA-1).
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/flac_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog <fixture.flac> <golden.pcm>

const std = @import("std");
const crypto = @import("std_crypto");
const filemod = @import("std_file");
const flac = @import("../flac.zig");
const stream = @import("../stream.zig");

const RDR_PATH: []const u8 = "/tmp/z9play_flac_reader.bin";

var arena_buf: [16 * 1024 * 1024]u8;
var out_buf: [400000]i16;
var unit_file: [128]u8;
var unit_out: [512]i16;

fn fail(msg: []const u8) void {
    var p: []const u8 = "flac_test: FAIL: ";
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
    var tmp: [20]u8 = [20]u8{0};
    for (tmp) |*item| {
        item.* = 0;
    }
    var n: usize = 0;
    var v: u64 = uint;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var buf: [20]u8 = [20]u8{0};
    for (buf) |*item| {
        item.* = 0;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = tmp[n - 1 - i];
    std.io.write(buf[0..n]);
}

fn sha1Of(data: []const u8, out: *[20]u8) void {
    var s: crypto.Sha1 = crypto.sha1Init();
    crypto.sha1Update(&s, data);
    crypto.sha1Final(&s, out);
}

fn hexByte(b: u8) void {
    var d: []const u8 = "0123456789abcdef";
    var s: [1]u8 = [1]u8{0};
    for (s) |*item| {
        item.* = 0;
    }
    s[0] = d[@intCast(usize, (b >> 4) & 0x0f)];
    std.io.write(s[0..1]);
    s[0] = d[@intCast(usize, b & 0x0f)];
    std.io.write(s[0..1]);
}

const RunResult = struct {
    frames: usize,
    golden_frames: usize,
    max_delta: i32,
    hash: [20]u8,
};

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

// One complete decode pass from a reset arena.
fn decodeOnce(arena: *std.arena.Arena, fixture: []const u8, golden: []const u8) RunResult {
    var data: []u8 = filemod.readAll(arena, fixture) catch {
        fail("cannot read fixture");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
    };
    var gold: []u8 = filemod.readAll(arena, golden) catch {
        fail("cannot read golden PCM");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
    };

    var fd: flac.FlacDecoder = flac.open(arena, data) catch {
        fail("flac.open failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
    };
    var ch: usize = @intCast(usize, fd.channels);

    var total: usize = 0;
    while (true) {
        var room: usize = out_buf.len - total * ch;
        if (room == 0) {
            fail("decoded output exceeds harness buffer");
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
        }
        var f: usize = flac.decode(&fd, arena, out_buf[total * ch ..]) catch |e| {
            if (e == error.OutOfMemory) {
                fail("flac.decode: arena OutOfMemory");
            } else {
                fail("flac.decode returned an error");
            }
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
        };
        if (f == 0) break;
        total += f;
    }

    var golden_frames: usize = gold.len / (2 * ch);
    var n: usize = total * ch;
    var gv: []i16 = @ptrCast([*]i16, gold.ptr)[0 .. golden_frames * ch];
    var md: i32 = 0;
    var i: usize = 0;
    while (i < n and i < gv.len) : (i += 1) {
        var d: i32 = @intCast(i32, out_buf[i]) - @intCast(i32, gv[i]);
        if (d < 0) d = -d;
        if (d > md) md = d;
    }
    if (total != golden_frames) {
        var p: []const u8 = "flac_test: FAIL: frame count ";
        std.io.write(p);
        writeU(@intCast(u64, total));
        var q: []const u8 = " != golden ";
        std.io.write(q);
        writeU(@intCast(u64, golden_frames));
        var nl: []const u8 = "\n";
        std.io.write(nl);
        std.os.exit(1);
    }

    var bytes: []const u8 = @ptrCast([*]const u8, out_buf[0..n].ptr)[0 .. n * 2];
    var hash: [20]u8 = [20]u8{0};
    for (hash) |*item| {
        item.* = 0;
    }
    sha1Of(bytes, &hash);
    return RunResult{ .frames = total, .golden_frames = golden_frames, .max_delta = md, .hash = hash };
}

// One complete decode pass through the file-backed streaming path. The
// returned shape matches decodeOnce so the caller can compare frame counts,
// PCM deltas, and hashes against the byte-slice oracle.
fn decodeStreamOnce(arena: *std.arena.Arena, fixture: []const u8, golden: []const u8) RunResult {
    var gold: []u8 = filemod.readAll(arena, golden) catch {
        fail("cannot read golden PCM");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
    };

    var fd: flac.StreamFlacDecoder = flac.openStream(arena, fixture) catch {
        fail("flac.openStream failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
    };
    var ch: usize = @intCast(usize, fd.channels);

    var total: usize = 0;
    while (true) {
        var room: usize = out_buf.len - total * ch;
        if (room == 0) {
            flac.closeStream(&fd);
            fail("streamed output exceeds harness buffer");
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
        }
        var f: usize = flac.decodeStream(&fd, arena, out_buf[total * ch ..]) catch |e| {
            flac.closeStream(&fd);
            if (e == error.OutOfMemory) {
                fail("flac.decodeStream: arena OutOfMemory");
            } else {
                fail("flac.decodeStream returned an error");
            }
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = [20]u8{0} };
        };
        if (f == 0) break;
        total += f;
    }
    flac.closeStream(&fd);

    var golden_frames: usize = gold.len / (2 * ch);
    var n: usize = total * ch;
    var gv: []i16 = @ptrCast([*]i16, gold.ptr)[0 .. golden_frames * ch];
    var md: i32 = 0;
    var i: usize = 0;
    while (i < n and i < gv.len) : (i += 1) {
        var d: i32 = @intCast(i32, out_buf[i]) - @intCast(i32, gv[i]);
        if (d < 0) d = -d;
        if (d > md) md = d;
    }
    if (total != golden_frames) {
        var p: []const u8 = "flac_test: FAIL: stream frame count ";
        std.io.write(p);
        writeU(@intCast(u64, total));
        var q: []const u8 = " != golden ";
        std.io.write(q);
        writeU(@intCast(u64, golden_frames));
        var nl: []const u8 = "\n";
        std.io.write(nl);
        std.os.exit(1);
    }

    var bytes: []const u8 = @ptrCast([*]const u8, out_buf[0..n].ptr)[0 .. n * 2];
    var hash: [20]u8 = [20]u8{0};
    for (hash) |*item| {
        item.* = 0;
    }
    sha1Of(bytes, &hash);
    return RunResult{ .frames = total, .golden_frames = golden_frames, .max_delta = md, .hash = hash };
}

fn sameBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn refReadBits(data: []const u8, pos: usize, n: u32) u64 {
    var v: u64 = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var at: usize = pos + @intCast(usize, i);
        var off: u32 = @intCast(u32, at & 7);
        var sh: u3 = @intCast(u3, 7 - off);
        var bit: u64 = @intCast(u64, (data[at >> 3] >> sh) & 1);
        v = (v << 1) | bit;
    }
    return v;
}

fn refReadSigned(data: []const u8, pos: usize, n: u32) i64 {
    if (n == 0) return 0;
    var uv: u64 = refReadBits(data, pos, n);
    var signbit: u64 = @intCast(u64, 1) << @intCast(u64, n - 1);
    if ((uv & signbit) == 0) return @intCast(i64, uv);
    var top: u64 = @intCast(u64, 1) << @intCast(u64, n);
    return @intCast(i64, uv) - @intCast(i64, top);
}

const RefUnary = struct {
    found: bool,
    q: u32,
    next: usize,
};

fn refUnary(data: []const u8, pos: usize) RefUnary {
    var p: usize = pos;
    var q: u32 = 0;
    while (p < data.len * 8) {
        var off: u32 = @intCast(u32, p & 7);
        var sh: u3 = @intCast(u3, 7 - off);
        if (((data[p >> 3] >> sh) & 1) != 0) {
            return RefUnary{ .found = true, .q = q, .next = p + 1 };
        }
        q += 1;
        p += 1;
    }
    return RefUnary{ .found = false, .q = q, .next = p };
}

fn fillReaderData() void {
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        var v: u32 = @intCast(u32, i);
        v = (v * 73 + 41) & 0xff;
        unit_file[i] = @intCast(u8, v);
    }
}

fn writeReaderFile(data: []const u8) void {
    filemod.writeAll(RDR_PATH, data) catch fail("cannot write reader test file");
}

fn openReader(arena: *std.arena.Arena) stream.BufferedFile {
    var bf: stream.BufferedFile = stream.bufferedFileOpen(arena, RDR_PATH) catch {
        fail("cannot open reader test file");
        return stream.zeroBufferedFile();
    };
    return bf;
}

fn testBitDifferential(arena: *std.arena.Arena) void {
    fillReaderData();
    writeReaderFile(unit_file[0..64]);
    var bf1: stream.BufferedFile = openReader(arena);
    var r1 = flac.testStreamBitReaderInit(&bf1);
    var widths: [18]u32 = [18]u32{ 1, 5, 3, 0, 8, 16, 2, 7, 13, 32, 4, 9, 11, 6, 1, 24, 10, 14 };
    var rp: usize = 0;
    var i: usize = 0;
    while (i < widths.len) : (i += 1) {
        var w: u32 = widths[i];
        var need: usize = @intCast(usize, w);
        if (rp + need > 64 * 8) break;
        var got: u64 = flac.testStreamBitReaderReadBits(&r1, w) catch {
            fail("sReadBits differential: unexpected Truncated");
            return;
        };
        var want: u64 = refReadBits(unit_file[0..64], rp, w);
        if (got != want) fail("sReadBits value mismatch vs per-bit reference");
        rp += need;
    }
    if (rp == 0) fail("sReadBits differential consumed no bits");
    stream.bufferedFileClose(&bf1);
    filemod.remove(RDR_PATH) catch {};

    fillReaderData();
    writeReaderFile(unit_file[0..64]);
    var bf2: stream.BufferedFile = openReader(arena);
    var r2 = flac.testStreamBitReaderInit(&bf2);
    var swidths: [13]u32 = [13]u32{ 1, 2, 3, 4, 5, 7, 8, 12, 16, 20, 24, 31, 32 };
    rp = 0;
    i = 0;
    while (i < swidths.len) : (i += 1) {
        var w: u32 = swidths[i];
        var need: usize = @intCast(usize, w);
        if (rp + need > 64 * 8) break;
        var got: i64 = flac.testStreamBitReaderReadSigned(&r2, w) catch {
            fail("sReadSigned differential: unexpected Truncated");
            return;
        };
        var want: i64 = refReadSigned(unit_file[0..64], rp, w);
        if (got != want) fail("sReadSigned value mismatch vs per-bit reference");
        rp += need;
    }
    stream.bufferedFileClose(&bf2);
    filemod.remove(RDR_PATH) catch {};

    i = 0;
    while (i < 20) : (i += 1) unit_file[i] = 0;
    unit_file[2] = 0x80;
    unit_file[4] = 0x40;
    unit_file[7] = 0x02;
    writeReaderFile(unit_file[0..20]);
    var bf3: stream.BufferedFile = openReader(arena);
    var r3 = flac.testStreamBitReaderInit(&bf3);
    rp = 0;
    i = 0;
    while (i < 8) : (i += 1) {
        var r = refUnary(unit_file[0..20], rp);
        if (!r.found) break;
        var got: u32 = flac.testStreamBitReaderReadUnary(&r3) catch {
            fail("sReadUnary differential: unexpected Truncated");
            return;
        };
        if (got != r.q) fail("sReadUnary value mismatch vs per-bit reference");
        rp = r.next;
        if (i == 2) break;
    }
    if (i < 2) fail("sReadUnary differential did not exercise enough runs");
    stream.bufferedFileClose(&bf3);
    filemod.remove(RDR_PATH) catch {};
}

fn testTruncated(arena: *std.arena.Arena) void {
    fillReaderData();
    writeReaderFile(unit_file[0..9]);
    var bf: stream.BufferedFile = openReader(arena);
    var r = flac.testStreamBitReaderInit(&bf);
    var rp: usize = 0;

    var g1: u64 = flac.testStreamBitReaderReadBits(&r, 13) catch {
        fail("13-bit read at start unexpectedly truncated");
        return;
    };
    if (g1 != refReadBits(unit_file[0..9], rp, 13)) fail("13-bit read value mismatch");
    rp += 13;
    var g2: u64 = flac.testStreamBitReaderReadBits(&r, 19) catch {
        fail("19-bit read before EOF unexpectedly truncated");
        return;
    };
    if (g2 != refReadBits(unit_file[0..9], rp, 19)) fail("19-bit read value mismatch");
    rp += 19;
    var g3: u64 = flac.testStreamBitReaderReadBits(&r, 32) catch {
        fail("32-bit read before EOF unexpectedly truncated");
        return;
    };
    if (g3 != refReadBits(unit_file[0..9], rp, 32)) fail("32-bit read value mismatch");
    rp += 32;
    var g4: u64 = flac.testStreamBitReaderReadBits(&r, 8) catch {
        fail("final 8-bit read at EOF unexpectedly truncated");
        return;
    };
    if (g4 != refReadBits(unit_file[0..9], rp, 8)) fail("final 8-bit read value mismatch");
    rp += 8;
    if (rp != 9 * 8) fail("truncated test did not consume exactly the file bits");

    var trunc1: bool = false;
    _ = flac.testStreamBitReaderReadBits(&r, 1) catch |e| {
        if (e == error.Truncated) trunc1 = true;
    };
    if (!trunc1) fail("read past EOF did not return error.Truncated");
    var trunc8: bool = false;
    _ = flac.testStreamBitReaderReadBits(&r, 8) catch |e| {
        if (e == error.Truncated) trunc8 = true;
    };
    if (!trunc8) fail("second read past EOF did not return error.Truncated");

    stream.bufferedFileClose(&bf);
    filemod.remove(RDR_PATH) catch {};
}

fn testRecording(arena: *std.arena.Arena) void {
    fillReaderData();
    writeReaderFile(unit_file[0..32]);
    var bf: stream.BufferedFile = openReader(arena);
    var r = flac.testStreamBitReaderInit(&bf);
    flac.testStreamBitReaderSetRecording(&r, true);

    var widths: [20]u32 = [20]u32{ 3, 5, 8, 8, 13, 11, 16, 8, 8, 8, 8, 1, 7, 8, 8, 8, 8, 8, 8, 8 };
    var rp: usize = 0;
    var i: usize = 0;
    while (i < widths.len) : (i += 1) {
        var w: u32 = widths[i];
        var got: u64 = flac.testStreamBitReaderReadBits(&r, w) catch {
            fail("recording header read unexpectedly truncated");
            return;
        };
        if (got != refReadBits(unit_file[0..32], rp, w)) fail("recording header read value mismatch");
        rp += @intCast(usize, w);
    }
    var hdr: [64]u8 = [64]u8{0};
    for (hdr) |*item| {
        item.* = 0;
    }
    var hdr_len: usize = flac.testStreamBitReaderCopyHdr(&r, hdr[0..]);
    if (hdr_len != 20) fail("recording captured the wrong number of header bytes");
    if (!sameBytes(hdr[0..hdr_len], unit_file[0..20])) {
        fail("recorded hdr differs from consumed header bytes");
    }

    flac.testStreamBitReaderSetRecording(&r, false);
    var extra: u64 = flac.testStreamBitReaderReadBits(&r, 32) catch {
        fail("post-recording read unexpectedly truncated");
        return;
    };
    if (extra != refReadBits(unit_file[0..32], rp, 32)) fail("post-recording read value mismatch");
    hdr_len = flac.testStreamBitReaderCopyHdr(&r, hdr[0..]);
    if (hdr_len != 20) fail("recording appended bytes after recording was disabled");

    stream.bufferedFileClose(&bf);
    filemod.remove(RDR_PATH) catch {};
}

fn crc8Ref(data: []const u8) u8 {
    var crc: u8 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        crc = crc ^ data[i];
        var j: u8 = 0;
        while (j < 8) : (j += 1) {
            if ((crc & 0x80) != 0) {
                crc = (crc *% 2) ^ 0x07;
            } else {
                crc = crc *% 2;
            }
        }
    }
    return crc;
}

fn buildFrameAt(off_in: usize, num: u8, hi: u8, lo: u8) usize {
    var off: usize = off_in;
    unit_file[off] = 0xff;
    unit_file[off + 1] = 0xf8; // sync, reserved 0, fixed block size
    unit_file[off + 2] = 0x19; // block 192, sample rate 44100
    unit_file[off + 3] = 0x08; // 1 channel, 16 bps, reserved 0
    unit_file[off + 4] = num; // fixed-block frame number
    unit_file[off + 5] = crc8Ref(unit_file[off .. off + 5]);
    unit_file[off + 6] = 0x00; // constant subframe, wasted bits 0
    unit_file[off + 7] = hi;
    unit_file[off + 8] = lo;
    unit_file[off + 9] = 0x00; // CRC-16 is read but not verified
    unit_file[off + 10] = 0x00;
    return off + 11;
}

fn buildTwoFrameFile() usize {
    var i: usize = 0;
    while (i < unit_file.len) : (i += 1) unit_file[i] = 0;
    unit_file[0] = 'f';
    unit_file[1] = 'L';
    unit_file[2] = 'a';
    unit_file[3] = 'C';
    unit_file[4] = 0x80; // last metadata block, STREAMINFO
    unit_file[5] = 0x00;
    unit_file[6] = 0x00;
    unit_file[7] = 0x22; // 34-byte STREAMINFO
    unit_file[8] = 0x00;
    unit_file[9] = 192; // min block
    unit_file[10] = 0x00;
    unit_file[11] = 192; // max block
    var pack: u64 = (@intCast(u64, 44100) << 44) | (@intCast(u64, 15) << 36) | 384;
    i = 0;
    while (i < 8) : (i += 1) {
        var sh: u32 = 56 - @intCast(u32, i * 8);
        unit_file[18 + i] = @intCast(u8, (pack >> @intCast(u64, sh)) & 0xff);
    }
    var off: usize = 42;
    off = buildFrameAt(off, 0, 0x00, 0x01);
    off = buildFrameAt(off, 1, 0x00, 0x02);
    return off;
}

fn testMultiFramePrefetch(arena: *std.arena.Arena) void {
    var len: usize = buildTwoFrameFile();
    writeReaderFile(unit_file[0..len]);
    var d: flac.StreamFlacDecoder = flac.openStream(arena, RDR_PATH) catch {
        fail("multi-frame: openStream failed");
        return;
    };
    var f1: usize = flac.decodeStream(&d, arena, unit_out[0..]) catch {
        flac.closeStream(&d);
        fail("multi-frame: frame 1 decode failed");
        return;
    };
    if (f1 != 192) {
        flac.closeStream(&d);
        fail("multi-frame: frame 1 sample count wrong");
        return;
    }
    if (unit_out[0] != 1) {
        flac.closeStream(&d);
        fail("multi-frame: frame 1 PCM wrong");
        return;
    }
    var f2: usize = flac.decodeStream(&d, arena, unit_out[0..]) catch {
        flac.closeStream(&d);
        fail("multi-frame: frame 2 header CRC-8 failed with prefetch");
        return;
    };
    if (f2 != 192) {
        flac.closeStream(&d);
        fail("multi-frame: frame 2 sample count wrong");
        return;
    }
    if (unit_out[0] != 2) {
        flac.closeStream(&d);
        fail("multi-frame: frame 2 PCM wrong");
        return;
    }
    var f3: usize = flac.decodeStream(&d, arena, unit_out[0..]) catch {
        flac.closeStream(&d);
        fail("multi-frame: end-of-stream check failed");
        return;
    };
    if (f3 != 0) {
        flac.closeStream(&d);
        fail("multi-frame: expected clean end of stream");
        return;
    }
    flac.closeStream(&d);
    filemod.remove(RDR_PATH) catch {};
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var arena = std.arena.init(arena_buf[0..]);

    std.arena.reset(&arena);
    testBitDifferential(&arena);
    std.arena.reset(&arena);
    testTruncated(&arena);
    std.arena.reset(&arena);
    testRecording(&arena);
    std.arena.reset(&arena);
    testMultiFramePrefetch(&arena);

    if (argc < 3) {
        var ok: []const u8 = "flac_test: PASS bit-reader unit tests\n";
        std.io.write(ok);
        return;
    }
    var fixture: []const u8 = argAt(argv, 1);
    var golden: []const u8 = argAt(argv, 2);

    std.arena.reset(&arena);
    var r1: RunResult = decodeOnce(&arena, fixture, golden);
    if (r1.max_delta != 0) fail("decoded PCM is not an exact match");

    std.arena.reset(&arena);
    var s1: RunResult = decodeStreamOnce(&arena, fixture, golden);
    if (s1.max_delta != 0) fail("streamed PCM is not an exact match");
    if (s1.frames != r1.frames) fail("streamed frame count differs from oracle");

    var i2: usize = 0;
    while (i2 < 20) : (i2 += 1) {
        if (s1.hash[i2] != r1.hash[i2]) {
            fail("streamed PCM differs from byte-slice oracle");
        }
    }

    std.arena.reset(&arena);
    var r2: RunResult = decodeOnce(&arena, fixture, golden);
    std.arena.reset(&arena);
    var r3: RunResult = decodeOnce(&arena, fixture, golden);
    std.arena.reset(&arena);
    var s2: RunResult = decodeStreamOnce(&arena, fixture, golden);
    std.arena.reset(&arena);
    var s3: RunResult = decodeStreamOnce(&arena, fixture, golden);

    i2 = 0;
    while (i2 < 20) : (i2 += 1) {
        if (r1.hash[i2] != r2.hash[i2] or r1.hash[i2] != r3.hash[i2]) {
            fail("3x byte-slice determinism mismatch");
        }
        if (s1.hash[i2] != s2.hash[i2] or s1.hash[i2] != s3.hash[i2]) {
            fail("3x stream determinism mismatch");
        }
    }

    var p: []const u8 = "flac_test: PASS frames=";
    std.io.write(p);
    writeU(@intCast(u64, r1.frames));
    var q: []const u8 = " golden=";
    std.io.write(q);
    writeU(@intCast(u64, r1.golden_frames));
    var m: []const u8 = " max_delta=";
    std.io.write(m);
    writeU(@intCast(u64, @intCast(u32, r1.max_delta)));
    var h: []const u8 = " sha1=";
    std.io.write(h);
    var i: usize = 0;
    while (i < 20) : (i += 1) hexByte(r1.hash[i]);
    var nl: []const u8 = "\n";
    std.io.write(nl);
}
