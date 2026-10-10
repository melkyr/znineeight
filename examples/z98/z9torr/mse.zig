// mse.zig — z9torr: BitTorrent Message Stream Encryption (MSE / PE) handshake.
//
// Spec 2026-10-09 §4.2 (binding; corrected 2026-10-09: the RC4 keys include
// SKEY = the torrent info_hash). Initiator (outbound) side only; the responder
// half lives in `tools/mock_mse_peer.zig`, which reuses the DH/hash helpers
// exported here.
//
// Byte layout (all big-endian), pinned against the canonical MSE spec and
// verified byte-for-byte against a recorded in-the-wild handshake (Transmission
// tests/libtransmission/handshake-test.cc, HandshakeTest.outgoingEncrypted):
//
//   step1 A->B: Ya (96) || PadA (0..512, plaintext)
//   step2 B->A: Yb (96) || PadB (0..512, plaintext)
//   step3 A->B: HASH('req1'||S)                        (20, plaintext)
//               HASH('req2'||SKEY) xor HASH('req3'||S) (20, plaintext)
//               ENCRYPT_A( VC(8 x 0) || crypto_provide(u32) ||
//                          len(PadC)(u16) || PadC || len(IA)(u16) || IA )
//   step4 B->A: ENCRYPT_B( VC(8 x 0) || crypto_select(u32) ||
//                          len(PadD)(u16) || PadD ) || ENCRYPT2(payload)
//   step5 A->B: ENCRYPT2(payload)
//
//   S      = Yb^Xa mod P = Ya^Xb mod P   (96-byte BE)
//   keyA   = SHA1("keyA" || S || SKEY)   A encrypts / B decrypts
//   keyB   = SHA1("keyB" || S || SKEY)   B encrypts / A decrypts
//   SKEY   = info_hash (20 bytes)
// Each RC4 context discards its first 1024 keystream bytes before use.
// Because PadB's length is unknown, A scans the INCOMING RAW bytes for the
// 8-byte ENCRYPT_B(VC) pattern (computed as the first 8 keystream bytes of the
// B->A RC4 context), consuming PadB unencrypted, then advances the RC4 context
// past the VC. PadA/PadC/PadD are sent as zero length.
//
// The handshake is BLOCKING (select(2)-gated on the non-blocking socket, with a
// fixed deadline), matching `wire.readHandshake`/`writeHandshake`; it does not
// use `@asyncSuspend`, so it is safe to call from `peerRun` before the message
// loop and avoids the D3/D4 coroutine-frame hazards.
//
// Z98 rules: free functions only, no generics/`anytype`, strict `@intCast`,
// every `switch` has `else`, string literals via `var s: []const u8`. D2: every
// slice is `[]u8`/`[]const u8` (primitive) or a fixed array.

const std = @import("std");
const std_net = @import("std_net");
const std_crypto = @import("std_crypto");
const logmod = @import("log.zig");

pub const MseError = error{
    MseFailed,
    BadMethod,
    Timeout,
    PeerClosed,
    NetFailed,
};

// Two RC4 contexts for one encrypted connection: `out` encrypts A->B (keyA),
// `in` decrypts B->A (keyB).
pub const Rc4Pair = struct {
    out: std_crypto.Rc4,
    in: std_crypto.Rc4,
};

pub const DH_LEN: usize = 96;
pub const HASH_LEN: usize = 20;
pub const VC_LEN: usize = 8;
pub const PAD_MAX: u32 = 512;
pub const DISCARD: usize = 1024;

// MSE crypto method bitfield bits (spec §4.2).
pub const CRYPTO_PLAINTEXT: u32 = 0x01;
pub const CRYPTO_RC4: u32 = 0x02;

// Absolute handshake deadline. Bounds a silent/non-MSE peer so the plaintext
// fallback reconnect fires promptly.
const DEADLINE_MS: u32 = 3000;

// Max raw bytes scanned for ENCRYPT_B(VC): PadB (<= 512) plus the VC itself.
const SCAN_MAX: u32 = PAD_MAX + 8;

