// stdlib_chacha_poly_xmod — STDLIB std_cipher ChaCha20/Poly1305/AEAD GREEN fixture.
//
// std_cipher.zig is a PURE (no imports, no allocation) Z98 module; this fixture
// imports it by module basename and exercises:
//   - chacha20Init / chacha20Xor (RFC 8439 §2.3.2 block, §2.4.2 XOR)
//   - poly1305Init / Update / Final (RFC 8439 §2.5.2, streaming split)
//   - chacha20Poly1305Seal / Open (RFC 8439 §2.8.2)
//   - a tampered AEAD tag MUST return error.AuthenticationFailed
//
// GREEN (contract): deterministic byte-exact stdout `cipher chacha ok\n`
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

pub fn main() void {
    var key: [32]u8 = undefined;
    _ = unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", key[0..]);

    var nonce: [12]u8 = undefined;
    _ = unhex("000000090000004a00000000", nonce[0..]);
    var zero: [64]u8 = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) zero[i] = 0;

    var s = cipher.chacha20Init(&key, &nonce, 1);
    var block: [64]u8 = undefined;
    cipher.chacha20Xor(&s, block[0..], zero[0..]);
    ckHex(block[0..], "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e", "chacha block");

    _ = unhex("000000000000004a00000000", nonce[0..]);
    var pt: []const u8 = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
    var ct: [114]u8 = undefined;
    s = cipher.chacha20Init(&key, &nonce, 1);
    cipher.chacha20Xor(&s, ct[0..], pt[0..]);
    ckHex(ct[0..], "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d", "chacha xor");

    var pkey: [32]u8 = undefined;
    _ = unhex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b", pkey[0..]);
    var msg: []const u8 = "Cryptographic Forum Research Group";
    var tag: [16]u8 = undefined;
    var p = cipher.poly1305Init(&pkey);
    cipher.poly1305Update(&p, msg[0..]);
    cipher.poly1305Final(&p, &tag);
    ckHex(tag[0..], "a8061dc1305136c6c22b8baf0c0127a9", "poly1305");

    p = cipher.poly1305Init(&pkey);
    cipher.poly1305Update(&p, msg[0..7]);
    cipher.poly1305Update(&p, msg[7..19]);
    cipher.poly1305Update(&p, msg[19..]);
    cipher.poly1305Final(&p, &tag);
    ckHex(tag[0..], "a8061dc1305136c6c22b8baf0c0127a9", "poly1305 streaming");

    var akey: [32]u8 = undefined;
    _ = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f", akey[0..]);
    var anonce: [12]u8 = undefined;
    _ = unhex("070000004041424344454647", anonce[0..]);
    var ad: [12]u8 = undefined;
    _ = unhex("50515253c0c1c2c3c4c5c6c7", ad[0..]);
    var act: [114]u8 = undefined;
    var atag: [16]u8 = undefined;
    cipher.chacha20Poly1305Seal(&akey, &anonce, ad[0..], pt[0..], act[0..], &atag) catch {
        ck(false, "aead seal");
    };
    ckHex(act[0..], "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116", "aead ct");
    ckHex(atag[0..], "1ae10b594f09e26a7e902ecbd0600691", "aead tag");

    var out: [114]u8 = undefined;
    cipher.chacha20Poly1305Open(&akey, &anonce, ad[0..], act[0..], &atag, out[0..]) catch {
        ck(false, "aead open");
    };
    i = 0;
    while (i < pt.len) : (i += 1) ck(out[i] == pt[i], "aead plaintext");

    var bad: [16]u8 = undefined;
    i = 0;
    while (i < 16) : (i += 1) bad[i] = atag[i];
    bad[0] = bad[0] ^ 1;
    var saw: bool = false;
    cipher.chacha20Poly1305Open(&akey, &anonce, ad[0..], act[0..], &bad, out[0..]) catch |err| {
        ck(err == error.AuthenticationFailed, "aead tamper tag");
        saw = true;
    };
    ck(saw, "aead tamper tag");

    if (g_fail == 0) {
        std.io.write("cipher chacha ok\n");
    } else {
        std.io.write("cipher chacha FAIL\n");
    }
}
