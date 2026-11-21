// stdlib_truststore_xmod — STDLIB std_x509 pinned trust store (Phase1 M3).
//
// Loads the hand-built §5.5 store vector (magic "Z98CA100", u32 count,
// u32 total_len, entry headers + subject/spki DER) and compares each anchor
// against the source certificate parsed by `std_x509`. Corrupt vectors pin the
// bad-magic, truncated-entry and wrong-total_len rejections.
//
// GREEN (contract): deterministic byte-exact stdout `truststore ok\n` (RUNRC=0).
const std = @import("std");
const x509 = @import("std_x509.zig");
const certs = @import("certs_data.zig");
const vecs = @import("vectors_data.zig");

var g_fail: u32 = 0;
var g_buf: [32768]u8 = undefined;
var g_arena = std.arena.init(g_buf[0..]);

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

fn expectCorrupt(bytes: []const u8, what: []const u8) void {
    var s: x509.TrustStore = undefined;
    x509.trustStoreLoad(&g_arena, bytes, &s) catch |e| {
        ck(e == error.Corrupt, what);
        return;
    };
    @panic(what);
}

pub fn main() void {
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&g_arena, vecs.store_roundtrip_bin[0..], &store) catch @panic("roundtrip load");
    ck(store.anchors.len == 6, "anchor count");

    var c: x509.Cert = undefined;
    x509.x509Parse(certs.ecdsa_root_der[0..], &c) catch @panic("ecdsa root parse");
    ck(eqBytes(store.anchors[0].subject, c.subject), "anchor0 subject");
    ck(eqBytes(store.anchors[0].spki, c.spki), "anchor0 spki");
    ck(store.anchors[0].not_before == 1577836800, "anchor0 not_before");
    ck(store.anchors[0].not_after == 2051222400, "anchor0 not_after");

    x509.x509Parse(certs.rsa_root_der[0..], &c) catch @panic("rsa root parse");
    ck(eqBytes(store.anchors[1].subject, c.subject), "anchor1 subject");
    ck(eqBytes(store.anchors[1].spki, c.spki), "anchor1 spki");
    ck(store.anchors[1].not_before == 1577836800, "anchor1 not_before");
    ck(store.anchors[1].not_after == 2051222400, "anchor1 not_after");

    expectCorrupt(vecs.corrupt_bad_magic_bin[0..], "bad magic");
    expectCorrupt(vecs.corrupt_truncated_entry_bin[0..], "truncated entry");
    expectCorrupt(vecs.corrupt_total_len_bin[0..], "wrong total_len");

    if (g_fail == 0) {
        std.io.write("truststore ok\n");
    } else {
        std.io.write("truststore FAIL\n");
    }
}
