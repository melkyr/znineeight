// stdlib_tls13_handshake_xmod — STDLIB std_tls TLS 1.3 client handshake (M5 T1).
//
// Canned server transcripts were captured from host `openssl s_server -tls1_3`
// with a deterministic client RNG seed, so replaying the same seed reproduces
// the exact ClientHello/Finished bytes and therefore the same transcript hash,
// key schedule, and traffic secrets.
//
// Scenarios:
//   - ECDSA P-256 certificate / TLS_AES_128_GCM_SHA256
//   - ECDSA P-256 certificate / TLS_CHACHA20_POLY1305_SHA256
//   - RSA certificate with RSA-PSS CertificateVerify / AES-128-GCM
//   - ECDSA P-384 certificate / ecdsa_secp384r1_sha384 CertificateVerify
//
// Each scenario pins the exact early/handshake/master and per-direction
// traffic secrets (independently verified against the OpenSSL key log),
// asserts the two-send action sequence (ClientHello, client Finished) and the
// captured ClientHello/Finished bytes, and checks server->client application
// data plus a client->server tlsWrite record round-trip.
//
// GREEN (contract): deterministic byte-exact stdout `tls 1.3 handshake ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const ecdsa_aes = @import("ecdsa_aes_data.zig");
const ecdsa_chacha = @import("ecdsa_chacha_data.zig");
const rsa_pss = @import("rsa_pss_data.zig");
const p384 = @import("p384_data.zig");

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
    suite: tls.CipherSuite,
    early_secret: []const u8,
    handshake_secret: []const u8,
    master_secret: []const u8,
    client_hs_secret: []const u8,
    server_hs_secret: []const u8,
    client_app_secret: []const u8,
    server_app_secret: []const u8,
};

