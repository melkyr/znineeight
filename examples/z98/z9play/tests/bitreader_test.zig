// bitreader_test.zig — deterministic differential test for the z9play Vorbis
// bit reader (vorbis_setup.BitReader).
//
// The reader is LSB-first: bit `p` lives at `data[p >> 3] >> (p & 7)`. This
// test compares it against a naive bit-by-bit reference over lengths 0..64 and
// read widths 1..32, and pins the interface promises used by the decoder:
//   1. `brRead` matches the reference and advances `pos` by exactly `n`;
//   2. a read past `nbits` returns `error.Truncated` with `pos` unchanged;
//   3. `brSkip` followed by `brRead` equals a naive read at the skipped offset,
//      including non-byte-aligned skips (1, 3, 7, 9, 13) from both aligned and
//      already-advanced positions;
//   4. `brSkip` past `nbits` returns `error.Truncated` with `pos` unchanged;
//   5. `brBitZero` matches the reference bit, and past the end returns 0 without
//      advancing `pos` past `nbits`.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/perf_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/bitreader_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const vs = @import("../vorbis_setup.zig");

var buf: [64]u8;

fn fail(msg: []const u8) void {
    var p: []const u8 = "bitreader_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// Deterministic, varied byte pattern; every length 0..64 is a prefix of it.
fn fill() void {
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        var v: u32 = @intCast(u32, i);
        v = (v * 73 + 41) & 0xff;
        buf[i] = @intCast(u8, v);
    }
}

// Naive LSB-first reference: read `n` bits starting at bit `pos`.
fn refRead(data: []const u8, pos: usize, n: u32) u32 {
    var v: u32 = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var at: usize = pos + @intCast(usize, i);
        var b: u32 = @intCast(u32, data[at >> 3]);
        var shift: u32 = @intCast(u32, at & 7);
        var bit: u32 = (b >> shift) & 1;
        var sh: u32 = i;
        v |= bit << sh;
    }
    return v;
}

fn tryRead(br: *vs.BitReader, n: u32) ?u32 {
    var v: u32 = vs.brRead(br, n) catch return null;
    return v;
}

fn trySkip(br: *vs.BitReader, n: u32) bool {
    vs.brSkip(br, n) catch return false;
    return true;
}

// (1) One read from a fresh reader; (2) past-end read leaves pos unchanged.
fn testSingleReads() void {
    var len: usize = 0;
    while (len <= 64) : (len += 1) {
        var data: []const u8 = buf[0..len];
        var total: usize = len * 8;
        var n: u32 = 1;
        while (n <= 32) : (n += 1) {
            var br: vs.BitReader = vs.brInit(data);
            var need: usize = @intCast(usize, n);
            if (need <= total) {
                var got_opt: ?u32 = tryRead(&br, n);
                if (got_opt) |got| {
                    var want: u32 = refRead(data, 0, n);
                    if (got != want) fail("single read value mismatch");
                    if (br.pos != need) fail("single read pos mismatch");
                } else {
                    fail("single read unexpectedly truncated");
                }
            } else {
                var got_opt: ?u32 = tryRead(&br, n);
                if (got_opt) |g| {
                    _ = g;
                    fail("past-end single read did not error");
                }
                if (br.pos != 0) fail("past-end single read moved pos");
            }
        }
    }
}

// Read a whole buffer in varying widths; every read must match the reference
// and leave `pos` at the exact consumed-bit count.
fn testStreaming() void {
    var len: usize = 1;
    while (len <= 64) : (len += 1) {
        var data: []const u8 = buf[0..len];
        var total: usize = len * 8;
        var br: vs.BitReader = vs.brInit(data);
        var k: u32 = 1;
        while (br.pos < total) {
            var need: u32 = k;
            var remaining: usize = total - br.pos;
            if (@intCast(usize, need) > remaining) {
                need = @intCast(u32, remaining);
            }
            var start: usize = br.pos;
            var got_opt: ?u32 = tryRead(&br, need);
            if (got_opt) |got| {
                var want: u32 = refRead(data, start, need);
                if (got != want) fail("stream read value mismatch");
                if (br.pos != start + @intCast(usize, need)) fail("stream read pos mismatch");
            } else {
                fail("stream read unexpectedly truncated");
            }
            k += 1;
            if (k > 32) k = 1;
        }
        if (br.pos != total) fail("stream final pos mismatch");
    }
}