// RFC 2409 MODP group 1 / Azureus MSE 768-bit safe prime, generator 2. Same
// literal as std_crypto's modpow fixtures and Task 1.
pub const DH_PRIME = [96]u8{
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xC9, 0x0F, 0xDA, 0xA2,
    0x21, 0x68, 0xC2, 0x34, 0xC4, 0xC6, 0x62, 0x8B, 0x80, 0xDC, 0x1C, 0xD1,
    0x29, 0x02, 0x4E, 0x08, 0x8A, 0x67, 0xCC, 0x74, 0x02, 0x0B, 0xBE, 0xA6,
    0x3B, 0x13, 0x9B, 0x22, 0x51, 0x4A, 0x08, 0x79, 0x8E, 0x34, 0x04, 0xDD,
    0xEF, 0x95, 0x19, 0xB3, 0xCD, 0x3A, 0x43, 0x1B, 0x30, 0x2B, 0x0A, 0x6D,
    0xF2, 0x5F, 0x14, 0x37, 0x4F, 0xE1, 0x35, 0x6D, 0x6D, 0x51, 0xC2, 0x45,
    0xE4, 0x85, 0xB5, 0x76, 0x62, 0x5E, 0x7E, 0xC6, 0xF4, 0x4C, 0x42, 0xE9,
    0xA6, 0x3A, 0x36, 0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x09, 0x05, 0x63,
};

// --- shared crypto helpers (also used by the responder mock) ----------------

// SHA1(label || data) into `out`.
pub fn hash2(label: []const u8, data: []const u8, out: *[HASH_LEN]u8) void {
    var h = std_crypto.sha1Init();
    std_crypto.sha1Update(&h, label);
    std_crypto.sha1Update(&h, data);
    std_crypto.sha1Final(&h, out);
}

// SHA1(label || a || b) into `out` (keyA/keyB derivation).
pub fn hash3(label: []const u8, a: []const u8, b: []const u8, out: *[HASH_LEN]u8) void {
    var h = std_crypto.sha1Init();
    std_crypto.sha1Update(&h, label);
    std_crypto.sha1Update(&h, a);
    std_crypto.sha1Update(&h, b);
    std_crypto.sha1Final(&h, out);
}

// Ya = 2^Xa mod P (96-byte BE out).
pub fn dhPublic(xa: []const u8, out: []u8) void {
    var two: [1]u8 = undefined;
    two[0] = 2;
    std_crypto.modpow(two[0..], xa, DH_PRIME[0..], out);
}

// S = Yb^Xa mod P (96-byte BE out).
pub fn dhShared(yb: []const u8, xa: []const u8, out: []u8) void {
    std_crypto.modpow(yb, xa, DH_PRIME[0..], out);
}

// keyA/keyB for an initiator: keyA = SHA1("keyA"||S||SKEY), keyB likewise.
pub fn deriveKeys(s: []const u8, info_hash: []const u8, key_a: *[HASH_LEN]u8, key_b: *[HASH_LEN]u8) void {
    var ka: []const u8 = "keyA";
    var kb: []const u8 = "keyB";
    hash3(ka, s, info_hash, key_a);
    hash3(kb, s, info_hash, key_b);
}

// Deterministic ephemeral 20-byte private key from a seed (non-zero).
pub fn makeSecret(seed: u32, out: []u8) void {
    var st: u32 = seed;
    if (st == 0) st = 1;
    var i: usize = 0;
    var any: u32 = 0;
    while (i < out.len) : (i += 1) {
        st = st *% @intCast(u32, 1664525) +% @intCast(u32, 1013904223);
        var b: u8 = @intCast(u8, (st >> 16) & @intCast(u32, 0xFF));
        out[i] = b;
        any |= @intCast(u32, b);
    }
    if (any == 0) out[0] = 1;
}

// --- local byte helpers -----------------------------------------------------
fn readU32BE(b: []const u8) u32 {
    return (@intCast(u32, b[0]) << 24) | (@intCast(u32, b[1]) << 16) |
        (@intCast(u32, b[2]) << 8) | @intCast(u32, b[3]);
}

