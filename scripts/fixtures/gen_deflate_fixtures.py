#!/usr/bin/env python3
"""Generate the std_deflate stdlib fixtures.

The seven repro/mi_matrix/stdlib_deflate_*_xmod dirs are emitted here from
python3's zlib module so the DEFLATE byte streams are real compressor output,
not hand-written approximations.  Each fixture embeds its own byte arrays (the
stdlib harness runs fixtures from a scratch CWD, so there is no runtime data
dependency).

`expected_error.txt` (corrupt fixture) is generated documentation only. It is
gitignored and is NOT read by the stdlib harness; the harness pins are
expected.txt and expected.rc, and they are always written here.

Usage: python3 scripts/fixtures/gen_deflate_fixtures.py
"""

import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MATRIX = os.path.join(ROOT, "repro", "mi_matrix")


def raw_deflate(data, level, strategy=zlib.Z_DEFAULT_STRATEGY):
    co = zlib.compressobj(level, zlib.DEFLATED, -15, 8, strategy)
    return co.compress(data) + co.flush()


def zlib_stream(data, level, strategy=zlib.Z_DEFAULT_STRATEGY):
    co = zlib.compressobj(level, zlib.DEFLATED, 15, 8, strategy)
    return co.compress(data) + co.flush()


def block_type(stream, offset):
    return (stream[offset] >> 1) & 3


def zig_bytes(name, data):
    lines = ["const %s = [_]u8{" % name]
    for i in range(0, len(data), 12):
        chunk = ", ".join("0x%02X" % b for b in data[i:i + 12])
        lines.append("    " + chunk + ",")
    lines.append("};")
    lines.append("")
    lines.append("pub fn %s_slice() []const u8 { return %s[0..]; }" % (name, name))
    return "\n".join(lines)


def write_fixture(name, data_zig, main_zig, expected, rc="0"):
    d = os.path.join(MATRIX, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "fixtures_data.zig"), "w", newline="\n") as f:
        f.write(data_zig)
    with open(os.path.join(d, "main.zig"), "w", newline="\n") as f:
        f.write(main_zig)
    with open(os.path.join(d, "expected.txt"), "w", newline="\n") as f:
        f.write(expected)
    with open(os.path.join(d, "expected.rc"), "w", newline="\n") as f:
        f.write(rc + "\n")


BASIC_TEMPLATE = """// stdlib_deflate_zlib_basic_xmod -- std_deflate (L4) RFC 1950 fixture.
//
// Covers zlib-wrapped stored, fixed-Huffman and dynamic-Huffman blocks, verifies
// the exact output bytes and that `used` equals the whole stream (wrapper
// included), and pins error.OutputTooSmall when dst cannot hold the output.
//
// GREEN: deterministic byte-exact stdout `deflate zlib basic ok\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectZ(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(g_dst[i] == want[i], what);
    }
}

fn expectTooSmall(src: []const u8, dst: []u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, dst, &used) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    expectZ(fx.z_stored_slice(), fx.z_stored_out_slice(), "zlib stored");
    expectZ(fx.z_fixed_slice(), fx.z_fixed_out_slice(), "zlib fixed");
    expectZ(fx.z_dynamic_slice(), fx.z_dynamic_out_slice(), "zlib dynamic");

    var small: [8]u8 = undefined;
    expectTooSmall(fx.z_dynamic_slice(), small[0..], "zlib dynamic too small");

    io.write("deflate zlib basic ok\\n");
}
"""

RAW_TEMPLATE = """// stdlib_deflate_raw_xmod -- std_deflate (L4) RFC 1951 raw fixture.
//
// Covers raw (unwrapped) stored, fixed-Huffman and dynamic-Huffman blocks and
// verifies exact output bytes and `used == src.len`.
//
// GREEN: deterministic byte-exact stdout `deflate raw ok\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectRaw(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(g_dst[i] == want[i], what);
    }
}

pub fn main() void {
    expectRaw(fx.raw_stored_slice(), fx.raw_stored_out_slice(), "raw stored");
    expectRaw(fx.raw_fixed_slice(), fx.raw_fixed_out_slice(), "raw fixed");
    expectRaw(fx.raw_dynamic_slice(), fx.raw_dynamic_out_slice(), "raw dynamic");

    io.write("deflate raw ok\\n");
}
"""

