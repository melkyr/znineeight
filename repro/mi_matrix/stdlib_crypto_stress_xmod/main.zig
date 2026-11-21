// stdlib_crypto_stress_xmod — STDLIB std_crypto (L5) hand-written stress table.
//
// No PRNG: the message is an explicit fixed pattern (`(i*31+7)%256`). Stresses:
//   - the RFC/FIPS normative KATs: SHA-1 (RFC 3174), SHA-256 (FIPS 180-4), MD5
//     (RFC 1321), CRC-32 (IEEE 802.3), for "abc", the empty input, and the
//     56-byte two-block message;
//   - streaming-vs-one-shot equality over many chunk splittings: every length
//     in a written table (0/1/2/3/55/56/57/63/64/65/119/120/127/128/129/200/
//     300/512) split one byte at a time, and the full 512-byte message split at
//     every chunk size in a written table (1/2/3/7/8/16/31/32/33/63/64/65/100/
//     127/128/129/256) — including the exact block boundaries 64 and 128.
//
// GREEN (contract): deterministic byte-exact stdout `crypto stress ok\n`
// (RUNRC=0).
const std = @import("std");
const crypto = @import("std_crypto.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn sha1One(msg: []const u8, out: *[20]u8) void {
    var s = crypto.sha1Init();
    crypto.sha1Update(&s, msg);
    crypto.sha1Final(&s, out);
}

fn sha1Chunk(msg: []const u8, chunk: usize, out: *[20]u8) void {
    var s = crypto.sha1Init();
    var i: usize = 0;
    while (i < msg.len) {
        var end: usize = i + chunk;
        if (end > msg.len) end = msg.len;
        crypto.sha1Update(&s, msg[i..end]);
        i = end;
    }
    crypto.sha1Final(&s, out);
}

fn sha256One(msg: []const u8, out: *[32]u8) void {
    var s = crypto.sha256Init();
    crypto.sha256Update(&s, msg);
    crypto.sha256Final(&s, out);
}

fn sha256Chunk(msg: []const u8, chunk: usize, out: *[32]u8) void {
    var s = crypto.sha256Init();
    var i: usize = 0;
    while (i < msg.len) {
        var end: usize = i + chunk;
        if (end > msg.len) end = msg.len;
        crypto.sha256Update(&s, msg[i..end]);
        i = end;
    }
    crypto.sha256Final(&s, out);
}

fn md5One(msg: []const u8, out: *[16]u8) void {
    var s = crypto.md5Init();
    crypto.md5Update(&s, msg);
    crypto.md5Final(&s, out);
}

fn md5Chunk(msg: []const u8, chunk: usize, out: *[16]u8) void {
    var s = crypto.md5Init();
    var i: usize = 0;
    while (i < msg.len) {
        var end: usize = i + chunk;
        if (end > msg.len) end = msg.len;
        crypto.md5Update(&s, msg[i..end]);
        i = end;
    }
    crypto.md5Final(&s, out);
}

fn crcOne(msg: []const u8) u32 {
    var c = crypto.crc32Init();
    c = crypto.crc32Update(c, msg);
    return crypto.crc32Final(c);
}

fn crcChunk(msg: []const u8, chunk: usize) u32 {
    var c = crypto.crc32Init();
    var i: usize = 0;
    while (i < msg.len) {
        var end: usize = i + chunk;
        if (end > msg.len) end = msg.len;
        c = crypto.crc32Update(c, msg[i..end]);
        i = end;
    }
    return crypto.crc32Final(c);
}

var g_msg: [512]u8 = undefined;

