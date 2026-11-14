// stdlib_asn1_xmod — STDLIB std_asn1 (Phase1 M3) DER reader fixture.
//
// std_asn1.zig is a PURE Z98 module: streaming TLV reader, no allocation, no
// imports. Slices point into the caller's input buffer. This fixture pins:
//   - universal SEQUENCE / INTEGER / OCTET STRING / OID / BIT STRING parsing
//   - context-specific tags and the high-tag-number form
//   - definite short-form and long-form lengths
//   - explicit-only lengths (indefinite 0x80 rejected)
//   - truncated TLV, nested length overflow, and malformed OID => Corrupt
//
// GREEN (contract): deterministic byte-exact stdout `asn1 ok\n` (RUNRC=0).
// Any structural mismatch or a malformed input that does not return
// `error.Corrupt` calls @panic.
const std = @import("std");
const asn1 = @import("std_asn1.zig");
const vec = @import("vectors_data.zig");

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

fn readTlv(r: *asn1.Asn1Reader, what: []const u8) asn1.Tlv {
    const t = asn1.asn1ReadTlv(r) catch @panic(what);
    return t;
}

fn expectTag(t: *const asn1.Tlv, cls: asn1.TagClass, tag: u32, cons: bool, what: []const u8) void {
    if (t.cls != cls) @panic(what);
    if (t.tag != tag) @panic(what);
    if (t.constructed != cons) @panic(what);
}

fn expectCorrupt(bytes: []const u8, what: []const u8) void {
    var r = asn1.asn1Init(bytes);
    _ = asn1.asn1ReadTlv(&r) catch |e| {
        ck(e == error.Corrupt, what);
        return;
    };
    @panic(what);
}

pub fn main() void {
    var seq_bytes = [_]u8{
        0x30, 0x11,
        0x02, 0x01, 0x2a,
        0x04, 0x03, 0x61, 0x62, 0x63,
        0x06, 0x03, 0x2a, 0x86, 0x48,
        0x03, 0x02, 0x00, 0xff,
    };
    var r = asn1.asn1Init(seq_bytes[0..]);
    const seq = readTlv(&r, "sequence");
    expectTag(&seq, asn1.TagClass.universal, 16, true, "sequence tag");
    ck(r.pos == r.data.len, "sequence consumed");
    ck(seq.full.len == seq_bytes.len, "sequence full span");

    var sr = asn1.asn1Init(seq.data);
    const i1 = readTlv(&sr, "integer");
    expectTag(&i1, asn1.TagClass.universal, 2, false, "integer tag");
    ck(i1.data.len == 1 and i1.data[0] == 0x2a, "integer value");

    const s1 = readTlv(&sr, "octet string");
    expectTag(&s1, asn1.TagClass.universal, 4, false, "octet tag");
    ck(eqBytes(s1.data, "abc"), "octet value");

    const o1 = readTlv(&sr, "oid");
    expectTag(&o1, asn1.TagClass.universal, 6, false, "oid tag");
    var want_oid = [_]u8{ 0x2a, 0x86, 0x48 };
    ck(eqBytes(o1.data, want_oid[0..]), "oid value");

    const b1 = readTlv(&sr, "bit string");
    expectTag(&b1, asn1.TagClass.universal, 3, false, "bit string tag");
    ck(b1.data.len == 2 and b1.data[0] == 0 and b1.data[1] == 0xff, "bit string value");
    ck(sr.pos == sr.data.len, "sequence contents consumed");

    var ctx_bytes = [_]u8{ 0xa0, 0x03, 0x02, 0x01, 0x07 };
    var cr = asn1.asn1Init(ctx_bytes[0..]);
    const ctx = readTlv(&cr, "context tag");
    expectTag(&ctx, asn1.TagClass.context, 0, true, "context tag 0");
    ck(ctx.data.len == 3 and ctx.data[0] == 0x02, "context content");
    ck(cr.pos == cr.data.len, "context consumed");

    var hi_bytes = [_]u8{ 0x1f, 0x81, 0x00, 0x01, 0x00 };
    var hr = asn1.asn1Init(hi_bytes[0..]);
    const hi = readTlv(&hr, "high tag");
    expectTag(&hi, asn1.TagClass.universal, 128, false, "high tag number");
    ck(hi.data.len == 1 and hi.data[0] == 0, "high tag content");

    var long_bytes: [203]u8 = undefined;
    long_bytes[0] = 0x30;
    long_bytes[1] = 0x81;
    long_bytes[2] = 0xc8;
    var li: usize = 0;
    while (li < 200) : (li += 1) long_bytes[3 + li] = @intCast(u8, li & 0xff);
    var lr = asn1.asn1Init(long_bytes[0..]);
    const lseq = readTlv(&lr, "long length");
    expectTag(&lseq, asn1.TagClass.universal, 16, true, "long length tag");
    ck(lseq.data.len == 200, "long length size");
    ck(lseq.data[199] == 199, "long length content");
    ck(lr.pos == lr.data.len, "long length consumed");

    expectCorrupt(vec.short_tlv_bin[0..], "truncated tlv");
    expectCorrupt(vec.indefinite_len_bin[0..], "indefinite length");
    expectCorrupt(vec.bad_oid_bin[0..], "bad oid");

    var nr = asn1.asn1Init(vec.nested_overflow_bin[0..]);
    const nseq = readTlv(&nr, "nested outer");
    expectTag(&nseq, asn1.TagClass.universal, 16, true, "nested outer tag");
    var nsr = asn1.asn1Init(nseq.data);
    _ = asn1.asn1ReadTlv(&nsr) catch |e| {
        ck(e == error.Corrupt, "nested overflow");
        if (g_fail == 0) {
            std.io.write("asn1 ok\n");
        } else {
            std.io.write("asn1 FAIL\n");
        }
        return;
    };
    @panic("nested overflow");
}
