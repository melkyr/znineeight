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
//   - ECDHE-ECDSA replay fed one byte at a time (fragmented Certificate record)
//     asserts action sequence: ClientHello send, client-flight send, established
//   - negative: flip a byte in the server Finished record -> HandshakeFailed
//   - negative: now_unix past the leaf/anchor validity -> CertificateExpired
//   - negative: hostname with no SAN match -> HostnameMismatch
//
// GREEN (contract): deterministic byte-exact stdout `tls handshake ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const ecdsa_aes = @import("ecdsa_aes_data.zig");
const rsa_chacha = @import("rsa_chacha_data.zig");

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

var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn drive(s: Scenario, chunk: usize, mutate_finished: bool, check_client: bool) !DriveResult {
    var server_buf: [16384]u8 = undefined;
    ck(s.server_raw.len <= server_buf.len, "server transcript fits");
    copyInto(server_buf[0..s.server_raw.len], s.server_raw[0..]);
    if (mutate_finished) {
        ck(s.finished_record_end > 0 and s.finished_record_end <= s.server_raw.len, "finished offset");
        server_buf[s.finished_record_end - 1] = server_buf[s.finished_record_end - 1] ^ 1;
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

fn expectHandshakeFailed(s: Scenario) void {
    _ = drive(s, 97, true, true) catch |e| {
        ck(e == error.HandshakeFailed, "bad finished");
        return;
    };
    @panic("bad finished");
}

fn expectExpired(s: Scenario) void {
    _ = drive(s, 97, false, false) catch |e| {
        ck(e == error.CertificateExpired, "expired leaf");
        return;
    };
    @panic("expired leaf");
}

fn expectHostnameMismatch(s: Scenario) void {
    _ = drive(s, 97, false, false) catch |e| {
        ck(e == error.HostnameMismatch, "hostname mismatch");
        return;
    };
    @panic("hostname mismatch");
}

pub fn main() void {
    const ecdsa = ecdsaScenario();
    const rsa = rsaScenario();

    var r1 = drive(ecdsa, 97, false, true) catch @panic("ecdsa/aes handshake");
    ck(r1.sends == 2 and r1.established, "ecdsa/aes actions");

    var r2 = drive(rsa, 163, false, true) catch @panic("rsa/chacha handshake");
    ck(r2.sends == 2 and r2.established, "rsa/chacha actions");

    var r3 = drive(ecdsa, 1, false, true) catch @panic("fragmented certificate handshake");
    ck(r3.sends == 2 and r3.established, "fragmented actions");

    expectHandshakeFailed(ecdsa);

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
