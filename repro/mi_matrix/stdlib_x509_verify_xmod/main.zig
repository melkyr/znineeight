// stdlib_x509_verify_xmod — STDLIB std_x509 (Phase1 M3) chain verify.
//
// Uses committed DER chains generated once with host `openssl`:
//   - ECDSA P-256 leaf -> P-384 intermediate -> P-384 root, SHA-384 links
//   - RSA-2048 chain, SHA-256 root self-signature, SHA-384 intermediate link,
//     SHA-512 leaf link
//   - ECDSA P-256 / SHA-256 chain
//   - wildcard SAN leaf under the ECDSA chain
//   - SHA-1 chain (UnsupportedAlgorithm)
//   - RSA-1024 issuer (UnsupportedAlgorithm: modulus < 2048)
//   - 9-deep CA chain (ChainTooLong)
//
// Negatives assert the exact error from the §5.4 error set. Trust anchors are
// trusted by fiat; the hand-built store vector pins the §5.5 format.
//
// GREEN (contract): deterministic byte-exact stdout `x509 verify ok\n` (RUNRC=0).
const std = @import("std");
const x509 = @import("std_x509.zig");
const certs = @import("certs_data.zig");
const vecs = @import("vectors_data.zig");

var g_fail: u32 = 0;

var g_store_buf: [32768]u8 = undefined;
var g_store_arena = std.arena.init(g_store_buf[0..]);
var g_store: x509.TrustStore = undefined;
var g_rsa_buf: [8192]u8 = undefined;
var g_rsa_arena = std.arena.init(g_rsa_buf[0..]);
var g_rsa_only: x509.TrustStore = undefined;
var g_security_buf: [8192]u8 = undefined;
var g_security_arena = std.arena.init(g_security_buf[0..]);
var g_security: x509.TrustStore = undefined;

const E_EXPIRED: u8 = 1;
const E_NOT_YET: u8 = 2;
const E_UNKNOWN: u8 = 3;
const E_HOSTNAME: u8 = 4;
const E_BADSIG: u8 = 5;
const E_TOO_LONG: u8 = 6;
const E_CORRUPT: u8 = 7;
const E_UNSUPPORTED: u8 = 8;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn expectOk(leaf: []const u8, inters: []const []const u8, host: []const u8, now: i64, what: []const u8) void {
    x509.x509VerifyChain(&g_store_arena, leaf, inters, &g_store, host, now) catch @panic(what);
}

fn expectOkStore(leaf: []const u8, inters: []const []const u8, store: *x509.TrustStore, host: []const u8, now: i64, what: []const u8) void {
    x509.x509VerifyChain(&g_store_arena, leaf, inters, store, host, now) catch @panic(what);
}

fn expectErr(leaf: []const u8, inters: []const []const u8, store: *x509.TrustStore, host: []const u8, now: i64, want: u8, what: []const u8) void {
    var matched: bool = false;
    x509.x509VerifyChain(&g_store_arena, leaf, inters, store, host, now) catch |e| {
        if (want == E_EXPIRED) matched = e == error.CertificateExpired;
        if (want == E_NOT_YET) matched = e == error.CertificateNotYetValid;
        if (want == E_UNKNOWN) matched = e == error.UnknownIssuer;
        if (want == E_HOSTNAME) matched = e == error.HostnameMismatch;
        if (want == E_BADSIG) matched = e == error.BadSignature;
        if (want == E_TOO_LONG) matched = e == error.ChainTooLong;
        if (want == E_CORRUPT) matched = e == error.Corrupt;
        if (want == E_UNSUPPORTED) matched = e == error.UnsupportedAlgorithm;
        ck(matched, what);
        return;
    };
    @panic(what);
}

