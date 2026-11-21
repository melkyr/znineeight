// stdlib_wg_handshake_xmod — STDLIB std_wireguard (Phase1 M6) NoiseIK fixture.
//
// Canned exchange captured from scripts/stdlib/ref/std_wireguard/ref.c (the
// vendored wireguard-lwip handshake subset, BSD-3-Clause):
//
//   ref seed=0x0123456789ABCDEF wall_unix_ns=1800000000123456789
//   static keys = RFC 7748 Alice/Bob keypairs; responder seed 0x0F1E2D3C4B5A6978
//
// Pins:
//   - initiation bytes byte-exact (ephemeral, encrypted static, encrypted
//     timestamp, mac1, zero mac2)
//   - TAI64N wire bytes are derived from wall_unix_ns (not now_ms)
//   - response processing + initiator transport keys byte-exact
//   - wrong static key -> AuthenticationFailed
//   - truncated response -> Corrupt
//   - mac1 mismatch -> Corrupt
//
// GREEN (contract): deterministic byte-exact stdout `wireguard handshake ok\n`
// (RUNRC=0). Any mismatch or wrong error calls @panic.
const std = @import("std");
const wg = @import("std_wireguard.zig");
const rand = @import("std_rand.zig");

const INIT_HEX = "01000000cf5492ac5ac39f7a9b74c617f2c191c2a9504e5dc0a0bb51edc1ab756de2a6883fdfa65f7c5c9820bad0f86cba59b3911b5251e0e5522aca30e7633ee3b54990f58d8082555f1fffa1c98a828bb2da07059593e3274039d419c4fdd4364ee749bb2bc2e3f21c67eb0e1420f9de88c10f3466ac286f3266335dacfe24859fd4c100000000000000000000000000000000";
const RESP_HEX = "02000000d4c3b2a1cf5492aca2627451101c3cf13a244ee3403409481612fc8d37b2e6b222e8c1769e7cb478bb058395ece9b7d32e6193f14352ecc584de82e50375993a68284568f45c25a000000000000000000000000000000000";
const TX_HEX = "1e30248f17e1a28a0eaaf896edf32830d0167347942393c15018c9585912bca6";
const RX_HEX = "b5eba4b4c280d30d0033299eda36840bc75e96dcfb842ed0e4f49cd3b6baa370";
const TS_HEX = "400000006b49d20a075bcd15";
const PRIV_I_HEX = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a";
const PRIV_R_HEX = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb";
const PUB_I_HEX = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a";
const PUB_R_HEX = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f";

const SEED_I: u64 = 0x0123456789ABCDEF;
const WALL_NS: u64 = 1800000000123456789;
const RESP_SENDER: u32 = 0xA1B2C3D4;

var g_fail: u32 = 0;
var g_peer: wg.WgPeer = undefined;
var g_peers: [1]wg.WgPeer = undefined;

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
    const n = unhex(hex, want[0..]);
    ck(got.len == n, what);
    var i: usize = 0;
    while (i < n) : (i += 1) ck(got[i] == want[i], what);
}

fn fill32(p: *[32]u8, v: u8) void {
    var i: usize = 0;
    while (i < 32) : (i += 1) p[i] = v;
}

fn resetPeer() void {
    fill32(&g_peer.static_priv, 0);
    fill32(&g_peer.remote_static_pub, 0);
    fill32(&g_peer.preshared_key, 0);
    g_peer.endpoint_ip = 0;
    g_peer.endpoint_port = 0;
    g_peer.allowed_ip_count = 0;
    fill32(&g_peer.public_key_dh, 0);
    fill32(&g_peer.label_mac1_key, 0);
    fill32(&g_peer.label_cookie_key, 0);
    g_peer.hs_valid = false;
    g_peer.hs_initiator = false;
    g_peer.local_index = 0;
    g_peer.remote_index = 0;
    fill32(&g_peer.ephemeral_priv, 0);
    fill32(&g_peer.remote_ephemeral, 0);
    fill32(&g_peer.hash, 0);
    fill32(&g_peer.chaining_key, 0);
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        g_peer.last_mac1[i] = 0;
        g_peer.cookie[i] = 0;
    }
    g_peer.has_mac1 = false;
    g_peer.cookie_valid = false;
    fill32(&g_peer.tx_key, 0);
    fill32(&g_peer.rx_key, 0);
    g_peer.session_valid = false;
    g_peer.last_handshake_sent_ms = 0;
    g_peer.last_handshake_received_ms = 0;
    g_peer.session_created_ms = 0;
    g_peer.handshake_attempts = 0;
}

fn setup(dev: *wg.WgDevice, priv_i: *const [32]u8) void {
    dev.peers = g_peers[0..];
    wg.wgInit(dev, priv_i);
    dev.rng = rand.xoshiroInit(SEED_I);
    wg.wgAddPeer(dev, &g_peer) catch @panic("add peer");
}

fn expectResponseError(dev: *wg.WgDevice, msg: []const u8, want: wg.WgError, what: []const u8) void {
    var saw: bool = false;
    wg.wgProcessResponse(dev, &dev.peers[0], msg) catch |err| {
        ck(err == want, what);
        saw = true;
    };
    ck(saw, what);
}

