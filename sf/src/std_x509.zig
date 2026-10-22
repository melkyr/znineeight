// std_x509.zig — Z98 std lib: X.509 certificate parsing.
//
// Contract (spec §5.4): alloc no | errors Corrupt only at parse time |
// coroutine no. Pure except the caller-supplied `Cert` output. Every returned
// slice (subject, issuer, spki, sig, san_dns entries) points into the caller's
// DER buffer; nothing is copied and the DER must outlive the `Cert`.
//
// `Cert` owns a fixed array of SAN entries: `SAN_MAX` (32). A certificate with
// more dNSName entries returns `error.Corrupt` (the parse API has no arena).
// `san_dns` points into `san_storage`; entries are in DER order.
//
// Fields:
//   subject/issuer  full DER Name TLV (header included)
//   spki            full DER SubjectPublicKeyInfo TLV
//   sig             signature BIT STRING octets (unused-bits byte stripped)
//   sig_alg/pk_alg  OID classification; unknown but well-formed OIDs are kept
//                   as `.unknown` (chain verification decides support)
//   not_before/after  UTC/GeneralizedTime -> i64 seconds since the Unix epoch
//   is_ca           basicConstraints cA (default false)
//   san_dns         dNSName GeneralNames only (email/URI/IP ignored)
//
// Time parsing accepts only the RFC 5280 DER forms: UTCTime
// "YYMMDDHHMMSSZ" (1950..2049) and GeneralizedTime "YYYYMMDDHHMMSSZ".

const asn1 = @import("std_asn1.zig");
const crypto = @import("std_crypto.zig");
const ecc = @import("std_ecc.zig");
const arena_mod = @import("std_arena.zig");

pub const X509Error = error{Corrupt};

pub const SAN_MAX: usize = 32;

pub const SigAlg = enum {
    ecdsa_sha256,
    ecdsa_sha384,
    rsa_pkcs1_sha256,
    rsa_pkcs1_sha384,
    rsa_pkcs1_sha512,
    rsa_pss,
    unknown,
};

pub const PkAlg = enum {
    ec_p256,
    ec_p384,
    rsa,
    unknown,
};

pub const Cert = struct {
    subject: []const u8,
    issuer: []const u8,
    spki: []const u8,
    tbs: []const u8,
    sig: []const u8,
    sig_alg: SigAlg,
    pk_alg: PkAlg,
    not_before: i64,
    not_after: i64,
    is_ca: bool,
    san_dns: []const []const u8,
    san_storage: [SAN_MAX][]const u8,
    san_count: usize,
};

const OID_ECDSA_SHA256 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02 };
const OID_ECDSA_SHA384 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03 };
const OID_RSA_SHA256 = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b };
const OID_RSA_SHA384 = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0c };
const OID_RSA_SHA512 = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0d };
const OID_RSA_PSS = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0a };
const OID_EC_PUBLIC_KEY = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 };
const OID_PRIME256V1 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };
const OID_SECP384R1 = [_]u8{ 0x2b, 0x81, 0x04, 0x00, 0x22 };
const OID_RSA_ENCRYPTION = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01 };
const OID_BASIC_CONSTRAINTS = [_]u8{ 0x55, 0x1d, 0x13 };
const OID_SUBJECT_ALT_NAME = [_]u8{ 0x55, 0x1d, 0x11 };

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn atEnd(r: *const asn1.Asn1Reader) bool {
    return asn1.asn1Remaining(r) == 0;
}

fn expectUniversal(r: *asn1.Asn1Reader, tag: u32, constructed: bool) X509Error!asn1.Tlv {
    var t = asn1.asn1ReadTlv(r) catch return error.Corrupt;
    if (t.cls != asn1.TagClass.universal) return error.Corrupt;
    if (t.tag != tag) return error.Corrupt;
    if (t.constructed != constructed) return error.Corrupt;
    return t;
}

fn expectContext(r: *asn1.Asn1Reader, tag: u32) X509Error!asn1.Tlv {
    var t = asn1.asn1ReadTlv(r) catch return error.Corrupt;
    if (t.cls != asn1.TagClass.context) return error.Corrupt;
    if (t.tag != tag) return error.Corrupt;
    return t;
}

