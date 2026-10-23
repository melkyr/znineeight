// std_wireguard.zig — Z98 std lib: WireGuard NoiseIK initiator handshake.
//
// Sans-I/O protocol state. This task (Phase 1 M6 Task 1) provides the fixed-size
// peer/device state plus the initiator half of the NoiseIK handshake:
//   - construction/identifier hashing and the WireGuard KDF (HMAC-BLAKE2s,
//     paper §5.4), not the keyed-BLAKE2s MAC
//   - initiation construction (ephemeral keygen + sender index from the
//     caller-seeded `dev.rng`, TAI64N from `wall_unix_ns`)
//   - encrypted static key and timestamp (ChaCha20-Poly1305, nonce 0)
//   - mac1 (keyed BLAKE2s-128) and mac2 (cookie, zero until a CookieReply is
//     consumed)
//   - handshake response processing and transport key derivation
//
// `wall_unix_ns` is the wire timestamp source. Never feed `now_ms` here: a
// monotonic TAI64N makes a restarted client look like a timestamp replay to the
// responder. Timers/transport/replay/cookies are Task 2; this file stores their
// state but does not implement them yet.
//
// Errors: Corrupt (length/type/mac), AuthenticationFailed (AEAD/DH),
// NoSession (response with no pending initiation), OutputTooSmall, NoSpace,
// InvalidPeer.

const cipher = @import("std_cipher.zig");
const crypto = @import("std_crypto.zig");
const ecc = @import("std_ecc.zig");
const rand = @import("std_rand.zig");

pub const WG_KEY_LEN: usize = 32;
pub const WG_HASH_LEN: usize = 32;
pub const WG_MAC_LEN: usize = 16;
pub const WG_TAI64N_LEN: usize = 12;
pub const WG_AUTHTAG_LEN: usize = 16;
pub const WG_INITIATION_LEN: usize = 148;
pub const WG_RESPONSE_LEN: usize = 92;
pub const WG_MAX_ALLOWED_IPS: usize = 8;

pub const WgKey = [WG_KEY_LEN]u8;

pub const WgError = error{
    Corrupt,
    AuthenticationFailed,
    NoSession,
    SessionExpired,
    OutputTooSmall,
    NoSpace,
    InvalidPeer,
};

pub const WgAllowedIp = struct {
    ip: u32,
    mask: u32,
};

pub const WgPeer = struct {
    // API shape from spec §5.7. The handshake authenticates the interface key
    // (`WgDevice.iface_priv`) to `remote_static_pub`; `static_priv` is kept for
    // callers that maintain a per-peer key copy.
    static_priv: WgKey,
    remote_static_pub: WgKey,
    preshared_key: WgKey,
    endpoint_ip: u32,
    endpoint_port: u16,
    allowed_ips: [WG_MAX_ALLOWED_IPS]WgAllowedIp,
    allowed_ip_count: usize,

    // Precomputed DH(iface_priv, remote_static_pub) and MAC label keys.
    public_key_dh: WgKey,
    label_mac1_key: WgKey,
    label_cookie_key: WgKey,

    // Handshake state.
    hs_valid: bool,
    hs_initiator: bool,
    local_index: u32,
    remote_index: u32,
    ephemeral_priv: WgKey,
    remote_ephemeral: WgKey,
    hash: WgKey,
    chaining_key: WgKey,
    last_mac1: [WG_MAC_LEN]u8,
    has_mac1: bool,

    // Cookie received in a CookieReply (Task 2 consumes the reply).
    cookie: [WG_MAC_LEN]u8,
    cookie_valid: bool,

    // Derived transport keys (Task 2 encrypts/decrypts with these).
    tx_key: WgKey,
    rx_key: WgKey,
    session_valid: bool,

    // Timer bookkeeping reserved for Task 2.
    last_handshake_sent_ms: u64,
    last_handshake_received_ms: u64,
    session_created_ms: u64,
    handshake_attempts: u32,
};

