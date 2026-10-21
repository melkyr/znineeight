// std_zstd.zig — Z98 std lib L4: RFC 8878 zstd frame decoder (subset).
//
// Contract (design spec §6.4): single-shot decompression into the caller's
// `dst`; history is `dst[0..written]`; no heap and no buffer beyond `dst`
// (entropy tables are function-local). Errors are exactly:
//   error.Corrupt       malformed/truncated/unsupported frame data
//   error.OutputTooSmall caller dst cannot hold the decoded content
//   error.WindowTooBig  frame window_log exceeds the caller cap
//
// Supported subset: standard frames (raw/RLE/compressed blocks), predefined,
// RLE and FSE-compressed Huffman/FSE tables, repeat modes, skippable frames.
// Dictionaries are not supported (a nonzero dictionary id is Corrupt).
//
// The decoder has no dependencies beyond L0-L2 (only types and arithmetic).
// `sf/src/std.zig` is intentionally not modified: L4 modules are imported by
// path.

pub const ZSTD_DEFAULT_WINDOW_LOG: u8 = 21;

const MAGIC: u32 = 0xFD2FB528;
const SKIPPABLE_MAGIC: u32 = 0x184D2A50;
const BLOCK_MAX: usize = 131072;

const LL_MAX: usize = 35;
const ML_MAX: usize = 52;
const OF_MAX: usize = 31;
const LL_FSE_LOG: u8 = 9;
const ML_FSE_LOG: u8 = 9;
const OF_FSE_LOG: u8 = 8;

const LL_BASE = [_]u32{
    0, 1, 2, 3, 4, 5, 6, 7,
    8, 9, 10, 11, 12, 13, 14, 15,
    16, 18, 20, 22, 24, 28, 32, 40,
    48, 64, 128, 256, 512, 1024, 2048, 4096,
    8192, 16384, 32768, 65536,
};

const LL_BITS = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3,
    4, 6, 7, 8, 9, 10, 11, 12,
    13, 14, 15, 16,
};

const ML_BASE = [_]u32{
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 26,
    27, 28, 29, 30, 31, 32, 33, 34,
    35, 37, 39, 41, 43, 47, 51, 59,
    67, 83, 99, 131, 259, 515, 1027, 2051,
    4099, 8195, 16387, 32771, 65539,
};

const ML_BITS = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3,
    4, 4, 5, 7, 8, 9, 10, 11,
    12, 13, 14, 15, 16,
};

const LL_DEFAULT = [_]i16{
    4, 3, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 3, 2, 1, 1, 1, 1, 1,
    -1, -1, -1, -1,
};

const ML_DEFAULT = [_]i16{
    1, 4, 3, 2, 2, 2, 2, 2,
    2, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, -1, -1,
    -1, -1, -1, -1, -1,
};

const OF_DEFAULT = [_]i16{
    1, 1, 1, 1, 1, 1, 2, 2,
    2, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    -1, -1, -1, -1, -1,
};

const FseEntry = struct {
    symbol: u8,
    nbits: u8,
    baseline: u16,
};

const FseTable = struct {
    entries: [512]FseEntry,
    log: u8,
    valid: bool,
};

const Decoder = struct {
    huf_symbols: [2048]u8,
    huf_nbits: [2048]u8,
    huf_log: u8,
    huf_valid: bool,
    ll: FseTable,
    of: FseTable,
    ml: FseTable,
    rep: [3]usize,
};

const RevBits = struct {
    data: []const u8,
    total: usize,
    pos: usize,
    last_bit: u8,
};

const FwdBits = struct {
    data: []const u8,
    bitpos: usize,
};

const LitReader = struct {
    kind: u8,
    data: []const u8,
    raw_pos: usize,
    rle_val: u8,
    lit_size: usize,
    used: usize,
    br: RevBits,
    stream_off: [4]usize,
    stream_len: [4]usize,
    stream_seg: [4]usize,
    stream_count: u8,
    stream_idx: u8,
    stream_rem: usize,
    stream_started: bool,
};

fn le16(s: []const u8, p: usize) u16 {
    return @intCast(u16, s[p]) | (@intCast(u16, s[p + 1]) << 8);
}

fn le24(s: []const u8, p: usize) u32 {
    return @intCast(u32, s[p]) |
        (@intCast(u32, s[p + 1]) << 8) |
        (@intCast(u32, s[p + 2]) << 16);
}

fn le32(s: []const u8, p: usize) u32 {
    return @intCast(u32, s[p]) |
        (@intCast(u32, s[p + 1]) << 8) |
        (@intCast(u32, s[p + 2]) << 16) |
        (@intCast(u32, s[p + 3]) << 24);
}

fn le64(s: []const u8, p: usize) u64 {
    var v: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        v |= @intCast(u64, s[p + i]) << @intCast(u64, i * 8);
    }
    return v;
}

fn highbit32(x: u32) u8 {
    var v: u32 = x;
    var n: u8 = 0;
    while (v > 1) {
        v = v >> 1;
        n += 1;
    }
    return n;
}

fn revInit(data: []const u8) !RevBits {
    if (data.len == 0) return error.Corrupt;
    const last: u8 = data[data.len - 1];
    if (last == 0) return error.Corrupt;
    const lv: u32 = @intCast(u32, last);
    var hb: u8 = 0;
    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        const mask: u32 = @intCast(u32, 1) << @intCast(u32, i);
        if ((lv & mask) != 0) hb = i;
    }
    return RevBits{
        .data = data,
        .total = (data.len - 1) * 8 + @intCast(usize, hb),
        .pos = 0,
        .last_bit = hb,
    };
}

