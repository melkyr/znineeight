// stdlib_wg_transport_xmod — STDLIB std_wireguard (Phase1 M6) transport fixture.
//
// Canned exchange + transport vectors captured from
// scripts/stdlib/ref/std_wireguard/ref.c (vendored wireguard-lwip subset,
// BSD-3-Clause):
//
//   ref seed=0x0123456789ABCDEF wall_unix_ns=1800000000123456789
//   static keys = RFC 7748 Alice/Bob keypairs; responder seed 0x0F1E2D3C4B5A6978
//
// Pins:
//   - transport data byte-exact vs ref (type 4, receiver, 64-bit counter,
//     zero padding to 16, ChaCha20-Poly1305 tag)
//   - counters 0/1/max-before-reject and SessionExpired after reject
//   - 2048-bit replay window: duplicate, too-old, in-window-not-seen
//   - timers: keepalive at 10 s, rekey at 120 s, retry at 5 s + jitter,
//     rejected session never encrypts at 180 s
//   - CookieReply consumption -> subsequent initiation carries mac2
//
// GREEN (contract): deterministic byte-exact stdout `wireguard transport ok\n`
// (RUNRC=0). Any mismatch or wrong action/error calls @panic.
const std = @import("std");
const wg = @import("std_wireguard.zig");
const cipher = @import("std_cipher.zig");
const rand = @import("std_rand.zig");

const PRIV_I_HEX = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a";
const PUB_R_HEX = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f";
const RESP_HEX = "02000000d4c3b2a1cf5492aca2627451101c3cf13a244ee3403409481612fc8d37b2e6b222e8c1769e7cb478bb058395ece9b7d32e6193f14352ecc584de82e50375993a68284568f45c25a000000000000000000000000000000000";
const COOKIE_REPLY_HEX = "03000000cf5492ac000102030405060708090a0b0c0d0e0f10111213141516171bed1ea5491192f1c710d2cc96a85d70740a32f6af197515a5c337843d1f212d";
const COOKIE_INIT_HEX = "01000000cf5492ac5ac39f7a9b74c617f2c191c2a9504e5dc0a0bb51edc1ab756de2a6883fdfa65f7c5c9820bad0f86cba59b3911b5251e0e5522aca30e7633ee3b54990f58d8082555f1fffa1c98a828bb2da07059593e3274039d419c4fdd4364ee749bb2bc2e3f21c67eb0e1420f9de88c10f3466ac286f3266335dacfe24859fd4c1da3c58e10b14ef16c6fc9272a5dd1882";
const TX0_HEX = "04000000d4c3b2a100000000000000003c1d454b2ffa5e2b2c6cfb1330b8d3d02ad4aee303176f955a423c2c40cbfaa9";
const TX1_HEX = "04000000d4c3b2a10100000000000000c9a3a70c59fb5a3e7e518aabcab9564a437c3cdcef1f9b0d9bf948393c00b489";
const TXMAX_HEX = "04000000d4c3b2a1fedfffffffffffff0fde66cda55701a5e7adac8d8e9f313d";

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
    i = 0;
    while (i < 32) : (i += 1) g_peer.replay_bitmap[i] = 0;
    g_peer.replay_counter = 0;
    g_peer.replay_valid = false;
    g_peer.sending_counter = 0;
    g_peer.last_tx_ms = 0;
    g_peer.last_rx_ms = 0;
}

fn setup(dev: *wg.WgDevice, priv_i: *const [32]u8) void {
    dev.peers = g_peers[0..];
    wg.wgInit(dev, priv_i);
    dev.rng = rand.xoshiroInit(SEED_I);
    wg.wgAddPeer(dev, &g_peer) catch @panic("add peer");
}

fn basePeer() void {
    resetPeer();
    _ = unhex(PRIV_I_HEX, g_peer.static_priv[0..]);
    _ = unhex(PUB_R_HEX, g_peer.remote_static_pub[0..]);
}

fn setupSession(dev: *wg.WgDevice, priv_i: *const [32]u8) void {
    var init: [wg.WG_INITIATION_LEN]u8 = undefined;
    var resp: [wg.WG_RESPONSE_LEN]u8 = undefined;
    _ = unhex(RESP_HEX, resp[0..]);
    basePeer();
    setup(dev, priv_i);
    _ = wg.wgCreateInitiation(dev, &dev.peers[0], WALL_NS, init[0..]) catch @panic("session initiation");
    wg.wgProcessResponse(dev, &dev.peers[0], resp[0..]) catch @panic("session response");
}

