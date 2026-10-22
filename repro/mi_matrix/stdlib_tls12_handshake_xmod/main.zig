// stdlib_tls12_handshake_xmod — STDLIB std_tls TLS 1.2 client handshake (M4 T2).
//
// Canned server transcripts were captured from host `openssl s_server` with a
// deterministic client RNG seed, so replaying the same seed reproduces the
// exact ClientHello/ClientKeyExchange/Finished bytes and therefore the same
// transcript hash and key schedule.
//
// Scenarios:
//   - ECDHE-ECDSA / AES-128-GCM-SHA256, whole server flight in sized chunks
//   - ECDHE-RSA / CHACHA20-POLY1305-SHA256
//   - ECDHE-x25519 / AES-128-GCM-SHA256
//   - ECDHE-ECDSA / AES-128-GCM-SHA256 with a >16 KiB Certificate message
//     split across two TLS records (asserts multi-record reassembly)
//   - ECDHE-ECDSA replay fed one byte at a time, asserting the meaningful
//     action sequence: ClientHello send, client-flight send, established
//   - negative: flip a byte in the server Finished record -> HandshakeFailed
//   - negative: flip the ServerKeyExchange signature -> HandshakeFailed
//   - negative: now_unix past the leaf/anchor validity -> CertificateExpired
//   - negative: hostname with no SAN match -> HostnameMismatch
//   - regression: short tlsWrite output -> OutputTooSmall with no bytes,
//     sequence advance, or stream corruption; retry then succeeds
//
// GREEN (contract): deterministic byte-exact stdout `tls handshake ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const ecdsa_aes = @import("ecdsa_aes_data.zig");
const rsa_chacha = @import("rsa_chacha_data.zig");
const x25519_data = @import("x25519_data.zig");
const big_cert = @import("big_cert_data.zig");

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
    while (i < got.len and i < want.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

const Scenario = struct {
    seed: u64,
    hostname: []const u8,
    now_unix: i64,
    store_bin: []const u8,
    server_raw: []const u8,
    client_hello: []const u8,
    client_flight: []const u8,
    app_plain: []const u8,
    finished_record_end: usize,
};

const DriveResult = struct { sends: usize, established: bool };

const TranscriptInfo = struct {
    cert_message_len: usize,
    cert_record_fragments: usize,
    ske_sig_offset: usize,
};

var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;

fn load16(in: []const u8, off: usize) usize {
    return (@intCast(usize, in[off]) << 8) | @intCast(usize, in[off + 1]);
}

fn load24(in: []const u8, off: usize) usize {
    return (@intCast(usize, in[off]) << 16) |
        (@intCast(usize, in[off + 1]) << 8) |
        @intCast(usize, in[off + 2]);
}

// Independent record/handshake walk over the canned server bytes. It proves
// the Certificate message really spans multiple TLS records (rather than only
// being split across driver input chunks) and locates the SKE signature byte.
fn scanTranscript(raw: []const u8) TranscriptInfo {
    var info = TranscriptInfo{
        .cert_message_len = 0,
        .cert_record_fragments = 0,
        .ske_sig_offset = 0,
    };
    var hs: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    var hs_rec: [tls.TLS_HANDSHAKE_MAX]u32 = undefined;
    var hs_off: [tls.TLS_HANDSHAKE_MAX]usize = undefined;
    var hs_len: usize = 0;
    var pos: usize = 0;
    var record_no: u32 = 0;

    while (pos + 5 <= raw.len) {
        const ctype = raw[pos];
        const rlen = load16(raw, pos + 3);
        const end = pos + 5 + rlen;
        if (end > raw.len) break;
        if (ctype == tls.content_handshake) {
            ck(hs_len + rlen <= hs.len, "scanner handshake buffer");
            var i: usize = 0;
            while (i < rlen) : (i += 1) {
                hs[hs_len] = raw[pos + 5 + i];
                hs_rec[hs_len] = record_no;
                hs_off[hs_len] = pos + 5 + i;
                hs_len += 1;
            }
            while (hs_len >= 4) {
                const mlen = load24(hs[0..], 1);
                const total = 4 + mlen;
                if (hs_len < total) break;
                if (hs[0] == 11) {
                    info.cert_message_len = mlen;
                    var frags: usize = 1;
                    var k: usize = 1;
                    while (k < total) : (k += 1) {
                        if (hs_rec[k] != hs_rec[k - 1]) frags += 1;
                    }
                    info.cert_record_fragments = frags;
                } else if (hs[0] == 12) {
                    info.ske_sig_offset = hs_off[total - 1];
                }
                var m: usize = 0;
                while (total + m < hs_len) : (m += 1) {
                    hs[m] = hs[total + m];
                    hs_rec[m] = hs_rec[total + m];
                    hs_off[m] = hs_off[total + m];
                }
                hs_len -= total;
            }
        }
        pos = end;
        record_no += 1;
    }
    return info;
}

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn drive(s: Scenario, chunk: usize, mutate_finished: bool, mutate_ske: bool, check_client: bool) !DriveResult {
    var server_buf: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    ck(s.server_raw.len <= server_buf.len, "server transcript fits");
    copyInto(server_buf[0..s.server_raw.len], s.server_raw[0..]);
    if (mutate_finished) {
        ck(s.finished_record_end > 0 and s.finished_record_end <= s.server_raw.len, "finished offset");
        server_buf[s.finished_record_end - 1] = server_buf[s.finished_record_end - 1] ^ 1;
    }
    if (mutate_ske) {
        const info = scanTranscript(s.server_raw[0..]);
        ck(info.ske_sig_offset > 0 and info.ske_sig_offset < s.server_raw.len, "ske signature offset");
        server_buf[info.ske_sig_offset] = server_buf[info.ske_sig_offset] ^ 1;
    }

    var arena = std.arena.init(g_store_arena_buf[0..]);
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&arena, s.store_bin[0..], &store) catch @panic("store load");

    var rng = rand.xoshiroInit(s.seed);
    var cfg = tls.TlsConfig{
        .hostname = s.hostname[0..],
        .store = &store,
        .rng = &rng,
        .now_unix = s.now_unix,
        .min_version = tls.TLS_VERSION_12,
        .max_version = tls.TLS_VERSION_12,
    };
    tls.tlsInit(&g_session, &cfg);

    var out: [8192]u8 = undefined;
    var sends: usize = 0;

    const first = try tls.tlsStep(&g_session, "", out[0..]);
    switch (first) {
        .send => |bytes| {
            sends += 1;
            if (check_client) ckBytes(bytes, s.client_hello[0..], "client hello bytes");
        },
        else => return error.BadAction,
    }

    var pos: usize = 0;
    var established: bool = false;
    var app_buf: [tls.TLS_MAX_RECORD]u8 = undefined;
    var app_len: usize = 0;

    while (pos < s.server_raw.len or !established) {
        var input: []const u8 = "";
        if (pos < s.server_raw.len) {
            var take: usize = chunk;
            if (take > s.server_raw.len - pos) take = s.server_raw.len - pos;
            input = server_buf[pos .. pos + take];
            pos += take;
        }

        const act = try tls.tlsStep(&g_session, input, out[0..]);
        var waiting: bool = false;
        switch (act) {
            .send => |bytes| {
                sends += 1;
                if (check_client and sends == 2) ckBytes(bytes, s.client_flight[0..], "client flight bytes");
            },
            .recv => |_| waiting = true,
            .wait => |_| waiting = true,
            .established => established = true,
            .closed => {
                if (!established) return error.Closed;
            },
            else => {},
        }

        var rd: [tls.TLS_MAX_RECORD]u8 = undefined;
        const n = tls.tlsRead(&g_session, rd[0..]) catch |e| return e;
        if (n > tls.TLS_MAX_RECORD - app_len) return error.AppTooLarge;
        copyInto(app_buf[app_len .. app_len + n], rd[0..n]);
        app_len += n;

        if (waiting and pos >= s.server_raw.len and !established) return error.HandshakeFailed;
        if (established and pos >= s.server_raw.len) break;
    }

    if (check_client) {
        ck(sends == 2, "two client sends");
        ck(established, "established");
        ckBytes(app_buf[0..app_len], s.app_plain[0..], "application plaintext");
    }
    return DriveResult{ .sends = sends, .established = established };
}