pub const WgDevice = struct {
    iface_priv: WgKey,
    iface_pub: WgKey,
    peers: []WgPeer,
    peer_count: usize,
    rng: rand.Xoshiro256,
    label_mac1_key: WgKey,
    label_cookie_key: WgKey,
};

const CONSTRUCTION = "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s";
const IDENTIFIER = "WireGuard v1 zx2c4 Jason@zx2c4.com";
const LABEL_MAC1 = "mac1----";
const LABEL_COOKIE = "cookie--";

fn zeroBytes(out: []u8) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) out[i] = 0;
}

fn copyBytes(dst: []u8, src: []const u8) void {
    var n: usize = src.len;
    if (n > dst.len) n = dst.len;
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = src[i];
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) diff |= a[i] ^ b[i];
    return diff == 0;
}

fn isZero32(p: []const u8) bool {
    var acc: u8 = 0;
    var i: usize = 0;
    while (i < 32) : (i += 1) acc |= p[i];
    return acc == 0;
}

pub fn load32le(p: []const u8, off: usize) u32 {
    return @intCast(u32, p[off]) |
        (@intCast(u32, p[off + 1]) << 8) |
        (@intCast(u32, p[off + 2]) << 16) |
        (@intCast(u32, p[off + 3]) << 24);
}

pub fn store32le(p: []u8, off: usize, v: u32) void {
    p[off] = @intCast(u8, v & 0xFF);
    p[off + 1] = @intCast(u8, (v >> 8) & 0xFF);
    p[off + 2] = @intCast(u8, (v >> 16) & 0xFF);
    p[off + 3] = @intCast(u8, (v >> 24) & 0xFF);
}

fn blake2s(data: []const u8, out: []u8) void {
    var s = crypto.blake2sInit("", @intCast(u32, out.len));
    crypto.blake2sUpdate(&s, data);
    crypto.blake2sFinal(&s, out);
}

fn blake2s2(a: []const u8, b: []const u8, out: []u8) void {
    var s = crypto.blake2sInit("", @intCast(u32, out.len));
    crypto.blake2sUpdate(&s, a);
    crypto.blake2sUpdate(&s, b);
    crypto.blake2sFinal(&s, out);
}

fn keyedMac15(key: []const u8, msg: []const u8, out: *[WG_MAC_LEN]u8) void {
    var s = crypto.blake2sInit(key, WG_MAC_LEN);
    crypto.blake2sUpdate(&s, msg);
    crypto.blake2sFinal(&s, out[0..]);
}

fn hmacBlake2s(out: *[WG_HASH_LEN]u8, key: []const u8, msg: []const u8) void {
    var k_ipad: [64]u8 = undefined;
    var k_opad: [64]u8 = undefined;
    var tk: [WG_HASH_LEN]u8 = undefined;
    zeroBytes(k_ipad[0..]);
    zeroBytes(k_opad[0..]);

    var k: []const u8 = key;
    if (k.len > 64) {
        blake2s(k, tk[0..]);
        k = tk[0..];
    }
    copyBytes(k_ipad[0..], k);
    copyBytes(k_opad[0..], k);
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        k_ipad[i] = k_ipad[i] ^ 0x36;
        k_opad[i] = k_opad[i] ^ 0x5C;
    }

    var inner: [WG_HASH_LEN]u8 = undefined;
    var s = crypto.blake2sInit("", WG_HASH_LEN);
    crypto.blake2sUpdate(&s, k_ipad[0..]);
    crypto.blake2sUpdate(&s, msg);
    crypto.blake2sFinal(&s, inner[0..]);

    s = crypto.blake2sInit("", WG_HASH_LEN);
    crypto.blake2sUpdate(&s, k_opad[0..]);
    crypto.blake2sUpdate(&s, inner[0..]);
    crypto.blake2sFinal(&s, out[0..]);
}