pub fn main() void {
    x509.trustStoreLoad(&g_store_arena, vecs.store_roundtrip_bin[0..], &g_store) catch @panic("store load");
    x509.trustStoreLoad(&g_rsa_arena, vecs.store_rsa_only_bin[0..], &g_rsa_only) catch @panic("rsa store load");
    x509.trustStoreLoad(&g_security_arena, vecs.store_security_bin[0..], &g_security) catch @panic("security store load");
    ck(g_store.anchors.len == 6, "store anchor count");
    ck(g_security.anchors.len == 1, "security store anchor count");

    const ECDSA_NOW: i64 = 1735689600; // 2025-01-01T00:00:00Z

    var ecdsa_inters = [_][]const u8{certs.ecdsa_int_der[0..]};
    var ecdsa_bad_inters = [_][]const u8{certs.ecdsa_int_badsig_der[0..]};
    var rsa_inters = [_][]const u8{certs.rsa_int_der[0..]};
    var p256_inters = [_][]const u8{certs.p256_int_der[0..]};
    var long_inters = [_][]const u8{
        certs.long_ca8_der[0..],
        certs.long_ca7_der[0..],
        certs.long_ca6_der[0..],
        certs.long_ca5_der[0..],
        certs.long_ca4_der[0..],
        certs.long_ca3_der[0..],
        certs.long_ca2_der[0..],
        certs.long_ca1_der[0..],
        certs.long_ca0_der[0..],
    };
    var sha1_inters = [_][]const u8{certs.sha1_int_der[0..]};
    var no_inters = [_][]const u8{certs.ecdsa_leaf_der[0..]};
    var backtrack_wrong_inters = [_][]const u8{certs.security_int_wrong_der[0..]};
    var backtrack_inters = [_][]const u8{
        certs.security_int_wrong_der[0..],
        certs.security_int_correct_der[0..],
    };

    expectOk(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], "leaf-verify.example.test", ECDSA_NOW, "ecdsa valid");
    expectOk(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], "LEAF-VERIFY.EXAMPLE.TEST", ECDSA_NOW, "exact case-insensitive");
    expectOk(certs.rsa_leaf_der[0..], rsa_inters[0..], "rsa-verify.example.test", ECDSA_NOW, "rsa valid");
    expectOk(certs.p256_leaf_der[0..], p256_inters[0..], "p256-verify.example.test", ECDSA_NOW, "p256 valid");
    expectOk(certs.wildcard_leaf_der[0..], ecdsa_inters[0..], "a.example.com", ECDSA_NOW, "wildcard one label");
    expectOk(certs.wildcard_leaf_der[0..], ecdsa_inters[0..], "A.EXAMPLE.COM", ECDSA_NOW, "wildcard case-insensitive");

    // Validity boundaries: not_before = 1704067200, not_after = 1893456000.
    expectOk(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], "leaf-verify.example.test", 1704067200, "not_before inclusive");
    expectOk(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], "leaf-verify.example.test", 1893456000, "not_after inclusive");
    expectErr(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], &g_store, "leaf-verify.example.test", 1704067199, E_NOT_YET, "not_before -1");
    expectErr(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], &g_store, "leaf-verify.example.test", 1893456001, E_EXPIRED, "not_after +1");

    expectErr(certs.ecdsa_leaf_der[0..], ecdsa_bad_inters[0..], &g_store, "leaf-verify.example.test", ECDSA_NOW, E_BADSIG, "bit-flipped intermediate sig");
    expectErr(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], &g_rsa_only, "leaf-verify.example.test", ECDSA_NOW, E_UNKNOWN, "anchor missing");
    expectErr(certs.ecdsa_leaf_der[0..], ecdsa_inters[0..], &g_store, "leaf-verify.example.org", ECDSA_NOW, E_HOSTNAME, "exact mismatch");
    expectErr(certs.wildcard_leaf_der[0..], ecdsa_inters[0..], &g_store, "a.b.example.com", ECDSA_NOW, E_HOSTNAME, "wildcard multi-label");
    expectErr(certs.wildcard_leaf_der[0..], ecdsa_inters[0..], &g_store, "example.com", ECDSA_NOW, E_HOSTNAME, "wildcard bare suffix");
    expectErr(certs.long_leaf_der[0..], long_inters[0..], &g_store, "long-verify.example.test", ECDSA_NOW, E_TOO_LONG, "9-deep chain");
    expectErr(certs.sha1_leaf_der[0..], sha1_inters[0..], &g_store, "sha1-verify.example.test", ECDSA_NOW, E_UNSUPPORTED, "sha1 link");
    expectErr(certs.rsa1024_leaf_der[0..], no_inters[0..0], &g_store, "rsa1024-verify.example.test", ECDSA_NOW, E_UNSUPPORTED, "rsa 1024 issuer");
    expectOkStore(certs.backtrack_leaf_der[0..], backtrack_inters[0..], &g_security, "backtrack.example.test", ECDSA_NOW, "same-subject backtracking");
    expectErr(certs.backtrack_leaf_der[0..], backtrack_wrong_inters[0..], &g_security, "backtrack.example.test", ECDSA_NOW, E_BADSIG, "wrong same-subject intermediate");
    expectErr(certs.rsa1024_leaf_rsa2048root_der[0..], no_inters[0..0], &g_security, "rsa1024-leaf.example.test", ECDSA_NOW, E_UNSUPPORTED, "rsa 1024 leaf key");
    expectErr(certs.ecdsa_leaf_der[0..0], no_inters[0..0], &g_store, "x", ECDSA_NOW, E_CORRUPT, "empty leaf");

    if (g_fail == 0) {
        std.io.write("x509 verify ok\n");
    } else {
        std.io.write("x509 verify FAIL\n");
    }
}