fn sigAlgFromOid(oid: []const u8) SigAlg {
    if (eqBytes(oid, OID_ECDSA_SHA256[0..])) return SigAlg.ecdsa_sha256;
    if (eqBytes(oid, OID_ECDSA_SHA384[0..])) return SigAlg.ecdsa_sha384;
    if (eqBytes(oid, OID_RSA_SHA256[0..])) return SigAlg.rsa_pkcs1_sha256;
    if (eqBytes(oid, OID_RSA_SHA384[0..])) return SigAlg.rsa_pkcs1_sha384;
    if (eqBytes(oid, OID_RSA_SHA512[0..])) return SigAlg.rsa_pkcs1_sha512;
    if (eqBytes(oid, OID_RSA_PSS[0..])) return SigAlg.rsa_pss;
    return SigAlg.unknown;
}

fn parseAlgId(r: *asn1.Asn1Reader) X509Error!asn1.Tlv {
    const seq = try expectUniversal(r, 16, true);
    var sr = asn1.asn1Init(seq.data);
    const oid = try expectUniversal(&sr, 6, false);
    while (!atEnd(&sr)) {
        _ = asn1.asn1ReadTlv(&sr) catch return error.Corrupt;
    }
    return oid;
}

fn bitStringOctets(t: *const asn1.Tlv) X509Error![]const u8 {
    if (t.data.len < 1) return error.Corrupt;
    const unused: u8 = t.data[0];
    if (unused > 7) return error.Corrupt;
    if (unused != 0) return error.Corrupt;
    return t.data[1..];
}

fn digit(d: []const u8, off: usize) X509Error!i64 {
    const c: u8 = d[off];
    if (c < '0' or c > '9') return error.Corrupt;
    return @intCast(i64, c - '0');
}

fn two(d: []const u8, off: usize) X509Error!i64 {
    const hi = try digit(d, off);
    const lo = try digit(d, off + 1);
    return hi * 10 + lo;
}

fn four(d: []const u8, off: usize) X509Error!i64 {
    const a = try digit(d, off);
    const b = try digit(d, off + 1);
    const c = try digit(d, off + 2);
    const e = try digit(d, off + 3);
    return ((a * 10 + b) * 10 + c) * 10 + e;
}

fn isLeap(y: i64) bool {
    if (y % 400 == 0) return true;
    if (y % 100 == 0) return false;
    return y % 4 == 0;
}

fn daysInMonth(y: i64, m: i64) i64 {
    if (m == 1 or m == 3 or m == 5 or m == 7 or m == 8 or m == 10 or m == 12) return 31;
    if (m == 4 or m == 6 or m == 9 or m == 11) return 30;
    if (m == 2) {
        if (isLeap(y)) return 29;
        return 28;
    }
    return 0;
}

fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    var y = y_in;
    if (m <= 2) y -= 1;
    const era = y / 400;
    const yoe = y - era * 400;
    var mp = m - 3;
    if (m <= 2) mp = m + 9;
    const doy = (153 * mp + 2) / 5 + d - 1;
    const doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

fn parseTime(t: *const asn1.Tlv) X509Error!i64 {
    if (t.cls != asn1.TagClass.universal) return error.Corrupt;
    var year: i64 = 0;
    var month: i64 = 0;
    var day: i64 = 0;
    var hour: i64 = 0;
    var minute: i64 = 0;
    var sec: i64 = 0;
    if (t.tag == 23) {
        if (t.data.len != 13) return error.Corrupt;
        if (t.data[12] != 'Z') return error.Corrupt;
        const yy = try two(t.data, 0);
        if (yy >= 50) {
            year = 1900 + yy;
        } else {
            year = 2000 + yy;
        }
        month = try two(t.data, 2);
        day = try two(t.data, 4);
        hour = try two(t.data, 6);
        minute = try two(t.data, 8);
        sec = try two(t.data, 10);
    } else if (t.tag == 24) {
        if (t.data.len != 15) return error.Corrupt;
        if (t.data[14] != 'Z') return error.Corrupt;
        year = try four(t.data, 0);
        month = try two(t.data, 4);
        day = try two(t.data, 6);
        hour = try two(t.data, 8);
        minute = try two(t.data, 10);
        sec = try two(t.data, 12);
    } else {
        return error.Corrupt;
    }
    if (year < 1) return error.Corrupt;
    if (month < 1 or month > 12) return error.Corrupt;
    if (day < 1 or day > daysInMonth(year, month)) return error.Corrupt;
    if (hour > 23 or minute > 59 or sec > 59) return error.Corrupt;
    const days = daysFromCivil(year, month, day);
    return days * 86400 + hour * 3600 + minute * 60 + sec;
}

