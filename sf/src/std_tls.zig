// std_tls.zig — Z98 std lib: TLS 1.2 record layer (Phase1 M4 Task 1).
//
// Sans-I/O record codec + AEAD protection for the four M4 suites. Imports only
// the pure M2 AEADs (`std_cipher`); no allocation, no sockets, no clock.
//
// Surface (record layer only; handshake is M4 Task 2):
//   encodeRecord / parseRecordHeader / decodeRecord  (5-byte header, 16 KiB cap)
//   RecordReader                                      (incremental + memmove)
//   recordNonce / recordAad / sealFragment / openFragment
//   protectRecord / unprotectRecord                   (per-suite wire layout)
//
// Wire AEAD (TLS 1.2):
//   AES-128-GCM (RFC 5288): nonce = fixed_iv[4] || explicit[8]; explicit nonce
//     (= sequence number) is transmitted; AAD = seq || type || version || len.
//   ChaCha20-Poly1305 (RFC 7905): nonce = (0x00^4 || seq_be64) XOR fixed_iv[12];
//     no explicit nonce; AAD = seq || type || version || len.
//
// Errors: Corrupt (malformed lengths/truncation), AuthenticationFailed (AEAD
// tag/nonce tamper), RecordTooLarge (> TLS_MAX_RECORD or reader overflow),
// Closed (clean end of stream at a record boundary).

const cipher = @import("std_cipher.zig");

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