fn mixHash(h: *[WG_HASH_LEN]u8, data: []const u8) void {
    var prev: [WG_HASH_LEN]u8 = undefined;
    copyBytes(prev[0..], h[0..]);
    blake2s2(prev[0..], data, h[0..]);
}

fn kdf1(ck: *[WG_HASH_LEN]u8, data: []const u8) void {
    var tau0: [WG_HASH_LEN]u8 = undefined;
    var one: [1]u8 = undefined;
    one[0] = 1;
    hmacBlake2s(&tau0, ck[0..], data);
    hmacBlake2s(ck, tau0[0..], one[0..]);
}

// WireGuard KDF2: ck := T1, key := T2.
fn kdf2(ck: *[WG_HASH_LEN]u8, data: []const u8, key: *[WG_HASH_LEN]u8) void {
    var tau0: [WG_HASH_LEN]u8 = undefined;
    var input: [WG_HASH_LEN + 1]u8 = undefined;
    var t1: [WG_HASH_LEN]u8 = undefined;
    hmacBlake2s(&tau0, ck[0..], data);
    input[0] = 1;
    hmacBlake2s(&t1, tau0[0..], input[0..1]);
    copyBytes(input[0..WG_HASH_LEN], t1[0..]);
    input[WG_HASH_LEN] = 2;
    hmacBlake2s(key, tau0[0..], input[0..]);
    copyBytes(ck[0..], t1[0..]);
}

// WireGuard KDF3: ck := T1, tau := T2, key := T3.
fn kdf3(ck: *[WG_HASH_LEN]u8, data: []const u8, tau: *[WG_HASH_LEN]u8, key: *[WG_HASH_LEN]u8) void {
    var tau0: [WG_HASH_LEN]u8 = undefined;
    var input: [WG_HASH_LEN + 1]u8 = undefined;
    var t1: [WG_HASH_LEN]u8 = undefined;
    hmacBlake2s(&tau0, ck[0..], data);
    input[0] = 1;
    hmacBlake2s(&t1, tau0[0..], input[0..1]);
    copyBytes(input[0..WG_HASH_LEN], t1[0..]);
    input[WG_HASH_LEN] = 2;
    hmacBlake2s(tau, tau0[0..], input[0..]);
    copyBytes(input[0..WG_HASH_LEN], tau[0..]);
    input[WG_HASH_LEN] = 3;
    hmacBlake2s(key, tau0[0..], input[0..]);
    copyBytes(ck[0..], t1[0..]);
}

fn macKey(out: *[WG_HASH_LEN]u8, pub_key: *const [WG_KEY_LEN]u8, label: []const u8) void {
    blake2s2(label, pub_key[0..], out[0..]);
}

fn sealHandshake(key: *const [WG_KEY_LEN]u8, ad: []const u8, pt: []const u8, ct: []u8, tag: *[WG_MAC_LEN]u8) WgError!void {
    var nonce: [12]u8 = undefined;
    zeroBytes(nonce[0..]);
    cipher.chacha20Poly1305Seal(key, &nonce, ad, pt, ct, tag) catch return error.Corrupt;
}

fn openHandshake(key: *const [WG_KEY_LEN]u8, ad: []const u8, ct: []const u8, tag: *const [WG_MAC_LEN]u8, pt: []u8) WgError!void {
    var nonce: [12]u8 = undefined;
    zeroBytes(nonce[0..]);
    cipher.chacha20Poly1305Open(key, &nonce, ad, ct, tag, pt) catch |err| {
        if (err == error.AuthenticationFailed) return error.AuthenticationFailed;
        return error.Corrupt;
    };
}

fn fillRandom(rng: *rand.Xoshiro256, out: []u8) void {
    var i: usize = 0;
    while (i < out.len) {
        const v: u64 = rand.xoshiroNext(rng);
        var j: usize = 0;
        while (j < 8 and i < out.len) : (j += 1) {
            out[i] = @intCast(u8, (v >> @intCast(u6, (7 - j) * 8)) & 0xFF);
            i += 1;
        }
    }
}