var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn drive(s: Scenario, chunk: usize) !void {
    var server_buf: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    ck(s.server_raw.len <= server_buf.len, "server transcript fits");
    copyInto(server_buf[0..s.server_raw.len], s.server_raw[0..]);

    var arena = std.arena.init(g_store_arena_buf[0..]);
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&arena, s.store_bin[0..], &store) catch @panic("store load");

    var rng = rand.xoshiroInit(s.seed);
    var cfg = tls.TlsConfig{
        .hostname = s.hostname[0..],
        .store = &store,
        .rng = &rng,
        .now_unix = s.now_unix,
        .min_version = tls.TLS_VERSION_13,
        .max_version = tls.TLS_VERSION_13,
    };
    tls.tlsInit(&g_session, &cfg);

    var out: [8192]u8 = undefined;
    var sends: usize = 0;

    const first = try tls.tlsStep(&g_session, "", out[0..]);
    switch (first) {
        .send => |bytes| {
            sends += 1;
            ckBytes(bytes, s.client_hello[0..], "client hello bytes");
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
                if (sends == 2) ckBytes(bytes, s.client_flight[0..], "client finished bytes");
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

    ck(sends == 2, "two client sends");
    ck(established, "established");
    ck(g_session.version == tls.TLS_VERSION_13, "negotiated version");
    ck(g_session.suite == s.suite, "negotiated suite");
    ckBytes(app_buf[0..app_len], s.app_plain[0..], "application plaintext");
    ckBytes(g_session.early_secret[0..], s.early_secret[0..], "early secret");
    ckBytes(g_session.handshake_secret[0..], s.handshake_secret[0..], "handshake secret");
    ckBytes(g_session.master_secret[0..], s.master_secret[0..], "master secret");
    ckBytes(g_session.client_hs_secret[0..], s.client_hs_secret[0..], "client hs traffic");
    ckBytes(g_session.server_hs_secret[0..], s.server_hs_secret[0..], "server hs traffic");
    ckBytes(g_session.client_app_secret[0..], s.client_app_secret[0..], "client app traffic");
    ckBytes(g_session.server_app_secret[0..], s.server_app_secret[0..], "server app traffic");
}

fn checkWriteRoundTrip() void {
    var short_out: [5]u8 = undefined;
    short_out[0] = 0xAA;
    const seq_before = g_session.write_seq;
    var saw: bool = false;
    _ = tls.tlsWrite(&g_session, "ping", short_out[0..]) catch |e| {
        ck(e == error.OutputTooSmall, "short write error");
        saw = true;
    };
    ck(saw, "short write rejected");
    ck(g_session.write_seq == seq_before, "short write leaves sequence unchanged");
    ck(short_out[0] == 0xAA, "short write leaves output untouched");

    const msg = "ping";
    var out: [128]u8 = undefined;
    const n = tls.tlsWrite(&g_session, msg, out[0..]) catch @panic("tlsWrite");
    ck(g_session.write_seq == seq_before + 1, "write sequence advanced");

    var hdr: tls.RecordHeader = undefined;
    var frag: []const u8 = undefined;
    tls.decodeRecord(out[0..n], &hdr, &frag) catch @panic("write decode");
    ck(hdr.content_type == tls.content_application_data, "write outer type");
    ck(hdr.version == tls.TLS_VERSION_12, "write legacy version");

    var pt: [64]u8 = undefined;
    const m = tls.unprotectRecord13(g_session.suite,
        g_session.client_key[0..tls.suiteKeyLen(g_session.suite)],
        g_session.client_iv[0..12], seq_before, frag, pt[0..]) catch @panic("write unprotect");
    ck(m == msg.len + 1, "write plaintext length");
    ckBytes(pt[0..msg.len], msg, "write plaintext");
    ck(pt[msg.len] == tls.content_application_data, "write inner type");
}

// Exact-max TLS 1.3 plaintext: 16384 content bytes + the inner content type =
// 16385 AEAD plaintext bytes. Feeding the resulting record through tlsStep
// exercises the 1.3 receive buffer at its maximum size.
fn checkMaxAppRecord() void {
    var plain: [tls.TLS_MAX_PLAINTEXT_RECORD]u8 = undefined;
    var i: usize = 0;
    while (i < plain.len) : (i += 1) plain[i] = @intCast(u8, (i * 7 + 3) & 0xFF);

    var wire: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    const n = tls.protectRecord13(g_session.suite,
        g_session.server_key[0..tls.suiteKeyLen(g_session.suite)],
        g_session.server_iv[0..12], g_session.read_seq,
        tls.content_application_data, plain[0..], wire[0..]) catch @panic("max protect");
    ck(n == tls.TLS_MAX_PLAINTEXT_RECORD + 1 + 16, "max protected length");

    var framed: [tls.TLS_MAX_WIRE_RECORD + tls.RECORD_HEADER_LEN]u8 = undefined;
    const flen = tls.encodeRecord(tls.content_application_data, tls.TLS_VERSION_12,
        wire[0..n], framed[0..]) catch @panic("max encode");

    var out: [64]u8 = undefined;
    _ = tls.tlsStep(&g_session, framed[0..flen], out[0..]) catch @panic("max record step");

    var got: [tls.TLS_MAX_RECORD]u8 = undefined;
    const rn = tls.tlsRead(&g_session, got[0..]) catch @panic("max record read");
    ck(rn == tls.TLS_MAX_PLAINTEXT_RECORD, "max application bytes");
    ckBytes(got[0..rn], plain[0..], "max application content");
}

fn ecdsaAesScenario() Scenario {
    return Scenario{
        .seed = ecdsa_aes.seed,
        .hostname = ecdsa_aes.hostname[0..],
        .now_unix = ecdsa_aes.now_unix,
        .store_bin = ecdsa_aes.store_bin[0..],
        .server_raw = ecdsa_aes.server_raw[0..],
        .client_hello = ecdsa_aes.client_hello[0..],
        .client_flight = ecdsa_aes.client_flight[0..],
        .app_plain = ecdsa_aes.app_plain[0..],
        .suite = tls.CipherSuite.tls13_aes_128_gcm_sha256,
        .early_secret = ecdsa_aes.early_secret[0..],
        .handshake_secret = ecdsa_aes.handshake_secret[0..],
        .master_secret = ecdsa_aes.master_secret[0..],
        .client_hs_secret = ecdsa_aes.client_hs_secret[0..],
        .server_hs_secret = ecdsa_aes.server_hs_secret[0..],
        .client_app_secret = ecdsa_aes.client_app_secret[0..],
        .server_app_secret = ecdsa_aes.server_app_secret[0..],
    };
}

fn ecdsaChachaScenario() Scenario {
    return Scenario{
        .seed = ecdsa_chacha.seed,
        .hostname = ecdsa_chacha.hostname[0..],
        .now_unix = ecdsa_chacha.now_unix,
        .store_bin = ecdsa_chacha.store_bin[0..],
        .server_raw = ecdsa_chacha.server_raw[0..],
        .client_hello = ecdsa_chacha.client_hello[0..],
        .client_flight = ecdsa_chacha.client_flight[0..],
        .app_plain = ecdsa_chacha.app_plain[0..],
        .suite = tls.CipherSuite.tls13_chacha20_poly1305_sha256,
        .early_secret = ecdsa_chacha.early_secret[0..],
        .handshake_secret = ecdsa_chacha.handshake_secret[0..],
        .master_secret = ecdsa_chacha.master_secret[0..],
        .client_hs_secret = ecdsa_chacha.client_hs_secret[0..],
        .server_hs_secret = ecdsa_chacha.server_hs_secret[0..],
        .client_app_secret = ecdsa_chacha.client_app_secret[0..],
        .server_app_secret = ecdsa_chacha.server_app_secret[0..],
    };
}

fn rsaPssScenario() Scenario {
    return Scenario{
        .seed = rsa_pss.seed,
        .hostname = rsa_pss.hostname[0..],
        .now_unix = rsa_pss.now_unix,
        .store_bin = rsa_pss.store_bin[0..],
        .server_raw = rsa_pss.server_raw[0..],
        .client_hello = rsa_pss.client_hello[0..],
        .client_flight = rsa_pss.client_flight[0..],
        .app_plain = rsa_pss.app_plain[0..],
        .suite = tls.CipherSuite.tls13_aes_128_gcm_sha256,
        .early_secret = rsa_pss.early_secret[0..],
        .handshake_secret = rsa_pss.handshake_secret[0..],
        .master_secret = rsa_pss.master_secret[0..],
        .client_hs_secret = rsa_pss.client_hs_secret[0..],
        .server_hs_secret = rsa_pss.server_hs_secret[0..],
        .client_app_secret = rsa_pss.client_app_secret[0..],
        .server_app_secret = rsa_pss.server_app_secret[0..],
    };
}

fn p384Scenario() Scenario {
    return Scenario{
        .seed = p384.seed,
        .hostname = p384.hostname[0..],
        .now_unix = p384.now_unix,
        .store_bin = p384.store_bin[0..],
        .server_raw = p384.server_raw[0..],
        .client_hello = p384.client_hello[0..],
        .client_flight = p384.client_flight[0..],
        .app_plain = p384.app_plain[0..],
        .suite = tls.CipherSuite.tls13_aes_128_gcm_sha256,
        .early_secret = p384.early_secret[0..],
        .handshake_secret = p384.handshake_secret[0..],
        .master_secret = p384.master_secret[0..],
        .client_hs_secret = p384.client_hs_secret[0..],
        .server_hs_secret = p384.server_hs_secret[0..],
        .client_app_secret = p384.client_app_secret[0..],
        .server_app_secret = p384.server_app_secret[0..],
    };
}

pub fn main() void {
    drive(ecdsaAesScenario(), 97) catch @panic("ecdsa/aes handshake");
    checkWriteRoundTrip();
    checkMaxAppRecord();

    drive(ecdsaChachaScenario(), 163) catch @panic("ecdsa/chacha handshake");
    drive(rsaPssScenario(), 113) catch @panic("rsa/pss handshake");
    drive(p384Scenario(), 127) catch @panic("p384 handshake");

    const aes_scenario = ecdsaAesScenario();
    drive(aes_scenario, aes_scenario.server_raw.len) catch @panic("one-chunk ecdsa/aes handshake");
    drive(ecdsaAesScenario(), 1) catch @panic("fragmented ecdsa/aes handshake");

    if (g_fail == 0) {
        std.io.write("tls 1.3 handshake ok\n");
    } else {
        std.io.write("tls 1.3 handshake FAIL\n");
    }
}
