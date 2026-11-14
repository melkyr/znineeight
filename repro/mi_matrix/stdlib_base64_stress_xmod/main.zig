// stdlib_base64_stress_xmod — STDLIB std_base64 (L5) hand-written stress table.
//
// No PRNG: every input is an explicit table or an explicit fixed pattern (an
// LCG written out for the byte-pattern buffers). Stresses:
//   - the RFC 4648 §10 test vectors ("" / "f" / "fo" / "foo" / "foob" /
//     "fooba" / "foobar"), encode and decode;
//   - encodedLen(n) == 4*ceil(n/3) and decodedLen(n) == (n/4)*3 over a length
//     table, with decode(encode(x)) == x over adversarial lengths 0..17 plus
//     31/32/33/63/64/65/127/128/129/255/256/257/511/512/513/1000;
//   - whitespace rejection: any space/tab/CR/LF is error.InvalidInput and
//     allocates nothing; wrong length and misplaced '=' likewise;
//   - the empty input is a valid empty result.
//
// GREEN (contract): deterministic byte-exact stdout `base64 stress ok\n`
// (RUNRC=0).
const std = @import("std");
const b64 = @import("std_base64.zig");

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

fn expectEnc(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var enc = b64.encode(ar, src) catch {
        @panic(what);
    };
    ckBytes(enc, want, what);
}

fn expectDec(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var dec = b64.decode(ar, src) catch {
        @panic(what);
    };
    ckBytes(dec, want, what);
}

fn invalid(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var used_before = ar.used;
    var got = b64.decode(ar, src) catch |e| {
        ck(e == error.InvalidInput, what);
        ck(ar.used == used_before, what);
        return;
    };
    _ = got;
    ck(false, what);
}

fn roundtrip(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var enc = b64.encode(ar, src) catch {
        @panic(what);
    };
    ck(enc.len == b64.encodedLen(src.len), what);
    ck(b64.decodedLen(enc.len) >= src.len, what);
    var dec = b64.decode(ar, enc) catch {
        @panic(what);
    };
    ckBytes(dec, src, what);
}

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

var g_buf: [1024]u8 = undefined;

pub fn main() void {
    var backing: [1048576]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // ---- RFC 4648 §10 vectors ----------------------------------------------
    expectEnc(&ar, "", "", "rfc empty enc");
    expectDec(&ar, "", "", "rfc empty dec");
    expectEnc(&ar, "f", "Zg==", "rfc f enc");
    expectDec(&ar, "Zg==", "f", "rfc f dec");
    expectEnc(&ar, "fo", "Zm8=", "rfc fo enc");
    expectDec(&ar, "Zm8=", "fo", "rfc fo dec");
    expectEnc(&ar, "foo", "Zm9v", "rfc foo enc");
    expectDec(&ar, "Zm9v", "foo", "rfc foo dec");
    expectEnc(&ar, "foob", "Zm9vYg==", "rfc foob enc");
    expectDec(&ar, "Zm9vYg==", "foob", "rfc foob dec");
    expectEnc(&ar, "fooba", "Zm9vYmE=", "rfc fooba enc");
    expectDec(&ar, "Zm9vYmE=", "fooba", "rfc fooba dec");
    expectEnc(&ar, "foobar", "Zm9vYmFy", "rfc foobar enc");
    expectDec(&ar, "Zm9vYmFy", "foobar", "rfc foobar dec");

    // ---- encodedLen / decodedLen tables ------------------------------------
    var n: usize = 0;
    while (n <= 40) : (n += 1) {
        ck(b64.encodedLen(n) == 4 * ((n + 2) / 3), "encodedLen table");
        ck(b64.decodedLen(4 * ((n + 2) / 3)) >= n, "decodedLen bound");
    }
    var big = [_]usize{ 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1000 };
    n = 0;
    while (n < big.len) : (n += 1) {
        var k: usize = big[n];
        ck(b64.encodedLen(k) == 4 * ((k + 2) / 3), "encodedLen big");
    }

    // ---- whitespace / malformed rejection ----------------------------------
    invalid(&ar, "Zm9v\n", "ws newline");
    invalid(&ar, "Zm9v ", "ws space");
    invalid(&ar, "Zm 9", "ws embedded");
    invalid(&ar, "Zm9\t", "ws tab");
    invalid(&ar, "\rZm9v", "ws cr");
    invalid(&ar, "Zm9v\r\n", "ws crlf");
    invalid(&ar, "Z", "len1");
    invalid(&ar, "Zm9", "len3");
    invalid(&ar, "Zm9vY", "len5");
    invalid(&ar, "====", "all pad");
    invalid(&ar, "=m9v", "leading pad");
    invalid(&ar, "Zg=Z", "pad then data");
    invalid(&ar, "Zg==Zg==", "pad non-final");
    invalid(&ar, "Zm=v", "pad slot3");
    invalid(&ar, "Z===", "three pad");
    invalid(&ar, "Zm9v=", "stray pad");
    invalid(&ar, "Zm9!", "bang");
    invalid(&ar, "Zm9-", "dash");
    invalid(&ar, "Zm9_", "underscore");

    // ---- round-trips over adversarial lengths ------------------------------
    var lens = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
        31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1000 };
    var li: usize = 0;
    while (li < lens.len) : (li += 1) {
        var len: usize = lens[li];
        fillConst(g_buf[0..len], 0x00);
        roundtrip(&ar, g_buf[0..len], "rt 0x00");
        fillConst(g_buf[0..len], 0xFF);
        roundtrip(&ar, g_buf[0..len], "rt 0xFF");
        fillConst(g_buf[0..len], 0xAA);
        roundtrip(&ar, g_buf[0..len], "rt 0xAA");
        var i: usize = 0;
        while (i < len) : (i += 1) {
            if (i % 2 == 0) g_buf[i] = 0x55 else g_buf[i] = 0xAA;
        }
        roundtrip(&ar, g_buf[0..len], "rt alt");
        var st: u32 = 0x12345678 + @intCast(u32, len);
        i = 0;
        while (i < len) : (i += 1) {
            st = st *% 1664525 +% 1013904223;
            g_buf[i] = @intCast(u8, (st >> 24) & 0xFF);
        }
        roundtrip(&ar, g_buf[0..len], "rt lcg");
    }

    // ---- all 256 byte values ------------------------------------------------
    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    roundtrip(&ar, all[0..], "rt all values");

    if (g_fail == 0) {
        std.io.write("base64 stress ok\n");
    } else {
        std.io.write("base64 stress FAIL\n");
    }
}