fn generatePrivate(rng: *rand.Xoshiro256, out: *[WG_KEY_LEN]u8) void {
    fillRandom(rng, out[0..]);
    out[0] = out[0] & 248;
    out[31] = (out[31] & 127) | 64;
}

fn nextIndex(dev: *WgDevice) u32 {
    while (true) {
        const v: u32 = @intCast(u32, rand.xoshiroNext(&dev.rng) & @intCast(u64, 0xFFFFFFFF));
        if (v == 0 or v == 0xFFFFFFFF) continue;
        var used: bool = false;
        var i: usize = 0;
        while (i < dev.peer_count) : (i += 1) {
            const p = &dev.peers[i];
            if (p.hs_valid and p.local_index == v) used = true;
        }
        if (!used) return v;
    }
    return 0;
}

fn deriveLabelKeys(dev: *WgDevice, pub_key: *const [WG_KEY_LEN]u8, mac1: *[WG_HASH_LEN]u8, cookie: *[WG_HASH_LEN]u8) void {
    macKey(mac1, pub_key, LABEL_MAC1);
    macKey(cookie, pub_key, LABEL_COOKIE);
}

pub fn wgTai64n(wall_unix_ns: u64, out: *[WG_TAI64N_LEN]u8) void {
    const seconds: u64 = 0x400000000000000A + (wall_unix_ns / 1000000000);
    const nanos: u32 = @intCast(u32, wall_unix_ns % 1000000000);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        out[7 - i] = @intCast(u8, (seconds >> @intCast(u6, i * 8)) & 0xFF);
    }
    i = 0;
    while (i < 4) : (i += 1) {
        out[11 - i] = @intCast(u8, (@intCast(u64, nanos) >> @intCast(u6, i * 8)) & 0xFF);
    }
}

pub fn wgInit(dev: *WgDevice, iface_priv: *const [WG_KEY_LEN]u8) void {
    copyBytes(dev.iface_priv[0..], iface_priv[0..]);
    zeroBytes(dev.iface_pub[0..]);
    ecc.x25519Base(iface_priv, &dev.iface_pub) catch {
        zeroBytes(dev.iface_pub[0..]);
    };
    deriveLabelKeys(dev, &dev.iface_pub, &dev.label_mac1_key, &dev.label_cookie_key);
    dev.peer_count = 0;
    dev.rng = rand.xoshiroInit(0);
}

pub fn wgAddPeer(dev: *WgDevice, peer: *const WgPeer) WgError!void {
    if (isZero32(peer.remote_static_pub[0..])) return error.InvalidPeer;
    if (dev.peer_count >= dev.peers.len) return error.NoSpace;
    var dh: [WG_KEY_LEN]u8 = undefined;
    ecc.x25519(&dev.iface_priv, &peer.remote_static_pub, &dh) catch return error.InvalidPeer;
    if (isZero32(dh[0..])) return error.InvalidPeer;

    var slot = &dev.peers[dev.peer_count];
    slot.* = peer.*;
    copyBytes(slot.public_key_dh[0..], dh[0..]);
    deriveLabelKeys(dev, &slot.remote_static_pub, &slot.label_mac1_key, &slot.label_cookie_key);
    slot.hs_valid = false;
    slot.hs_initiator = false;
    slot.local_index = 0;
    slot.remote_index = 0;
    slot.has_mac1 = false;
    slot.cookie_valid = false;
    slot.session_valid = false;
    zeroBytes(slot.last_mac1[0..]);
    zeroBytes(slot.cookie[0..]);
    zeroBytes(slot.tx_key[0..]);
    zeroBytes(slot.rx_key[0..]);
    zeroBytes(slot.hash[0..]);
    zeroBytes(slot.chaining_key[0..]);
    zeroBytes(slot.ephemeral_priv[0..]);
    zeroBytes(slot.remote_ephemeral[0..]);
    dev.peer_count += 1;
}

