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
    try parseTbs(tbs.data, out);
}