fn revBit(br: *const RevBits, k: usize) u32 {
    const lb: usize = @intCast(usize, br.last_bit);
    var byte: u8 = 0;
    var bp: usize = 0;
    if (k < lb) {
        byte = br.data[br.data.len - 1];
        bp = lb - 1 - k;
    } else {
        const k2: usize = k - lb;
        byte = br.data[br.data.len - 2 - k2 / 8];
        bp = 7 - k2 % 8;
    }
    const bv: u32 = @intCast(u32, byte);
    return (bv >> @intCast(u32, bp)) & 1;
}

fn revPeek(br: *const RevBits, n: usize) u32 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var bit: u32 = 0;
        if (br.pos + i < br.total) bit = revBit(br, br.pos + i);
        v = (v << 1) | bit;
    }
    return v;
}

fn revRead(br: *RevBits, n: usize) !u32 {
    if (n == 0) return 0;
    if (br.pos + n > br.total) return error.Corrupt;
    const v = revPeek(br, n);
    br.pos += n;
    return v;
}

fn revAdvance(br: *RevBits, n: usize) !void {
    if (br.pos + n > br.total) return error.Corrupt;
    br.pos += n;
}

fn revReadPad(br: *RevBits, n: usize) u32 {
    const v = revPeek(br, n);
    br.pos += n;
    return v;
}

fn fwdPeek(br: *const FwdBits, n: usize) u32 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const k: usize = br.bitpos + i;
        var bit: u32 = 0;
        if (k < br.data.len * 8) {
            const byte: u8 = br.data[k / 8];
            bit = (@intCast(u32, byte) >> @intCast(u32, k % 8)) & 1;
        }
        v |= bit << @intCast(u32, i);
    }
    return v;
}

fn fwdRead(br: *FwdBits, n: usize) !u32 {
    if (br.bitpos + n > br.data.len * 8) return error.Corrupt;
    const v = fwdPeek(br, n);
    br.bitpos += n;
    return v;
}

fn fwdSkip(br: *FwdBits, n: usize) !void {
    if (br.bitpos + n > br.data.len * 8) return error.Corrupt;
    br.bitpos += n;
}

fn buildFse(t: *FseTable, norm: *const [256]i16, max_symbol: usize, table_log: u8) !void {
    if (table_log == 0 or table_log > 9) return error.Corrupt;
    var table_size: usize = 1;
    var z: u8 = 0;
    while (z < table_log) : (z += 1) table_size *= 2;

    var symbol_next: [256]u16 = undefined;
    var high: usize = table_size - 1;
    var s: usize = 0;
    while (s <= max_symbol) : (s += 1) {
        if (norm[s] == -1) {
            t.entries[high].symbol = @intCast(u8, s);
            high -= 1;
            symbol_next[s] = 1;
        } else {
            symbol_next[s] = @intCast(u16, norm[s]);
        }
    }

    const step: usize = (table_size >> 1) + (table_size >> 3) + 3;
    var position: usize = 0;
    s = 0;
    while (s <= max_symbol) : (s += 1) {
        const n: i16 = norm[s];
        if (n > 0) {
            var c: i16 = 0;
            while (c < n) : (c += 1) {
                t.entries[position].symbol = @intCast(u8, s);
                position = (position + step) & (table_size - 1);
                while (position > high) {
                    position = (position + step) & (table_size - 1);
                }
            }
        }
    }
    if (position != 0) return error.Corrupt;

    var u: usize = 0;
    while (u < table_size) : (u += 1) {
        const sym: u8 = t.entries[u].symbol;
        const next: u32 = @intCast(u32, symbol_next[sym]);
        symbol_next[sym] += 1;
        const nb: u8 = table_log - highbit32(next);
        const shifted: u32 = next << @intCast(u32, nb);
        t.entries[u].nbits = nb;
        t.entries[u].baseline = @intCast(u16, shifted - @intCast(u32, table_size));
    }
    t.log = table_log;
    t.valid = true;
}

fn setRleTable(t: *FseTable, symbol: u8) void {
    t.entries[0].symbol = symbol;
    t.entries[0].nbits = 0;
    t.entries[0].baseline = 0;
    t.log = 0;
    t.valid = true;
}

fn readNCount(data: []const u8, max_symbol: usize, max_log: u8,
              norm: *[256]i16, table_log: *u8) !usize {
    var br = FwdBits{ .data = data, .bitpos = 0 };
    var i: usize = 0;
    while (i < 256) : (i += 1) norm[i] = 0;

    const lo4 = try fwdRead(&br, 4);
    var nb_bits: i32 = @intCast(i32, lo4) + 5;
    if (nb_bits < 5 or nb_bits > @intCast(i32, max_log)) return error.Corrupt;
    table_log.* = @intCast(u8, nb_bits);

    var remaining: i32 = @intCast(i32, (@intCast(u32, 1) << @intCast(u32, nb_bits)) + 1);
    var threshold: i32 = @intCast(i32, @intCast(u32, 1) << @intCast(u32, nb_bits));
    nb_bits += 1;
    var charnum: usize = 0;
    var previous0: bool = false;

    while (true) {
        if (previous0) {
            var n0: usize = charnum;
            while (true) {
                const rep = try fwdRead(&br, 2);
                if (rep == 3) {
                    n0 += 3;
                } else {
                    n0 += @intCast(usize, rep);
                    break;
                }
            }
            if (n0 > max_symbol + 1) return error.Corrupt;
            while (charnum < n0) : (charnum += 1) norm[charnum] = 0;
        }

        const maxv: i32 = (2 * threshold - 1) - remaining;
        const peek = fwdPeek(&br, @intCast(usize, nb_bits));
        var count: i32 = 0;
        if ((peek & @intCast(u32, threshold - 1)) < @intCast(u32, maxv)) {
            count = @intCast(i32, peek & @intCast(u32, threshold - 1));
            try fwdSkip(&br, @intCast(usize, nb_bits - 1));
        } else {
            count = @intCast(i32, peek & @intCast(u32, 2 * threshold - 1));
            if (count >= threshold) count -= maxv;
            try fwdSkip(&br, @intCast(usize, nb_bits));
        }
        count -= 1;
        if (count < 0) {
            remaining -= 1;
        } else {
            remaining -= count;
        }
        if (charnum > max_symbol) return error.Corrupt;
        norm[charnum] = @intCast(i16, count);
        charnum += 1;
        previous0 = count == 0;

        if (remaining < threshold) {
            if (remaining <= 1) break;
            nb_bits = @intCast(i32, highbit32(@intCast(u32, remaining))) + 1;
            threshold = @intCast(i32, @intCast(u32, 1) << @intCast(u32, nb_bits - 1));
        }
        if (charnum >= max_symbol + 1) break;
    }

    if (remaining != 1) return error.Corrupt;
    return (br.bitpos + 7) / 8;
}

