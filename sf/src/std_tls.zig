// std_tls.zig — Z98 std lib: TLS 1.2 record layer + client handshake (M4).
//
// Sans-I/O record codec + AEAD protection for the four M4 suites plus the TLS
// 1.2 client state machine (ECDHE P-256/x25519, SNI, PRF_SHA256 Finished).
// Imports the pure M2 primitives; no sockets and no wall-clock reads (the
// driver supplies `now_unix`).
//
// Record layer:
//   encodeRecord / parseRecordHeader / decodeRecord  (5-byte header, 16 KiB cap)
//   RecordReader                                      (incremental + memmove)
//   recordNonce / recordAad / sealFragment / openFragment
//   protectRecord / unprotectRecord                   (per-suite wire layout)
//
// Handshake (spec §5.6):
//   TlsAction / TlsConfig / TlsSession / tlsInit / tlsStep / tlsRead / tlsWrite
//   states SendClientHello .. Established; Finished verify_data is 12 bytes.
//   ClientHello offers SNI, secp256r1 + x25519, and exactly the four M4 suites.
//   The transcript is SHA-256 over every handshake message (record headers are
//   excluded) and PRF_SHA256 derives the master secret and key block.
//
// Wire AEAD (TLS 1.2):
//   AES-128-GCM (RFC 5288): nonce = fixed_iv[4] || explicit[8]; explicit nonce
//     (= sequence number) is transmitted; AAD = seq || type || version || len.
//   ChaCha20-Poly1305 (RFC 7905): nonce = (0x00^4 || seq_be64) XOR fixed_iv[12];
//     no explicit nonce; AAD = seq || type || version || len.
//
// Errors: Corrupt (malformed lengths/truncation), AuthenticationFailed (AEAD
// tag/nonce tamper), RecordTooLarge (> TLS_MAX_RECORD or reader overflow),
// Closed (clean end of stream at a record boundary), plus the handshake and
// certificate errors below. Every pre-Established failure fails closed.

const cipher = @import("std_cipher.zig");
const crypto = @import("std_crypto.zig");
const ecc = @import("std_ecc.zig");
const rand = @import("std_rand.zig");
const asn1 = @import("std_asn1.zig");
const x509 = @import("std_x509.zig");
const arena_mod = @import("std_arena.zig");

pub const TLS_MAX_RECORD: usize = 16384;
pub const RECORD_HEADER_LEN: usize = 5;
pub const TLS_VERSION_12: u16 = 0x0303;

pub const content_change_cipher_spec: u8 = 20;
pub const content_alert: u8 = 21;
pub const content_handshake: u8 = 22;
pub const content_application_data: u8 = 23;

pub const CipherSuite = enum {
    ecdsa_aes_128_gcm_sha256,
    rsa_aes_128_gcm_sha256,
    ecdsa_chacha20_poly1305_sha256,
    rsa_chacha20_poly1305_sha256,
};

pub const RecordError = error{
    Corrupt,
    AuthenticationFailed,
    RecordTooLarge,
    Closed,
};

pub const RecordHeader = struct {
    content_type: u8,
    version: u16,
    length: u16,
};

fn storeU16be(out: []u8, off: usize, v: u16) void {
    out[off] = @intCast(u8, v >> 8);
    out[off + 1] = @intCast(u8, v & 0xFF);
}

fn loadU16be(in: []const u8, off: usize) u16 {
    return (@intCast(u16, in[off]) << 8) | @intCast(u16, in[off + 1]);
}

fn storeU64be(out: []u8, off: usize, v: u64) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        out[off + i] = @intCast(u8, (v >> @intCast(u6, (7 - i) * 8)) & 0xFF);
    }
}

fn copyBytes(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

pub fn suiteIsAesGcm(suite: CipherSuite) bool {
    if (suite == CipherSuite.ecdsa_aes_128_gcm_sha256) return true;
    if (suite == CipherSuite.rsa_aes_128_gcm_sha256) return true;
    return false;
}

pub fn suiteKeyLen(suite: CipherSuite) usize {
    if (suiteIsAesGcm(suite)) return 16;
    return 32;
}

pub fn suiteFixedIvLen(suite: CipherSuite) usize {
    if (suiteIsAesGcm(suite)) return 4;
    return 12;
}

// --- record codec -----------------------------------------------------------

pub fn encodeRecord(content_type: u8, version: u16, payload: []const u8, out: []u8) RecordError!usize {
    if (payload.len > TLS_MAX_RECORD) return error.RecordTooLarge;
    const total = RECORD_HEADER_LEN + payload.len;
    if (out.len < total) return error.Corrupt;
    out[0] = content_type;
    storeU16be(out, 1, version);
    storeU16be(out, 3, @intCast(u16, payload.len));
    copyBytes(out[RECORD_HEADER_LEN..total], payload);
    return total;
}

pub fn parseRecordHeader(raw: []const u8) RecordError!RecordHeader {
    if (raw.len < RECORD_HEADER_LEN) return error.Corrupt;
    const length = loadU16be(raw, 3);
    if (@intCast(usize, length) > TLS_MAX_RECORD) return error.RecordTooLarge;
    return RecordHeader{
        .content_type = raw[0],
        .version = loadU16be(raw, 1),
        .length = length,
    };
}

pub fn decodeRecord(raw: []const u8, header: *RecordHeader, fragment: *[]const u8) RecordError!void {
    const h = try parseRecordHeader(raw);
    const need = RECORD_HEADER_LEN + @intCast(usize, h.length);
    if (raw.len < need) return error.Corrupt;
    header.* = h;
    fragment.* = raw[RECORD_HEADER_LEN..need];
}

// Incremental input buffer. `start`/`len` delimit unconsumed bytes; appends
// compact with memmove before growing, so a returned fragment stays valid until
// the next append (callers consume it before feeding more input).
pub const RecordReader = struct {
    buf: [TLS_MAX_RECORD + RECORD_HEADER_LEN]u8,
    start: usize,
    len: usize,
    closed: bool,
};

pub fn readerInit(r: *RecordReader) void {
    r.start = 0;
    r.len = 0;
    r.closed = false;
}

pub fn readerBuffered(r: *const RecordReader) usize {
    return r.len - r.start;
}

pub fn readerAppend(r: *RecordReader, data: []const u8) RecordError!void {
    if (r.start > 0) {
        const remaining = r.len - r.start;
        var i: usize = 0;
        while (i < remaining) : (i += 1) {
            r.buf[i] = r.buf[r.start + i];
        }
        r.start = 0;
        r.len = remaining;
    }
    if (r.len + data.len > r.buf.len) return error.RecordTooLarge;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        r.buf[r.len + i] = data[i];
    }
    r.len += data.len;
}

