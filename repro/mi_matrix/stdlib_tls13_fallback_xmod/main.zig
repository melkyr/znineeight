// stdlib_tls13_fallback_xmod — STDLIB std_tls 1.3 downgrade sentinel (M5 T1).
//
// The captured ClientHello offers both TLS 1.3 and TLS 1.2. The server flight
// comes from a real OpenSSL TLS 1.2-only server, so it negotiates 1.2 and does
// NOT carry the RFC 8446 §4.1.3 downgrade sentinel. Per RFC 8446, ABSENCE of
// the sentinel is normal and this fallback must complete.
//
// The server certificate is RSA and the SKE is forced to
// rsa_pss_rsae_sha256 (0x0804), so this fixture also positively exercises the
// TLS 1.2 RSA-PSS ServerKeyExchange verifier branch.
//
// A second run writes the sentinel into ServerHello.random. Per RFC 8446 the
// client MUST abort at ServerHello.
//
// GREEN (contract): deterministic byte-exact stdout `tls 1.3 fallback ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const fb = @import("fallback_data.zig");

const server_hello_random_offset: usize = 11;

var g_fail: u32 = 0;
var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;

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

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn load16(in: []const u8, off: usize) usize {
    return (@intCast(usize, in[off]) << 8) | @intCast(usize, in[off + 1]);
}

fn load24(in: []const u8, off: usize) usize {
    return (@intCast(usize, in[off]) << 16) |
        (@intCast(usize, in[off + 1]) << 8) |
        @intCast(usize, in[off + 2]);
}

// Locate ServerKeyExchange in the captured server flight and return its group
// and signature algorithm.
fn scanSke(raw: []const u8, group_out: *u16, sig_alg_out: *u16) bool {
    var hs: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    var hs_len: usize = 0;
    var pos: usize = 0;
    while (pos + 5 <= raw.len) {
        const ctype = raw[pos];
        const rlen = load16(raw, pos + 3);
        const end = pos + 5 + rlen;
        if (end > raw.len) break;
        if (ctype == tls.content_handshake) {
            if (hs_len + rlen > hs.len) return false;
            copyInto(hs[hs_len .. hs_len + rlen], raw[pos + 5 .. end]);
            hs_len += rlen;
            while (hs_len >= 4) {
                const mlen = load24(hs[0..], 1);
                const total = 4 + mlen;
                if (hs_len < total) break;
                if (hs[0] == 12) {
                    const body = hs[4..total];
                    if (body.len < 5 or body[0] != 3) return false;
                    const pub_len = @intCast(usize, body[3]);
                    if (4 + pub_len + 4 > body.len) return false;
                    group_out.* = @intCast(u16, load16(body, 1));
                    sig_alg_out.* = @intCast(u16, load16(body, 4 + pub_len));
                    return true;
                }
                var i: usize = 0;
                while (total + i < hs_len) : (i += 1) hs[i] = hs[total + i];
                hs_len -= total;
            }
        }
        pos = end;
    }
    return false;
}

fn drive(s: []const u8, chunk: usize) !void {
    var server_buf: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    ck(s.len <= server_buf.len, "server transcript fits");
    copyInto(server_buf[0..s.len], s);

    var arena = std.arena.init(g_store_arena_buf[0..]);
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&arena, fb.store_bin[0..], &store) catch @panic("store load");

    var rng = rand.xoshiroInit(fb.seed);
    var cfg = tls.TlsConfig{
        .hostname = fb.hostname[0..],
        .store = &store,
        .rng = &rng,
        .now_unix = fb.now_unix,
        .min_version = tls.TLS_VERSION_12,
        .max_version = tls.TLS_VERSION_13,
    };
    tls.tlsInit(&g_session, &cfg);

    var out: [8192]u8 = undefined;
    var sends: usize = 0;

    const first = try tls.tlsStep(&g_session, "", out[0..]);
    switch (first) {
        .send => |bytes| {
            sends += 1;
            ckBytes(bytes, fb.client_hello[0..], "combined client hello bytes");
        },
        else => return error.BadAction,
    }

    var pos: usize = 0;
    var established: bool = false;
    var app_buf: [tls.TLS_MAX_RECORD]u8 = undefined;
    var app_len: usize = 0;

    while (pos < s.len or !established) {
        var input: []const u8 = "";
        if (pos < s.len) {
            var take: usize = chunk;
            if (take > s.len - pos) take = s.len - pos;
            input = server_buf[pos .. pos + take];
            pos += take;
        }

        const act = try tls.tlsStep(&g_session, input, out[0..]);
        var waiting: bool = false;
        switch (act) {
            .send => |bytes| {
                sends += 1;
                if (sends == 2) ckBytes(bytes, fb.client_flight[0..], "client flight bytes");
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

        if (waiting and pos >= s.len and !established) return error.HandshakeFailed;
        if (established and pos >= s.len) break;
    }

    ck(sends == 2, "two client sends");
    ck(established, "established");
    ck(g_session.version == tls.TLS_VERSION_12, "negotiated TLS 1.2");
    ck(g_session.suite == tls.CipherSuite.rsa_aes_128_gcm_sha256, "fallback suite");
    ckBytes(app_buf[0..app_len], fb.app_plain[0..], "application plaintext");
}

fn checkSentinelHelper() void {
    var random: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) random[i] = @intCast(u8, i);
    ck(!tls.hasDowngradeSentinel(random[0..]), "no sentinel");
    const sentinel = [_]u8{ 0x44, 0x4F, 0x57, 0x4E, 0x47, 0x52, 0x44, 0x01 };
    i = 0;
    while (i < 8) : (i += 1) random[24 + i] = sentinel[i];
    ck(tls.hasDowngradeSentinel(random[0..]), "sentinel present");
    random[31] = 0x00;
    ck(!tls.hasDowngradeSentinel(random[0..]), "sentinel mismatch");
}

fn expectSentinelAbort() void {
    var raw: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    copyInto(raw[0..fb.server_raw.len], fb.server_raw[0..]);
    const sentinel = [_]u8{ 0x44, 0x4F, 0x57, 0x4E, 0x47, 0x52, 0x44, 0x01 };
    var i: usize = 0;
    while (i < 8) : (i += 1) raw[server_hello_random_offset + 24 + i] = sentinel[i];

    var saw: bool = false;
    drive(raw[0..fb.server_raw.len], 97) catch |e| {
        ck(e == error.HandshakeFailed, "sentinel abort error");
        saw = true;
    };
    ck(saw, "sentinel present aborts");
    ck(g_session.state == .RecvServerHello, "aborted at server hello");
}

pub fn main() void {
    checkSentinelHelper();

    drive(fb.server_raw[0..], 97) catch @panic("fallback handshake");

    var group: u16 = 0;
    var sig_alg: u16 = 0;
    ck(scanSke(fb.server_raw[0..], &group, &sig_alg), "ske located");
    ck(group == 0x001D, "ske x25519 group");
    ck(sig_alg == 0x0804, "ske rsa_pss_rsae_sha256");

    expectSentinelAbort();

    if (g_fail == 0) {
        std.io.write("tls 1.3 fallback ok\n");
    } else {
        std.io.write("tls 1.3 fallback FAIL\n");
    }
}
