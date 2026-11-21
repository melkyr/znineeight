// stdlib_tls_record_xmod — STDLIB std_tls record layer GREEN fixture (M4 T1).
//
// std_tls.zig is the new pure record layer. This fixture pins:
//   - 5-byte record encode/decode (type, version, 16-bit length)
//   - plaintext cap 16384, wire-payload cap 16408; exact AES-GCM (16408) and
//     ChaCha20-Poly1305 (16400) boundaries, one-over rejects on both limits
//   - RecordReader incremental input buffering: fragmented header/payload and
//     a clean-close error.Closed / truncated-close error.Corrupt
//   - AES-128-GCM (RFC 5288): fixed_iv || explicit seq, explicit nonce on the
//     wire; canned ciphertext for seq 0 and 7, with AAD and empty AAD
//   - ChaCha20-Poly1305 (RFC 7905): nonce = (0x00^4 || seq_be64) XOR fixed_iv;
//     canned ciphertext for seq 0 and 7, with AAD and empty AAD
//   - tamper -> error.AuthenticationFailed, malformed record -> error.Corrupt
//
// GREEN (contract): deterministic byte-exact stdout `tls record ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");

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
    var want: [512]u8 = undefined;
    const n = unhex(hex, want[0..]);
    ck(got.len == n, what);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len and i < want.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn aesSuite() tls.CipherSuite {
    return tls.CipherSuite.ecdsa_aes_128_gcm_sha256;
}

fn chachaSuite() tls.CipherSuite {
    return tls.CipherSuite.ecdsa_chacha20_poly1305_sha256;
}

fn checkHeaderAndFragments() void {
    var pt: []const u8 = "TLS record KAT";
    var enc: [64]u8 = undefined;
    const n = tls.encodeRecord(tls.content_application_data, tls.TLS_VERSION_12, pt[0..], enc[0..]) catch @panic("encode");
    ck(n == 5 + pt.len, "encode length");
    ckHex(enc[0..n], "170303000e544c53207265636f7264204b4154", "encode bytes");

    var hdr: tls.RecordHeader = undefined;
    var frag: []const u8 = undefined;
    tls.decodeRecord(enc[0..n], &hdr, &frag) catch @panic("decode");
    ck(hdr.content_type == tls.content_application_data, "decode type");
    ck(hdr.version == tls.TLS_VERSION_12, "decode version");
    ck(hdr.length == @intCast(u16, pt.len), "decode length");
    ckBytes(frag, pt, "decode fragment");

    var big: [tls.TLS_MAX_WIRE_RECORD + 1]u8 = undefined;
    var out: [16]u8 = undefined;
    var saw: bool = false;
    _ = tls.encodeRecord(tls.content_handshake, tls.TLS_VERSION_12, big[0..], out[0..]) catch |e| {
        ck(e == error.RecordTooLarge, "encode too large");
        saw = true;
    };
    ck(saw, "encode too large");

    var huge: [5]u8 = undefined;
    _ = unhex("1703034019", huge[0..]); // 16409 = wire cap + 1
    saw = false;
    tls.parseRecordHeader(huge[0..]) catch |e| {
        ck(e == error.RecordTooLarge, "header too large");
        saw = true;
    };
    ck(saw, "header too large");
}

fn fillPattern(buf: []u8, seed: u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @intCast(u8, (i + @intCast(usize, seed)) & 0xFF);
    }
}