DYNAMIC_TEMPLATE = """// stdlib_deflate_dynamic_xmod -- std_deflate (L4) dynamic-block fixture.
//
// The streams are real zlib output whose first DEFLATE block is dynamic
// (BTYPE=2): the code-length alphabet, literal/length alphabet and distance
// alphabet are all rebuilt from the per-block header. Exact output is checked.
//
// GREEN: deterministic byte-exact stdout `deflate dynamic ok\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectZ(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(g_dst[i] == want[i], what);
    }
}

pub fn main() void {
    expectZ(fx.dyn_lorem_slice(), fx.dyn_lorem_out_slice(), "dynamic lorem");
    expectZ(fx.dyn_english_slice(), fx.dyn_english_out_slice(), "dynamic english");

    io.write("deflate dynamic ok\\n");
}
"""

USED_TEMPLATE = """// stdlib_deflate_used_xmod -- std_deflate (L4) consumed-input fixture.
//
// Two independent zlib streams are concatenated. Decoding the first must report
// exactly its own byte length in `used` (wrapper bytes included) so a caller can
// start the second stream at src[used..]. Both exact output lengths and both
// exact `used` values are asserted (Review Focus 2).
//
// GREEN: deterministic byte-exact stdout `deflate used ok\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

pub fn main() void {
    const all = fx.used_concat_slice();
    const first = fx.used_first_slice();
    const second = fx.used_second_slice();
    const expect1 = fx.used_first_len();
    const expect2 = fx.used_second_len();
    const out1 = fx.used_first_out_len();
    const out2 = fx.used_second_out_len();

    var used1: usize = 0;
    const n1 = deflate.inflateZlib(all[0..], g_dst[0..], &used1) catch {
        @panic("first stream");
    };
    ck(@intCast(usize, n1) == out1, "first output length");
    ck(used1 == expect1, "first used exact");
    ck(used1 == first.len, "first used slice length");
    ckBytes(g_dst[0..@intCast(usize, n1)], fx.used_first_out_slice(), "first output bytes");

    var used2: usize = 0;
    const n2 = deflate.inflateZlib(all[used1..], g_dst[0..], &used2) catch {
        @panic("second stream");
    };
    ck(@intCast(usize, n2) == out2, "second output length");
    ck(used2 == expect2, "second used exact");
    ck(used2 == second.len, "second used slice length");
    ckBytes(g_dst[0..@intCast(usize, n2)], fx.used_second_out_slice(), "second output bytes");
    ck(used1 + used2 == all.len, "concat consumed");

    io.write("deflate used ok\\n");
}
"""

MULTIBLOCK_TEMPLATE = """// stdlib_deflate_multiblock_xmod -- std_deflate (L4) multi-block fixture.
//
// The stream starts with a BFINAL=0 stored block, continues with a BFINAL=0
// fixed-Huffman block (plus zlib's sync-flush empty stored block), and ends
// with a BFINAL=1 fixed block. A decoder that mishandles `while (!final)` stops
// after the first block and fails the exact-output check.
//
// GREEN: deterministic byte-exact stdout `deflate multiblock ok\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn expectZ(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    ckBytes(g_dst[0..@intCast(usize, n)], want, what);
}

fn expectRaw(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    ckBytes(g_dst[0..@intCast(usize, n)], want, what);
}

pub fn main() void {
    expectZ(fx.mb_zlib_slice(), fx.mb_out_slice(), "multiblock zlib");
    expectRaw(fx.mb_raw_slice(), fx.mb_out_slice(), "multiblock raw");

    io.write("deflate multiblock ok\\n");
}
"""

TOOSMALL_TEMPLATE = """// stdlib_deflate_toosmall_xmod -- std_deflate (L4) OutputTooSmall fixture.
//
// Both entry points are given a valid generated stream and a destination that
// cannot hold the decoded payload. Each must return error.OutputTooSmall.
//
// GREEN: deterministic byte-exact stdout `deflate too small ok\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

fn expectTooSmallZ(src: []const u8, dst: []u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, dst, &used) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectTooSmallRaw(src: []const u8, dst: []u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, dst, &used) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    var small: [16]u8 = undefined;
    expectTooSmallZ(fx.ts_zlib_slice(), small[0..], "zlib too small");
    expectTooSmallRaw(fx.ts_raw_slice(), small[0..], "raw too small");

    io.write("deflate too small ok\\n");
}
"""