fn parseValidity(t: *const asn1.Tlv, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(t.data);
    const nb = asn1.asn1ReadTlv(&r) catch return error.Corrupt;
    const na = asn1.asn1ReadTlv(&r) catch return error.Corrupt;
    if (!atEnd(&r)) return error.Corrupt;
    out.not_before = try parseTime(&nb);
    out.not_after = try parseTime(&na);
}

fn parseSpki(t: *const asn1.Tlv, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(t.data);
    const alg = try expectUniversal(&r, 16, true);
    var ar = asn1.asn1Init(alg.data);
    const oid = try expectUniversal(&ar, 6, false);
    if (eqBytes(oid.data, OID_RSA_ENCRYPTION[0..])) {
        out.pk_alg = PkAlg.rsa;
    } else if (eqBytes(oid.data, OID_EC_PUBLIC_KEY[0..])) {
        if (atEnd(&ar)) return error.Corrupt;
        const curve = try expectUniversal(&ar, 6, false);
        if (eqBytes(curve.data, OID_PRIME256V1[0..])) {
            out.pk_alg = PkAlg.ec_p256;
        } else if (eqBytes(curve.data, OID_SECP384R1[0..])) {
            out.pk_alg = PkAlg.ec_p384;
        } else {
            out.pk_alg = PkAlg.unknown;
        }
    } else {
        out.pk_alg = PkAlg.unknown;
    }
    const bits = try expectUniversal(&r, 3, false);
    _ = try bitStringOctets(&bits);
    if (!atEnd(&r)) return error.Corrupt;
}

fn parseBasicConstraints(data: []const u8, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(data);
    const seq = try expectUniversal(&r, 16, true);
    if (!atEnd(&r)) return error.Corrupt;
    var sr = asn1.asn1Init(seq.data);
    var is_ca: bool = false;
    if (!atEnd(&sr)) {
        const first = asn1.asn1ReadTlv(&sr) catch return error.Corrupt;
        if (first.cls == asn1.TagClass.universal and first.tag == 1) {
            if (first.data.len != 1) return error.Corrupt;
            is_ca = first.data[0] != 0;
            if (!atEnd(&sr)) {
                const pl = asn1.asn1ReadTlv(&sr) catch return error.Corrupt;
                if (pl.cls != asn1.TagClass.universal or pl.tag != 2) return error.Corrupt;
            }
        } else if (first.cls == asn1.TagClass.universal and first.tag == 2) {
            // pathLen without an explicit cA BOOLEAN; cA stays default false.
        } else {
            return error.Corrupt;
        }
    }
    if (!atEnd(&sr)) return error.Corrupt;
    out.is_ca = is_ca;
}

fn parseSan(data: []const u8, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(data);
    const seq = try expectUniversal(&r, 16, true);
    if (!atEnd(&r)) return error.Corrupt;
    var sr = asn1.asn1Init(seq.data);
    while (!atEnd(&sr)) {
        const gn = asn1.asn1ReadTlv(&sr) catch return error.Corrupt;
        if (gn.cls == asn1.TagClass.context and gn.tag == 2) {
            if (gn.constructed) return error.Corrupt;
            if (out.san_count >= SAN_MAX) return error.Corrupt;
            out.san_storage[out.san_count] = gn.data;
            out.san_count += 1;
        }
    }
}

