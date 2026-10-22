// std_asn1.zig — Z98 std lib: streaming DER (ASN.1) TLV reader.
//
// Contract: alloc no | errors Corrupt only | coroutine no. Pure (no imports).
// The reader never copies: every returned (class, tag, data, full) points into
// the caller's input buffer. Only DER definite lengths are accepted:
// indefinite length (0x80), non-minimal length/tag encodings, truncated
// headers/bodies, and malformed OID contents all return `error.Corrupt`.
//
// Usage:
//   var r = asn1Init(der);
//   const seq = try asn1ReadTlv(&r);
//   var sr = asn1Init(seq.data);
//   const oid = try asn1ReadTlv(&sr);
//
// High-tag-number form is supported (tag numbers >= 31); primitive contents
// are opaque except universal OID, whose base-128 encoding is validated here.

pub const Asn1Error = error{Corrupt};

pub const TagClass = enum {
    universal,
    application,
    context,
    private,
};

pub const Tlv = struct {
    cls: TagClass,
    constructed: bool,
    tag: u32,
    data: []const u8,
    full: []const u8,
};

pub const Asn1Reader = struct {
    data: []const u8,
    pos: usize,
};

pub fn asn1Init(data: []const u8) Asn1Reader {
    var r: Asn1Reader = Asn1Reader{ .data = data, .pos = 0 };
    return r;
}

pub fn asn1Remaining(r: *const Asn1Reader) usize {
    if (r.pos >= r.data.len) return 0;
    return r.data.len - r.pos;
}

fn classOf(b: u8) TagClass {
    var c: u8 = b & 0xC0;
    if (c == 0x00) return TagClass.universal;
    if (c == 0x40) return TagClass.application;
    if (c == 0x80) return TagClass.context;
    return TagClass.private;
}

// DER OID contents: one or more base-128 subidentifiers, minimally encoded
// (no leading 0x80 group), with the high bit clear on the final octet.
fn oidContentValid(d: []const u8) bool {
    if (d.len == 0) return false;
    var start: usize = 0;
    var i: usize = 0;
    while (i < d.len) : (i += 1) {
        if ((d[i] & 0x80) == 0) {
            if (i > start and d[start] == 0x80) return false;
            start = i + 1;
        }
    }
    if (start != d.len) return false;
    return true;
}

pub fn asn1ReadTlv(r: *Asn1Reader) Asn1Error!Tlv {
    if (r.pos >= r.data.len) return error.Corrupt;
    const start: usize = r.pos;
    const b0: u8 = r.data[r.pos];
    r.pos += 1;
    const cls = classOf(b0);
    const constructed: bool = (b0 & 0x20) != 0;
    var tagnum: u32 = @intCast(u32, b0 & 0x1F);
    if (tagnum == 0x1F) {
        tagnum = 0;
        var groups: usize = 0;
        while (true) {
            if (r.pos >= r.data.len) return error.Corrupt;
            const tb: u8 = r.data[r.pos];
            r.pos += 1;
            if (groups >= 4) return error.Corrupt;
            if (groups == 0 and tb == 0x80) return error.Corrupt;
            tagnum = (tagnum << 7) | @intCast(u32, tb & 0x7F);
            groups += 1;
            if ((tb & 0x80) == 0) break;
        }
        if (tagnum < 31) return error.Corrupt;
    }

    if (r.pos >= r.data.len) return error.Corrupt;
    const lb: u8 = r.data[r.pos];
    r.pos += 1;
    var len: usize = 0;
    if (lb < 0x80) {
        len = @intCast(usize, lb);
    } else if (lb == 0x80) {
        return error.Corrupt;
    } else {
        const n: usize = @intCast(usize, lb & 0x7F);
        if (n == 0 or n > 4) return error.Corrupt;
        if (n > r.data.len - r.pos) return error.Corrupt;
        if (r.data[r.pos] == 0) return error.Corrupt;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            len = (len << 8) | @intCast(usize, r.data[r.pos + i]);
        }
        r.pos += n;
        if (len < 128) return error.Corrupt;
    }
    if (len > r.data.len - r.pos) return error.Corrupt;
    const content: []const u8 = r.data[r.pos .. r.pos + len];
    r.pos += len;
    if (cls == TagClass.universal and tagnum == 6) {
        if (!oidContentValid(content)) return error.Corrupt;
    }
    const full: []const u8 = r.data[start..r.pos];
    var t: Tlv = Tlv{
        .cls = cls,
        .constructed = constructed,
        .tag = tagnum,
        .data = content,
        .full = full,
    };
    return t;
}