fn checkRecordLimits() void {
    var plain: [tls.TLS_MAX_PLAINTEXT_RECORD]u8 = undefined;
    var over: [tls.TLS_MAX_PLAINTEXT_RECORD + 1]u8 = undefined;
    var wire: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var framed: [tls.TLS_MAX_WIRE_RECORD + tls.RECORD_HEADER_LEN]u8 = undefined;
    var recovered: [tls.TLS_MAX_PLAINTEXT_RECORD]u8 = undefined;
    fillPattern(plain[0..], 1);
    fillPattern(over[0..], 2);

    var aes_key: [16]u8 = undefined;
    var aes_iv: [4]u8 = undefined;
    fillPattern(aes_key[0..], 3);
    fillPattern(aes_iv[0..], 4);
    var n = tls.protectRecord(aesSuite(), aes_key[0..], aes_iv[0..], 0,
        tls.content_application_data, tls.TLS_VERSION_12, plain[0..], wire[0..]) catch @panic("aes max protect");
    ck(n == tls.TLS_MAX_WIRE_RECORD, "aes wire boundary");
    const framed_len = tls.encodeRecord(tls.content_application_data, tls.TLS_VERSION_12, wire[0..n], framed[0..]) catch @panic("aes max encode");
    ck(framed_len == tls.RECORD_HEADER_LEN + tls.TLS_MAX_WIRE_RECORD, "aes framed boundary");
    var hdr: tls.RecordHeader = undefined;
    var frag: []const u8 = undefined;
    tls.decodeRecord(framed[0..framed_len], &hdr, &frag) catch @panic("aes max decode");
    ck(hdr.length == @intCast(u16, tls.TLS_MAX_WIRE_RECORD), "aes header boundary");
    ck(frag.len == tls.TLS_MAX_WIRE_RECORD, "aes wire decode length");
    const m = tls.unprotectRecord(aesSuite(), aes_key[0..], aes_iv[0..], 0,
        tls.content_application_data, tls.TLS_VERSION_12, wire[0..n], recovered[0..]) catch @panic("aes max unprotect");
    ck(m == tls.TLS_MAX_PLAINTEXT_RECORD, "aes recovered boundary");
    ckBytes(recovered[0..], plain[0..], "aes recovered bytes");

    var saw: bool = false;
    _ = tls.protectRecord(aesSuite(), aes_key[0..], aes_iv[0..], 0,
        tls.content_application_data, tls.TLS_VERSION_12, over[0..], wire[0..]) catch |e| {
        ck(e == error.RecordTooLarge, "aes plaintext over boundary");
        saw = true;
    };
    ck(saw, "aes plaintext over boundary");

    var ch_key: [32]u8 = undefined;
    var ch_iv: [12]u8 = undefined;
    fillPattern(ch_key[0..], 5);
    fillPattern(ch_iv[0..], 6);
    n = tls.protectRecord(chachaSuite(), ch_key[0..], ch_iv[0..], 0,
        tls.content_application_data, tls.TLS_VERSION_12, plain[0..], wire[0..]) catch @panic("chacha max protect");
    ck(n == tls.TLS_MAX_PLAINTEXT_RECORD + 16, "chacha wire boundary");
    const ch_framed_len = tls.encodeRecord(tls.content_application_data, tls.TLS_VERSION_12, wire[0..n], framed[0..]) catch @panic("chacha max encode");
    ck(ch_framed_len == tls.RECORD_HEADER_LEN + n, "chacha framed boundary");
    tls.decodeRecord(framed[0..ch_framed_len], &hdr, &frag) catch @panic("chacha max decode");
    ck(hdr.length == @intCast(u16, n), "chacha header boundary");
    const ch_m = tls.unprotectRecord(chachaSuite(), ch_key[0..], ch_iv[0..], 0,
        tls.content_application_data, tls.TLS_VERSION_12, wire[0..n], recovered[0..]) catch @panic("chacha max unprotect");
    ck(ch_m == tls.TLS_MAX_PLAINTEXT_RECORD, "chacha recovered boundary");
    ckBytes(recovered[0..], plain[0..], "chacha recovered bytes");

    saw = false;
    _ = tls.protectRecord(chachaSuite(), ch_key[0..], ch_iv[0..], 0,
        tls.content_application_data, tls.TLS_VERSION_12, over[0..], wire[0..]) catch |e| {
        ck(e == error.RecordTooLarge, "chacha plaintext over boundary");
        saw = true;
    };
    ck(saw, "chacha plaintext over boundary");
}

