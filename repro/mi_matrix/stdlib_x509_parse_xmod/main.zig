// stdlib_x509_parse_xmod — STDLIB std_x509 (Phase1 M3) certificate parse.
//
// Uses a committed corpus of real DER certificates (generated once with host
// `openssl`) embedded by the generated certs_data.zig. The harness runs from a
// scratch CWD, so the fixture never reads files.
//
// Pins:
//   - ECDSA P-256 / P-384 and RSA-2048 keys
//   - ecdsa-with-SHA256/384 and sha256/384/512WithRSAEncryption signature OIDs
//   - subject / issuer / SPKI / signature spans (self-signed: subject == issuer)
//   - UTCTime and GeneralizedTime -> i64 unix seconds
//   - basicConstraints CA:TRUE and CA:FALSE
//   - SAN dNSName extraction (only tag [2]; email/URI names ignored)
//   - fixed SAN capacity overflow => Corrupt
//   - malformed certificates (truncated, indefinite length, nested overflow,
//     bad OID) => Corrupt
//
// GREEN (contract): deterministic byte-exact stdout `x509 parse ok\n` (RUNRC=0).
const std = @import("std");
const x509 = @import("std_x509.zig");
const certs = @import("certs_data.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parseOk(der: []const u8, out: *x509.Cert, what: []const u8) void {
    x509.x509Parse(der, out) catch @panic(what);
}

fn checkCommon(c: *const x509.Cert, what: []const u8) void {
    ck(c.subject.len > 0, what);
    ck(c.issuer.len > 0, what);
    ck(c.spki.len > 0, what);
    ck(c.sig.len > 0, what);
    ck(eqBytes(c.subject, c.issuer), what);
}

fn hasSan(c: *const x509.Cert, want: []const u8, what: []const u8) void {
    var i: usize = 0;
    while (i < c.san_dns.len) : (i += 1) {
        if (eqBytes(c.san_dns[i], want)) return;
    }
    @panic(what);
}

fn checkLeaf(c: *const x509.Cert, sig: x509.SigAlg, pk: x509.PkAlg, san: []const u8, what: []const u8) void {
    checkCommon(c, what);
    ck(c.sig_alg == sig, what);
    ck(c.pk_alg == pk, what);
    ck(!c.is_ca, what);
    ck(c.not_before == 1704067200, what);
    ck(c.not_after == 1893456000, what);
    ck(c.san_dns.len == 1, what);
    hasSan(c, san, what);
}

fn expectCorrupt(der: []const u8, what: []const u8) void {
    var c: x509.Cert = undefined;
    x509.x509Parse(der, &c) catch |e| {
        ck(e == error.Corrupt, what);
        return;
    };
    @panic(what);
}

pub fn main() void {
    var c: x509.Cert = undefined;

    parseOk(certs.leaf_p256_der[0..], &c, "leaf p256 parse");
    checkLeaf(&c, x509.SigAlg.ecdsa_sha256, x509.PkAlg.ec_p256, "leaf-p256.example.test", "leaf p256");

    parseOk(certs.leaf_p384_der[0..], &c, "leaf p384 parse");
    checkLeaf(&c, x509.SigAlg.ecdsa_sha384, x509.PkAlg.ec_p384, "leaf-p384.example.test", "leaf p384");

    parseOk(certs.leaf_rsa_sha256_der[0..], &c, "rsa sha256 parse");
    checkLeaf(&c, x509.SigAlg.rsa_pkcs1_sha256, x509.PkAlg.rsa, "leaf-rsa-sha256.example.test", "rsa sha256");

    parseOk(certs.leaf_rsa_sha384_der[0..], &c, "rsa sha384 parse");
    checkLeaf(&c, x509.SigAlg.rsa_pkcs1_sha384, x509.PkAlg.rsa, "leaf-rsa-sha384.example.test", "rsa sha384");

    parseOk(certs.leaf_rsa_sha512_der[0..], &c, "rsa sha512 parse");
    checkLeaf(&c, x509.SigAlg.rsa_pkcs1_sha512, x509.PkAlg.rsa, "leaf-rsa-sha512.example.test", "rsa sha512");

    parseOk(certs.ca_basic_der[0..], &c, "ca basic parse");
    checkCommon(&c, "ca basic");
    ck(c.sig_alg == x509.SigAlg.ecdsa_sha256, "ca sig alg");
    ck(c.pk_alg == x509.PkAlg.ec_p256, "ca pk alg");
    ck(c.is_ca, "ca basic is_ca");
    ck(c.not_before == 1577836800, "ca not_before");
    ck(c.not_after == 2051222400, "ca not_after");
    ck(c.san_dns.len == 0, "ca no san");

    parseOk(certs.san_wildcard_der[0..], &c, "san wildcard parse");
    checkCommon(&c, "san wildcard");
    ck(c.sig_alg == x509.SigAlg.ecdsa_sha256, "wildcard sig alg");
    ck(c.pk_alg == x509.PkAlg.ec_p256, "wildcard pk alg");
    ck(!c.is_ca, "wildcard not ca");
    ck(c.not_before == 1704067200, "wildcard not_before");
    ck(c.not_after == 1893456000, "wildcard not_after");
    ck(c.san_dns.len == 3, "wildcard san count");
    hasSan(&c, "example.test", "wildcard san 0");
    hasSan(&c, "*.example.test", "wildcard san 1");
    hasSan(&c, "www.example.test", "wildcard san 2");

    parseOk(certs.expired_der[0..], &c, "expired parse");
    checkCommon(&c, "expired");
    ck(c.not_before == 1577836800, "expired not_before");
    ck(c.not_after == 1609459199, "expired not_after");
    ck(c.san_dns.len == 1, "expired san count");
    hasSan(&c, "expired.example.test", "expired san");

    parseOk(certs.generalized_der[0..], &c, "generalized parse");
    checkCommon(&c, "generalized");
    ck(c.not_before == 2524608000, "generalized not_before");
    ck(c.not_after == 2840140800, "generalized not_after");
    ck(c.san_dns.len == 1, "generalized san count");
    hasSan(&c, "generalized.example.test", "generalized san");

    expectCorrupt(certs.overcap_der[0..], "san capacity overflow");
    expectCorrupt(certs.malformed_truncated_der[0..], "truncated cert");
    expectCorrupt(certs.malformed_indefinite_der[0..], "indefinite cert");
    expectCorrupt(certs.malformed_nested_der[0..], "nested overflow cert");
    expectCorrupt(certs.malformed_bad_oid_der[0..], "bad oid cert");

    if (g_fail == 0) {
        std.io.write("x509 parse ok\n");
    } else {
        std.io.write("x509 parse FAIL\n");
    }
}