// Build a WireGuard handshake initiation (type 1, 148 bytes) into `out`.
// The ephemeral private key and sender index are drawn from `dev.rng`; seed it
// explicitly (`dev.rng = rand.xoshiroInit(seed)`) for deterministic output.
pub fn wgCreateInitiation(dev: *WgDevice, peer: *WgPeer, wall_unix_ns: u64, out: []u8) WgError!usize {
    if (out.len < WG_INITIATION_LEN) return error.OutputTooSmall;
    if (isZero32(dev.iface_pub[0..])) return error.InvalidPeer;

    var ck: [WG_HASH_LEN]u8 = undefined;
    var hash: [WG_HASH_LEN]u8 = undefined;
    var key: [WG_KEY_LEN]u8 = undefined;
    var dh: [WG_KEY_LEN]u8 = undefined;
    var eph_priv: [WG_KEY_LEN]u8 = undefined;
    var eph_pub: [WG_KEY_LEN]u8 = undefined;
    var timestamp: [WG_TAI64N_LEN]u8 = undefined;
    var tag: [WG_MAC_LEN]u8 = undefined;
    var mac1: [WG_MAC_LEN]u8 = undefined;
    var mac2: [WG_MAC_LEN]u8 = undefined;

    zeroBytes(out[0..WG_INITIATION_LEN]);
    blake2s(CONSTRUCTION, ck[0..]);
    blake2s2(ck[0..], IDENTIFIER, hash[0..]);
    mixHash(&hash, peer.remote_static_pub[0..]);

    generatePrivate(&dev.rng, &eph_priv);
    ecc.x25519Base(&eph_priv, &eph_pub) catch return error.InvalidPeer;
    copyBytes(out[8..40], eph_pub[0..]);

    kdf1(&ck, out[8..40]);
    mixHash(&hash, out[8..40]);

    ecc.x25519(&eph_priv, &peer.remote_static_pub, &dh) catch return error.AuthenticationFailed;
    if (isZero32(dh[0..])) return error.AuthenticationFailed;
    kdf2(&ck, dh[0..], &key);
    sealHandshake(&key, hash[0..], dev.iface_pub[0..], out[40..72], &tag) catch return error.Corrupt;
    copyBytes(out[72..88], tag[0..]);
    mixHash(&hash, out[40..88]);

    // DH(iface_priv, remote_static_pub) is precomputed by wgAddPeer.
    copyBytes(dh[0..], peer.public_key_dh[0..]);
    kdf2(&ck, dh[0..], &key);
    wgTai64n(wall_unix_ns, &timestamp);
    sealHandshake(&key, hash[0..], timestamp[0..], out[88..100], &tag) catch return error.Corrupt;
    copyBytes(out[100..116], tag[0..]);
    mixHash(&hash, out[88..116]);

    out[0] = 1;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;
    const idx = nextIndex(dev);
    store32le(out, 4, idx);

    keyedMac15(peer.label_mac1_key[0..], out[0 .. WG_INITIATION_LEN - 2 * WG_MAC_LEN], &mac1);
    copyBytes(out[116..132], mac1[0..]);
    if (peer.cookie_valid) {
        keyedMac15(peer.cookie[0..], out[0 .. WG_INITIATION_LEN - WG_MAC_LEN], &mac2);
        copyBytes(out[132..148], mac2[0..]);
    } else {
        zeroBytes(out[132..148]);
    }

    peer.hs_valid = true;
    peer.hs_initiator = true;
    peer.local_index = idx;
    peer.remote_index = 0;
    copyBytes(peer.ephemeral_priv[0..], eph_priv[0..]);
    zeroBytes(peer.remote_ephemeral[0..]);
    copyBytes(peer.hash[0..], hash[0..]);
    copyBytes(peer.chaining_key[0..], ck[0..]);
    copyBytes(peer.last_mac1[0..], out[116..132]);
    peer.has_mac1 = true;
    return WG_INITIATION_LEN;
}