fn loadDefault(t: *FseTable, which: u8) !void {
    var norm: [256]i16 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) norm[i] = 0;
    if (which == 0) {
        i = 0;
        while (i < LL_DEFAULT.len) : (i += 1) norm[i] = LL_DEFAULT[i];
        try buildFse(t, &norm, LL_MAX, 6);
    } else if (which == 1) {
        i = 0;
        while (i < OF_DEFAULT.len) : (i += 1) norm[i] = OF_DEFAULT[i];
        try buildFse(t, &norm, OF_MAX, 5);
    } else {
        i = 0;
        while (i < ML_DEFAULT.len) : (i += 1) norm[i] = ML_DEFAULT[i];
        try buildFse(t, &norm, ML_MAX, 6);
    }
}

fn decodeFseTwoState(out: []u8, t: *const FseTable, stream: []const u8) !usize {
    var br = try revInit(stream);
    var s1: u32 = 0;
    var s2: u32 = 0;
    if (t.log > 0) {
        s1 = try revRead(&br, @intCast(usize, t.log));
        s2 = try revRead(&br, @intCast(usize, t.log));
    }
    var n: usize = 0;
    var turn: u8 = 0;
    while (true) {
        if (turn == 0) {
            const e = t.entries[s1];
            if (n >= out.len) return error.Corrupt;
            out[n] = e.symbol;
            n += 1;
            if (br.pos + @intCast(usize, e.nbits) > br.total) {
                if (n >= out.len) return error.Corrupt;
                out[n] = t.entries[s2].symbol;
                n += 1;
                break;
            }
            const low = try revRead(&br, @intCast(usize, e.nbits));
            s1 = @intCast(u32, e.baseline) + low;
            turn = 1;
        } else {
            const e = t.entries[s2];
            if (n >= out.len) return error.Corrupt;
            out[n] = e.symbol;
            n += 1;
            if (br.pos + @intCast(usize, e.nbits) > br.total) {
                if (n >= out.len) return error.Corrupt;
                out[n] = t.entries[s1].symbol;
                n += 1;
                break;
            }
            const low = try revRead(&br, @intCast(usize, e.nbits));
            s2 = @intCast(u32, e.baseline) + low;
            turn = 0;
        }
    }
    return n;
}