pub fn readerMarkClosed(r: *RecordReader) void {
    r.closed = true;
}

// true: one complete record (header + fragment) is available. false: need more
// input. Errors: RecordTooLarge (declared length), Corrupt (truncated at close),
// Closed (clean close exactly at a record boundary).
pub fn readerNext(r: *RecordReader, header: *RecordHeader, fragment: *[]const u8) RecordError!bool {
    const avail = r.len - r.start;
    if (avail == 0) {
        if (r.closed) return error.Closed;
        return false;
    }
    if (avail < RECORD_HEADER_LEN) {
        if (r.closed) return error.Corrupt;
        return false;
    }
    const h = parseRecordHeader(r.buf[r.start..r.len]) catch |e| return e;
    const need = RECORD_HEADER_LEN + @intCast(usize, h.length);
    if (avail < need) {
        if (r.closed) return error.Corrupt;
        return false;
    }
    header.* = h;
    fragment.* = r.buf[r.start + RECORD_HEADER_LEN .. r.start + need];
    r.start += need;
    return true;
}

// --- AEAD seam --------------------------------------------------------------

pub fn recordAad(seq: u64, content_type: u8, version: u16, plaintext_len: usize, out: *[13]u8) RecordError!void {
    if (plaintext_len > TLS_MAX_RECORD) return error.RecordTooLarge;
    storeU64be(out[0..], 0, seq);
    out[8] = content_type;
    storeU16be(out[0..], 9, version);
    storeU16be(out[0..], 11, @intCast(u16, plaintext_len));
}

pub fn recordNonce(suite: CipherSuite, fixed_iv: []const u8, seq: u64, out: *[12]u8) RecordError!void {
    if (suiteIsAesGcm(suite)) {
        if (fixed_iv.len != 4) return error.Corrupt;
        copyBytes(out[0..4], fixed_iv[0..4]);
        storeU64be(out[0..], 4, seq);
        return;
    }
    if (fixed_iv.len != 12) return error.Corrupt;
    var seq_be: [8]u8 = undefined;
    storeU64be(seq_be[0..], 0, seq);
    var i: usize = 0;
    while (i < 4) : (i += 1) out[i] = fixed_iv[i];
    i = 0;
    while (i < 8) : (i += 1) out[4 + i] = seq_be[i] ^ fixed_iv[4 + i];
}

// Raw AEAD edge (no record framing); exposes the AAD input for KATs.
pub fn sealFragment(suite: CipherSuite, key: []const u8, nonce: *const [12]u8, ad: []const u8, pt: []const u8, ct: []u8, tag: *[16]u8) RecordError!void {
    if (key.len != suiteKeyLen(suite)) return error.Corrupt;
    if (ct.len != pt.len) return error.Corrupt;
    if (suiteIsAesGcm(suite)) {
        cipher.aes128GcmSeal(@ptrCast(*const [16]u8, key.ptr), nonce, ad, pt, ct, tag) catch return error.Corrupt;
        return;
    }
    cipher.chacha20Poly1305Seal(@ptrCast(*const [32]u8, key.ptr), nonce, ad, pt, ct, tag) catch return error.Corrupt;
}

pub fn openFragment(suite: CipherSuite, key: []const u8, nonce: *const [12]u8, ad: []const u8, ct: []const u8, tag: *const [16]u8, pt: []u8) RecordError!void {
    if (key.len != suiteKeyLen(suite)) return error.Corrupt;
    if (pt.len != ct.len) return error.Corrupt;
    if (suiteIsAesGcm(suite)) {
        cipher.aes128GcmOpen(@ptrCast(*const [16]u8, key.ptr), nonce, ad, ct, tag, pt) catch |e| {
            if (e == error.AuthenticationFailed) return error.AuthenticationFailed;
            return error.Corrupt;
        };
        return;
    }
    cipher.chacha20Poly1305Open(@ptrCast(*const [32]u8, key.ptr), nonce, ad, ct, tag, pt) catch |e| {
        if (e == error.AuthenticationFailed) return error.AuthenticationFailed;
        return error.Corrupt;
    };
}

// --- record protection ------------------------------------------------------

// Returns the protected fragment length. AES-GCM includes the 8-byte explicit
// nonce; both suites include the 16-byte tag.
pub fn protectRecord(suite: CipherSuite, key: []const u8, fixed_iv: []const u8, seq: u64, content_type: u8, version: u16, pt: []const u8, out: []u8) RecordError!usize {
    if (pt.len > TLS_MAX_RECORD) return error.RecordTooLarge;
    if (key.len != suiteKeyLen(suite)) return error.Corrupt;
    if (fixed_iv.len != suiteFixedIvLen(suite)) return error.Corrupt;

    var aad: [13]u8 = undefined;
    try recordAad(seq, content_type, version, pt.len, &aad);

    if (suiteIsAesGcm(suite)) {
        const total = 8 + pt.len + 16;
        if (out.len < total) return error.Corrupt;
        storeU64be(out, 0, seq);
        var nonce: [12]u8 = undefined;
        copyBytes(nonce[0..4], fixed_iv[0..4]);
        storeU64be(nonce[0..], 4, seq);
        var tag: *[16]u8 = @ptrCast(*[16]u8, &out[8 + pt.len]);
        try sealFragment(suite, key, &nonce, aad[0..], pt, out[8 .. 8 + pt.len], tag);
        return total;
    }

    const total = pt.len + 16;
    if (out.len < total) return error.Corrupt;
    var nonce: [12]u8 = undefined;
    try recordNonce(suite, fixed_iv, seq, &nonce);
    var tag: *[16]u8 = @ptrCast(*[16]u8, &out[pt.len]);
    try sealFragment(suite, key, &nonce, aad[0..], pt, out[0..pt.len], tag);
    return total;
}