CORRUPT_TEMPLATE = """// stdlib_deflate_corrupt_xmod -- std_deflate (L4) malformed-input fixture.
//
// Every case must surface error.Corrupt (not a crash, not a silent success):
// bad FCHECK, FDICT (unsupported dictionary), bad Adler-32, truncated zlib,
// bad CM, truncated raw, a reserved block type, a stored-block LEN/NLEN
// mismatch, and a distance-too-far match. The program catches and prints a
// deterministic success line, so expected.rc is 0.
//
// expected_error.txt is generated documentation only (gitignored, not read by
// the harness); expected.txt + expected.rc are the pins.
//
// GREEN: deterministic byte-exact stdout `deflate corrupt rejected\\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn expectCorruptZ(src: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectCorruptRaw(src: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, g_dst[0..], &used) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    expectCorruptZ(fx.corrupt_bad_fcheck_slice(), "bad fcheck");
    expectCorruptZ(fx.corrupt_fdict_slice(), "fdict");
    expectCorruptZ(fx.corrupt_bad_adler_slice(), "bad adler");
    expectCorruptZ(fx.corrupt_truncated_slice(), "truncated zlib");
    expectCorruptZ(fx.corrupt_bad_cm_slice(), "bad cm");
    expectCorruptRaw(fx.corrupt_raw_truncated_slice(), "truncated raw");
    expectCorruptRaw(fx.corrupt_raw_reserved_slice(), "reserved block type");
    expectCorruptRaw(fx.corrupt_stored_mismatch_slice(), "stored len/nlen mismatch");
    expectCorruptRaw(fx.corrupt_distance_far_slice(), "distance too far");

    io.write("deflate corrupt rejected\\n");
}
"""


def build_basic():
    stored_out = b"stored deflate block fixture. " * 8
    fixed_out = b"fixed huffman block: abcabcabcabcabcabc hello hello hello"
    dynamic_out = (b"Lorem ipsum dolor sit amet, consectetur adipiscing elit, "
                   b"sed do eiusmod tempor incididunt ut labore et dolore "
                   b"magna aliqua. ") * 60

    z_stored = zlib_stream(stored_out, 0)
    z_fixed = zlib_stream(fixed_out, 6, zlib.Z_FIXED)
    z_dynamic = zlib_stream(dynamic_out, 6)

    assert block_type(z_stored, 2) == 0, "stored fixture is not stored"
    assert block_type(z_fixed, 2) == 1, "fixed fixture is not fixed"
    assert block_type(z_dynamic, 2) == 2, "dynamic fixture is not dynamic"

    parts = [
        zig_bytes("z_stored", z_stored),
        zig_bytes("z_stored_out", stored_out),
        zig_bytes("z_fixed", z_fixed),
        zig_bytes("z_fixed_out", fixed_out),
        zig_bytes("z_dynamic", z_dynamic),
        zig_bytes("z_dynamic_out", dynamic_out),
    ]
    write_fixture("stdlib_deflate_zlib_basic_xmod", "\n\n".join(parts) + "\n",
                  BASIC_TEMPLATE, "deflate zlib basic ok\n")


def build_raw():
    stored_out = b"raw stored deflate fixture! " * 10
    fixed_out = b"raw fixed huffman: abcabcabcabcabcabc hello hello hello"
    dynamic_out = (b"Pack my box with five dozen liquor jugs. "
                   b"How vexingly quick daft zebras jump! ") * 80

    raw_stored = raw_deflate(stored_out, 0)
    raw_fixed = raw_deflate(fixed_out, 6, zlib.Z_FIXED)
    raw_dynamic = raw_deflate(dynamic_out, 6)

    assert block_type(raw_stored, 0) == 0, "raw stored fixture is not stored"
    assert block_type(raw_fixed, 0) == 1, "raw fixed fixture is not fixed"
    assert block_type(raw_dynamic, 0) == 2, "raw dynamic fixture is not dynamic"

    parts = [
        zig_bytes("raw_stored", raw_stored),
        zig_bytes("raw_stored_out", stored_out),
        zig_bytes("raw_fixed", raw_fixed),
        zig_bytes("raw_fixed_out", fixed_out),
        zig_bytes("raw_dynamic", raw_dynamic),
        zig_bytes("raw_dynamic_out", dynamic_out),
    ]
    write_fixture("stdlib_deflate_raw_xmod", "\n\n".join(parts) + "\n",
                  RAW_TEMPLATE, "deflate raw ok\n")