fn huffmanReadTree(st: *Decoder, data: []const u8) !usize {
    if (data.len == 0) return error.Corrupt;
    var weights: [256]u8 = undefined;
    const header: u8 = data[0];
    var o_size: usize = 0;
    var consumed: usize = 0;

    if (header >= 128) {
        o_size = @intCast(usize, @intCast(u32, header) - 127);
        const nbytes: usize = (o_size + 1) / 2;
        if (1 + nbytes > data.len) return error.Corrupt;
        if (o_size >= 256) return error.Corrupt;
        var n: usize = 0;
        while (n < o_size) : (n += 2) {
            const b: u8 = data[1 + n / 2];
            weights[n] = b >> 4;
            weights[n + 1] = b & 15;
        }
        consumed = 1 + nbytes;
    } else {
        const csize: usize = @intCast(usize, header);
        if (csize == 0 or 1 + csize > data.len) return error.Corrupt;
        const series = data[1 .. 1 + csize];
        var norm: [256]i16 = undefined;
        var table_log: u8 = 0;
        const nc = try readNCount(series, 255, 6, &norm, &table_log);
        if (nc >= series.len) return error.Corrupt;
        var wt: FseTable = undefined;
        try buildFse(&wt, &norm, 255, table_log);
        o_size = try decodeFseTwoState(weights[0..255], &wt, series[nc..]);
        consumed = 1 + csize;
    }

    if (o_size == 0 or o_size >= 256) return error.Corrupt;
    var rank: [12]u32 = undefined;
    var w: usize = 0;
    while (w < 12) : (w += 1) rank[w] = 0;
    var weight_total: u32 = 0;
    var n: usize = 0;
    while (n < o_size) : (n += 1) {
        const ww: u8 = weights[n];
        if (ww > 11) return error.Corrupt;
        rank[ww] += 1;
        if (ww > 0) weight_total += @intCast(u32, 1) << @intCast(u32, ww - 1);
    }
    if (weight_total == 0) return error.Corrupt;

    const table_log: u8 = highbit32(weight_total) + 1;
    if (table_log > 11) return error.Corrupt;
    const total: u32 = @intCast(u32, 1) << @intCast(u32, table_log);
    if (weight_total >= total) return error.Corrupt;
    const rest: u32 = total - weight_total;
    const rest_hb: u8 = highbit32(rest);
    if ((@intCast(u32, 1) << @intCast(u32, rest_hb)) != rest) return error.Corrupt;
    const last_weight: u8 = rest_hb + 1;
    if (last_weight > 11) return error.Corrupt;
    weights[o_size] = last_weight;
    rank[last_weight] += 1;
    const nb_symbols: usize = o_size + 1;

    if (rank[1] < 2 or (rank[1] & 1) != 0) return error.Corrupt;

    var rank_start: [12]u32 = undefined;
    var cursor: [12]u32 = undefined;
    var next_start: u32 = 0;
    w = 0;
    while (w < 12) : (w += 1) {
        rank_start[w] = next_start;
        cursor[w] = next_start;
        next_start += rank[w];
    }

    var symbols: [256]u8 = undefined;
    n = 0;
    while (n < nb_symbols) : (n += 1) {
        const ww: u8 = weights[n];
        symbols[cursor[ww]] = @intCast(u8, n);
        cursor[ww] += 1;
    }

    var table_pos: usize = 0;
    var sym_pos: usize = @intCast(usize, rank[0]);
    w = 1;
    while (w <= @intCast(usize, table_log)) : (w += 1) {
        const cnt: usize = @intCast(usize, rank[w]);
        const length: usize = @intCast(usize, @intCast(u32, 1) << @intCast(u32, w - 1));
        const nb: u8 = table_log + 1 - @intCast(u8, w);
        var si: usize = 0;
        while (si < cnt) : (si += 1) {
            const sym: u8 = symbols[sym_pos];
            sym_pos += 1;
            var j: usize = 0;
            while (j < length) : (j += 1) {
                if (table_pos >= 2048) return error.Corrupt;
                st.huf_symbols[table_pos] = sym;
                st.huf_nbits[table_pos] = nb;
                table_pos += 1;
            }
        }
    }
    if (table_pos != (@intCast(usize, 1) << @intCast(u32, table_log))) return error.Corrupt;

    st.huf_log = table_log;
    st.huf_valid = true;
    return consumed;
}

fn litSetRaw(lr: *LitReader, data: []const u8, size: usize) void {
    lr.kind = 0;
    lr.data = data;
    lr.raw_pos = 0;
    lr.lit_size = size;
    lr.used = 0;
}

fn litSetRle(lr: *LitReader, value: u8, size: usize) void {
    lr.kind = 1;
    lr.rle_val = value;
    lr.lit_size = size;
    lr.used = 0;
}

fn litSetHuff(lr: *LitReader, data: []const u8, off0: usize, len0: usize,
              off1: usize, len1: usize, off2: usize, len2: usize,
              off3: usize, len3: usize, seg0: usize, seg1: usize,
              seg2: usize, seg3: usize, count: u8, size: usize) void {
    lr.kind = 2;
    lr.data = data;
    lr.lit_size = size;
    lr.used = 0;
    lr.stream_off[0] = off0;
    lr.stream_off[1] = off1;
    lr.stream_off[2] = off2;
    lr.stream_off[3] = off3;
    lr.stream_len[0] = len0;
    lr.stream_len[1] = len1;
    lr.stream_len[2] = len2;
    lr.stream_len[3] = len3;
    lr.stream_seg[0] = seg0;
    lr.stream_seg[1] = seg1;
    lr.stream_seg[2] = seg2;
    lr.stream_seg[3] = seg3;
    lr.stream_count = count;
    lr.stream_idx = 0;
    lr.stream_rem = 0;
    lr.stream_started = false;
}

fn litNext(st: *const Decoder, lr: *LitReader) !u8 {
    if (lr.used >= lr.lit_size) return error.Corrupt;
    if (lr.kind == 0) {
        const b: u8 = lr.data[lr.raw_pos];
        lr.raw_pos += 1;
        lr.used += 1;
        return b;
    }
    if (lr.kind == 1) {
        lr.used += 1;
        return lr.rle_val;
    }

    while (!lr.stream_started) {
        if (lr.stream_idx >= lr.stream_count) return error.Corrupt;
        const idx: usize = @intCast(usize, lr.stream_idx);
        const off: usize = lr.stream_off[idx];
        const len: usize = lr.stream_len[idx];
        if (off + len > lr.data.len) return error.Corrupt;
        lr.br = try revInit(lr.data[off .. off + len]);
        lr.stream_rem = lr.stream_seg[idx];
        lr.stream_started = true;
        if (lr.stream_rem == 0) {
            if (lr.br.pos != lr.br.total) return error.Corrupt;
            lr.stream_started = false;
            lr.stream_idx += 1;
        }
    }

    if (!st.huf_valid) return error.Corrupt;
    const idx = revPeek(&lr.br, @intCast(usize, st.huf_log));
    const sym: u8 = st.huf_symbols[idx];
    const nb: u8 = st.huf_nbits[idx];
    if (nb == 0) return error.Corrupt;
    try revAdvance(&lr.br, @intCast(usize, nb));
    lr.used += 1;
    lr.stream_rem -= 1;
    if (lr.stream_rem == 0) {
        if (lr.br.pos != lr.br.total) return error.Corrupt;
        lr.stream_started = false;
        lr.stream_idx += 1;
    }
    return sym;
}