fn writeU32BE(b: []u8, v: u32) void {
    b[0] = @intCast(u8, (v >> 24) & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (v >> 16) & @intCast(u32, 0xFF));
    b[2] = @intCast(u8, (v >> 8) & @intCast(u32, 0xFF));
    b[3] = @intCast(u8, v & @intCast(u32, 0xFF));
}

fn readU16BE(b: []const u8) u16 {
    return (@intCast(u16, b[0]) << 8) | @intCast(u16, b[1]);
}

fn writeU16BE(b: []u8, v: u16) void {
    b[0] = @intCast(u8, (v >> 8) & @intCast(u16, 0xFF));
    b[1] = @intCast(u8, v & @intCast(u16, 0xFF));
}

fn burn1024(ctx: *std_crypto.Rc4) void {
    var burn: [DISCARD]u8 = undefined;
    var i: usize = 0;
    while (i < DISCARD) : (i += 1) burn[i] = 0;
    std_crypto.rc4Apply(ctx, burn[0..]);
}

// --- blocking, select-gated transport ---------------------------------------

fn waitReadable(sock: std_net.Socket, remaining_ms: i32) MseError!void {
    var s: std_net.Socket = sock;
    var fds: std_net.fd_set = undefined;
    std_net.fdZero(@ptrCast(*u8, &fds));
    std_net.fdSet(s, @ptrCast(*u8, &fds));
    const sr = std_net.select(s + 1, @ptrCast(*u8, &fds), null, null, remaining_ms);
    if (sr == 0) return error.Timeout;
    if (sr < 0) return error.NetFailed;
}

fn waitWritable(sock: std_net.Socket, remaining_ms: i32) MseError!void {
    var s: std_net.Socket = sock;
    var fds: std_net.fd_set = undefined;
    std_net.fdZero(@ptrCast(*u8, &fds));
    std_net.fdSet(s, @ptrCast(*u8, &fds));
    const sr = std_net.select(s + 1, null, @ptrCast(*u8, &fds), null, remaining_ms);
    if (sr == 0) return error.Timeout;
    if (sr < 0) return error.NetFailed;
}

fn sendAllMse(sock: std_net.Socket, data: []const u8, start_ms: u32) MseError!void {
    var s: std_net.Socket = sock;
    var off: usize = 0;
    while (off < data.len) {
        var now: u32 = std.time.ticksMs();
        if (now - start_ms >= DEADLINE_MS) return error.Timeout;
        var rem: i32 = @intCast(i32, DEADLINE_MS - (now - start_ms));
        const n = std_net.sendNonBlocking(&s, data[off..]) catch |e| {
            if (e == error.WouldBlock) {
                try waitWritable(sock, rem);
                continue;
            }
            return error.NetFailed;
        };
        if (n == 0) return error.NetFailed;
        off += n;
    }
}

fn recvExactMse(sock: std_net.Socket, dst: []u8, start_ms: u32) MseError!void {
    var s: std_net.Socket = sock;
    var off: usize = 0;
    while (off < dst.len) {
        var now: u32 = std.time.ticksMs();
        if (now - start_ms >= DEADLINE_MS) return error.Timeout;
        var rem: i32 = @intCast(i32, DEADLINE_MS - (now - start_ms));
        const n = std_net.recvNonBlocking(&s, dst[off..]) catch |e| {
            if (e == error.WouldBlock) {
                try waitReadable(sock, rem);
                continue;
            }
            return error.NetFailed;
        };
        if (n == 0) return error.PeerClosed;
        off += n;
    }
}

// Read exactly `dst.len` bytes then RC4-decrypt them in place.
fn recvDecMse(sock: std_net.Socket, ctx: *std_crypto.Rc4, dst: []u8, start_ms: u32) MseError!void {
    try recvExactMse(sock, dst, start_ms);
    std_crypto.rc4Apply(ctx, dst);
}

fn isZero8(b: []const u8) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (b[i] != 0) return false;
    }
    return true;
}