fn parseExtensions(data: []const u8, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(data);
    const seq = try expectUniversal(&r, 16, true);
    if (!atEnd(&r)) return error.Corrupt;
    var sr = asn1.asn1Init(seq.data);
    while (!atEnd(&sr)) {
        const ext = try expectUniversal(&sr, 16, true);
        var xr = asn1.asn1Init(ext.data);
        const oid = try expectUniversal(&xr, 6, false);
        if (atEnd(&xr)) return error.Corrupt;
        var value = asn1.asn1ReadTlv(&xr) catch return error.Corrupt;
        if (value.cls == asn1.TagClass.universal and value.tag == 1) {
            if (value.data.len != 1) return error.Corrupt;
            value = asn1.asn1ReadTlv(&xr) catch return error.Corrupt;
        }
        if (value.cls != asn1.TagClass.universal) return error.Corrupt;
        if (value.tag != 4 or value.constructed) return error.Corrupt;
        if (!atEnd(&xr)) return error.Corrupt;
        if (eqBytes(oid.data, OID_BASIC_CONSTRAINTS[0..])) {
            try parseBasicConstraints(value.data, out);
        } else if (eqBytes(oid.data, OID_SUBJECT_ALT_NAME[0..])) {
            try parseSan(value.data, out);
        }
    }
}

fn parseTbs(data: []const u8, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(data);
    var first = asn1.asn1ReadTlv(&r) catch return error.Corrupt;
    if (first.cls == asn1.TagClass.context and first.tag == 0 and first.constructed) {
        var vr = asn1.asn1Init(first.data);
        const ver = try expectUniversal(&vr, 2, false);
        if (ver.data.len == 0) return error.Corrupt;
        if (!atEnd(&vr)) return error.Corrupt;
        const serial = try expectUniversal(&r, 2, false);
        if (serial.data.len == 0) return error.Corrupt;
    } else {
        if (first.cls != asn1.TagClass.universal) return error.Corrupt;
        if (first.tag != 2 or first.constructed) return error.Corrupt;
        if (first.data.len == 0) return error.Corrupt;
    }

    _ = try parseAlgId(&r);
    const issuer = try expectUniversal(&r, 16, true);
    const validity = try expectUniversal(&r, 16, true);
    const subject = try expectUniversal(&r, 16, true);
    const spki = try expectUniversal(&r, 16, true);

    out.issuer = issuer.full;
    out.subject = subject.full;
    out.spki = spki.full;
    try parseValidity(&validity, out);
    try parseSpki(&spki, out);

    out.is_ca = false;
    out.san_count = 0;
    while (!atEnd(&r)) {
        const extra = asn1.asn1ReadTlv(&r) catch return error.Corrupt;
        if (extra.cls != asn1.TagClass.context) return error.Corrupt;
        if (extra.tag == 3) {
            if (!extra.constructed) return error.Corrupt;
            try parseExtensions(extra.data, out);
        } else if (extra.tag != 1 and extra.tag != 2) {
            return error.Corrupt;
        }
    }
    out.san_dns = out.san_storage[0..out.san_count];
}

pub fn x509Parse(der: []const u8, out: *Cert) X509Error!void {
    var r = asn1.asn1Init(der);
    const cert = try expectUniversal(&r, 16, true);
    if (!atEnd(&r)) return error.Corrupt;
    var cr = asn1.asn1Init(cert.data);
    const tbs = try expectUniversal(&cr, 16, true);
    const alg = try parseAlgId(&cr);
    const sig_bits = try expectUniversal(&cr, 3, false);
    if (!atEnd(&cr)) return error.Corrupt;

    const sig = try bitStringOctets(&sig_bits);
    out.sig = sig;
    out.sig_alg = sigAlgFromOid(alg.data);
    out.tbs = tbs.full;
    try parseTbs(tbs.data, out);
}

// ---------------------------------------------------------------------------
// Chain verification + pinned trust store (spec §5.4 / §5.5).
// ---------------------------------------------------------------------------

pub const X509VerifyError = error{
    CertificateExpired,
    CertificateNotYetValid,
    UnknownIssuer,
    HostnameMismatch,
    BadSignature,
    ChainTooLong,
    Corrupt,
    UnsupportedAlgorithm,
};

pub const TrustStoreError = error{ Corrupt, OutOfMemory };

pub const MAX_CHAIN: usize = 8;

pub const TrustAnchor = struct {
    subject: []const u8,
    spki: []const u8,
    not_before: i64,
    not_after: i64,
};

pub const TrustStore = struct {
    anchors: []TrustAnchor,
};

fn readU16Le(bytes: []const u8, off: usize) u16 {
    return @intCast(u16, bytes[off]) | (@intCast(u16, bytes[off + 1]) << 8);
}