fn checkFragmentedReader() void {
    var r1: [16]u8 = undefined;
    const n1 = tls.encodeRecord(tls.content_handshake, tls.TLS_VERSION_12, "abcdef", r1[0..]) catch @panic("enc1");
    var r2: [16]u8 = undefined;
    const n2 = tls.encodeRecord(tls.content_application_data, tls.TLS_VERSION_12, "xyz", r2[0..]) catch @panic("enc2");
    var joined: [64]u8 = undefined;
    var i: usize = 0;
    while (i < n1) : (i += 1) joined[i] = r1[i];
    i = 0;
    while (i < n2) : (i += 1) joined[n1 + i] = r2[i];

    var r = tls.RecordReader{ .buf = undefined, .start = 0, .len = 0, .closed = false };
    tls.readerInit(&r);
    tls.readerAppend(&r, joined[0..2]) catch @panic("append1");
    var hdr: tls.RecordHeader = undefined;
    var frag: []const u8 = undefined;
    var more = tls.readerNext(&r, &hdr, &frag) catch @panic("next1");
    ck(!more, "fragment header partial");

    tls.readerAppend(&r, joined[2..5]) catch @panic("append2");
    more = tls.readerNext(&r, &hdr, &frag) catch @panic("next2");
    ck(!more, "fragment payload partial");

    tls.readerAppend(&r, joined[5..n1]) catch @panic("append3");
    more = tls.readerNext(&r, &hdr, &frag) catch @panic("next3");
    ck(more, "fragment record1");
    ck(hdr.content_type == tls.content_handshake, "fragment type1");
    ckBytes(frag, "abcdef", "fragment payload1");

    tls.readerAppend(&r, joined[n1 .. n1 + n2]) catch @panic("append4");
    more = tls.readerNext(&r, &hdr, &frag) catch @panic("next4");
    ck(more, "fragment record2");
    ck(hdr.content_type == tls.content_application_data, "fragment type2");
    ckBytes(frag, "xyz", "fragment payload2");

    more = tls.readerNext(&r, &hdr, &frag) catch @panic("next5");
    ck(!more, "fragment no more");

    tls.readerMarkClosed(&r);
    var saw: bool = false;
    _ = tls.readerNext(&r, &hdr, &frag) catch |e| {
        ck(e == error.Closed, "reader clean closed");
        saw = true;
    };
    ck(saw, "reader clean closed");

    var tr = tls.RecordReader{ .buf = undefined, .start = 0, .len = 0, .closed = false };
    tls.readerInit(&tr);
    tls.readerAppend(&tr, joined[0..3]) catch @panic("append trunc");
    tls.readerMarkClosed(&tr);
    saw = false;
    _ = tls.readerNext(&tr, &hdr, &frag) catch |e| {
        ck(e == error.Corrupt, "reader truncated");
        saw = true;
    };
    ck(saw, "reader truncated");
}

fn aesRecordKats() void {
    var key: [16]u8 = undefined;
    _ = unhex("000102030405060708090a0b0c0d0e0f", key[0..]);
    var fixed_iv: [4]u8 = undefined;
    _ = unhex("a1a2a3a4", fixed_iv[0..]);
    var pt: []const u8 = "TLS record KAT";

    var out: [128]u8 = undefined;
    var plain: [64]u8 = undefined;

    var n = tls.protectRecord(aesSuite(), key[0..], fixed_iv[0..], 0, tls.content_application_data, tls.TLS_VERSION_12, pt[0..], out[0..]) catch @panic("aes protect 0");
    ckHex(out[0..n], "000000000000000065ffd41d2a037dcb42abbeade1b983e3e472c61b9cb2bbff6c153a191740", "aes seq0");
    var m = tls.unprotectRecord(aesSuite(), key[0..], fixed_iv[0..], 0, tls.content_application_data, tls.TLS_VERSION_12, out[0..n], plain[0..]) catch @panic("aes unprotect 0");
    ckBytes(plain[0..m], pt, "aes seq0 plaintext");

    n = tls.protectRecord(aesSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, pt[0..], out[0..]) catch @panic("aes protect 7");
    ckHex(out[0..n], "0000000000000007b11c8ff1e9792d26d38c6a631de2ee20c2e3b0e2e5b86f6472bdd0c426e2", "aes seq7");
    m = tls.unprotectRecord(aesSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, out[0..n], plain[0..]) catch @panic("aes unprotect 7");
    ckBytes(plain[0..m], pt, "aes seq7 plaintext");

    var bad: [128]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) bad[i] = out[i];
    bad[n - 1] = bad[n - 1] ^ 1;
    var saw: bool = false;
    _ = tls.unprotectRecord(aesSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, bad[0..n], plain[0..]) catch |e| {
        ck(e == error.AuthenticationFailed, "aes tamper tag");
        saw = true;
    };
    ck(saw, "aes tamper tag");

    saw = false;
    _ = tls.unprotectRecord(aesSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, out[0..8], plain[0..]) catch |e| {
        ck(e == error.Corrupt, "aes malformed");
        saw = true;
    };
    ck(saw, "aes malformed");

    var nonce: [12]u8 = undefined;
    var ct: [64]u8 = undefined;
    var tag: [16]u8 = undefined;
    var empty: []const u8 = "";
    tls.recordNonce(aesSuite(), fixed_iv[0..], 0, &nonce) catch @panic("aes nonce0");
    tls.sealFragment(aesSuite(), key[0..], &nonce, empty, pt[0..], ct[0..pt.len], &tag) catch @panic("aes seal noaad0");
    ckHex(ct[0..pt.len], "65ffd41d2a037dcb42abbeade1b9", "aes noaad ct0");
    ckHex(tag[0..], "7f659e5e81b48bcca814ddb632013898", "aes noaad tag0");
    tls.recordNonce(aesSuite(), fixed_iv[0..], 7, &nonce) catch @panic("aes nonce7");
    tls.sealFragment(aesSuite(), key[0..], &nonce, empty, pt[0..], ct[0..pt.len], &tag) catch @panic("aes seal noaad7");
    ckHex(ct[0..pt.len], "b11c8ff1e9792d26d38c6a631de2", "aes noaad ct7");
    ckHex(tag[0..], "bdf435cdf524a30b6d6b54d68ca7ae78", "aes noaad tag7");
}