fn setupLiterals(st: *Decoder, src: []const u8, pos: *usize, block_end: usize,
                  lr: *LitReader) !usize {
    if (pos.* >= block_end) return error.Corrupt;
    const first: u8 = src[pos.*];
    const lit_type: u8 = first & 3;
    const sf: u8 = (first >> 2) & 3;

    if (lit_type == 0 or lit_type == 1) {
        var hdr: usize = 0;
        var size: usize = 0;
        if (sf == 0 or sf == 2) {
            hdr = 1;
            size = @intCast(usize, first >> 3);
        } else if (sf == 1) {
            hdr = 2;
            if (pos.* + hdr > block_end) return error.Corrupt;
            size = @intCast(usize, le16(src, pos.*) >> 4);
        } else {
            hdr = 3;
            if (pos.* + hdr > block_end) return error.Corrupt;
            size = @intCast(usize, le24(src, pos.*) >> 4);
        }
        if (size > BLOCK_MAX) return error.Corrupt;
        if (lit_type == 0) {
            if (pos.* + hdr + size > block_end) return error.Corrupt;
            litSetRaw(lr, src[pos.* + hdr .. pos.* + hdr + size], size);
            pos.* += hdr + size;
        } else {
            if (pos.* + hdr + 1 > block_end) return error.Corrupt;
            litSetRle(lr, src[pos.* + hdr], size);
            pos.* += hdr + 1;
        }
        return size;
    }

    var lh: usize = 0;
    var lit_size: usize = 0;
    var lit_csize: usize = 0;
    var single: bool = false;
    var lhc: u32 = 0;
    if (pos.* + 3 > block_end) return error.Corrupt;
    lhc = @intCast(u32, src[pos.*]) |
        (@intCast(u32, src[pos.* + 1]) << 8) |
        (@intCast(u32, src[pos.* + 2]) << 16);

    if (sf == 0 or sf == 1) {
        lh = 3;
        single = sf == 0;
        lit_size = @intCast(usize, (lhc >> 4) & 0x3FF);
        lit_csize = @intCast(usize, (lhc >> 14) & 0x3FF);
    } else if (sf == 2) {
        lh = 4;
        if (pos.* + lh > block_end) return error.Corrupt;
        lhc |= @intCast(u32, src[pos.* + 3]) << 24;
        lit_size = @intCast(usize, (lhc >> 4) & 0x3FFF);
        lit_csize = @intCast(usize, lhc >> 18);
    } else {
        lh = 5;
        if (pos.* + lh > block_end) return error.Corrupt;
        lhc |= @intCast(u32, src[pos.* + 3]) << 24;
        lit_size = @intCast(usize, (lhc >> 4) & 0x3FFFF);
        lit_csize = @intCast(usize, (lhc >> 22)) +
            (@intCast(usize, src[pos.* + 4]) << 10);
    }
    if (lit_size > BLOCK_MAX or lit_csize > BLOCK_MAX) return error.Corrupt;
    if (pos.* + lh + lit_csize > block_end) return error.Corrupt;

    const content_start: usize = pos.* + lh;
    const content_end: usize = content_start + lit_csize;
    var tree_bytes: usize = 0;
    if (lit_type == 2) {
        tree_bytes = try huffmanReadTree(st, src[content_start..content_end]);
    } else if (!st.huf_valid) {
        return error.Corrupt;
    }
    if (tree_bytes > lit_csize) return error.Corrupt;
    const streams_size: usize = lit_csize - tree_bytes;

    if (single) {
        if (streams_size == 0) return error.Corrupt;
        const off: usize = content_start + tree_bytes;
        litSetHuff(lr, src, off, streams_size, 0, 0, 0, 0, 0, 0,
                   lit_size, 0, 0, 0, 1, lit_size);
    } else {
        if (lit_size < 6) return error.Corrupt;
        if (streams_size < 6) return error.Corrupt;
        const jt: usize = content_start + tree_bytes;
        const s1: usize = @intCast(usize, le16(src, jt));
        const s2: usize = @intCast(usize, le16(src, jt + 2));
        const s3: usize = @intCast(usize, le16(src, jt + 4));
        const body: usize = streams_size - 6;
        if (s1 + s2 + s3 > body) return error.Corrupt;
        const s4: usize = body - s1 - s2 - s3;
        const seg: usize = (lit_size + 3) / 4;
        if (seg * 3 > lit_size) return error.Corrupt;
        const last: usize = lit_size - seg * 3;
        const base: usize = jt + 6;
        litSetHuff(lr, src, base, s1, base + s1, s2, base + s1 + s2, s3,
                   base + s1 + s2 + s3, s4, seg, seg, seg, last, 4, lit_size);
    }
    pos.* = content_end;
    return lit_size;
}

fn resolveOffset(rep: *[3]usize, offset_value: usize, lit_len: usize) !usize {
    if (offset_value > 3) {
        const off: usize = offset_value - 3;
        if (off == 0) return error.Corrupt;
        rep[2] = rep[1];
        rep[1] = rep[0];
        rep[0] = off;
        return off;
    }
    var code: usize = offset_value;
    if (lit_len == 0) code += 1;
    if (code == 1) {
        return rep[0];
    } else if (code == 2) {
        const off: usize = rep[1];
        rep[1] = rep[0];
        rep[0] = off;
        return off;
    } else if (code == 3) {
        const off: usize = rep[2];
        rep[2] = rep[1];
        rep[1] = rep[0];
        rep[0] = off;
        return off;
    } else {
        const off: usize = rep[0] - 1;
        if (off == 0) return error.Corrupt;
        rep[2] = rep[1];
        rep[1] = rep[0];
        rep[0] = off;
        return off;
    }
}