// (3) brSkip then brRead equals a naive read at the skipped offset. The prefix
// read moves pos off a byte boundary so brSkip must not rewind accumulator
// bits.
fn testSkipThenRead() void {
    var skips: [5]u32 = [5]u32{ 1, 3, 7, 9, 13 };
    var len: usize = 0;
    while (len <= 64) : (len += 1) {
        var data: []const u8 = buf[0..len];
        var total: usize = len * 8;
        var pre: u32 = 0;
        while (pre <= 7) : (pre += 1) {
            var si: usize = 0;
            while (si < 5) : (si += 1) {
                var s: u32 = skips[si];
                var n: u32 = 1;
                while (n <= 32) : (n += 1) {
                    var need: usize = @intCast(usize, pre) + @intCast(usize, s) + @intCast(usize, n);
                    if (need > total) continue;
                    var br: vs.BitReader = vs.brInit(data);
                    var got_pre_opt: ?u32 = tryRead(&br, pre);
                    if (got_pre_opt) |got_pre| {
                        var want_pre: u32 = refRead(data, 0, pre);
                        if (got_pre != want_pre) fail("skip test prefix value mismatch");
                    } else {
                        fail("skip test prefix unexpectedly truncated");
                    }
                    var at: usize = @intCast(usize, pre);
                    if (!trySkip(&br, s)) fail("skip test skip unexpectedly truncated");
                    if (br.pos != at + @intCast(usize, s)) fail("skip test pos after skip mismatch");
                    var got_opt: ?u32 = tryRead(&br, n);
                    if (got_opt) |got| {
                        var want: u32 = refRead(data, at + @intCast(usize, s), n);
                        if (got != want) fail("skip test read value mismatch");
                        if (br.pos != need) fail("skip test final pos mismatch");
                    } else {
                        fail("skip test read unexpectedly truncated");
                    }
                }
            }
        }
    }
}

// (4) Skip exactly to nbits succeeds; read then truncates without moving pos.
// Any skip past nbits returns Truncated and leaves pos untouched.
fn testSkipPastEnd() void {
    var len: usize = 0;
    while (len <= 64) : (len += 1) {
        var data: []const u8 = buf[0..len];
        var total: usize = len * 8;
        var pre: usize = 0;
        while (pre <= total and pre <= 9) : (pre += 1) {
            var br: vs.BitReader = vs.brInit(data);
            if (pre > 0) {
                if (!trySkip(&br, @intCast(u32, pre))) fail("valid prefix skip failed");
            }
            var to_end: usize = total - pre;
            if (to_end > 0) {
                var n32: u32 = @intCast(u32, to_end);
                if (!trySkip(&br, n32)) fail("skip to end failed");
                if (br.pos != total) fail("skip to end pos mismatch");
                var before: usize = br.pos;
                var got_opt: ?u32 = tryRead(&br, 1);
                if (got_opt) |g| {
                    _ = g;
                    fail("read after skip-to-end did not truncate");
                }
                if (br.pos != before) fail("truncated read after skip-to-end moved pos");
            }

            var br2: vs.BitReader = vs.brInit(data);
            if (pre > 0) {
                if (!trySkip(&br2, @intCast(u32, pre))) fail("valid prefix skip failed (2)");
            }
            var before2: usize = br2.pos;
            var over: u32 = 1;
            while (over <= 13) : (over += 1) {
                var bad: usize = to_end + @intCast(usize, over);
                if (trySkip(&br2, @intCast(u32, bad))) fail("past-end skip succeeded");
                if (br2.pos != before2) fail("past-end skip moved pos");
            }
        }
    }
}

// (5) brBitZero matches the reference bit; past the end it yields 0 and clamps
// pos at nbits. Interleaving with brRead checks refill/anchor consistency.
fn testBitZero() void {
    var len: usize = 0;
    while (len <= 64) : (len += 1) {
        var data: []const u8 = buf[0..len];
        var total: usize = len * 8;
        var br: vs.BitReader = vs.brInit(data);
        var i: usize = 0;
        while (i < total) : (i += 1) {
            var bit: u32 = vs.brBitZero(&br);
            var want: u32 = refRead(data, i, 1);
            if (bit != want) fail("brBitZero value mismatch");
            if (br.pos != i + 1) fail("brBitZero pos mismatch");
        }
        var k: u32 = 0;
        while (k < 16) : (k += 1) {
            var bit: u32 = vs.brBitZero(&br);
            if (bit != 0) fail("brBitZero past end returned 1");
            if (br.pos != total) fail("brBitZero advanced past nbits");
        }

        var br2: vs.BitReader = vs.brInit(data);
        var p: usize = 0;
        var step: u32 = 1;
        while (p < total) {
            if ((step & 1) == 1) {
                var bit: u32 = vs.brBitZero(&br2);
                var want: u32 = refRead(data, p, 1);
                if (bit != want) fail("mixed brBitZero value mismatch");
                p += 1;
            } else {
                var n: u32 = step % 9;
                if (n == 0) n = 1;
                var remaining: usize = total - p;
                if (@intCast(usize, n) > remaining) n = @intCast(u32, remaining);
                var got_opt: ?u32 = tryRead(&br2, n);
                if (got_opt) |got| {
                    var want: u32 = refRead(data, p, n);
                    if (got != want) fail("mixed brRead value mismatch");
                } else {
                    fail("mixed brRead unexpectedly truncated");
                }
                p += @intCast(usize, n);
            }
            if (br2.pos != p) fail("mixed pos mismatch");
            step += 1;
        }
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    fill();
    testSingleReads();
    testStreaming();
    testSkipThenRead();
    testSkipPastEnd();
    testBitZero();

    var ok: []const u8 = "bitreader_test: PASS reads=0..64 widths=1..32 skip=1,3,7,9,13 pastend=ok bitzero=ok\n";
    std.io.write(ok);
    std.os.exit(0);
}