fn chachaRecordKats() void {
    var key: [32]u8 = undefined;
    _ = unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", key[0..]);
    var fixed_iv: [12]u8 = undefined;
    _ = unhex("b0b1b2b3b4b5b6b7b8b9babb", fixed_iv[0..]);
    var pt: []const u8 = "TLS record KAT";

    var out: [128]u8 = undefined;
    var plain: [64]u8 = undefined;

    var n = tls.protectRecord(chachaSuite(), key[0..], fixed_iv[0..], 0, tls.content_application_data, tls.TLS_VERSION_12, pt[0..], out[0..]) catch @panic("chacha protect 0");
    ckHex(out[0..n], "c33172888f8deae83112b6cdee1eada65c0184ed8dbc3d9fe39fc87dae77", "chacha seq0");
    var m = tls.unprotectRecord(chachaSuite(), key[0..], fixed_iv[0..], 0, tls.content_application_data, tls.TLS_VERSION_12, out[0..n], plain[0..]) catch @panic("chacha unprotect 0");
    ckBytes(plain[0..m], pt, "chacha seq0 plaintext");

    n = tls.protectRecord(chachaSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, pt[0..], out[0..]) catch @panic("chacha protect 7");
    ckHex(out[0..n], "fada2356dea6d985f3ea97fa4edf201cd245476c76210a30dd6d8278994c", "chacha seq7");
    m = tls.unprotectRecord(chachaSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, out[0..n], plain[0..]) catch @panic("chacha unprotect 7");
    ckBytes(plain[0..m], pt, "chacha seq7 plaintext");

    var bad: [128]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) bad[i] = out[i];
    bad[n - 1] = bad[n - 1] ^ 1;
    var saw: bool = false;
    _ = tls.unprotectRecord(chachaSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, bad[0..n], plain[0..]) catch |e| {
        ck(e == error.AuthenticationFailed, "chacha tamper tag");
        saw = true;
    };
    ck(saw, "chacha tamper tag");

    saw = false;
    _ = tls.unprotectRecord(chachaSuite(), key[0..], fixed_iv[0..], 7, tls.content_application_data, tls.TLS_VERSION_12, out[0..8], plain[0..]) catch |e| {
        ck(e == error.Corrupt, "chacha malformed");
        saw = true;
    };
    ck(saw, "chacha malformed");

    var nonce: [12]u8 = undefined;
    var ct: [64]u8 = undefined;
    var tag: [16]u8 = undefined;
    var empty: []const u8 = "";
    tls.recordNonce(chachaSuite(), fixed_iv[0..], 0, &nonce) catch @panic("chacha nonce0");
    tls.sealFragment(chachaSuite(), key[0..], &nonce, empty, pt[0..], ct[0..pt.len], &tag) catch @panic("chacha seal noaad0");
    ckHex(ct[0..pt.len], "c33172888f8deae83112b6cdee1e", "chacha noaad ct0");
    ckHex(tag[0..], "301813796662393393141cd4042fad30", "chacha noaad tag0");
    tls.recordNonce(chachaSuite(), fixed_iv[0..], 7, &nonce) catch @panic("chacha nonce7");
    tls.sealFragment(chachaSuite(), key[0..], &nonce, empty, pt[0..], ct[0..pt.len], &tag) catch @panic("chacha seal noaad7");
    ckHex(ct[0..pt.len], "fada2356dea6d985f3ea97fa4edf", "chacha noaad ct7");
    ckHex(tag[0..], "9667139e84b6681b81e1f20699a4923e", "chacha noaad tag7");
}

pub fn main() void {
    checkHeaderAndFragments();
    checkRecordLimits();
    checkFragmentedReader();
    aesRecordKats();
    chachaRecordKats();

    if (g_fail == 0) {
        std.io.write("tls record ok\n");
    } else {
        std.io.write("tls record FAIL\n");
    }
}