fn applySeqTable(t: *FseTable, which: u8, mode: u8, src: []const u8,
                 pos: *usize, block_end: usize) !void {
    if (mode == 0) {
        try loadDefault(t, which);
    } else if (mode == 1) {
        if (pos.* >= block_end) return error.Corrupt;
        const sym: u8 = src[pos.*];
        pos.* += 1;
        if (which == 0) {
            if (@intCast(usize, sym) > LL_MAX) return error.Corrupt;
        } else if (which == 1) {
            if (@intCast(usize, sym) > OF_MAX) return error.Corrupt;
        } else {
            if (@intCast(usize, sym) > ML_MAX) return error.Corrupt;
        }
        setRleTable(t, sym);
    } else if (mode == 2) {
        if (pos.* >= block_end) return error.Corrupt;
        var norm: [256]i16 = undefined;
        var table_log: u8 = 0;
        var max_sym: usize = LL_MAX;
        var max_log: u8 = LL_FSE_LOG;
        if (which == 1) {
            max_sym = OF_MAX;
            max_log = OF_FSE_LOG;
        } else if (which == 2) {
            max_sym = ML_MAX;
            max_log = ML_FSE_LOG;
        }
        const used = try readNCount(src[pos.*..block_end], max_sym, max_log, &norm, &table_log);
        if (used > block_end - pos.*) return error.Corrupt;
        pos.* += used;
        try buildFse(t, &norm, max_sym, table_log);
    } else {
        if (!t.valid) return error.Corrupt;
    }
}

fn setupSequences(st: *Decoder, src: []const u8, pos: *usize,
                  block_end: usize) !u32 {
    if (pos.* >= block_end) return error.Corrupt;
    const b0: u8 = src[pos.*];
    pos.* += 1;
    var nb: u32 = 0;
    if (b0 == 0) {
        if (pos.* != block_end) return error.Corrupt;
        return 0;
    } else if (b0 < 128) {
        nb = @intCast(u32, b0);
    } else if (b0 < 255) {
        if (pos.* >= block_end) return error.Corrupt;
        nb = (@intCast(u32, b0) - 128) * 256 + @intCast(u32, src[pos.*]);
        pos.* += 1;
    } else {
        if (pos.* + 2 > block_end) return error.Corrupt;
        nb = @intCast(u32, le16(src, pos.*)) + 0x7F00;
        pos.* += 2;
    }

    if (pos.* >= block_end) return error.Corrupt;
    const modes: u8 = src[pos.*];
    pos.* += 1;
    if ((modes & 3) != 0) return error.Corrupt;
    const ll_mode: u8 = (modes >> 6) & 3;
    const of_mode: u8 = (modes >> 4) & 3;
    const ml_mode: u8 = (modes >> 2) & 3;

    try applySeqTable(&st.ll, 0, ll_mode, src, pos, block_end);
    try applySeqTable(&st.of, 1, of_mode, src, pos, block_end);
    try applySeqTable(&st.ml, 2, ml_mode, src, pos, block_end);
    return nb;
}

fn copyLiterals(st: *const Decoder, lr: *LitReader, dst: []u8,
                op: *usize, n: usize) !void {
    if (lr.used + n > lr.lit_size) return error.Corrupt;
    if (op.* + n > dst.len) return error.OutputTooSmall;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[op.* + i] = try litNext(st, lr);
    }
    op.* += n;
}

fn decodeCompressedBlock(st: *Decoder, src: []const u8, pos: *usize,
                         block_end: usize, dst: []u8, written: *usize,
                         window_size: u64, block_max: usize) !void {
    const block_start: usize = written.*;
    var lr: LitReader = undefined;
    const lit_size = try setupLiterals(st, src, pos, block_end, &lr);
    const nb_seq = try setupSequences(st, src, pos, block_end);

    if (nb_seq == 0) {
        try copyLiterals(st, &lr, dst, written, lit_size);
    } else {
        const stream = src[pos.*..block_end];
        var br = try revInit(stream);
        var ll_state: u32 = 0;
        var of_state: u32 = 0;
        var ml_state: u32 = 0;
        if (st.ll.log > 0) ll_state = try revRead(&br, @intCast(usize, st.ll.log));
        if (st.of.log > 0) of_state = try revRead(&br, @intCast(usize, st.of.log));
        if (st.ml.log > 0) ml_state = try revRead(&br, @intCast(usize, st.ml.log));

        var si: u32 = 0;
        while (si < nb_seq) : (si += 1) {
            const ll_e = st.ll.entries[ll_state];
            const of_e = st.of.entries[of_state];
            const ml_e = st.ml.entries[ml_state];
            const ll_code: usize = @intCast(usize, ll_e.symbol);
            const of_code: usize = @intCast(usize, of_e.symbol);
            const ml_code: usize = @intCast(usize, ml_e.symbol);
            if (ll_code > LL_MAX or of_code > OF_MAX or ml_code > ML_MAX) {
                return error.Corrupt;
            }

            var offset_value: u64 = 1;
            if (of_code > 0) {
                const extra = try revRead(&br, of_code);
                offset_value = (@intCast(u64, 1) << @intCast(u64, of_code)) +
                    @intCast(u64, extra);
            }
            const match_len: usize = @intCast(usize,
                ML_BASE[ml_code] + try revRead(&br, @intCast(usize, ML_BITS[ml_code])));
            const lit_len: usize = @intCast(usize,
                LL_BASE[ll_code] + try revRead(&br, @intCast(usize, LL_BITS[ll_code])));

            if (lit_len > lr.lit_size - lr.used) return error.Corrupt;
            try copyLiterals(st, &lr, dst, written, lit_len);

            const offset: usize = try resolveOffset(&st.rep, @intCast(usize, offset_value), lit_len);
            if (offset == 0 or offset > written.*) return error.Corrupt;
            if (@intCast(u64, offset) > window_size) return error.Corrupt;
            if (match_len > dst.len - written.*) return error.OutputTooSmall;

            var mi: usize = 0;
            while (mi < match_len) : (mi += 1) {
                dst[written.* + mi] = dst[written.* - offset + mi];
            }
            written.* += match_len;

            const ll_low = revReadPad(&br, @intCast(usize, ll_e.nbits));
            ll_state = @intCast(u32, ll_e.baseline) + ll_low;
            const ml_low = revReadPad(&br, @intCast(usize, ml_e.nbits));
            ml_state = @intCast(u32, ml_e.baseline) + ml_low;
            const of_low = revReadPad(&br, @intCast(usize, of_e.nbits));
            of_state = @intCast(u32, of_e.baseline) + of_low;
        }

        if (br.pos < br.total or br.pos > br.total + 64) return error.Corrupt;
        const remain: usize = lr.lit_size - lr.used;
        try copyLiterals(st, &lr, dst, written, remain);
    }

    if (lr.used != lr.lit_size) return error.Corrupt;
    if (lr.kind == 2) {
        if (lr.stream_started or @intCast(usize, lr.stream_idx) != @intCast(usize, lr.stream_count)) {
            return error.Corrupt;
        }
    }
    if (written.* - block_start > block_max) return error.Corrupt;
}

