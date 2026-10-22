// stdlib_tls13_fallback_xmod — STDLIB std_tls 1.3 downgrade sentinel (M5 T1).
//
// The captured ClientHello offers both TLS 1.3 and TLS 1.2. The server flight
// comes from a real OpenSSL TLS 1.2-only server, so it negotiates 1.2 and does
// NOT carry the RFC 8446 §4.1.3 downgrade sentinel. The client must fail closed
// at ServerHello.
//
// A second run patches the sentinel into ServerHello.random. The client then
// passes the downgrade check and proceeds through Certificate to
// ServerKeyExchange, where the (now invalid) SKE signature fails the handshake.
// That proves the positive sentinel branch is reached, not just rejected.
//
// `hasDowngradeSentinel` is also checked directly for both values.
//
// GREEN (contract): deterministic byte-exact stdout `tls 1.3 fallback ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const tls = @import("std_tls.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const fb = @import("fallback_data.zig");

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

fn run(raw: []const u8) !void {
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
    const first = try tls.tlsStep(&g_session, "", out[0..]);
    switch (first) {
        .send => |bytes| ck(eqBytes(bytes, fb.client_hello[0..]), "combined client hello bytes"),
        else => return error.BadAction,
    }
    _ = try tls.tlsStep(&g_session, raw, out[0..]);
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
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

pub fn main() void {
    checkSentinelHelper();

    var raw: [tls.TLS_HANDSHAKE_MAX]u8 = undefined;
    copyInto(raw[0..fb.server_raw.len], fb.server_raw[0..]);

    var saw: bool = false;
    run(raw[0..fb.server_raw.len]) catch |e| {
        ck(e == error.HandshakeFailed, "unsentineled fallback fails closed");
        saw = true;
    };
    ck(saw, "unsentineled fallback rejected");
    ck(g_session.state == .RecvServerHello, "rejected at server hello");

    const sentinel = [_]u8{ 0x44, 0x4F, 0x57, 0x4E, 0x47, 0x52, 0x44, 0x01 };
    var i: usize = 0;
    while (i < 8) : (i += 1) raw[fb.server_hello_random_offset + 24 + i] = sentinel[i];

    saw = false;
    run(raw[0..fb.server_raw.len]) catch |e| {
        ck(e == error.HandshakeFailed, "patched-sentinel fallback stops at SKE signature");
        saw = true;
    };
    ck(saw, "patched-sentinel fallback rejected");
    ck(g_session.state == .RecvServerKeyExchange, "sentinel accepted, reached SKE signature check");

    if (g_fail == 0) {
        std.io.write("tls 1.3 fallback ok\n");
    } else {
        std.io.write("tls 1.3 fallback FAIL\n");
    }
}