// Returns the plaintext length in `out`.
pub fn unprotectRecord(suite: CipherSuite, key: []const u8, fixed_iv: []const u8, seq: u64, content_type: u8, version: u16, record: []const u8, out: []u8) RecordError!usize {
    if (key.len != suiteKeyLen(suite)) return error.Corrupt;
    if (fixed_iv.len != suiteFixedIvLen(suite)) return error.Corrupt;

    if (suiteIsAesGcm(suite)) {
        if (record.len < 8 + 16) return error.Corrupt;
        const pt_len = record.len - 8 - 16;
        if (pt_len > TLS_MAX_RECORD) return error.RecordTooLarge;
        if (out.len < pt_len) return error.Corrupt;
        var aad: [13]u8 = undefined;
        try recordAad(seq, content_type, version, pt_len, &aad);
        var nonce: [12]u8 = undefined;
        copyBytes(nonce[0..4], fixed_iv[0..4]);
        copyBytes(nonce[4..12], record[0..8]);
        var tag: *const [16]u8 = @ptrCast(*const [16]u8, &record[8 + pt_len]);
        try openFragment(suite, key, &nonce, aad[0..], record[8 .. 8 + pt_len], tag, out[0..pt_len]);
        return pt_len;
    }

    if (record.len < 16) return error.Corrupt;
    const pt_len = record.len - 16;
    if (pt_len > TLS_MAX_RECORD) return error.RecordTooLarge;
    if (out.len < pt_len) return error.Corrupt;
    var aad: [13]u8 = undefined;
    try recordAad(seq, content_type, version, pt_len, &aad);
    var nonce: [12]u8 = undefined;
    try recordNonce(suite, fixed_iv, seq, &nonce);
    var tag: *const [16]u8 = @ptrCast(*const [16]u8, &record[pt_len]);
    try openFragment(suite, key, &nonce, aad[0..], record[0..pt_len], tag, out[0..pt_len]);
    return pt_len;
}

// ---------------------------------------------------------------------------
// TLS 1.2 handshake (spec §5.6)
// ---------------------------------------------------------------------------

// Reassembly cap for one handshake message. A certificate chain larger than a
// single 16 KiB record arrives as several TLS record fragments; 64 KiB admits
// real multi-record chains while keeping TlsSession fixed-size.
pub const TLS_HANDSHAKE_MAX: usize = 65536;
pub const TLS_FINISHED_LEN: usize = 12;
const TLS_PENDING_MAX: usize = 8192;
const TLS_APP_MAX: usize = TLS_MAX_RECORD * 2;
const TLS_MAX_PLAINTEXT_PER_RECORD: usize = TLS_MAX_RECORD - 24;

const hs_client_hello: u8 = 1;
const hs_server_hello: u8 = 2;
const hs_new_session_ticket: u8 = 4;
const hs_certificate: u8 = 11;
const hs_server_key_exchange: u8 = 12;
const hs_server_hello_done: u8 = 14;
const hs_client_key_exchange: u8 = 16;
const hs_finished: u8 = 20;

const group_secp256r1: u16 = 0x0017;
const group_x25519: u16 = 0x001D;

const sig_ecdsa_sha256: u16 = 0x0403;
const sig_rsa_pkcs1_sha256: u16 = 0x0401;

const suite_ecdsa_aes_128_gcm_sha256: u16 = 0xC02B;
const suite_rsa_aes_128_gcm_sha256: u16 = 0xC02F;
const suite_ecdsa_chacha20_poly1305_sha256: u16 = 0xCCA9;
const suite_rsa_chacha20_poly1305_sha256: u16 = 0xCCA8;

const OID_EC_PUBLIC_KEY = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 };
const OID_PRIME256V1 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };
const OID_RSA_ENCRYPTION = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01 };

pub const TlsError = error{
    BadAction,
    AppTooLarge,
    OutputTooSmall,
    BadConfig,
    HandshakeFailed,
    UnsupportedVersion,
    UnsupportedSuite,
    UnsupportedGroup,
    CertificateExpired,
    CertificateNotYetValid,
    UnknownIssuer,
    HostnameMismatch,
    BadSignature,
    ChainTooLong,
    UnsupportedAlgorithm,
    Corrupt,
    AuthenticationFailed,
    RecordTooLarge,
    Closed,
    WeakPublicKey,
    InvalidPrivateKey,
    InvalidPublicKey,
};

pub const TlsAction = union(enum) {
    send: []const u8,
    recv: usize,
    wait: u32,
    established: void,
    closed: void,
};

pub const TlsConfig = struct {
    hostname: []const u8,
    store: *x509.TrustStore,
    rng: *rand.Xoshiro256,
    now_unix: i64,
    min_version: u16,
    max_version: u16,
};

pub const HandshakeState = enum {
    SendClientHello,
    RecvServerHello,
    RecvCertificate,
    RecvServerKeyExchange,
    RecvServerHelloDone,
    SendClientKeyExchange,
    SendChangeCipherSpec,
    SendFinished,
    RecvChangeCipherSpec,
    RecvFinished,
    Established,
    Error,
};

const PeerKey = struct {
    kind: u8, // 1 = ECDSA P-256, 2 = RSA
    ec_pub: [65]u8,
    rsa_n: [512]u8,
    rsa_n_len: usize,
    rsa_e: u32,
};

pub const TlsSession = struct {
    cfg: TlsConfig,
    state: HandshakeState,
    reader: RecordReader,
    hs_buf: [TLS_HANDSHAKE_MAX]u8,
    hs_len: usize,
    transcript: crypto.Sha256,
    client_random: [32]u8,
    server_random: [32]u8,
    suite: CipherSuite,
    peer_group: u16,
    peer_pub: [65]u8,
    peer_pub_len: usize,
    peer_key: PeerKey,
    pre_master: [32]u8,
    master: [48]u8,
    client_key: [32]u8,
    server_key: [32]u8,
    client_iv: [12]u8,
    server_iv: [12]u8,
    write_seq: u64,
    read_seq: u64,
    write_cipher: bool,
    read_cipher: bool,
    closed: bool,
    pending: [TLS_PENDING_MAX]u8,
    pending_len: usize,
    app: [TLS_APP_MAX]u8,
    app_start: usize,
    app_end: usize,
};