fn windowCap(log: u8) u64 {
    if (log >= 63) return 0xFFFFFFFFFFFFFFFF;
    return @intCast(u64, 1) << @intCast(u64, log);
}

fn resetDecoder(st: *Decoder) void {
    st.huf_log = 0;
    st.huf_valid = false;
    st.ll.valid = false;
    st.ll.log = 0;
    st.of.valid = false;
    st.of.log = 0;
    st.ml.valid = false;
    st.ml.log = 0;
    st.rep[0] = 1;
    st.rep[1] = 4;
    st.rep[2] = 8;
}

fn rotl64(x: u64, n: u32) u64 {
    const s: u32 = n % 64;
    if (s == 0) return x;
    var mask: u64 = 0xFFFFFFFFFFFFFFFF;
    if (64 - s < 64) {
        mask = (@intCast(u64, 1) << @intCast(u64, 64 - s)) - 1;
    }
    const keep: u64 = x & mask;
    return (keep << @intCast(u64, s)) | (x >> @intCast(u64, 64 - s));
}

fn xxh64Round(acc: u64, input: u64) u64 {
    const p2: u64 = 14029467366897019727;
    const p1: u64 = 11400714785074694791;
    var a: u64 = acc +% (input *% p2);
    a = rotl64(a, 31);
    return a *% p1;
}

fn xxh64Merge(acc: u64, val: u64) u64 {
    const p1: u64 = 11400714785074694791;
    const p4: u64 = 9650029242287828579;
    var a: u64 = acc ^ xxh64Round(0, val);
    return a *% p1 +% p4;
}

fn xxh64(data: []const u8) u64 {
    const p1: u64 = 11400714785074694791;
    const p2: u64 = 14029467366897019727;
    const p3: u64 = 1609587929392839161;
    const p4: u64 = 9650029242287828579;
    const p5: u64 = 2870177450012600261;

    var p: usize = 0;
    var h: u64 = 0;
    if (data.len >= 32) {
        const v1i: u64 = p1 +% p2;
        var v1: u64 = v1i;
        var v2: u64 = p2;
        var v3: u64 = 0;
        var v4: u64 = 0 -% p1;
        while (p + 32 <= data.len) : (p += 32) {
            v1 = xxh64Round(v1, le64(data, p));
            v2 = xxh64Round(v2, le64(data, p + 8));
            v3 = xxh64Round(v3, le64(data, p + 16));
            v4 = xxh64Round(v4, le64(data, p + 24));
        }
        h = rotl64(v1, 1) +% rotl64(v2, 7) +% rotl64(v3, 12) +% rotl64(v4, 18);
        h = xxh64Merge(h, v1);
        h = xxh64Merge(h, v2);
        h = xxh64Merge(h, v3);
        h = xxh64Merge(h, v4);
    } else {
        h = p5;
    }
    h = h +% @intCast(u64, data.len);
    while (p + 8 <= data.len) : (p += 8) {
        const k1 = xxh64Round(0, le64(data, p));
        h ^= k1;
        h = rotl64(h, 27) *% p1 +% p4;
    }
    if (p + 4 <= data.len) {
        h ^= @intCast(u64, le32(data, p)) *% p1;
        h = rotl64(h, 23) *% p2 +% p3;
        p += 4;
    }
    while (p < data.len) : (p += 1) {
        h ^= @intCast(u64, data[p]) *% p5;
        h = rotl64(h, 11) *% p1;
    }
    h ^= h >> 33;
    h = h *% p2;
    h ^= h >> 29;
    h = h *% p3;
    h ^= h >> 32;
    return h;
}