pub fn main() void {
    var abc: []const u8 = "abc";
    var empty: []const u8 = "";
    var long: []const u8 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";

    // ---- SHA-1 KATs (RFC 3174) ---------------------------------------------
    var s1_abc = [_]u8{
        0xa9, 0x99, 0x3e, 0x36, 0x47, 0x06, 0x81, 0x6a, 0xba, 0x3e,
        0x25, 0x71, 0x78, 0x50, 0xc2, 0x6c, 0x9c, 0xd0, 0xd8, 0x9d,
    };
    var s1_empty = [_]u8{
        0xda, 0x39, 0xa3, 0xee, 0x5e, 0x6b, 0x4b, 0x0d, 0x32, 0x55,
        0xbf, 0xef, 0x95, 0x60, 0x18, 0x90, 0xaf, 0xd8, 0x07, 0x09,
    };
    var s1_long = [_]u8{
        0x84, 0x98, 0x3e, 0x44, 0x1c, 0x3b, 0xd2, 0x6e, 0xba, 0xae,
        0x4a, 0xa1, 0xf9, 0x51, 0x29, 0xe5, 0xe5, 0x46, 0x70, 0xf1,
    };
    var d20: [20]u8 = undefined;
    sha1One(abc, &d20);
    ckBytes(d20[0..], s1_abc[0..], "sha1 abc");
    sha1One(empty, &d20);
    ckBytes(d20[0..], s1_empty[0..], "sha1 empty");
    sha1One(long, &d20);
    ckBytes(d20[0..], s1_long[0..], "sha1 long");

    // ---- SHA-256 KATs (FIPS 180-4) -----------------------------------------
    var s2_abc = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    var s2_empty = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    var s2_long = [_]u8{
        0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
        0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
        0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
        0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1,
    };
    var d32: [32]u8 = undefined;
    sha256One(abc, &d32);
    ckBytes(d32[0..], s2_abc[0..], "sha256 abc");
    sha256One(empty, &d32);
    ckBytes(d32[0..], s2_empty[0..], "sha256 empty");
    sha256One(long, &d32);
    ckBytes(d32[0..], s2_long[0..], "sha256 long");

    // ---- MD5 KATs (RFC 1321) -----------------------------------------------
    var m_abc = [_]u8{
        0x90, 0x01, 0x50, 0x98, 0x3c, 0xd2, 0x4f, 0xb0,
        0xd6, 0x96, 0x3f, 0x7d, 0x28, 0xe1, 0x7f, 0x72,
    };
    var m_empty = [_]u8{
        0xd4, 0x1d, 0x8c, 0xd9, 0x8f, 0x00, 0xb2, 0x04,
        0xe9, 0x80, 0x09, 0x98, 0xec, 0xf8, 0x42, 0x7e,
    };
    var m_long = [_]u8{
        0x82, 0x15, 0xef, 0x07, 0x96, 0xa2, 0x0b, 0xca,
        0xaa, 0xe1, 0x16, 0xd3, 0x87, 0x6c, 0x66, 0x4a,
    };
    var d16: [16]u8 = undefined;
    md5One(abc, &d16);
    ckBytes(d16[0..], m_abc[0..], "md5 abc");
    md5One(empty, &d16);
    ckBytes(d16[0..], m_empty[0..], "md5 empty");
    md5One(long, &d16);
    ckBytes(d16[0..], m_long[0..], "md5 long");

    // ---- CRC-32 KATs (IEEE 802.3) ------------------------------------------
    var check: []const u8 = "123456789";
    ck(crcOne(check) == 0xCBF43926, "crc32 123456789");
    ck(crcOne(empty) == 0x00000000, "crc32 empty");

    // ---- streaming-vs-one-shot over a written length table -----------------
    var lens = [_]usize{ 0, 1, 2, 3, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 200, 300, 512 };
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        g_msg[i] = @intCast(u8, (i * 31 + 7) % 256);
    }
    var li: usize = 0;
    while (li < lens.len) : (li += 1) {
        var n: usize = lens[li];
        var one20: [20]u8 = undefined;
        var one32: [32]u8 = undefined;
        var one16: [16]u8 = undefined;
        sha1One(g_msg[0..n], &one20);
        sha256One(g_msg[0..n], &one32);
        md5One(g_msg[0..n], &one16);
        var onec = crcOne(g_msg[0..n]);
        var st20: [20]u8 = undefined;
        var st32: [32]u8 = undefined;
        var st16: [16]u8 = undefined;
        sha1Chunk(g_msg[0..n], 1, &st20);
        sha256Chunk(g_msg[0..n], 1, &st32);
        md5Chunk(g_msg[0..n], 1, &st16);
        var stc = crcChunk(g_msg[0..n], 1);
        ckBytes(st20[0..], one20[0..], "sha1 1-byte stream");
        ckBytes(st32[0..], one32[0..], "sha256 1-byte stream");
        ckBytes(st16[0..], one16[0..], "md5 1-byte stream");
        ck(stc == onec, "crc32 1-byte stream");
    }

    // ---- many chunk sizes on the full 512-byte message ---------------------
    var chunks = [_]usize{ 1, 2, 3, 7, 8, 16, 31, 32, 33, 63, 64, 65, 100, 127, 128, 129, 256 };
    var one20: [20]u8 = undefined;
    var one32: [32]u8 = undefined;
    var one16: [16]u8 = undefined;
    sha1One(g_msg[0..512], &one20);
    sha256One(g_msg[0..512], &one32);
    md5One(g_msg[0..512], &one16);
    var onec = crcOne(g_msg[0..512]);
    var ci: usize = 0;
    while (ci < chunks.len) : (ci += 1) {
        var ch: usize = chunks[ci];
        var st20: [20]u8 = undefined;
        var st32: [32]u8 = undefined;
        var st16: [16]u8 = undefined;
        sha1Chunk(g_msg[0..512], ch, &st20);
        sha256Chunk(g_msg[0..512], ch, &st32);
        md5Chunk(g_msg[0..512], ch, &st16);
        var stc = crcChunk(g_msg[0..512], ch);
        ckBytes(st20[0..], one20[0..], "sha1 chunk stream");
        ckBytes(st32[0..], one32[0..], "sha256 chunk stream");
        ckBytes(st16[0..], one16[0..], "md5 chunk stream");
        ck(stc == onec, "crc32 chunk stream");
    }

    // ---- empty-input streaming equals the empty one-shot -------------------
    var o20: [20]u8 = undefined;
    var o32: [32]u8 = undefined;
    var o16: [16]u8 = undefined;
    var e20: [20]u8 = undefined;
    var e32: [32]u8 = undefined;
    var e16: [16]u8 = undefined;
    sha1One(empty, &o20);
    sha1Chunk(empty, 1, &e20);
    ckBytes(e20[0..], o20[0..], "sha1 empty stream");
    sha256One(empty, &o32);
    sha256Chunk(empty, 1, &e32);
    ckBytes(e32[0..], o32[0..], "sha256 empty stream");
    md5One(empty, &o16);
    md5Chunk(empty, 1, &e16);
    ckBytes(e16[0..], o16[0..], "md5 empty stream");
    ck(crcChunk(empty, 1) == crcOne(empty), "crc32 empty stream");

    if (g_fail == 0) {
        std.io.write("crypto stress ok\n");
    } else {
        std.io.write("crypto stress FAIL\n");
    }
}