fn readU32Le(bytes: []const u8, off: usize) u32 {
    return @intCast(u32, bytes[off]) |
        (@intCast(u32, bytes[off + 1]) << 8) |
        (@intCast(u32, bytes[off + 2]) << 16) |
        (@intCast(u32, bytes[off + 3]) << 24);
}

fn copyTo(dst: [*]u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

// Pinned little-endian store (spec §5.5):
//   "Z98CA100" | u32 count | u32 total_len | entries
//   entry = u16 subject_len, u16 spki_len, u32 not_before, u32 not_after,
//           subject_der, spki_der
pub fn trustStoreLoad(arena: *arena_mod.Arena, bytes: []const u8, out: *TrustStore) TrustStoreError!void {
    if (bytes.len < 16) return error.Corrupt;
    if (bytes[0] != 'Z' or bytes[1] != '9' or bytes[2] != '8' or bytes[3] != 'C' or
        bytes[4] != 'A' or bytes[5] != '1' or bytes[6] != '0' or bytes[7] != '0')
        return error.Corrupt;
    const count = readU32Le(bytes, 8);
    const total_len = readU32Le(bytes, 12);
    if (@intCast(usize, total_len) != bytes.len) return error.Corrupt;
    // Each entry needs at least its 12-byte header; reject absurd counts before
    // sizing the anchor array.
    if (@intCast(usize, count) > (bytes.len - 16) / 12) return error.Corrupt;

    const n = @intCast(usize, count);
    const raw = arena_mod.alloc(arena, n * @sizeOf(TrustAnchor)) catch return error.OutOfMemory;
    var anchors: [*]TrustAnchor = @ptrCast([*]TrustAnchor, raw);

    var off: usize = 16;
    var idx: usize = 0;
    while (idx < n) : (idx += 1) {
        if (bytes.len - off < 12) return error.Corrupt;
        const subject_len = @intCast(usize, readU16Le(bytes, off));
        const spki_len = @intCast(usize, readU16Le(bytes, off + 2));
        const not_before = @intCast(i64, readU32Le(bytes, off + 4));
        const not_after = @intCast(i64, readU32Le(bytes, off + 8));
        off += 12;
        if (subject_len == 0 or spki_len == 0) return error.Corrupt;
        if (subject_len + spki_len > bytes.len - off) return error.Corrupt;

        const sraw = arena_mod.alloc(arena, subject_len) catch return error.OutOfMemory;
        copyTo(sraw, bytes[off .. off + subject_len]);
        const kraw = arena_mod.alloc(arena, spki_len) catch return error.OutOfMemory;
        copyTo(kraw, bytes[off + subject_len .. off + subject_len + spki_len]);
        anchors[idx] = TrustAnchor{
            .subject = sraw[0..subject_len],
            .spki = kraw[0..spki_len],
            .not_before = not_before,
            .not_after = not_after,
        };
        off += subject_len + spki_len;
    }
    if (off != bytes.len) return error.Corrupt;
    out.anchors = anchors[0..n];
}

fn checkValidity(not_before: i64, not_after: i64, now_unix: i64) X509VerifyError!void {
    if (now_unix < not_before) return error.CertificateNotYetValid;
    if (now_unix > not_after) return error.CertificateExpired;
}

// Split an SPKI into (algorithm OID, curve OID or empty, key octets).
fn spkiParts(spki_der: []const u8, alg: *[]const u8, curve: *[]const u8, key: *[]const u8) X509VerifyError!void {
    var r = asn1.asn1Init(spki_der);
    const seq = asn1.asn1ReadTlv(&r) catch return error.BadSignature;
    if (seq.cls != asn1.TagClass.universal or seq.tag != 16 or !seq.constructed) return error.BadSignature;
    if (!atEnd(&r)) return error.BadSignature;
    var sr = asn1.asn1Init(seq.data);
    const alg_seq = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    if (alg_seq.cls != asn1.TagClass.universal or alg_seq.tag != 16 or !alg_seq.constructed) return error.BadSignature;
    var ar = asn1.asn1Init(alg_seq.data);
    const oid = asn1.asn1ReadTlv(&ar) catch return error.BadSignature;
    if (oid.cls != asn1.TagClass.universal or oid.tag != 6 or oid.constructed) return error.BadSignature;
    alg.* = oid.data;
    curve.* = oid.data[0..0];
    while (!atEnd(&ar)) {
        const p = asn1.asn1ReadTlv(&ar) catch return error.BadSignature;
        if (p.cls == asn1.TagClass.universal and p.tag == 6 and !p.constructed) curve.* = p.data;
    }
    const bits = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    if (bits.cls != asn1.TagClass.universal or bits.tag != 3 or bits.constructed) return error.BadSignature;
    if (!atEnd(&sr)) return error.BadSignature;
    if (bits.data.len < 2 or bits.data[0] != 0) return error.BadSignature;
    key.* = bits.data[1..];
}

// DER INTEGER -> fixed-width big-endian (left padded with zeros).
fn derIntToFixed(data: []const u8, out: []u8) X509VerifyError!void {
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

fn ecdsaSigParts(sig: []const u8, r_out: []u8, s_out: []u8) X509VerifyError!void {
    var r = asn1.asn1Init(sig);
    const seq = asn1.asn1ReadTlv(&r) catch return error.BadSignature;
    if (seq.cls != asn1.TagClass.universal or seq.tag != 16 or !seq.constructed) return error.BadSignature;
    if (!atEnd(&r)) return error.BadSignature;
    var sr = asn1.asn1Init(seq.data);
    const ri = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    const si = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    if (!atEnd(&sr)) return error.BadSignature;
    if (ri.cls != asn1.TagClass.universal or ri.tag != 2 or ri.constructed) return error.BadSignature;
    if (si.cls != asn1.TagClass.universal or si.tag != 2 or si.constructed) return error.BadSignature;
    try derIntToFixed(ri.data, r_out);
    try derIntToFixed(si.data, s_out);
}

fn effectiveBitLen(bytes: []const u8) usize {
    var i: usize = 0;
    while (i < bytes.len and bytes[i] == 0) : (i += 1) {}
    if (i >= bytes.len) return 0;
    var bits: usize = (bytes.len - i - 1) * 8;
    var v: u8 = bytes[i];
    while (v != 0) {
        bits += 1;
        v = v >> 1;
    }
    return bits;
}

fn rsaKeyParams(key_der: []const u8, n_out: *[]const u8, e_out: *u32) X509VerifyError!void {
    var r = asn1.asn1Init(key_der);
    const seq = asn1.asn1ReadTlv(&r) catch return error.BadSignature;
    if (seq.cls != asn1.TagClass.universal or seq.tag != 16 or !seq.constructed) return error.BadSignature;
    if (!atEnd(&r)) return error.BadSignature;
    var sr = asn1.asn1Init(seq.data);
    const mod = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    const exp = asn1.asn1ReadTlv(&sr) catch return error.BadSignature;
    if (!atEnd(&sr)) return error.BadSignature;
    if (mod.cls != asn1.TagClass.universal or mod.tag != 2 or mod.constructed) return error.BadSignature;
    if (exp.cls != asn1.TagClass.universal or exp.tag != 2 or exp.constructed) return error.BadSignature;

    if (mod.data.len == 0) return error.BadSignature;
    if ((mod.data[0] & 0x80) != 0) return error.BadSignature;
    var ms: usize = 0;
    while (ms < mod.data.len and mod.data[ms] == 0) : (ms += 1) {}
    if (ms >= mod.data.len) return error.BadSignature;
    n_out.* = mod.data[ms..];

    if (exp.data.len == 0) return error.BadSignature;
    if ((exp.data[0] & 0x80) != 0) return error.BadSignature;
    var es: usize = 0;
    while (es < exp.data.len and exp.data[es] == 0) : (es += 1) {}
    if (es >= exp.data.len) return error.BadSignature;
    if (exp.data.len - es > 4) return error.UnsupportedAlgorithm;

    var e: u32 = 0;
    var i: usize = es;
    while (i < exp.data.len) : (i += 1) e = (e << 8) | @intCast(u32, exp.data[i]);
    if (e == 0) return error.BadSignature;
    e_out.* = e;
}

const PathNode = struct {
    subject: []const u8,
    issuer: []const u8,
    spki: []const u8,
    tbs: []const u8,
    sig: []const u8,
    sig_alg: SigAlg,
    not_before: i64,
    not_after: i64,
    is_ca: bool,
};

fn pathCopy(dst: *PathNode, cert: *const Cert) void {
    dst.* = PathNode{
        .subject = cert.subject,
        .issuer = cert.issuer,
        .spki = cert.spki,
        .tbs = cert.tbs,
        .sig = cert.sig,
        .sig_alg = cert.sig_alg,
        .not_before = cert.not_before,
        .not_after = cert.not_after,
        .is_ca = cert.is_ca,
    };
}

fn verifySignature(cert: *const PathNode, issuer_spki: []const u8) X509VerifyError!void {
    var alg: []const u8 = undefined;
    var curve: []const u8 = undefined;
    var key: []const u8 = undefined;
    try spkiParts(issuer_spki, &alg, &curve, &key);

    if (cert.sig_alg == SigAlg.ecdsa_sha256) {
        if (!eqBytes(alg, OID_EC_PUBLIC_KEY[0..])) return error.UnsupportedAlgorithm;
        if (!eqBytes(curve, OID_PRIME256V1[0..])) return error.UnsupportedAlgorithm;
        if (key.len != 65 or key[0] != 0x04) return error.UnsupportedAlgorithm;
        var pub_key: [65]u8 = undefined;
        copyTo(pub_key[0..], key);
        var hash: [32]u8 = undefined;
        var h = crypto.sha256Init();
        crypto.sha256Update(&h, cert.tbs);
        crypto.sha256Final(&h, &hash);
        var r: [32]u8 = undefined;
        var s: [32]u8 = undefined;
        try ecdsaSigParts(cert.sig, r[0..], s[0..]);
        if (!ecc.p256EcdsaVerify(&pub_key, &hash, &r, &s)) return error.BadSignature;
        return;
    }
    if (cert.sig_alg == SigAlg.ecdsa_sha384) {
        if (!eqBytes(alg, OID_EC_PUBLIC_KEY[0..])) return error.UnsupportedAlgorithm;
        if (!eqBytes(curve, OID_SECP384R1[0..])) return error.UnsupportedAlgorithm;
        if (key.len != 97 or key[0] != 0x04) return error.UnsupportedAlgorithm;
        var pub_key: [97]u8 = undefined;
        copyTo(pub_key[0..], key);
        var hash: [48]u8 = undefined;
        var h = crypto.sha384Init();
        crypto.sha384Update(&h, cert.tbs);
        crypto.sha384Final(&h, &hash);
        var r: [48]u8 = undefined;
        var s: [48]u8 = undefined;
        try ecdsaSigParts(cert.sig, r[0..], s[0..]);
        if (!ecc.p384EcdsaVerify(&pub_key, &hash, &r, &s)) return error.BadSignature;
        return;
    }
    if (cert.sig_alg == SigAlg.rsa_pkcs1_sha256 or
        cert.sig_alg == SigAlg.rsa_pkcs1_sha384 or
        cert.sig_alg == SigAlg.rsa_pkcs1_sha512)
    {
        if (!eqBytes(alg, OID_RSA_ENCRYPTION[0..])) return error.UnsupportedAlgorithm;
        var n: []const u8 = undefined;
        var e: u32 = 0;
        try rsaKeyParams(key, &n, &e);
        if (effectiveBitLen(n) < 2048) return error.UnsupportedAlgorithm;
        if (cert.sig_alg == SigAlg.rsa_pkcs1_sha256) {
            var hash: [32]u8 = undefined;
            var h = crypto.sha256Init();
            crypto.sha256Update(&h, cert.tbs);
            crypto.sha256Final(&h, &hash);
            crypto.rsaVerifyPkcs1v15(n, e, crypto.HashAlg.sha256, hash[0..], cert.sig) catch return error.BadSignature;
        } else if (cert.sig_alg == SigAlg.rsa_pkcs1_sha384) {
            var hash: [48]u8 = undefined;
            var h = crypto.sha384Init();
            crypto.sha384Update(&h, cert.tbs);
            crypto.sha384Final(&h, &hash);
            crypto.rsaVerifyPkcs1v15(n, e, crypto.HashAlg.sha384, hash[0..], cert.sig) catch return error.BadSignature;
        } else {
            var hash: [64]u8 = undefined;
            var h = crypto.sha512Init();
            crypto.sha512Update(&h, cert.tbs);
            crypto.sha512Final(&h, &hash);
            crypto.rsaVerifyPkcs1v15(n, e, crypto.HashAlg.sha512, hash[0..], cert.sig) catch return error.BadSignature;
        }
        return;
    }
    // RSA-PSS is reserved, SHA-1 OIDs parse as unknown, and every other sig alg
    // is outside the validation policy.
    return error.UnsupportedAlgorithm;
}

fn asciiLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn eqCharsCi(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (asciiLower(a[i]) != asciiLower(b[i])) return false;
    }
    return true;
}

fn endsWithCi(host: []const u8, suffix: []const u8) bool {
    if (host.len < suffix.len) return false;
    return eqCharsCi(host[host.len - suffix.len ..], suffix);
}

fn hostnameMatches(pattern: []const u8, host: []const u8) bool {
    if (pattern.len == 0 or host.len == 0) return false;

    if (pattern.len >= 2 and pattern[0] == '*' and pattern[1] == '.') {
        const suffix = pattern[2..];
        if (suffix.len == 0) return false;
        var i: usize = 0;
        while (i < suffix.len) : (i += 1) {
            if (suffix[i] == '*') return false;
        }
        if (!endsWithCi(host, suffix)) return false;
        const prefix_len = host.len - suffix.len;
        if (prefix_len == 0) return false;
        if (host[prefix_len - 1] != '.') return false;
        const label = host[0 .. prefix_len - 1];
        if (label.len == 0) return false;
        i = 0;
        while (i < label.len) : (i += 1) {
            if (label[i] == '.') return false;
        }
        return true;
    }

    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        if (pattern[i] == '*') return false;
    }
    return eqCharsCi(pattern, host);
}