fn putU16(out: []u8, off: usize, v: u16) void {
    storeU16be(out, off, v);
}

fn putU24(out: []u8, off: usize, v: usize) void {
    out[off] = @intCast(u8, (v >> 16) & 0xFF);
    out[off + 1] = @intCast(u8, (v >> 8) & 0xFF);
    out[off + 2] = @intCast(u8, v & 0xFF);
}

fn loadU24(in: []const u8, off: usize) usize {
    return (@intCast(usize, in[off]) << 16) |
        (@intCast(usize, in[off + 1]) << 8) |
        @intCast(usize, in[off + 2]);
}

fn eqSlice(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
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

fn prfSha256(secret: []const u8, label: []const u8, seed: []const u8, out: []u8) void {
    var a: [32]u8 = undefined;
    var h = crypto.hmacSha256Init(secret);
    crypto.hmacSha256Update(&h, label);
    crypto.hmacSha256Update(&h, seed);
    crypto.hmacSha256Final(&h, &a);

    var off: usize = 0;
    while (off < out.len) {
        var t: [32]u8 = undefined;
        var h2 = crypto.hmacSha256Init(secret);
        crypto.hmacSha256Update(&h2, a[0..]);
        crypto.hmacSha256Update(&h2, label);
        crypto.hmacSha256Update(&h2, seed);
        crypto.hmacSha256Final(&h2, &t);
        var take: usize = out.len - off;
        if (take > 32) take = 32;
        copyBytes(out[off .. off + take], t[0..take]);
        off += take;

        var na: [32]u8 = undefined;
        var ha = crypto.hmacSha256Init(secret);
        crypto.hmacSha256Update(&ha, a[0..]);
        crypto.hmacSha256Final(&ha, &na);
        a = na;
    }
}

fn suiteFromId(id: u16) TlsError!CipherSuite {
    if (id == suite_ecdsa_aes_128_gcm_sha256) return CipherSuite.ecdsa_aes_128_gcm_sha256;
    if (id == suite_rsa_aes_128_gcm_sha256) return CipherSuite.rsa_aes_128_gcm_sha256;
    if (id == suite_ecdsa_chacha20_poly1305_sha256) return CipherSuite.ecdsa_chacha20_poly1305_sha256;
    if (id == suite_rsa_chacha20_poly1305_sha256) return CipherSuite.rsa_chacha20_poly1305_sha256;
    return error.UnsupportedSuite;
}

fn derIntFixed(data: []const u8, out: []u8) TlsError!void {
    if (data.len == 0) return error.BadSignature;
    if ((data[0] & 0x80) != 0) return error.BadSignature;
    var start: usize = 0;
    while (start < data.len and data[start] == 0) : (start += 1) {}
    if (start >= data.len) return error.BadSignature;
    const n = data.len - start;
    if (n > out.len) return error.BadSignature;
    var i: usize = 0;
    while (i < out.len) : (i += 1) out[i] = 0;
    i = 0;
    while (i < n) : (i += 1) out[out.len - n + i] = data[start + i];
}

fn parseEcdsaSig(sig: []const u8, r_out: *[32]u8, s_out: *[32]u8) TlsError!void {
    var r = asn1.asn1Init(sig);
    const seq = asn1.asn1ReadTlv(&r) catch return error.BadSignature;
    if (seq.cls != asn1.TagClass.universal or seq.tag != 16 or !seq.constructed) return error.BadSignature;
    if (asn1.asn1Remaining(&r) != 0) return error.BadSignature;
    var sr = asn1.asn1Init(seq.data);
    const ri = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    const si = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    if (asn1.asn1Remaining(&sr) != 0) return error.BadSignature;
    if (ri.cls != asn1.TagClass.universal or ri.tag != 2 or ri.constructed) return error.BadSignature;
    if (si.cls != asn1.TagClass.universal or si.tag != 2 or si.constructed) return error.BadSignature;
    try derIntFixed(ri.data, r_out[0..]);
    try derIntFixed(si.data, s_out[0..]);
}

fn parsePeerKey(spki: []const u8, out: *PeerKey) TlsError!void {
    var r = asn1.asn1Init(spki);
    const seq = asn1.asn1ReadTlv(&r) catch return error.Corrupt;
    if (seq.cls != asn1.TagClass.universal or seq.tag != 16 or !seq.constructed) return error.Corrupt;
    if (asn1.asn1Remaining(&r) != 0) return error.Corrupt;
    var sr = asn1.asn1Init(seq.data);
    const alg = asn1.asn1ReadTlv(&sr) catch return error.Corrupt;
    const bits = asn1.asn1ReadTlv(&sr) catch return error.Corrupt;
    if (asn1.asn1Remaining(&sr) != 0) return error.Corrupt;
    if (alg.cls != asn1.TagClass.universal or alg.tag != 16 or !alg.constructed) return error.Corrupt;
    if (bits.cls != asn1.TagClass.universal or bits.tag != 3 or bits.constructed) return error.Corrupt;
    if (bits.data.len < 2 or bits.data[0] != 0) return error.Corrupt;

    var ar = asn1.asn1Init(alg.data);
    const oid = asn1.asn1ReadTlv(&ar) catch return error.Corrupt;
    if (oid.cls != asn1.TagClass.universal or oid.tag != 6 or oid.constructed) return error.Corrupt;

    const key = bits.data[1..];
    if (eqSlice(oid.data, OID_EC_PUBLIC_KEY[0..])) {
        if (asn1.asn1Remaining(&ar) == 0) return error.UnsupportedAlgorithm;
        const curve = asn1.asn1ReadTlv(&ar) catch return error.Corrupt;
        if (curve.cls != asn1.TagClass.universal or curve.tag != 6 or curve.constructed) return error.Corrupt;
        if (!eqSlice(curve.data, OID_PRIME256V1[0..])) return error.UnsupportedAlgorithm;
        if (key.len != 65 or key[0] != 0x04) return error.UnsupportedAlgorithm;
        out.kind = 1;
        copyBytes(out.ec_pub[0..], key);
        return;
    }
    if (eqSlice(oid.data, OID_RSA_ENCRYPTION[0..])) {
        var kr = asn1.asn1Init(key);
        const kseq = asn1.asn1ReadTlv(&kr) catch return error.Corrupt;
        if (kseq.cls != asn1.TagClass.universal or kseq.tag != 16 or !kseq.constructed) return error.Corrupt;
        if (asn1.asn1Remaining(&kr) != 0) return error.Corrupt;
        var ksr = asn1.asn1Init(kseq.data);
        const mod = asn1.asn1ReadTlv(&ksr) catch return error.Corrupt;
        const exp = asn1.asn1ReadTlv(&ksr) catch return error.Corrupt;
        if (asn1.asn1Remaining(&ksr) != 0) return error.Corrupt;
        if (mod.cls != asn1.TagClass.universal or mod.tag != 2 or mod.constructed) return error.Corrupt;
        if (exp.cls != asn1.TagClass.universal or exp.tag != 2 or exp.constructed) return error.Corrupt;
        if (mod.data.len == 0 or (mod.data[0] & 0x80) != 0) return error.BadSignature;
        var ms: usize = 0;
        while (ms < mod.data.len and mod.data[ms] == 0) : (ms += 1) {}
        if (ms >= mod.data.len) return error.BadSignature;
        const n = mod.data[ms..];
        if (n.len > out.rsa_n.len) return error.BadSignature;
        copyBytes(out.rsa_n[0..n.len], n);
        out.rsa_n_len = n.len;
        if (exp.data.len == 0 or (exp.data[0] & 0x80) != 0) return error.BadSignature;
        var es: usize = 0;
        while (es < exp.data.len and exp.data[es] == 0) : (es += 1) {}
        if (es >= exp.data.len or exp.data.len - es > 4) return error.UnsupportedAlgorithm;
        var e: u32 = 0;
        var i: usize = es;
        while (i < exp.data.len) : (i += 1) e = (e << 8) | @intCast(u32, exp.data[i]);
        if (e == 0) return error.BadSignature;
        out.rsa_e = e;
        out.kind = 2;
        return;
    }
    return error.UnsupportedAlgorithm;
}

fn verifyServerKeyExchange(sess: *TlsSession, params: []const u8, sig_alg: u16, sig: []const u8) TlsError!void {
    var hash: [32]u8 = undefined;
    var h = crypto.sha256Init();
    crypto.sha256Update(&h, sess.client_random[0..]);
    crypto.sha256Update(&h, sess.server_random[0..]);
    crypto.sha256Update(&h, params);
    crypto.sha256Final(&h, &hash);

    if (sig_alg == sig_ecdsa_sha256) {
        if (sess.peer_key.kind != 1) return error.UnsupportedAlgorithm;
        var r: [32]u8 = undefined;
        var s: [32]u8 = undefined;
        try parseEcdsaSig(sig, &r, &s);
        if (!ecc.p256EcdsaVerify(&sess.peer_key.ec_pub, &hash, &r, &s)) return error.BadSignature;
        return;
    }
    if (sig_alg == sig_rsa_pkcs1_sha256) {
        if (sess.peer_key.kind != 2) return error.UnsupportedAlgorithm;
        crypto.rsaVerifyPkcs1v15(sess.peer_key.rsa_n[0..sess.peer_key.rsa_n_len],
            sess.peer_key.rsa_e, crypto.HashAlg.sha256, hash[0..], sig) catch return error.BadSignature;
        return;
    }
    return error.UnsupportedAlgorithm;
}

fn queueRecord(sess: *TlsSession, content_type: u8, payload: []const u8) TlsError!void {
    var protected: [TLS_MAX_RECORD + 32]u8 = undefined;
    var frag: []const u8 = payload;
    if (sess.write_cipher) {
        const n = try protectRecord(sess.suite, sess.client_key[0..suiteKeyLen(sess.suite)],
            sess.client_iv[0..suiteFixedIvLen(sess.suite)],
            sess.write_seq, content_type, TLS_VERSION_12, payload, protected[0..]);
        sess.write_seq += 1;
        frag = protected[0..n];
    }
    const total = RECORD_HEADER_LEN + frag.len;
    if (sess.pending_len + total > sess.pending.len) return error.OutputTooSmall;
    _ = try encodeRecord(content_type, TLS_VERSION_12, frag, sess.pending[sess.pending_len..]);
    sess.pending_len += total;
}

fn deriveKeys(sess: *TlsSession) void {
    var seed: [64]u8 = undefined;
    copyBytes(seed[0..32], sess.client_random[0..]);
    copyBytes(seed[32..64], sess.server_random[0..]);
    prfSha256(sess.pre_master[0..], "master secret", seed[0..], sess.master[0..]);

    copyBytes(seed[0..32], sess.server_random[0..]);
    copyBytes(seed[32..64], sess.client_random[0..]);
    const klen = suiteKeyLen(sess.suite);
    const ivlen = suiteFixedIvLen(sess.suite);
    const need = 2 * klen + 2 * ivlen;
    var kb: [2 * 32 + 2 * 12]u8 = undefined;
    prfSha256(sess.master[0..], "key expansion", seed[0..], kb[0..need]);

    var off: usize = 0;
    copyBytes(sess.client_key[0..klen], kb[off .. off + klen]);
    off += klen;
    copyBytes(sess.server_key[0..klen], kb[off .. off + klen]);
    off += klen;
    copyBytes(sess.client_iv[0..ivlen], kb[off .. off + ivlen]);
    off += ivlen;
    copyBytes(sess.server_iv[0..ivlen], kb[off .. off + ivlen]);
}

fn computeFinished(sess: *TlsSession, label: []const u8, out: *[TLS_FINISHED_LEN]u8) void {
    var hash: [32]u8 = undefined;
    var h = sess.transcript;
    crypto.sha256Final(&h, &hash);
    prfSha256(sess.master[0..], label, hash[0..], out[0..]);
}

fn sendClientHello(sess: *TlsSession) TlsError!void {
    if (sess.cfg.min_version > TLS_VERSION_12 or sess.cfg.max_version < TLS_VERSION_12) {
        return error.UnsupportedVersion;
    }
    if (sess.cfg.hostname.len == 0 or sess.cfg.hostname.len > 255) return error.BadConfig;

    var msg: [512]u8 = undefined;
    var off: usize = 4;
    putU16(msg[0..], off, TLS_VERSION_12);
    off += 2;
    fillRandom(sess.cfg.rng, sess.client_random[0..]);
    copyBytes(msg[off .. off + 32], sess.client_random[0..]);
    off += 32;

    msg[off] = 0; // session_id length (no resumption)
    off += 1;

    putU16(msg[0..], off, 8);
    off += 2;
    putU16(msg[0..], off, suite_ecdsa_aes_128_gcm_sha256);
    off += 2;
    putU16(msg[0..], off, suite_rsa_aes_128_gcm_sha256);
    off += 2;
    putU16(msg[0..], off, suite_ecdsa_chacha20_poly1305_sha256);
    off += 2;
    putU16(msg[0..], off, suite_rsa_chacha20_poly1305_sha256);
    off += 2;

    msg[off] = 1; // compression methods
    off += 1;
    msg[off] = 0; // null
    off += 1;

    const ext_len_off = off;
    off += 2;
    const ext_start = off;

    putU16(msg[0..], off, 0x0000); // server_name
    off += 2;
    putU16(msg[0..], off, @intCast(u16, 5 + sess.cfg.hostname.len));
    off += 2;
    putU16(msg[0..], off, @intCast(u16, 3 + sess.cfg.hostname.len));
    off += 2;
    msg[off] = 0; // host_name
    off += 1;
    putU16(msg[0..], off, @intCast(u16, sess.cfg.hostname.len));
    off += 2;
    copyBytes(msg[off .. off + sess.cfg.hostname.len], sess.cfg.hostname);
    off += sess.cfg.hostname.len;

    putU16(msg[0..], off, 0x000A); // supported_groups
    off += 2;
    putU16(msg[0..], off, 6);
    off += 2;
    putU16(msg[0..], off, 4);
    off += 2;
    putU16(msg[0..], off, group_secp256r1);
    off += 2;
    putU16(msg[0..], off, group_x25519);
    off += 2;

    putU16(msg[0..], off, 0x000B); // ec_point_formats
    off += 2;
    putU16(msg[0..], off, 2);
    off += 2;
    msg[off] = 1;
    off += 1;
    msg[off] = 0;
    off += 1;

    putU16(msg[0..], off, 0x000D); // signature_algorithms
    off += 2;
    putU16(msg[0..], off, 6);
    off += 2;
    putU16(msg[0..], off, 4);
    off += 2;
    putU16(msg[0..], off, sig_ecdsa_sha256);
    off += 2;
    putU16(msg[0..], off, sig_rsa_pkcs1_sha256);
    off += 2;

    putU16(msg[0..], ext_len_off, @intCast(u16, off - ext_start));

    msg[0] = hs_client_hello;
    putU24(msg[0..], 1, off - 4);
    crypto.sha256Update(&sess.transcript, msg[0..off]);
    try queueRecord(sess, content_handshake, msg[0..off]);
    sess.state = .RecvServerHello;
}

fn handleServerHello(sess: *TlsSession, body: []const u8) TlsError!void {
    if (body.len < 2 + 32 + 1 + 2 + 1) return error.Corrupt;
    if (loadU16be(body, 0) != TLS_VERSION_12) return error.UnsupportedVersion;
    copyBytes(sess.server_random[0..], body[2..34]);
    var pos: usize = 34;
    const sid_len = @intCast(usize, body[pos]);
    pos += 1;
    if (pos + sid_len + 3 > body.len) return error.Corrupt;
    pos += sid_len;
    sess.suite = try suiteFromId(loadU16be(body, pos));
    pos += 2;
    if (body[pos] != 0) return error.HandshakeFailed;
}

fn handleCertificate(sess: *TlsSession, body: []const u8) TlsError!void {
    if (body.len < 3) return error.Corrupt;
    const list_len = loadU24(body, 0);
    if (list_len != body.len - 3) return error.Corrupt;

    var certs: [x509.MAX_CHAIN + 1][]const u8 = undefined;
    var count: usize = 0;
    var pos: usize = 3;
    while (pos < body.len) {
        if (body.len - pos < 3) return error.Corrupt;
        const n = loadU24(body, pos);
        pos += 3;
        if (n == 0 or n > body.len - pos) return error.Corrupt;
        if (count >= certs.len) return error.ChainTooLong;
        certs[count] = body[pos .. pos + n];
        count += 1;
        pos += n;
    }
    if (count == 0) return error.Corrupt;
    if (count - 1 > x509.MAX_CHAIN) return error.ChainTooLong;

    var inters: [x509.MAX_CHAIN][]const u8 = undefined;
    var i: usize = 0;
    while (i < count - 1) : (i += 1) inters[i] = certs[i + 1];

    var arena_buf: [1]u8 = undefined;
    var ar = arena_mod.init(arena_buf[0..]);
    x509.x509VerifyChain(&ar, certs[0], inters[0 .. count - 1], sess.cfg.store,
        sess.cfg.hostname, sess.cfg.now_unix) catch |e| return e;

    var leaf: x509.Cert = undefined;
    x509.x509Parse(certs[0], &leaf) catch return error.Corrupt;
    try parsePeerKey(leaf.spki, &sess.peer_key);
}

fn handleServerKeyExchange(sess: *TlsSession, body: []const u8) TlsError!void {
    if (body.len < 5) return error.Corrupt;
    if (body[0] != 3) return error.HandshakeFailed; // named_curve
    const group = loadU16be(body, 1);
    const pub_len = @intCast(usize, body[3]);
    if (4 + pub_len + 4 > body.len) return error.Corrupt;
    const params = body[0 .. 4 + pub_len];
    const sig_alg = loadU16be(body, 4 + pub_len);
    const sig_len = @intCast(usize, loadU16be(body, 6 + pub_len));
    if (8 + pub_len + sig_len != body.len) return error.Corrupt;
    const sig = body[8 + pub_len .. body.len];

    if (group == group_secp256r1) {
        if (pub_len != 65 or body[4] != 0x04) return error.HandshakeFailed;
    } else if (group == group_x25519) {
        if (pub_len != 32) return error.HandshakeFailed;
    } else {
        return error.UnsupportedGroup;
    }
    sess.peer_group = group;
    sess.peer_pub_len = pub_len;
    copyBytes(sess.peer_pub[0..pub_len], body[4 .. 4 + pub_len]);

    verifyServerKeyExchange(sess, params, sig_alg, sig) catch |e| {
        if (e == error.BadSignature) return error.HandshakeFailed;
        return e;
    };
}

fn sendClientFlight(sess: *TlsSession) TlsError!void {
    var shared: [32]u8 = undefined;
    var cke: [66]u8 = undefined;
    var pub_len: usize = 0;

    if (sess.peer_group == group_secp256r1) {
        var priv: [32]u8 = undefined;
        var pub_bytes: [65]u8 = undefined;
        ecc.p256Generate(sess.cfg.rng, &priv, &pub_bytes);
        try ecc.p256Ecdh(&priv, &sess.peer_pub, &shared);
        pub_len = 65;
        cke[0] = 65;
        copyBytes(cke[1..66], pub_bytes[0..]);
    } else if (sess.peer_group == group_x25519) {
        var priv: [32]u8 = undefined;
        fillRandom(sess.cfg.rng, priv[0..]);
        priv[0] = priv[0] & 248;
        priv[31] = (priv[31] & 127) | 64;
        var pub_bytes: [32]u8 = undefined;
        try ecc.x25519Base(&priv, &pub_bytes);
        var peer: [32]u8 = undefined;
        copyBytes(peer[0..], sess.peer_pub[0..32]);
        try ecc.x25519(&priv, &peer, &shared);
        pub_len = 32;
        cke[0] = 32;
        copyBytes(cke[1..33], pub_bytes[0..]);
    } else {
        return error.UnsupportedGroup;
    }
    copyBytes(sess.pre_master[0..], shared[0..]);

    var msg: [70]u8 = undefined;
    msg[0] = hs_client_key_exchange;
    putU24(msg[0..], 1, 1 + pub_len);
    copyBytes(msg[4 .. 4 + 1 + pub_len], cke[0 .. 1 + pub_len]);
    const msg_len = 4 + 1 + pub_len;
    crypto.sha256Update(&sess.transcript, msg[0..msg_len]);
    try queueRecord(sess, content_handshake, msg[0..msg_len]);

    deriveKeys(sess);

    var ccs = [_]u8{1};
    try queueRecord(sess, content_change_cipher_spec, ccs[0..1]);
    sess.write_cipher = true;

    var verify: [TLS_FINISHED_LEN]u8 = undefined;
    computeFinished(sess, "client finished", &verify);
    var fin: [16]u8 = undefined;
    fin[0] = hs_finished;
    putU24(fin[0..], 1, TLS_FINISHED_LEN);
    copyBytes(fin[4..16], verify[0..]);
    crypto.sha256Update(&sess.transcript, fin[0..16]);
    try queueRecord(sess, content_handshake, fin[0..16]);

    sess.state = .RecvChangeCipherSpec;
}

fn handleFinished(sess: *TlsSession, body: []const u8) TlsError!void {
    if (body.len != TLS_FINISHED_LEN) return error.HandshakeFailed;
    var want: [TLS_FINISHED_LEN]u8 = undefined;
    computeFinished(sess, "server finished", &want);
    if (!eqSlice(body, want[0..])) return error.HandshakeFailed;
    sess.state = .Established;
}

fn handleHandshakeMessage(sess: *TlsSession, msg_type: u8, body: []const u8) TlsError!void {
    if (msg_type == hs_server_hello) {
        if (sess.state != .RecvServerHello) return error.HandshakeFailed;
        try handleServerHello(sess, body);
        sess.state = .RecvCertificate;
        return;
    }
    if (msg_type == hs_certificate) {
        if (sess.state != .RecvCertificate) return error.HandshakeFailed;
        try handleCertificate(sess, body);
        sess.state = .RecvServerKeyExchange;
        return;
    }
    if (msg_type == hs_server_key_exchange) {
        if (sess.state != .RecvServerKeyExchange) return error.HandshakeFailed;
        try handleServerKeyExchange(sess, body);
        sess.state = .RecvServerHelloDone;
        return;
    }
    if (msg_type == hs_server_hello_done) {
        if (sess.state != .RecvServerHelloDone) return error.HandshakeFailed;
        if (body.len != 0) return error.HandshakeFailed;
        try sendClientFlight(sess);
        return;
    }
    if (msg_type == hs_new_session_ticket) {
        if (sess.state != .Established) return error.HandshakeFailed;
        return;
    }
    return error.HandshakeFailed;
}

fn drainHandshake(sess: *TlsSession) TlsError!void {
    while (sess.hs_len >= 4) {
        const mlen = loadU24(sess.hs_buf[0..], 1);
        if (mlen > TLS_HANDSHAKE_MAX - 4) return error.RecordTooLarge;
        const total = 4 + mlen;
        if (sess.hs_len < total) return;
        const msg_type = sess.hs_buf[0];
        if (msg_type == hs_finished and sess.state == .RecvFinished) {
            try handleFinished(sess, sess.hs_buf[4..total]);
            crypto.sha256Update(&sess.transcript, sess.hs_buf[0..total]);
        } else {
            crypto.sha256Update(&sess.transcript, sess.hs_buf[0..total]);
            try handleHandshakeMessage(sess, msg_type, sess.hs_buf[4..total]);
        }
        var i: usize = 0;
        while (total + i < sess.hs_len) : (i += 1) {
            sess.hs_buf[i] = sess.hs_buf[total + i];
        }
        sess.hs_len -= total;
        if (sess.pending_len > 0) return;
    }
}

fn decryptRecord(sess: *TlsSession, content_type: u8, frag: []const u8, pt: []u8) TlsError![]const u8 {
    if (!sess.read_cipher) return frag;
    const n = unprotectRecord(sess.suite, sess.server_key[0..suiteKeyLen(sess.suite)],
        sess.server_iv[0..suiteFixedIvLen(sess.suite)],
        sess.read_seq, content_type, TLS_VERSION_12, frag, pt) catch |e| {
        if (sess.state != .Established) return error.HandshakeFailed;
        return e;
    };
    sess.read_seq += 1;
    return pt[0..n];
}

fn bufferApplication(sess: *TlsSession, data: []const u8) TlsError!void {
    if (sess.app_end + data.len > sess.app.len) return error.AppTooLarge;
    copyBytes(sess.app[sess.app_end .. sess.app_end + data.len], data);
    sess.app_end += data.len;
}

fn handleRecord(sess: *TlsSession, hdr: *const RecordHeader, frag: []const u8) TlsError!void {
    var pt: [TLS_MAX_RECORD]u8 = undefined;

    if (hdr.content_type == content_handshake) {
        const plain = try decryptRecord(sess, content_handshake, frag, pt[0..]);
        if (sess.hs_len + plain.len > sess.hs_buf.len) return error.RecordTooLarge;
        copyBytes(sess.hs_buf[sess.hs_len .. sess.hs_len + plain.len], plain);
        sess.hs_len += plain.len;
        try drainHandshake(sess);
        return;
    }
    if (hdr.content_type == content_change_cipher_spec) {
        if (sess.state != .RecvChangeCipherSpec) return error.HandshakeFailed;
        if (frag.len != 1 or frag[0] != 1) return error.HandshakeFailed;
        sess.read_cipher = true;
        sess.read_seq = 0;
        sess.state = .RecvFinished;
        return;
    }
    if (hdr.content_type == content_application_data) {
        if (sess.state != .Established) return error.HandshakeFailed;
        const plain = try decryptRecord(sess, content_application_data, frag, pt[0..]);
        try bufferApplication(sess, plain);
        return;
    }
    if (hdr.content_type == content_alert) {
        const plain = try decryptRecord(sess, content_alert, frag, pt[0..]);
        if (plain.len < 2) return error.Corrupt;
        if (plain[1] == 0) {
            sess.closed = true;
            return;
        }
        return error.HandshakeFailed;
    }
    return error.HandshakeFailed;
}

fn flushPending(sess: *TlsSession, output: []u8) TlsError!TlsAction {
    const n = sess.pending_len;
    if (output.len < n) return error.OutputTooSmall;
    copyBytes(output[0..n], sess.pending[0..n]);
    sess.pending_len = 0;
    const sent: []const u8 = output[0..n];
    var action: TlsAction = TlsAction{ .send = sent };
    return action;
}

pub fn tlsInit(sess: *TlsSession, cfg: *TlsConfig) void {
    sess.cfg = cfg.*;
    sess.state = .SendClientHello;
    readerInit(&sess.reader);
    sess.hs_len = 0;
    sess.transcript = crypto.sha256Init();
    sess.suite = CipherSuite.ecdsa_aes_128_gcm_sha256;
    sess.peer_group = 0;
    sess.peer_pub_len = 0;
    sess.peer_key.kind = 0;
    sess.peer_key.rsa_n_len = 0;
    sess.peer_key.rsa_e = 0;
    sess.write_seq = 0;
    sess.read_seq = 0;
    sess.write_cipher = false;
    sess.read_cipher = false;
    sess.closed = false;
    sess.pending_len = 0;
    sess.app_start = 0;
    sess.app_end = 0;
}

pub fn tlsStep(sess: *TlsSession, input: []const u8, output: []u8) TlsError!TlsAction {
    if (sess.state == .Error) return error.HandshakeFailed;
    if (sess.closed) return TlsAction{ .closed = {} };
    if (input.len > 0) try readerAppend(&sess.reader, input);
    if (sess.pending_len > 0) return flushPending(sess, output);

    if (sess.state == .SendClientHello) {
        try sendClientHello(sess);
        return flushPending(sess, output);
    }

    while (true) {
        var hdr: RecordHeader = undefined;
        var frag: []const u8 = undefined;
        const more = readerNext(&sess.reader, &hdr, &frag) catch |e| {
            if (e == error.Closed) {
                if (sess.state == .Established) return TlsAction{ .closed = {} };
                return error.HandshakeFailed;
            }
            return e;
        };
        if (!more) break;
        try handleRecord(sess, &hdr, frag);
        if (sess.pending_len > 0) return flushPending(sess, output);
        if (sess.closed) return TlsAction{ .closed = {} };
    }

    if (sess.state == .Established) return TlsAction{ .established = {} };
    return TlsAction{ .recv = 1 };
}

pub fn tlsRead(sess: *TlsSession, out: []u8) TlsError!usize {
    const avail = sess.app_end - sess.app_start;
    if (avail == 0 or out.len == 0) return 0;
    var n = out.len;
    if (n > avail) n = avail;
    copyBytes(out[0..n], sess.app[sess.app_start .. sess.app_start + n]);
    sess.app_start += n;
    if (sess.app_start == sess.app_end) {
        sess.app_start = 0;
        sess.app_end = 0;
    }
    return n;
}

pub fn tlsWrite(sess: *TlsSession, data: []const u8, output: []u8) TlsError!usize {
    if (sess.state != .Established) return error.HandshakeFailed;
    if (data.len == 0) return 0;

    var chunks: usize = data.len / TLS_MAX_PLAINTEXT_PER_RECORD;
    if (data.len % TLS_MAX_PLAINTEXT_PER_RECORD != 0) chunks += 1;
    var overhead: usize = 16;
    if (suiteIsAesGcm(sess.suite)) overhead = 24;
    const needed = chunks * RECORD_HEADER_LEN + data.len + chunks * overhead;
    if (output.len < needed) return error.OutputTooSmall;

    var out_off: usize = 0;
    var pos: usize = 0;
    while (pos < data.len) {
        var take: usize = data.len - pos;
        if (take > TLS_MAX_PLAINTEXT_PER_RECORD) take = TLS_MAX_PLAINTEXT_PER_RECORD;

        var protected: [TLS_MAX_RECORD]u8 = undefined;
        const n = try protectRecord(sess.suite, sess.client_key[0..suiteKeyLen(sess.suite)],
            sess.client_iv[0..suiteFixedIvLen(sess.suite)],
            sess.write_seq, content_application_data, TLS_VERSION_12, data[pos .. pos + take], protected[0..]);
        sess.write_seq += 1;

        const total = RECORD_HEADER_LEN + n;
        if (output.len < out_off + total) return error.OutputTooSmall;
        _ = try encodeRecord(content_application_data, TLS_VERSION_12, protected[0..n], output[out_off..]);
        out_off += total;
        pos += take;
    }
    return out_off;
}
