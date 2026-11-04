// std_deflate.zig — Z98 std lib L4: RFC 1950 zlib / RFC 1951 deflate inflater.
//
// Contract: single-shot inflation into the caller's `dst`; no heap and no
// buffer beyond `dst` (decode tables are function-local fixed arrays). Errors:
//   error.Corrupt       malformed/truncated/unsupported stream (FDICT too)
//   error.OutputTooSmall caller dst cannot hold the decoded content
//
// `used` reports every input byte consumed, wrapper bytes included, so a caller
// can resume at src[used..] for concatenated streams. `inflateRaw` reads RFC
// 1951 only; `inflateZlib` validates CMF/FLG/FCHECK, rejects FDICT and verifies
// Adler-32. `sf/src/std.zig` is intentionally not modified: L4 modules are
// imported by path.

const MAXBITS: usize = 15;
const TABLE_SIZE: usize = 32768;
const INVALID: u16 = 0xFFFF;

const LENGTH_BASE = [_]u16{
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17, 19, 23, 27, 31,
    35, 43, 51, 59, 67, 83, 99, 115,
    131, 163, 195, 227, 258,
};

const LENGTH_EXTRA = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4,
    5, 5, 5, 5, 0,
};

const DIST_BASE = [_]u16{
    1, 2, 3, 4, 5, 7, 9, 13,
    17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577,
};

const DIST_EXTRA = [_]u8{
    0, 0, 0, 0, 1, 1, 2, 2,
    3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10,
    11, 11, 12, 12, 13, 13,
};

const CL_ORDER = [_]u8{
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5,
    11, 4, 12, 3, 13, 2, 14, 1, 15,
};

const Huff = struct {
    table: [TABLE_SIZE]u16,
    maxbits: u8,
};

const Bits = struct {
    src: []const u8,
    pos: usize,
    buf: u32,
    cnt: u8,
};

fn bFill(br: *Bits, n: u8) void {
    while (br.cnt < n and br.pos < br.src.len) {
        br.buf |= @intCast(u32, br.src[br.pos]) << @intCast(u32, br.cnt);
        br.pos += 1;
        br.cnt += 8;
    }
}

fn bPeek(br: *Bits, n: u8) u32 {
    bFill(br, n);
    const mask: u32 = (@intCast(u32, 1) << @intCast(u32, n)) - 1;
    return br.buf & mask;
}

fn bDrop(br: *Bits, n: u8) void {
    if (n == 0) return;
    br.buf = br.buf >> @intCast(u32, n);
    br.cnt -= n;
}

fn bRead(br: *Bits, n: u8) !u32 {
    if (n == 0) return 0;
    bFill(br, n);
    if (br.cnt < n) return error.Corrupt;
    const mask: u32 = (@intCast(u32, 1) << @intCast(u32, n)) - 1;
    const v: u32 = br.buf & mask;
    br.buf = br.buf >> @intCast(u32, n);
    br.cnt -= n;
    return v;
}

fn bAlign(br: *Bits) void {
    bDrop(br, br.cnt % 8);
}

fn bUsed(br: *const Bits) usize {
    return br.pos - @intCast(usize, br.cnt / 8);
}

fn reverseCode(code: u32, len: u8) u32 {
    var v: u32 = code;
    var r: u32 = 0;
    var i: u8 = 0;
    while (i < len) : (i += 1) {
        r = (r << 1) | (v & 1);
        v = v >> 1;
    }
    return r;
}