def build_dynamic():
    lorem_out = (b"Lorem ipsum dolor sit amet, consectetur adipiscing elit, "
                 b"sed do eiusmod tempor incididunt ut labore et dolore "
                 b"magna aliqua. ") * 60
    english_out = (b"The quick brown fox jumps over the lazy dog. Pack my box "
                   b"with five dozen liquor jugs. How vexingly quick daft "
                   b"zebras jump! ") * 80

    z_lorem = zlib_stream(lorem_out, 9)
    z_english = zlib_stream(english_out, 9)

    assert block_type(z_lorem, 2) == 2, "lorem dynamic fixture is not dynamic"
    assert block_type(z_english, 2) == 2, "english dynamic fixture is not dynamic"

    parts = [
        zig_bytes("dyn_lorem", z_lorem),
        zig_bytes("dyn_lorem_out", lorem_out),
        zig_bytes("dyn_english", z_english),
        zig_bytes("dyn_english_out", english_out),
    ]
    write_fixture("stdlib_deflate_dynamic_xmod", "\n\n".join(parts) + "\n",
                  DYNAMIC_TEMPLATE, "deflate dynamic ok\n")


def build_used():
    first_out = b"first stream: alpha alpha alpha" * 3
    second_out = b"second payload with different length and bytes 0123456789 ABCDEFGHIJ"

    first = zlib_stream(first_out, 6)
    second = zlib_stream(second_out, 9)
    assert block_type(first, 2) in (1, 2), "first used stream block type"
    assert block_type(second, 2) in (1, 2), "second used stream block type"

    parts = [
        zig_bytes("used_concat", first + second),
        zig_bytes("used_first", first),
        zig_bytes("used_second", second),
        zig_bytes("used_first_out", first_out),
        zig_bytes("used_second_out", second_out),
        "pub fn used_first_len() usize { return %d; }" % len(first),
        "",
        "pub fn used_second_len() usize { return %d; }" % len(second),
        "",
        "pub fn used_first_out_len() usize { return %d; }" % len(first_out),
        "",
        "pub fn used_second_out_len() usize { return %d; }" % len(second_out),
    ]
    write_fixture("stdlib_deflate_used_xmod", "\n\n".join(parts) + "\n",
                  USED_TEMPLATE, "deflate used ok\n")


def zlib_wrap_raw(raw, data):
    cmf = 0x78
    flg_high = 0x80  # FLEVEL 2, FDICT clear
    fcheck = (31 - ((cmf * 256 + flg_high) % 31)) % 31
    flg = flg_high | fcheck
    assert (cmf * 256 + flg) % 31 == 0
    return bytes([cmf, flg]) + raw + struct.pack(">I", zlib.adler32(data) & 0xFFFFFFFF)