fn eq8(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// --- initiator handshake ----------------------------------------------------

// Name for an `mse.MseError` in the `Z9TORR_LOG` stage trace.
fn mseErrName(e: MseError) []const u8 {
    if (e == error.MseFailed) return "MseFailed";
    if (e == error.BadMethod) return "BadMethod";
    if (e == error.Timeout) return "Timeout";
    if (e == error.PeerClosed) return "PeerClosed";
    if (e == error.NetFailed) return "NetFailed";
    return "Unknown";
}

// `mse stage=<label> fail err=<name>` — record the exact failing stage then
// return the error unchanged. Strictly a formatter (no-op when logging is off).
fn stageFail(label: []const u8, e: MseError) MseError {
    logmod.s("mse stage=");
    logmod.s(label);
    logmod.s(" fail err=");
    logmod.s(mseErrName(e));
    logmod.nl();
    return e;
}

// Outbound MSE/PE handshake: send Ya, read Yb, sync on the responder's VC, and
// return the two RC4 contexts (already advanced past the 1024-byte discard and
// the 8-byte VC). We offer RC4 only; a responder that selects anything else is
// `MseError.BadMethod`, and the caller falls back to a plaintext reconnect.
pub fn mseConnect(sock: std_net.Socket, info_hash: []const u8, seed: u32) MseError!Rc4Pair {
    if (info_hash.len != HASH_LEN) return error.MseFailed;
    var start_ms: u32 = std.time.ticksMs();

    // step 1: ephemeral key + Ya (PadA empty).
    var xa: [HASH_LEN]u8 = undefined;
    makeSecret(seed, xa[0..]);
    var ya: [DH_LEN]u8 = undefined;
    dhPublic(xa[0..], ya[0..]);
    logmod.s("mse stage=ya len=");
    logmod.u32v(@intCast(u32, DH_LEN));
    logmod.s(" hex=");
    logmod.hex(ya[0..]);
    logmod.nl();
    sendAllMse(sock, ya[0..], start_ms) catch |e| return stageFail("ya", e);

    // step 2: read Yb (PadB is handled by the VC scan below).
    var yb: [DH_LEN]u8 = undefined;
    recvExactMse(sock, yb[0..], start_ms) catch |e| return stageFail("yb", e);
    logmod.s("mse stage=yb len=");
    logmod.u32v(@intCast(u32, DH_LEN));
    logmod.s(" hex=");
    logmod.hex(yb[0..]);
    logmod.nl();

    var s: [DH_LEN]u8 = undefined;
    dhShared(yb[0..], xa[0..], s[0..]);

    var key_a: [HASH_LEN]u8 = undefined;
    var key_b: [HASH_LEN]u8 = undefined;
    deriveKeys(s[0..], info_hash, &key_a, &key_b);
    logmod.s("mse stage=keys key_a=");
    logmod.hex(key_a[0..]);
    logmod.s(" key_b=");
    logmod.hex(key_b[0..]);
    logmod.nl();

    var rc4_out: std_crypto.Rc4 = undefined;
    var rc4_in: std_crypto.Rc4 = undefined;
    std_crypto.rc4Init(key_a[0..], &rc4_out);
    std_crypto.rc4Init(key_b[0..], &rc4_in);
    burn1024(&rc4_out);
    burn1024(&rc4_in);

    // step 3: req1, req2xor, ENCRYPT_A(VC, provide, len(PadC)=0, len(IA)=0).
    var req1: [HASH_LEN]u8 = undefined;
    hash2("req1", s[0..], &req1);
    var r2: [HASH_LEN]u8 = undefined;
    hash2("req2", info_hash, &r2);
    var r3: [HASH_LEN]u8 = undefined;
    hash2("req3", s[0..], &r3);
    var req2x: [HASH_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < HASH_LEN) : (i += 1) req2x[i] = r2[i] ^ r3[i];
    logmod.s("mse stage=req1 hex=");
    logmod.hex(req1[0..]);
    logmod.nl();
    logmod.s("mse stage=req2xor hex=");
    logmod.hex(req2x[0..]);
    logmod.nl();
    sendAllMse(sock, req1[0..], start_ms) catch |e| return stageFail("req1", e);
    sendAllMse(sock, req2x[0..], start_ms) catch |e| return stageFail("req2xor", e);

    var blk: [VC_LEN + 4 + 2 + 2]u8 = undefined;
    i = 0;
    while (i < VC_LEN) : (i += 1) blk[i] = 0;
    writeU32BE(blk[VC_LEN..VC_LEN + 4], CRYPTO_RC4);
    writeU16BE(blk[VC_LEN + 4 .. VC_LEN + 6], 0); // len(PadC)
    writeU16BE(blk[VC_LEN + 6 .. VC_LEN + 8], 0); // len(IA)
    std_crypto.rc4Apply(&rc4_out, blk[0..]);
    logmod.s("mse stage=provide_enc hex=");
    logmod.hex(blk[0..]);
    logmod.nl();
    sendAllMse(sock, blk[0..], start_ms) catch |e| return stageFail("provide", e);

    // step 4: scan the raw B->A bytes for ENCRYPT_B(VC).
    var peeker: std_crypto.Rc4 = rc4_in;
    var enc_vc: [VC_LEN]u8 = undefined;
    i = 0;
    while (i < VC_LEN) : (i += 1) enc_vc[i] = 0;
    std_crypto.rc4Apply(&peeker, enc_vc[0..]);
    logmod.s("mse stage=enc_vc hex=");
    logmod.hex(enc_vc[0..]);
    logmod.nl();

    var win: [VC_LEN]u8 = undefined;
    i = 0;
    while (i < VC_LEN) : (i += 1) win[i] = 0;
    var cnt: usize = 0;
    var found: bool = false;
    var scanned: u32 = 0;
    while (scanned < SCAN_MAX and !found) : (scanned += 1) {
        var b: [1]u8 = undefined;
        recvExactMse(sock, b[0..], start_ms) catch |e| return stageFail("vcscan", e);
        var k: usize = 0;
        while (k + 1 < VC_LEN) : (k += 1) win[k] = win[k + 1];
        win[VC_LEN - 1] = b[0];
        cnt += 1;
        if (cnt >= VC_LEN and eq8(win[0..], enc_vc[0..])) found = true;
    }
    logmod.s("mse stage=vcsync found=");
    if (found) {
        logmod.s("1");
    } else {
        logmod.s("0");
    }
    logmod.s(" scanned=");
    logmod.u32v(scanned);
    logmod.nl();
    if (!found) return error.MseFailed;

    // Advance the real B->A context past the 8-byte VC.
    std_crypto.rc4Apply(&rc4_in, enc_vc[0..]);

    // crypto_select (u32) + len(PadD)(u16) + PadD.
    var sel_b: [4]u8 = undefined;
    recvDecMse(sock, &rc4_in, sel_b[0..], start_ms) catch |e| return stageFail("select", e);
    var method: u32 = readU32BE(sel_b[0..]);
    logmod.s("mse stage=select method=");
    logmod.u32v(method);
    logmod.nl();
    if (method != CRYPTO_RC4) return error.BadMethod;

    var pdl_b: [2]u8 = undefined;
    recvDecMse(sock, &rc4_in, pdl_b[0..], start_ms) catch |e| return stageFail("padd_len", e);
    var pad_d_len: u32 = @intCast(u32, readU16BE(pdl_b[0..]));
    logmod.s("mse stage=padd len=");
    logmod.u32v(pad_d_len);
    logmod.nl();
    var skipped: u32 = 0;
    while (skipped < pad_d_len) : (skipped += 1) {
        var one: [1]u8 = undefined;
        recvDecMse(sock, &rc4_in, one[0..], start_ms) catch |e| return stageFail("padd_body", e);
    }

    logmod.s("mse stage=done");
    logmod.nl();
    var pair: Rc4Pair = undefined;
    pair.out = rc4_out;
    pair.in = rc4_in;
    return pair;
}