fn buildHuff(h: *Huff, lens: []const u8, n: usize, allow_incomplete: bool) !void {
    var counts: [16]u16 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) counts[i] = 0;

    var max_len: u8 = 0;
    var nonzero: usize = 0;
    i = 0;
    while (i < n) : (i += 1) {
        const l: u8 = lens[i];
        if (l > 15) return error.Corrupt;
        if (l != 0) {
            counts[l] += 1;
            nonzero += 1;
            if (l > max_len) max_len = l;
        }
    }

    var left: i32 = 1;
    var bits: usize = 1;
    while (bits <= 15) : (bits += 1) {
        left = (left << 1) - @intCast(i32, counts[bits]);
        if (left < 0) return error.Corrupt;
    }
    if (left > 0) {
        if (!allow_incomplete) return error.Corrupt;
        if (nonzero != 0 and (max_len != 1 or nonzero > 1)) return error.Corrupt;
    }

    if (max_len == 0) {
        h.maxbits = 1;
    } else {
        h.maxbits = max_len;
    }
    const size: usize = @intCast(usize, 1) << @intCast(usize, h.maxbits);
    i = 0;
    while (i < size) : (i += 1) h.table[i] = INVALID;

    var next: [16]u32 = undefined;
    i = 0;
    while (i < 16) : (i += 1) next[i] = 0;

    var code: u32 = 0;
    bits = 1;
    while (bits <= 15) : (bits += 1) {
        code = (code + @intCast(u32, counts[bits - 1])) << 1;
        next[bits] = code;
    }

    i = 0;
    while (i < n) : (i += 1) {
        const l: u8 = lens[i];
        if (l == 0) continue;
        const c: u32 = next[l];
        next[l] += 1;
        const lim: u32 = @intCast(u32, 1) << @intCast(u32, l);
        if (c >= lim) return error.Corrupt;
        const rev: u32 = reverseCode(c, l);
        const entry: u16 = (@intCast(u16, l) << 9) | @intCast(u16, i);
        const step: usize = @intCast(usize, 1) << @intCast(usize, l);
        var idx: usize = @intCast(usize, rev);
        while (idx < size) : (idx += step) {
            h.table[idx] = entry;
        }
    }
}

fn decodeSym(br: *Bits, h: *const Huff) !u16 {
    const raw: u32 = bPeek(br, h.maxbits);
    const idx: usize = @intCast(usize, raw);
    const e: u16 = h.table[idx];
    if (e == INVALID) return error.Corrupt;
    const nb: u8 = @intCast(u8, e >> 9);
    if (nb > br.cnt) return error.Corrupt;
    bDrop(br, nb);
    return e & 0x01FF;
}

fn buildFixed(lit: *Huff, dist: *Huff) !void {
    var lit_lens: [288]u8 = undefined;
    var dist_lens: [32]u8 = undefined;

    var i: usize = 0;
    while (i < 144) : (i += 1) lit_lens[i] = 8;
    while (i < 256) : (i += 1) lit_lens[i] = 9;
    while (i < 280) : (i += 1) lit_lens[i] = 7;
    while (i < 288) : (i += 1) lit_lens[i] = 8;

    i = 0;
    while (i < 32) : (i += 1) dist_lens[i] = 5;

    try buildHuff(lit, lit_lens[0..], 288, false);
    try buildHuff(dist, dist_lens[0..], 32, false);
}

fn buildDynamic(br: *Bits, lit: *Huff, dist: *Huff) !void {
    const hlit: usize = @intCast(usize, try bRead(br, 5)) + 257;
    const hdist: usize = @intCast(usize, try bRead(br, 5)) + 1;
    const hclen: usize = @intCast(usize, try bRead(br, 4)) + 4;
    if (hlit > 286 or hdist > 30) return error.Corrupt;

    var cl_lens: [19]u8 = undefined;
    var i: usize = 0;
    while (i < 19) : (i += 1) cl_lens[i] = 0;

    i = 0;
    while (i < hclen) : (i += 1) {
        const slot: usize = @intCast(usize, CL_ORDER[i]);
        cl_lens[slot] = @intCast(u8, try bRead(br, 3));
    }

    var cl: Huff = undefined;
    try buildHuff(&cl, cl_lens[0..], 19, false);

    var all: [320]u8 = undefined;
    const total: usize = hlit + hdist;
    i = 0;
    while (i < total) {
        const sym: u16 = try decodeSym(br, &cl);
        if (sym < 16) {
            all[i] = @intCast(u8, sym);
            i += 1;
        } else if (sym == 16) {
            if (i == 0) return error.Corrupt;
            const prev: u8 = all[i - 1];
            const rep: usize = @intCast(usize, try bRead(br, 2)) + 3;
            if (rep > total - i) return error.Corrupt;
            var k: usize = 0;
            while (k < rep) : (k += 1) all[i + k] = prev;
            i += rep;
        } else if (sym == 17) {
            const rep: usize = @intCast(usize, try bRead(br, 3)) + 3;
            if (rep > total - i) return error.Corrupt;
            var k: usize = 0;
            while (k < rep) : (k += 1) all[i + k] = 0;
            i += rep;
        } else if (sym == 18) {
            const rep: usize = @intCast(usize, try bRead(br, 7)) + 11;
            if (rep > total - i) return error.Corrupt;
            var k: usize = 0;
            while (k < rep) : (k += 1) all[i + k] = 0;
            i += rep;
        } else {
            return error.Corrupt;
        }
    }

    if (all[256] == 0) return error.Corrupt;
    try buildHuff(lit, all[0..hlit], hlit, true);
    try buildHuff(dist, all[hlit..total], hdist, true);
}

