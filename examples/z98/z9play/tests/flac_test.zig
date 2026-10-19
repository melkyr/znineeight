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

var arena_buf: [16 * 1024 * 1024]u8 = undefined;
var out_buf: [400000]i16 = undefined;

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

fn sha1Of(data: []const u8, out: *[20]u8) void {
    var s: crypto.Sha1 = crypto.sha1Init();
    crypto.sha1Update(&s, data);
    crypto.sha1Final(&s, out);
}

fn hexByte(b: u8) void {
    var d: []const u8 = "0123456789abcdef";
    var s: [1]u8 = undefined;
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
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
    };
    var gold: []u8 = filemod.readAll(arena, golden) catch {
        fail("cannot read golden PCM");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
    };

    var fd: flac.FlacDecoder = flac.open(arena, data) catch {
        fail("flac.open failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
    };
    var ch: usize = @intCast(usize, fd.channels);

    var total: usize = 0;
    while (true) {
        var room: usize = out_buf.len - total * ch;
        if (room == 0) {
            fail("decoded output exceeds harness buffer");
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
        }
        var f: usize = flac.decode(&fd, arena, out_buf[total * ch ..]) catch |e| {
            if (e == error.OutOfMemory) {
                fail("flac.decode: arena OutOfMemory");
            } else {
                fail("flac.decode returned an error");
            }
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
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
    var hash: [20]u8 = undefined;
    sha1Of(bytes, &hash);
    return RunResult{ .frames = total, .golden_frames = golden_frames, .max_delta = md, .hash = hash };
}

// One complete decode pass through the file-backed streaming path. The
// returned shape matches decodeOnce so the caller can compare frame counts,
// PCM deltas, and hashes against the byte-slice oracle.
fn decodeStreamOnce(arena: *std.arena.Arena, fixture: []const u8, golden: []const u8) RunResult {
    var gold: []u8 = filemod.readAll(arena, golden) catch {
        fail("cannot read golden PCM");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
    };

    var fd: flac.StreamFlacDecoder = flac.openStream(arena, fixture) catch {
        fail("flac.openStream failed");
        return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
    };
    var ch: usize = @intCast(usize, fd.channels);

    var total: usize = 0;
    while (true) {
        var room: usize = out_buf.len - total * ch;
        if (room == 0) {
            flac.closeStream(&fd);
            fail("streamed output exceeds harness buffer");
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
        }
        var f: usize = flac.decodeStream(&fd, arena, out_buf[total * ch ..]) catch |e| {
            flac.closeStream(&fd);
            if (e == error.OutOfMemory) {
                fail("flac.decodeStream: arena OutOfMemory");
            } else {
                fail("flac.decodeStream returned an error");
            }
            return RunResult{ .frames = 0, .golden_frames = 0, .max_delta = 0, .hash = undefined };
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
    var hash: [20]u8 = undefined;
    sha1Of(bytes, &hash);
    return RunResult{ .frames = total, .golden_frames = golden_frames, .max_delta = md, .hash = hash };
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    if (argc < 3) {
        fail("usage: flac_test <fixture.flac> <golden.pcm>");
        return;
    }
    var fixture: []const u8 = argAt(argv, 1);
    var golden: []const u8 = argAt(argv, 2);

    var arena = std.arena.init(arena_buf[0..]);

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