fn ecdsaScenario() Scenario {
    return Scenario{
        .seed = ecdsa_aes.seed,
        .hostname = ecdsa_aes.hostname[0..],
        .now_unix = ecdsa_aes.now_unix,
        .store_bin = ecdsa_aes.store_bin[0..],
        .server_raw = ecdsa_aes.server_raw[0..],
        .client_hello = ecdsa_aes.client_hello[0..],
        .client_flight = ecdsa_aes.client_flight[0..],
        .app_plain = ecdsa_aes.app_plain[0..],
        .finished_record_end = ecdsa_aes.finished_record_end,
    };
}

fn rsaScenario() Scenario {
    return Scenario{
        .seed = rsa_chacha.seed,
        .hostname = rsa_chacha.hostname[0..],
        .now_unix = rsa_chacha.now_unix,
        .store_bin = rsa_chacha.store_bin[0..],
        .server_raw = rsa_chacha.server_raw[0..],
        .client_hello = rsa_chacha.client_hello[0..],
        .client_flight = rsa_chacha.client_flight[0..],
        .app_plain = rsa_chacha.app_plain[0..],
        .finished_record_end = rsa_chacha.finished_record_end,
    };
}

fn x25519Scenario() Scenario {
    return Scenario{
        .seed = x25519_data.seed,
        .hostname = x25519_data.hostname[0..],
        .now_unix = x25519_data.now_unix,
        .store_bin = x25519_data.store_bin[0..],
        .server_raw = x25519_data.server_raw[0..],
        .client_hello = x25519_data.client_hello[0..],
        .client_flight = x25519_data.client_flight[0..],
        .app_plain = x25519_data.app_plain[0..],
        .finished_record_end = x25519_data.finished_record_end,
    };
}