fn matchHostname(cert: *const Cert, hostname: []const u8) X509VerifyError!void {
    var i: usize = 0;
    while (i < cert.san_dns.len) : (i += 1) {
        if (hostnameMatches(cert.san_dns[i], hostname)) return;
    }
    return error.HostnameMismatch;
}

pub fn x509VerifyChain(arena: *arena_mod.Arena, leaf_der: []const u8,
    intermediates: []const []const u8, store: *TrustStore,
    hostname: []const u8, now_unix: i64) X509VerifyError!void
{
    _ = arena;
    var leaf: Cert = undefined;
    x509Parse(leaf_der, &leaf) catch return error.Corrupt;
    var path: [MAX_CHAIN]PathNode = undefined;
    pathCopy(&path[0], &leaf);
    var depth: usize = 1;
    var anchor_idx: usize = 0;

    while (true) {
        const cur_issuer = path[depth - 1].issuer;
        var found_anchor: bool = false;
        var ai: usize = 0;
        while (ai < store.anchors.len) : (ai += 1) {
            if (eqBytes(store.anchors[ai].subject, cur_issuer)) {
                anchor_idx = ai;
                found_anchor = true;
                break;
            }
        }
        if (found_anchor) break;

        var chosen: bool = false;
        var j: usize = 0;
        while (j < intermediates.len) : (j += 1) {
            var ic: Cert = undefined;
            x509Parse(intermediates[j], &ic) catch return error.Corrupt;
            if (!eqBytes(ic.subject, cur_issuer)) continue;
            if (!ic.is_ca) continue;
            if (depth >= MAX_CHAIN) return error.ChainTooLong;
            pathCopy(&path[depth], &ic);
            depth += 1;
            chosen = true;
            break;
        }
        if (!chosen) return error.UnknownIssuer;
    }

    var i: usize = 0;
    while (i < depth) : (i += 1) {
        var issuer_spki: []const u8 = undefined;
        if (i + 1 < depth) {
            issuer_spki = path[i + 1].spki;
        } else {
            issuer_spki = store.anchors[anchor_idx].spki;
        }
        try verifySignature(&path[i], issuer_spki);
    }

    i = 0;
    while (i < depth) : (i += 1) {
        try checkValidity(path[i].not_before, path[i].not_after, now_unix);
    }
    try checkValidity(store.anchors[anchor_idx].not_before, store.anchors[anchor_idx].not_after, now_unix);
    try matchHostname(&leaf, hostname);
}