pub fn main() void {
    var priv_i: [32]u8 = undefined;
    var priv_r: [32]u8 = undefined;
    var init: [wg.WG_INITIATION_LEN]u8 = undefined;
    var resp: [wg.WG_RESPONSE_LEN]u8 = undefined;
    _ = unhex(PRIV_I_HEX, priv_i[0..]);
    _ = unhex(PRIV_R_HEX, priv_r[0..]);
    _ = unhex(RESP_HEX, resp[0..]);

    resetPeer();
    _ = unhex(PRIV_I_HEX, g_peer.static_priv[0..]);
    _ = unhex(PUB_R_HEX, g_peer.remote_static_pub[0..]);

    // Positive exchange: initiation bytes then response -> transport keys.
    var dev: wg.WgDevice = undefined;
    setup(&dev, &priv_i);
    ckHex(dev.iface_pub[0..], PUB_I_HEX, "interface pub");
    const n = wg.wgCreateInitiation(&dev, &dev.peers[0], WALL_NS, init[0..]) catch @panic("create initiation");
    ck(n == wg.WG_INITIATION_LEN, "initiation length");
    ckHex(init[0..], INIT_HEX, "initiation bytes");
    ck(init[132] == 0 and init[147] == 0, "mac2 zero without cookie");

    var ts: [wg.WG_TAI64N_LEN]u8 = undefined;
    wg.wgTai64n(WALL_NS, &ts);
    ckHex(ts[0..], TS_HEX, "tai64n from wall_unix_ns");
    // A wall clock change must move the wire timestamp; a monotonic value that
    // happens to equal a small millis count must not be used instead.
    var ts2: [wg.WG_TAI64N_LEN]u8 = undefined;
    wg.wgTai64n(WALL_NS + 1000000000, &ts2);
    var ts_diff: bool = false;
    var ti: usize = 0;
    while (ti < wg.WG_TAI64N_LEN) : (ti += 1) {
        if (ts[ti] != ts2[ti]) ts_diff = true;
    }
    ck(ts_diff, "tai64n advances with wall time");

    wg.wgProcessResponse(&dev, &dev.peers[0], resp[0..]) catch @panic("process response");
    ck(dev.peers[0].remote_index == RESP_SENDER, "response sender index");
    ckHex(dev.peers[0].tx_key[0..], TX_HEX, "tx key");
    ckHex(dev.peers[0].rx_key[0..], RX_HEX, "rx key");
    ck(dev.peers[0].session_valid, "session valid");

    // Wrong static key: the initiation was built with priv_i, but the response
    // is checked against a different interface private key. mac1 still uses
    // the old public key, so the AEAD/final DH fails AuthenticationFailed.
    var dev_bad: wg.WgDevice = undefined;
    setup(&dev_bad, &priv_i);
    resetPeer();
    _ = unhex(PRIV_I_HEX, g_peer.static_priv[0..]);
    _ = unhex(PUB_R_HEX, g_peer.remote_static_pub[0..]);
    var init_bad: [wg.WG_INITIATION_LEN]u8 = undefined;
    _ = wg.wgCreateInitiation(&dev_bad, &dev_bad.peers[0], WALL_NS, init_bad[0..]) catch @panic("init bad");
    var alt_priv: [32]u8 = undefined;
    _ = unhex(PRIV_R_HEX, alt_priv[0..]);
    var ai: usize = 0;
    while (ai < 32) : (ai += 1) dev_bad.iface_priv[ai] = alt_priv[ai];
    expectResponseError(&dev_bad, resp[0..], error.AuthenticationFailed, "wrong static key");

    // Truncated response -> Corrupt.
    var dev_trunc: wg.WgDevice = undefined;
    setup(&dev_trunc, &priv_i);
    var init_trunc: [wg.WG_INITIATION_LEN]u8 = undefined;
    _ = wg.wgCreateInitiation(&dev_trunc, &dev_trunc.peers[0], WALL_NS, init_trunc[0..]) catch @panic("init trunc");
    expectResponseError(&dev_trunc, resp[0 .. wg.WG_RESPONSE_LEN - 1], error.Corrupt, "truncated response");

    // mac1 mismatch -> Corrupt.
    var dev_mac: wg.WgDevice = undefined;
    setup(&dev_mac, &priv_i);
    var init_mac: [wg.WG_INITIATION_LEN]u8 = undefined;
    _ = wg.wgCreateInitiation(&dev_mac, &dev_mac.peers[0], WALL_NS, init_mac[0..]) catch @panic("init mac");
    var bad_resp: [wg.WG_RESPONSE_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < wg.WG_RESPONSE_LEN) : (i += 1) bad_resp[i] = resp[i];
    bad_resp[60] = bad_resp[60] ^ 1;
    expectResponseError(&dev_mac, bad_resp[0..], error.Corrupt, "mac1 mismatch");

    if (g_fail == 0) {
        std.io.write("wireguard handshake ok\n");
    } else {
        std.io.write("wireguard handshake FAIL\n");
    }
}