fn bigCertScenario() Scenario {
    return Scenario{
        .seed = big_cert.seed,
        .hostname = big_cert.hostname[0..],
        .now_unix = big_cert.now_unix,
        .store_bin = big_cert.store_bin[0..],
        .server_raw = big_cert.server_raw[0..],
        .client_hello = big_cert.client_hello[0..],
        .client_flight = big_cert.client_flight[0..],
        .app_plain = big_cert.app_plain[0..],
        .finished_record_end = big_cert.finished_record_end,
    };
}

fn expectHandshakeFailed(s: Scenario) void {
    _ = drive(s, 97, true, false, true) catch |e| {
        ck(e == error.HandshakeFailed, "bad finished");
        return;
    };
    @panic("bad finished");
}

fn expectSkeFailed(s: Scenario) void {
    _ = drive(s, 97, false, true, false) catch |e| {
        ck(e == error.HandshakeFailed, "bad server key exchange signature");
        return;
    };
    @panic("bad server key exchange signature");
}

fn checkWriteAtomic() void {
    var data: [17000]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, i & 0xFF);

    var short_out: [16389]u8 = undefined;
    short_out[0] = 0xAA;
    const seq_before = g_session.write_seq;
    var saw: bool = false;
    _ = tls.tlsWrite(&g_session, data[0..], short_out[0..]) catch |e| {
        ck(e == error.OutputTooSmall, "short write error");
        saw = true;
    };
    ck(saw, "short write rejected");
    ck(g_session.write_seq == seq_before, "short write leaves sequence unchanged");
    ck(short_out[0] == 0xAA, "short write leaves output untouched");

    var big_out: [20000]u8 = undefined;
    const n = tls.tlsWrite(&g_session, data[0..], big_out[0..]) catch @panic("write retry");
    ck(n == 17058, "write total after retry");
    ck(g_session.write_seq == seq_before + 2, "write sequence after retry");
}

// TLS 1.2 ChaCha20-Poly1305 has no explicit nonce: exact output size for
// 17000 bytes is 17000 + 2 records * (5 header + 16 tag) = 17042.
fn checkWriteExactFit() void {
    var data: [17000]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, i & 0xFF);

    var out: [17042]u8 = undefined;
    const seq_before = g_session.write_seq;
    const n = tls.tlsWrite(&g_session, data[0..], out[0..]) catch @panic("exact fit write");
    ck(n == 17042, "exact fit length");
    ck(g_session.write_seq == seq_before + 2, "exact fit sequence");
}

fn expectExpired(s: Scenario) void {
    _ = drive(s, 97, false, false, false) catch |e| {
        ck(e == error.CertificateExpired, "expired leaf");
        return;
    };
    @panic("expired leaf");
}

fn expectHostnameMismatch(s: Scenario) void {
    _ = drive(s, 97, false, false, false) catch |e| {
        ck(e == error.HostnameMismatch, "hostname mismatch");
        return;
    };
    @panic("hostname mismatch");
}

pub fn main() void {
    const ecdsa = ecdsaScenario();
    const rsa = rsaScenario();
    const x25519 = x25519Scenario();
    const big = bigCertScenario();

    const big_info = scanTranscript(big.server_raw[0..]);
    ck(big_info.cert_message_len > tls.TLS_MAX_RECORD, "big certificate exceeds one record");
    ck(big_info.cert_record_fragments >= 2, "big certificate spans multiple records");
    ck(big_info.ske_sig_offset > 0, "ske signature located");

    var r1 = drive(ecdsa, 97, false, false, true) catch @panic("ecdsa/aes handshake");
    ck(r1.sends == 2 and r1.established, "ecdsa/aes actions");
    checkWriteAtomic();

    var r2 = drive(rsa, 163, false, false, true) catch @panic("rsa/chacha handshake");
    ck(r2.sends == 2 and r2.established, "rsa/chacha actions");
    checkWriteExactFit();

    var r3 = drive(x25519, 113, false, false, true) catch @panic("x25519 handshake");
    ck(r3.sends == 2 and r3.established, "x25519 actions");

    var r4 = drive(big, 1, false, false, true) catch @panic("big certificate handshake");
    ck(r4.sends == 2 and r4.established, "big certificate actions");

    var r6 = drive(big, big.server_raw.len, false, false, true) catch @panic("big certificate one-chunk handshake");
    ck(r6.sends == 2 and r6.established, "big certificate one-chunk actions");

    var r5 = drive(ecdsa, 1, false, false, true) catch @panic("fragmented input handshake");
    ck(r5.sends == 2 and r5.established, "fragmented input actions");

    expectHandshakeFailed(ecdsa);
    expectSkeFailed(ecdsa);

    var expired = ecdsaScenario();
    expired.now_unix = 4102444800; // 2100-01-01
    expectExpired(expired);

    var wrong_host = ecdsaScenario();
    wrong_host.hostname = "wrong.example.test";
    expectHostnameMismatch(wrong_host);

    if (g_fail == 0) {
        std.io.write("tls handshake ok\n");
    } else {
        std.io.write("tls handshake FAIL\n");
    }
}