fn decodeBlock(br: *Bits, lit: *const Huff, dist: *const Huff,
               dst: []u8, op: *usize) !void {
    while (true) {
        const sym: usize = @intCast(usize, try decodeSym(br, lit));
        if (sym < 256) {
            if (op.* >= dst.len) return error.OutputTooSmall;
            dst[op.*] = @intCast(u8, sym);
            op.* += 1;
        } else if (sym == 256) {
            return;
        } else if (sym <= 285) {
            const li: usize = sym - 257;
            const len: usize = @intCast(usize, LENGTH_BASE[li]) +
                @intCast(usize, try bRead(br, LENGTH_EXTRA[li]));
            const dsym: u16 = try decodeSym(br, dist);
            if (dsym > 29) return error.Corrupt;
            const di: usize = @intCast(usize, dsym);
            const distance: usize = @intCast(usize, DIST_BASE[di]) +
                @intCast(usize, try bRead(br, DIST_EXTRA[di]));
            if (distance == 0 or distance > op.*) return error.Corrupt;
            if (len > dst.len - op.*) return error.OutputTooSmall;
            var k: usize = 0;
            while (k < len) : (k += 1) {
                dst[op.* + k] = dst[op.* - distance + k];
            }
            op.* += len;
        } else {
            return error.Corrupt;
        }
    }
}

fn inflateStream(br: *Bits, dst: []u8, op: *usize) !void {
    var final: bool = false;
    while (!final) {
        final = (try bRead(br, 1)) != 0;
        const btype: u32 = try bRead(br, 2);
        if (btype == 0) {
            bAlign(br);
            const blen: u32 = try bRead(br, 16);
            const nlen: u32 = try bRead(br, 16);
            if ((blen ^ nlen) != 0xFFFF) return error.Corrupt;
            const len: usize = @intCast(usize, blen);
            if (len > dst.len - op.*) return error.OutputTooSmall;
            var i: usize = 0;
            while (i < len) : (i += 1) {
                dst[op.* + i] = @intCast(u8, try bRead(br, 8));
            }
            op.* += len;
        } else if (btype == 1 or btype == 2) {
            var lit: Huff = undefined;
            var dist: Huff = undefined;
            if (btype == 1) {
                try buildFixed(&lit, &dist);
            } else {
                try buildDynamic(br, &lit, &dist);
            }
            try decodeBlock(br, &lit, &dist, dst, op);
        } else {
            return error.Corrupt;
        }
    }
}

fn adler32(data: []const u8) u32 {
    var s1: u32 = 1;
    var s2: u32 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        s1 = (s1 + @intCast(u32, data[i])) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
}

pub fn inflateRaw(src: []const u8, dst: []u8, used: *usize) !u32 {
    var br: Bits = undefined;
    br.src = src;
    br.pos = 0;
    br.buf = 0;
    br.cnt = 0;
    var op: usize = 0;
    try inflateStream(&br, dst, &op);
    used.* = bUsed(&br);
    return @intCast(u32, op);
}

pub fn inflateZlib(src: []const u8, dst: []u8, used: *usize) !u32 {
    if (src.len < 6) return error.Corrupt;
    const cmf: u8 = src[0];
    const flg: u8 = src[1];
    if ((cmf & 0x0F) != 8) return error.Corrupt;
    if ((cmf >> 4) > 7) return error.Corrupt;
    const hdr: u32 = @intCast(u32, cmf) * 256 + @intCast(u32, flg);
    if (hdr % 31 != 0) return error.Corrupt;
    if ((flg & 0x20) != 0) return error.Corrupt;

    var br: Bits = undefined;
    br.src = src[2..];
    br.pos = 0;
    br.buf = 0;
    br.cnt = 0;
    var op: usize = 0;
    try inflateStream(&br, dst, &op);

    const deflate_used: usize = bUsed(&br);
    const apos: usize = 2 + deflate_used;
    if (apos > src.len) return error.Corrupt;
    if (src.len - apos < 4) return error.Corrupt;
    const want: u32 = adler32(dst[0..op]);
    var got: u32 = @intCast(u32, src[apos]) << 24;
    got |= @intCast(u32, src[apos + 1]) << 16;
    got |= @intCast(u32, src[apos + 2]) << 8;
    got |= @intCast(u32, src[apos + 3]);
    if (got != want) return error.Corrupt;

    used.* = apos + 4;
    return @intCast(u32, op);
}
