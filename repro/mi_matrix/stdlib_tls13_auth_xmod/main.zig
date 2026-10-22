// stdlib_tls13_auth_xmod — STDLIB std_tls TLS 1.3 authentication negatives (M5 T1).
//
// Replays a captured RSA-cert TLS 1.3 handshake (RSA-PSS CertificateVerify)
// and asserts fail-closed behavior before `Established`:
//   - baseline: the untouched transcript establishes with RSA-PSS
//   - PKCS#1 v1.5 CertificateVerify scheme (0x0401) -> error.HandshakeFailed
//   - tampered server Finished ciphertext -> error.HandshakeFailed
//   - server key_share group changed to secp256r1 -> error.UnsupportedGroup
//
// The PKCS#1 transcript is generated at capture time by decrypting the real
// CertificateVerify record, rewriting only the scheme field, and re-sealing it;
// the client must reject on the scheme before attempting a signature check.
//
// GREEN (contract): deterministic byte-exact stdout `tls 1.3 auth ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const rsa_pss = @import("rsa_pss_data.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn load16(in: []const u8, off: usize) usize {
    return (@intCast(usize, in[off]) << 8) | @intCast(usize, in[off + 1]);
}

fn keyshareGroupOffset(raw: []const u8) usize {
    if (raw.len < 9) return 0;
    if (raw[0] != tls.content_handshake or raw[5] != 2) return 0;
    const body = raw[9..];
    if (body.len < 39) return 0;
    if (load16(body, 0) != tls.TLS_VERSION_12) return 0;
    const sid_len = @intCast(usize, body[34]);
    var pos: usize = 35 + sid_len + 2 + 1;
    if (pos + 2 > body.len) return 0;
    const ext_len = load16(body, pos);
    pos += 2;
    const end = pos + ext_len;
    if (end > body.len) return 0;
    while (pos + 4 <= end) {
        const ext_type = load16(body, pos);
        const ext_len2 = load16(body, pos + 2);
        pos += 4;
        if (pos + ext_len2 > end) return 0;
        if (ext_type == 0x0033) return 9 + pos;
        pos += ext_len2;
    }
    return 0;
}

fn driveRaw(raw: []const u8) !void {
    ck(raw.len <= tls.TLS_HANDSHAKE_MAX, "transcript fits");
    var server_buf: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    copyInto(server_buf[0..raw.len], raw);

    var arena = std.arena.init(g_store_arena_buf[0..]);
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&arena, rsa_pss.store_bin[0..], &store) catch @panic("store load");

    var rng = rand.xoshiroInit(rsa_pss.seed);
    var cfg = tls.TlsConfig{
        .hostname = rsa_pss.hostname[0..],
        .store = &store,
        .rng = &rng,
        .now_unix = rsa_pss.now_unix,
        .min_version = tls.TLS_VERSION_13,
        .max_version = tls.TLS_VERSION_13,
    };
    tls.tlsInit(&g_session, &cfg);

    var out: [8192]u8 = undefined;
    const first = try tls.tlsStep(&g_session, "", out[0..]);
    switch (first) {
        .send => |_| {},
        else => return error.BadAction,
    }

    var pos: usize = 0;
    var established: bool = false;
    while (pos < raw.len or !established) {
        var input: []const u8 = "";
        if (pos < raw.len) {
            var take: usize = 97;
            if (take > raw.len - pos) take = raw.len - pos;
            input = server_buf[pos .. pos + take];
            pos += take;
        }
        const act = try tls.tlsStep(&g_session, input, out[0..]);
        var waiting: bool = false;
        switch (act) {
            .send => |_| {},
            .recv => |_| waiting = true,
            .wait => |_| waiting = true,
            .established => established = true,
            .closed => return error.Closed,
            else => {},
        }
        if (waiting and pos >= raw.len and !established) return error.HandshakeFailed;
        if (established and pos >= raw.len) return;
    }
    if (!established) return error.HandshakeFailed;
}

fn expectError(raw: []const u8, want: tls.TlsError, what: []const u8) void {
    driveRaw(raw) catch |e| {
        ck(e == want, what);
        return;
    };
    @panic(what);
}

pub fn main() void {
    ck(rsa_pss.pkcs1_server_raw.len == rsa_pss.server_raw.len, "pkcs1 transcript length");
    ck(rsa_pss.finished_record_end > 0, "finished offset");
    ck(rsa_pss.finished_record_end <= rsa_pss.server_raw.len, "finished offset bounds");

    driveRaw(rsa_pss.server_raw[0..]) catch @panic("rsa-pss baseline");
    ck(g_session.version == tls.TLS_VERSION_13, "baseline version");
    ck(g_session.suite == tls.CipherSuite.tls13_aes_128_gcm_sha256, "baseline suite");

    expectError(rsa_pss.pkcs1_server_raw[0..], error.HandshakeFailed, "pkcs1 certificate verify");

    var bad_fin: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    copyInto(bad_fin[0..rsa_pss.server_raw.len], rsa_pss.server_raw[0..]);
    bad_fin[rsa_pss.finished_record_end - 1] = bad_fin[rsa_pss.finished_record_end - 1] ^ 1;
    expectError(bad_fin[0..rsa_pss.server_raw.len], error.HandshakeFailed, "bad finished");

    var bad_group: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    copyInto(bad_group[0..rsa_pss.server_raw.len], rsa_pss.server_raw[0..]);
    const off = keyshareGroupOffset(bad_group[0..rsa_pss.server_raw.len]);
    ck(off != 0, "key share group located");
    bad_group[off] = 0x00;
    bad_group[off + 1] = 0x17; // secp256r1: not offered in 1.3 key_share
    expectError(bad_group[0..rsa_pss.server_raw.len], error.UnsupportedGroup, "unknown key share group");

    if (g_fail == 0) {
        std.io.write("tls 1.3 auth ok\n");
    } else {
        std.io.write("tls 1.3 auth FAIL\n");
    }
}