class BitWriter:
    def __init__(self):
        self.bits = []

    def lsb(self, value, n):
        for i in range(n):
            self.bits.append((value >> i) & 1)

    def code(self, value, n):
        for i in range(n - 1, -1, -1):
            self.bits.append((value >> i) & 1)

    def bytes(self):
        out = bytearray((len(self.bits) + 7) // 8)
        for i, bit in enumerate(self.bits):
            if bit:
                out[i // 8] |= 1 << (i % 8)
        return bytes(out)


def build_multiblock():
    stored_out = b"stored block before the fixed block. " * 10
    fixed_out = b"fixed huffman block in the middle of the stream. " * 6
    final_out = b"final fixed block closes the deflate stream. " * 8
    all_out = stored_out + fixed_out + final_out

    stored_block = bytes([0x00]) + struct.pack(
        "<HH", len(stored_out), len(stored_out) ^ 0xFFFF) + stored_out

    co = zlib.compressobj(6, zlib.DEFLATED, -15, 8, zlib.Z_FIXED)
    remainder = co.compress(fixed_out) + co.flush(zlib.Z_SYNC_FLUSH)
    remainder += co.compress(final_out) + co.flush(zlib.Z_FINISH)
    raw = stored_block + remainder

    assert block_type(raw, 0) == 0, "multiblock first block is not stored"
    second_off = 5 + len(stored_out)
    assert block_type(raw, second_off) == 1, "multiblock second block is not fixed"
    assert zlib.decompress(raw, -15) == all_out, "multiblock raw self-check"
    wrapped = zlib_wrap_raw(raw, all_out)
    assert zlib.decompress(wrapped, 15) == all_out, "multiblock zlib self-check"

    parts = [
        zig_bytes("mb_zlib", wrapped),
        zig_bytes("mb_raw", raw),
        zig_bytes("mb_out", all_out),
    ]
    write_fixture("stdlib_deflate_multiblock_xmod", "\n\n".join(parts) + "\n",
                  MULTIBLOCK_TEMPLATE, "deflate multiblock ok\n")


def build_toosmall():
    out = (b"OutputTooSmall fixture payload: the destination is deliberately "
           b"smaller than this decoded text. ") * 4
    ts_raw = raw_deflate(out, 6)
    ts_zlib = zlib_stream(out, 6)
    assert zlib.decompress(ts_raw, -15) == out
    assert zlib.decompress(ts_zlib) == out

    parts = [
        zig_bytes("ts_raw", ts_raw),
        zig_bytes("ts_zlib", ts_zlib),
        zig_bytes("ts_out", out),
    ]
    write_fixture("stdlib_deflate_toosmall_xmod", "\n\n".join(parts) + "\n",
                  TOOSMALL_TEMPLATE, "deflate too small ok\n")


def fdict_wrapper(cmf, original):
    # Build an otherwise valid RFC 1950 header with FDICT set. No DICTID is
    # needed: std_deflate rejects FDICT before reading the payload.
    flg_high = 0x20  # FDICT, FLEVEL 0
    fcheck = (31 - ((cmf * 256 + flg_high) % 31)) % 31
    flg = flg_high | fcheck
    assert (cmf * 256 + flg) % 31 == 0
    return bytes([cmf, flg]) + original[2:]


def build_corrupt():
    payload_out = b"corrupt fixture payload: " * 8
    good = zlib_stream(payload_out, 6)

    bad_fcheck = bytearray(good)
    bad_fcheck[1] ^= 0x01

    bad_adler = bytearray(good)
    bad_adler[-1] ^= 0x80

    truncated = good[:len(good) - 7]

    bad_cm = bytearray(good)
    bad_cm[0] = 0x77  # CM=7, not DEFLATE

    fdict = fdict_wrapper(good[0], good)

    raw_dynamic = raw_deflate((b"raw corrupt sample " * 40), 6)
    raw_truncated = raw_dynamic[:len(raw_dynamic) - 3]

    mismatch = BitWriter()
    mismatch.lsb(1, 1)  # BFINAL
    mismatch.lsb(0, 2)  # BTYPE=00 stored
    stored_mismatch = mismatch.bytes() + struct.pack("<HH", 5, 0) + b"ABCDE"

    far = BitWriter()
    far.lsb(1, 1)        # BFINAL
    far.lsb(1, 2)        # BTYPE=01 fixed
    far.code(0x30 + 65, 8)  # literal 'A'
    far.code(1, 7)       # length code 257 -> length 3 (no extra bits)
    far.code(1, 5)       # distance code 1 -> distance 2 (no extra bits)
    far.code(0, 7)       # end-of-block 256
    distance_far = far.bytes()
    try:
        zlib.decompress(distance_far, -15)
        raise AssertionError("distance-too-far fixture unexpectedly decoded")
    except zlib.error:
        pass

    parts = [
        zig_bytes("corrupt_bad_fcheck", bytes(bad_fcheck)),
        zig_bytes("corrupt_fdict", fdict),
        zig_bytes("corrupt_bad_adler", bytes(bad_adler)),
        zig_bytes("corrupt_truncated", truncated),
        zig_bytes("corrupt_bad_cm", bytes(bad_cm)),
        zig_bytes("corrupt_raw_truncated", raw_truncated),
        zig_bytes("corrupt_raw_reserved", b"\x07"),
        zig_bytes("corrupt_stored_mismatch", stored_mismatch),
        zig_bytes("corrupt_distance_far", distance_far),
    ]
    write_fixture("stdlib_deflate_corrupt_xmod", "\n\n".join(parts) + "\n",
                  CORRUPT_TEMPLATE, "deflate corrupt rejected\n")
    d = os.path.join(MATRIX, "stdlib_deflate_corrupt_xmod")
    with open(os.path.join(d, "expected_error.txt"), "w", newline="\n") as f:
        f.write(
            "Documentation only, not a harness pin: the stdlib harness reads\n"
            "expected.txt and expected.rc (both generated). This file is\n"
            "gitignored. The fixture catches error.Corrupt for every case\n"
            "(bad FCHECK, FDICT, bad Adler-32, truncated zlib, bad CM,\n"
            "truncated raw, reserved block type, stored LEN/NLEN mismatch,\n"
            "distance too far) and exits 0.\n"
        )


def main():
    build_basic()
    build_raw()
    build_dynamic()
    build_used()
    build_multiblock()
    build_toosmall()
    build_corrupt()


if __name__ == "__main__":
    main()