// Process a WireGuard handshake response (type 2, 92 bytes). On success the
// peer has `tx_key`/`rx_key` for the initiator direction and `session_valid`.
pub fn wgProcessResponse(dev: *WgDevice, peer: *WgPeer, msg: []const u8) WgError!void {
    if (msg.len != WG_RESPONSE_LEN) return error.Corrupt;
    if (msg[0] != 2 or msg[1] != 0 or msg[2] != 0 or msg[3] != 0) return error.Corrupt;
    if (!peer.hs_valid or !peer.hs_initiator) return error.NoSession;

    const sender = load32le(msg, 4);
    const receiver = load32le(msg, 8);
    if (receiver != peer.local_index) return error.Corrupt;

    var want_mac: [WG_MAC_LEN]u8 = undefined;
    keyedMac15(dev.label_mac1_key[0..], msg[0 .. WG_RESPONSE_LEN - 2 * WG_MAC_LEN], &want_mac);
    if (!eqBytes(want_mac[0..], msg[60..76])) return error.Corrupt;

    var mac2_zero: u8 = 0;
    var i: usize = 0;
    while (i < WG_MAC_LEN) : (i += 1) mac2_zero |= msg[76 + i];
    if (mac2_zero != 0) {
        if (!peer.cookie_valid) return error.Corrupt;
        keyedMac15(peer.cookie[0..], msg[0 .. WG_RESPONSE_LEN - WG_MAC_LEN], &want_mac);
        if (!eqBytes(want_mac[0..], msg[76..92])) return error.Corrupt;
    }

    var hash: [WG_HASH_LEN]u8 = undefined;
    var ck: [WG_HASH_LEN]u8 = undefined;
    var key: [WG_KEY_LEN]u8 = undefined;
    var tau: [WG_HASH_LEN]u8 = undefined;
    var dh: [WG_KEY_LEN]u8 = undefined;
    var tx: [WG_KEY_LEN]u8 = undefined;
    var rx: [WG_KEY_LEN]u8 = undefined;
    var remote_eph: [WG_KEY_LEN]u8 = undefined;
    var tag: [WG_MAC_LEN]u8 = undefined;
    copyBytes(remote_eph[0..], msg[12..44]);
    copyBytes(hash[0..], peer.hash[0..]);
    copyBytes(ck[0..], peer.chaining_key[0..]);

    kdf1(&ck, remote_eph[0..]);
    mixHash(&hash, remote_eph[0..]);

    ecc.x25519(&peer.ephemeral_priv, &remote_eph, &dh) catch return error.AuthenticationFailed;
    if (isZero32(dh[0..])) return error.AuthenticationFailed;
    kdf1(&ck, dh[0..]);

    ecc.x25519(&dev.iface_priv, &remote_eph, &dh) catch return error.AuthenticationFailed;
    if (isZero32(dh[0..])) return error.AuthenticationFailed;
    kdf1(&ck, dh[0..]);

    kdf3(&ck, peer.preshared_key[0..], &tau, &key);
    mixHash(&hash, tau[0..]);

    // enc_empty is a 16-byte tag over the empty plaintext.
    var empty: [1]u8 = undefined;
    copyBytes(tag[0..], msg[44..60]);
    openHandshake(&key, hash[0..], empty[0..0], &tag, empty[0..0]) catch |err| {
        return err;
    };

    kdf2(&ck, empty[0..0], &rx);
    copyBytes(tx[0..], ck[0..]);

    copyBytes(peer.tx_key[0..], tx[0..]);
    copyBytes(peer.rx_key[0..], rx[0..]);
    peer.remote_index = sender;
    peer.session_valid = true;
    peer.hs_valid = false;
    peer.hs_initiator = false;
}