fn decodeFrame(st: *Decoder, src: []const u8, start: usize, dst: []u8,
               written: *usize, max_window_log: u8) !usize {
    var pos: usize = start;
    if (pos + 5 > src.len) return error.Corrupt;
    if (le32(src, pos) != MAGIC) return error.Corrupt;
    pos += 4;

    const desc: u8 = src[pos];
    pos += 1;
    if ((desc & 8) != 0) return error.Corrupt;
    const fcs_flag: u8 = desc >> 6;
    const single: bool = ((desc >> 5) & 1) != 0;
    const has_checksum: bool = ((desc >> 2) & 1) != 0;
    const did_flag: u8 = desc & 3;

    var window_size: u64 = 0;
    if (!single) {
        if (pos >= src.len) return error.Corrupt;
        const wd: u8 = src[pos];
        pos += 1;
        const exp: u8 = wd >> 3;
        const mant: u8 = wd & 7;
        const wlog: u8 = 10 + exp;
        if (wlog > max_window_log) return error.WindowTooBig;
        const base: u64 = @intCast(u64, 1) << @intCast(u64, wlog);
        const add: u64 = (base / 8) * @intCast(u64, mant);
        window_size = base + add;
    }

    var did_size: usize = 0;
    if (did_flag == 1) did_size = 1;
    if (did_flag == 2) did_size = 2;
    if (did_flag == 3) did_size = 4;
    if (pos + did_size > src.len) return error.Corrupt;
    var dict_id: u64 = 0;
    if (did_size == 1) dict_id = @intCast(u64, src[pos]);
    if (did_size == 2) dict_id = @intCast(u64, le16(src, pos));
    if (did_size == 4) dict_id = @intCast(u64, le32(src, pos));
    pos += did_size;
    if (dict_id != 0) return error.Corrupt;

    var fcs_size: usize = 0;
    if (fcs_flag == 0) {
        if (single) fcs_size = 1;
    } else if (fcs_flag == 1) {
        fcs_size = 2;
    } else if (fcs_flag == 2) {
        fcs_size = 4;
    } else {
        fcs_size = 8;
    }
    if (pos + fcs_size > src.len) return error.Corrupt;
    var frame_size: u64 = 0;
    var have_size: bool = fcs_size != 0;
    if (fcs_size == 1) frame_size = @intCast(u64, src[pos]);
    if (fcs_size == 2) frame_size = @intCast(u64, le16(src, pos)) + 256;
    if (fcs_size == 4) frame_size = @intCast(u64, le32(src, pos));
    if (fcs_size == 8) frame_size = le64(src, pos);
    pos += fcs_size;

    if (single) {
        window_size = frame_size;
        if (window_size > windowCap(max_window_log)) return error.WindowTooBig;
    }
    if (have_size) {
        if (frame_size > @intCast(u64, dst.len - written.*)) return error.OutputTooSmall;

    }

    const frame_start: usize = written.*;
    var block_max: usize = BLOCK_MAX;
    if (window_size < @intCast(u64, block_max)) block_max = @intCast(usize, window_size);

    while (true) {
        if (pos + 3 > src.len) return error.Corrupt;
        const h: u32 = le24(src, pos);
        pos += 3;
        const last: bool = (h & 1) != 0;
        const btype: u8 = @intCast(u8, (h >> 1) & 3);
        const bsize: usize = @intCast(usize, h >> 3);
        if (btype == 0) {
            if (bsize > block_max) return error.Corrupt;
            if (bsize > src.len - pos) return error.Corrupt;
            if (bsize > dst.len - written.*) return error.OutputTooSmall;
            var i: usize = 0;
            while (i < bsize) : (i += 1) dst[written.* + i] = src[pos + i];
            written.* += bsize;
            pos += bsize;
        } else if (btype == 1) {
            if (pos >= src.len) return error.Corrupt;
            if (bsize > block_max) return error.Corrupt;
            if (bsize > dst.len - written.*) return error.OutputTooSmall;
            const v: u8 = src[pos];
            var i: usize = 0;
            while (i < bsize) : (i += 1) dst[written.* + i] = v;
            written.* += bsize;
            pos += 1;
        } else if (btype == 2) {
            if (bsize > src.len - pos) return error.Corrupt;
            if (bsize > block_max) return error.Corrupt;
            const block_end: usize = pos + bsize;
            try decodeCompressedBlock(st, src, &pos, block_end, dst, written,
                                      window_size, block_max);
            pos = block_end;
        } else {
            return error.Corrupt;
        }
        if (last) break;
    }

    if (have_size and @intCast(u64, written.* - frame_start) != frame_size) {
        return error.Corrupt;
    }

    if (has_checksum) {
        if (pos + 4 > src.len) return error.Corrupt;
        const want: u32 = le32(src, pos);
        pos += 4;
        const got: u64 = xxh64(dst[frame_start..written.*]);
        if (@intCast(u32, got & 0xFFFFFFFF) != want) return error.Corrupt;
    }
    return pos;
}

pub fn zstdDecompress(src: []const u8, dst: []u8, max_window_log: u8) !u32 {
    if (src.len == 0) return error.Corrupt;
    var st: Decoder = undefined;
    var written: usize = 0;
    var pos: usize = 0;
    var saw_frame: bool = false;

    while (pos < src.len) {
        if (pos + 4 > src.len) return error.Corrupt;
        const magic = le32(src, pos);
        if (magic == MAGIC) {
            resetDecoder(&st);
            pos = try decodeFrame(&st, src, pos, dst, &written, max_window_log);
            saw_frame = true;
        } else if ((magic & 0xFFFFFFF0) == SKIPPABLE_MAGIC) {
            if (pos + 8 > src.len) return error.Corrupt;
            const fsize: usize = @intCast(usize, le32(src, pos + 4));
            pos += 8;
            if (fsize > src.len - pos) return error.Corrupt;
            pos += fsize;
        } else {
            return error.Corrupt;
        }
    }
    if (!saw_frame and src.len == 0) return error.Corrupt;
    if (written > 0xFFFFFFFF) return error.Corrupt;
    return @intCast(u32, written);
}