fn expectSendError(dev: *wg.WgDevice, now: u64, want: wg.WgError, what: []const u8) void {
    var out: [wg.WG_TRANSPORT_HDR_LEN + 2048 + wg.WG_AUTHTAG_LEN]u8 = undefined;
    var saw: bool = false;
    _ = wg.wgSend(dev, now, 0, out[0..0], out[0..]) catch |err| {
        ck(err == want, what);
        saw = true;
    };
    ck(saw, what);
}

fn store64le(p: []u8, off: usize, v: u64) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) p[off + i] = @intCast(u8, (v >> @intCast(u64, i * 8)) & 0xFF);
}

fn load64le(p: []const u8, off: usize) u64 {
    var v: u64 = 0;
    var shift: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        v |= @intCast(u64, p[off + i]) << shift;
        shift += 8;
    }
    return v;
}

fn makeTransport(key: *const [32]u8, receiver: u32, counter: u64, inner: []const u8, out: []u8) usize {
    const padded: usize = (inner.len + 15) & ~@as(usize, 15);
    const total: usize = wg.WG_TRANSPORT_HDR_LEN + padded + wg.WG_AUTHTAG_LEN;
    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;
    out[0] = 4;
    wg.store32le(out, 4, receiver);
    store64le(out, 8, counter);
    i = 0;
    while (i < inner.len) : (i += 1) out[wg.WG_TRANSPORT_HDR_LEN + i] = inner[i];
    var nonce: [12]u8 = undefined;
    i = 0;
    while (i < 12) : (i += 1) nonce[i] = 0;
    store64le(nonce[0..], 4, counter);
    var tag: [16]u8 = undefined;
    cipher.chacha20Poly1305Seal(key, &nonce, out[0..0],
        out[wg.WG_TRANSPORT_HDR_LEN .. wg.WG_TRANSPORT_HDR_LEN + padded],
        out[wg.WG_TRANSPORT_HDR_LEN .. wg.WG_TRANSPORT_HDR_LEN + padded], &tag) catch @panic("make transport");
    i = 0;
    while (i < 16) : (i += 1) out[wg.WG_TRANSPORT_HDR_LEN + padded + i] = tag[i];
    return total;
}

fn ipv4Header(out: []u8, total_len: u16) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) out[i] = 0;
    out[0] = 0x45;
    out[2] = @intCast(u8, total_len >> 8);
    out[3] = @intCast(u8, total_len & 0xFF);
}

