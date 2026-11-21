// stdlib_aes_gcm_xmod — STDLIB std_cipher AES-128/GCM GREEN fixture.
//
// std_cipher.zig is a PURE (no imports, no allocation) Z98 module; this fixture
// imports it by module basename and exercises:
//   - aes128Init / aes128EncryptBlock (FIPS-197 Appendix C.1)
//   - aes128GcmSeal / Open over NIST GCM spec test cases 1-4
//     (empty PT/AD, empty AD, full block counts, non-empty AD)
//   - a tampered GCM tag MUST return error.AuthenticationFailed
//   - a seal leaves the caller arena's `used` unchanged (T-tables are const,
//     not stack/arena)
//
// GREEN (contract): deterministic byte-exact stdout `cipher aes gcm ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const cipher = @import("std_cipher.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn hexNib(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return c - 'A' + 10;
}

fn unhex(s: []const u8, out: []u8) usize {
    var i: usize = 0;
    while (i * 2 + 1 < s.len) : (i += 1) {
        out[i] = (hexNib(s[i * 2]) << 4) | hexNib(s[i * 2 + 1]);
    }
    return i;
}

fn ckHex(got: []const u8, hex: []const u8, what: []const u8) void {
    var want: [256]u8 = undefined;
    var n: usize = unhex(hex, want[0..]);
    ck(got.len == n, what);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn gcmCase(kh: []const u8, ih: []const u8, ah: []const u8, ph: []const u8, ch: []const u8, th: []const u8, what: []const u8) void {
    var key: [16]u8 = undefined;
    var iv: [12]u8 = undefined;
    var ad: [256]u8 = undefined;
    var pt: [256]u8 = undefined;
    var want_tag: [16]u8 = undefined;
    var got_ct: [256]u8 = undefined;
    var got_pt: [256]u8 = undefined;
    var tag: [16]u8 = undefined;
    _ = unhex(kh, key[0..]);
    _ = unhex(ih, iv[0..]);
    var an: usize = unhex(ah, ad[0..]);
    var pn: usize = unhex(ph, pt[0..]);
    _ = unhex(th, want_tag[0..]);

    cipher.aes128GcmSeal(&key, &iv, ad[0..an], pt[0..pn], got_ct[0..pn], &tag) catch {
        ck(false, what);
    };
    ckHex(got_ct[0..pn], ch, what);
    ckHex(tag[0..], th, what);

    cipher.aes128GcmOpen(&key, &iv, ad[0..an], got_ct[0..pn], &tag, got_pt[0..pn]) catch {
        ck(false, what);
    };
    var i: usize = 0;
    while (i < pn) : (i += 1) ck(got_pt[i] == pt[i], what);
}

pub fn main() void {
    var key: [16]u8 = undefined;
    var plain: [16]u8 = undefined;
    var want: [16]u8 = undefined;
    var out: [16]u8 = undefined;
    _ = unhex("000102030405060708090a0b0c0d0e0f", key[0..]);
    _ = unhex("00112233445566778899aabbccddeeff", plain[0..]);
    _ = unhex("69c4e0d86a7b0430d8cdb78070b4c55a", want[0..]);
    var a = cipher.aes128Init(&key);
    cipher.aes128EncryptBlock(&a, &plain, &out);
    var i: usize = 0;
    while (i < 16) : (i += 1) ck(out[i] == want[i], "aes block");

    gcmCase("00000000000000000000000000000000", "000000000000000000000000", "", "", "", "58e2fccefa7e3061367f1d57a4e7455a", "gcm 1");
    gcmCase("00000000000000000000000000000000", "000000000000000000000000", "", "00000000000000000000000000000000", "0388dace60b6a392f328c2b971b2fe78", "ab6e47d42cec13bdf53a67b21257bddf", "gcm 2");
    gcmCase("feffe9928665731c6d6a8f9467308308", "cafebabefacedbaddecaf888", "", "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255", "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985", "4d5c2af327cd64a62cf35abd2ba6fab4", "gcm 3");
    gcmCase("feffe9928665731c6d6a8f9467308308", "cafebabefacedbaddecaf888", "feedfacedeadbeeffeedfacedeadbeefabaddad2", "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39", "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091", "5bc94fbc3221a5db94fae95ae7121a47", "gcm 4");

    var abuf: [64]u8 = undefined;
    var ar = std.arena.init(abuf[0..]);
    var used0: usize = ar.used;
    var tkey: [16]u8 = undefined;
    var tiv: [12]u8 = undefined;
    var ttag: [16]u8 = undefined;
    var tct: [16]u8 = undefined;
    _ = unhex("00000000000000000000000000000000", tkey[0..]);
    _ = unhex("000000000000000000000000", tiv[0..]);
    cipher.aes128GcmSeal(&tkey, &tiv, ttag[0..0], tct[0..0], tct[0..0], &ttag) catch {
        ck(false, "gcm arena");
    };
    ck(ar.used == used0, "gcm arena");

    var bad: [16]u8 = undefined;
    _ = unhex("ab6e47d42cec13bdf53a67b21257bddf", bad[0..]);
    bad[15] = bad[15] ^ 1;
    var saw: bool = false;
    cipher.aes128GcmOpen(&tkey, &tiv, ttag[0..0], tct[0..0], &bad, tct[0..0]) catch |err| {
        ck(err == error.AuthenticationFailed, "gcm tamper tag");
        saw = true;
    };
    ck(saw, "gcm tamper tag");

    if (g_fail == 0) {
        std.io.write("cipher aes gcm ok\n");
    } else {
        std.io.write("cipher aes gcm FAIL\n");
    }
}