pub fn main() void {
    var priv_i: [32]u8 = undefined;
    _ = unhex(PRIV_I_HEX, priv_i[0..]);

    // ---- transport encrypt: counters 0/1/max-1, padding to 16 ----
    var dev: wg.WgDevice = undefined;
    setupSession(&dev, &priv_i);
    var out: [wg.WG_TRANSPORT_HDR_LEN + 2048 + wg.WG_AUTHTAG_LEN]u8 = undefined;
    var pt_a: [13]u8 = undefined;
    _ = unhex("4500001daabbccdd0102030405", pt_a[0..]);
    var pt_b: [3]u8 = undefined;
    _ = unhex("deadbe", pt_b[0..]);

    dev.peers[0].sending_counter = 0;
    dev.peers[0].session_created_ms = 1000;
    dev.peers[0].last_tx_ms = 1000;
    var n = wg.wgSend(&dev, 1000, 0, pt_a[0..], out[0..]) catch @panic("send counter 0");
    ck(n == 48, "counter 0 length");
    ckHex(out[0..n], TX0_HEX, "transport counter 0");
    ck(load64le(out[0..], 8) == 0, "counter 0 wire");

    n = wg.wgSend(&dev, 1000, 0, pt_b[0..], out[0..]) catch @panic("send counter 1");
    ck(n == 48, "counter 1 length");
    ckHex(out[0..n], TX1_HEX, "transport counter 1");
    ck(load64le(out[0..], 8) == 1, "counter 1 wire monotonic");

    dev.peers[0].sending_counter = wg.WG_REJECT_AFTER_MESSAGES - 1;
    n = wg.wgSend(&dev, 1000, 0, out[0..0], out[0..]) catch @panic("send max-1");
    ck(n == 32, "max-1 keepalive length");
    ckHex(out[0..n], TXMAX_HEX, "transport max-before-reject");
    ck(load64le(out[0..], 8) == wg.WG_REJECT_AFTER_MESSAGES - 1, "max-1 wire");
    expectSendError(&dev, 1000, error.SessionExpired, "reject after max counter");

    var dev_none: wg.WgDevice = undefined;
    basePeer();
    setup(&dev_none, &priv_i);
    expectSendError(&dev_none, 1000, error.NoSession, "send without session");

    var dev_exp: wg.WgDevice = undefined;
    setupSession(&dev_exp, &priv_i);
    expectSendError(&dev_exp, wg.WG_REJECT_AFTER_TIME_MS, error.SessionExpired, "send after reject time");

    // ---- replay window (2048-bit) ----
    var dev_rx: wg.WgDevice = undefined;
    setupSession(&dev_rx, &priv_i);
    dev_rx.peers[0].session_created_ms = 0;
    var inner: [20]u8 = undefined;
    ipv4Header(inner[0..], 20);
    var pkt: [wg.WG_TRANSPORT_HDR_LEN + 2048 + wg.WG_AUTHTAG_LEN]u8 = undefined;
    var plain: [2048]u8 = undefined;

    const receiver = dev_rx.peers[0].local_index;
    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 0, inner[0..], pkt[0..]);
    var act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx counter 0");
    switch (act) {
        .inner_packet => |m| ck(m == inner.len, "rx counter 0 length"),
        else => ck(false, "rx counter 0 action"),
    }
    ckHex(plain[0..inner.len], "4500001400000000000000000000000000000000", "rx inner bytes");

    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx duplicate");
    switch (act) {
        .dropped_replay => {},
        else => ck(false, "duplicate replay"),
    }

    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 2047, inner[0..], pkt[0..]);
    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx 2047");
    switch (act) {
        .inner_packet => {},
        else => ck(false, "window edge accepted"),
    }

    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 0, inner[0..], pkt[0..]);
    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx old seen");
    switch (act) {
        .dropped_replay => {},
        else => ck(false, "old seen replay"),
    }

    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 1000, inner[0..], pkt[0..]);
    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx in-window unseen");
    switch (act) {
        .inner_packet => {},
        else => ck(false, "in-window unseen accepted"),
    }

    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 1000, inner[0..], pkt[0..]);
    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx in-window duplicate");
    switch (act) {
        .dropped_replay => {},
        else => ck(false, "in-window duplicate dropped"),
    }

    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 4096, inner[0..], pkt[0..]);
    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx 4096");
    switch (act) {
        .inner_packet => {},
        else => ck(false, "window advance accepted"),
    }

    n = makeTransport(&dev_rx.peers[0].rx_key, receiver, 1000, inner[0..], pkt[0..]);
    act = wg.wgReceive(&dev_rx, 0, pkt[0..n], plain[0..]) catch @panic("rx too old");
    switch (act) {
        .dropped_replay => {},
        else => ck(false, "too-old replay"),
    }

    // ---- timer sweep: 10 s keepalive, 120 s rekey, 5 s + jitter retry, 180 s reject ----
    var dev_t: wg.WgDevice = undefined;
    setupSession(&dev_t, &priv_i);
    dev_t.rng = rand.xoshiroInit(SEED_I);
    var tout: [wg.WG_INITIATION_LEN]u8 = undefined;

    act = wg.wgTick(&dev_t, 0, WALL_NS, tout[0..]) catch @panic("tick 0");
    switch (act) {
        .none => {},
        else => ck(false, "tick 0"),
    }
    act = wg.wgTick(&dev_t, wg.WG_KEEPALIVE_TIMEOUT_MS - 1, WALL_NS, tout[0..]) catch @panic("tick 9999");
    switch (act) {
        .none => {},
        else => ck(false, "tick before keepalive"),
    }
    act = wg.wgTick(&dev_t, wg.WG_KEEPALIVE_TIMEOUT_MS, WALL_NS, tout[0..]) catch @panic("tick 10000");
    switch (act) {
        .send_keepalive => |m| {
            ck(m == 32, "keepalive length");
            ck(tout[0] == 4, "keepalive type");
            ck(load64le(tout[0..], 8) == 0, "keepalive counter");
            ck(dev_t.peers[0].sending_counter == 1, "keepalive counter advance");
        },
        else => ck(false, "keepalive at 10 s"),
    }

    dev_t.peers[0].last_tx_ms = wg.WG_REKEY_AFTER_TIME_MS - 1;
    act = wg.wgTick(&dev_t, wg.WG_REKEY_AFTER_TIME_MS - 1, WALL_NS, tout[0..]) catch @panic("tick 119999");
    switch (act) {
        .none => {},
        else => ck(false, "tick before rekey"),
    }
    act = wg.wgTick(&dev_t, wg.WG_REKEY_AFTER_TIME_MS, WALL_NS, tout[0..]) catch @panic("tick 120000");
    switch (act) {
        .send_handshake => |m| {
            ck(m == wg.WG_INITIATION_LEN, "rekey length");
            ck(dev_t.peers[0].last_handshake_sent_ms == wg.WG_REKEY_AFTER_TIME_MS, "rekey timestamp");
            ck(dev_t.peers[0].handshake_attempts == 1, "rekey attempts");
        },
        else => ck(false, "rekey at 120 s"),
    }

    act = wg.wgTick(&dev_t, wg.WG_REKEY_AFTER_TIME_MS + 5136, WALL_NS, tout[0..]) catch @panic("tick retry-1");
    switch (act) {
        .none => {},
        else => ck(false, "tick before rekey retry"),
    }
    act = wg.wgTick(&dev_t, wg.WG_REKEY_AFTER_TIME_MS + 5137, WALL_NS, tout[0..]) catch @panic("tick retry");
    switch (act) {
        .send_handshake => |m| {
            ck(m == wg.WG_INITIATION_LEN, "retry length");
            ck(dev_t.peers[0].handshake_attempts == 2, "retry attempts");
        },
        else => ck(false, "rekey retry 5 s + jitter"),
    }

    expectSendError(&dev_t, wg.WG_REJECT_AFTER_TIME_MS, error.SessionExpired, "reject at 180 s");
    act = wg.wgTick(&dev_t, wg.WG_REJECT_AFTER_TIME_MS, WALL_NS, tout[0..]) catch @panic("tick 180000");
    switch (act) {
        .send_handshake => |m| ck(m == wg.WG_INITIATION_LEN, "expired tick rekey length"),
        else => ck(false, "expired tick never keepalive/encrypt"),
    }
    act = wg.wgTick(&dev_t, wg.WG_REJECT_AFTER_TIME_MS + 1, WALL_NS, tout[0..]) catch @panic("tick 180001");
    switch (act) {
        .none => {},
        else => ck(false, "expired pending handshake no keepalive"),
    }

    // ---- CookieReply consumption -> mac2 on subsequent initiation ----
    var dev_c: wg.WgDevice = undefined;
    basePeer();
    setup(&dev_c, &priv_i);
    var init1: [wg.WG_INITIATION_LEN]u8 = undefined;
    n = wg.wgCreateInitiation(&dev_c, &dev_c.peers[0], WALL_NS, init1[0..]) catch @panic("cookie init1");
    ck(n == wg.WG_INITIATION_LEN, "cookie init1 length");
    ck(!dev_c.peers[0].cookie_valid, "cookie starts invalid");
    var reply: [64]u8 = undefined;
    _ = unhex(COOKIE_REPLY_HEX, reply[0..]);
    act = wg.wgReceive(&dev_c, 0, reply[0..], plain[0..]) catch @panic("cookie receive");
    switch (act) {
        .none => {},
        else => ck(false, "cookie reply action"),
    }
    ck(dev_c.peers[0].cookie_valid, "cookie stored");

    // The old pending handshake is abandoned before re-initiating with mac2.
    dev_c.peers[0].hs_valid = false;
    dev_c.peers[0].local_index = 0;
    dev_c.rng = rand.xoshiroInit(SEED_I);
    var init2: [wg.WG_INITIATION_LEN]u8 = undefined;
    n = wg.wgCreateInitiation(&dev_c, &dev_c.peers[0], WALL_NS, init2[0..]) catch @panic("cookie init2");
    ck(n == wg.WG_INITIATION_LEN, "cookie init2 length");
    ckHex(init2[0..n], COOKIE_INIT_HEX, "cookie mac2 initiation");
    var diff: bool = false;
    var i: usize = 0;
    while (i < wg.WG_MAC_LEN) : (i += 1) {
        if (init1[132 + i] != init2[132 + i]) diff = true;
    }
    ck(diff, "cookie mac2 changes");

    if (g_fail == 0) {
        std.io.write("wireguard transport ok\n");
    } else {
        std.io.write("wireguard transport FAIL\n");
    }
}
