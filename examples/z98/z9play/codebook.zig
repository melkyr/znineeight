// codebook.zig — Vorbis codebook Huffman decode tables + VQ vector unpack
// (z9play M1, Task 2).
//
// buildDecodeTable turns a parsed vorbis_setup.Codebook (its canonical code
// lengths) into a binary decision tree; decodeScalar walks it one stream bit at
// a time. Vorbis codes are canonical: entries are assigned, in entry order, the
// lowest-valued unused codeword of their length, and a codeword is read
// left-to-right with the leftmost bit as its MSb (spec 3.2.1). The byte-level
// reader is LSB-first (spec 2.1), but a codeword is a bit *string*: the first
// bit read is the codeword's MSb. Walking the tree MSb-first therefore needs no
// reversal of the stream — only a table-based index would need one.
//
// decodeVector maps a decoded entry through the VQ lookup (types 1/2) to a
// vector of f64 values (spec 3.2.1, "VQ lookup table vector representation").
// The Z98 subset has f64 arithmetic (+ - * /) but no float builtins; the packed
// Vorbis float32 min/delta are unpacked with exact power-of-two scaling.
//
// Pure Z98: free functions, no generics/@Type/@cImport, strict @intCast, no
// switch; every string literal is written via `var s: []const u8`.

const std = @import("std");
const ogg = @import("ogg.zig");
const vs = @import("vorbis_setup.zig");

// A built codebook. `codes` holds the canonical codeword per entry (MSb-first,
// meaningful only where `lengths[i] != 0`); `left`/`right`/`sym` form the
// decision tree (sym >= 0 marks a leaf holding the entry number). `single_sym`
// is >= 0 for a tolerated single-entry codebook (spec errata), in which case
// decodeScalar sinks one bit and returns it.
pub const DecodeTable = struct {
    dimensions: u16,
    entries: u32,
    lookup_type: u32,
    value_bits: u32,
    sequence_p: bool,
    lookup_values: u32,
    min_value: f64,
    delta_value: f64,
    multiplicands: []u32,
    lengths: []const u8,
    codes: []u32,
    left: []i32,
    right: []i32,
    sym: []i32,
    node_count: u32,
    max_len: u32,
    used: u32,
    single_sym: i32,
};

// float32_unpack (spec 9.2.2): mantissa * 2^(exponent-788), sign applied. The
// power-of-two scaling is exact (only exponent shifts), so no precision is
// lost between the packed Vorbis float32 and the returned f64.
fn float32Unpack(x: u32) f64 {
    var mantissa: u32 = x & 0x1fffff;
    var exponent: u32 = (x & 0x7fe00000) >> 21;
    var v: f64 = @intToFloat(f64, mantissa);
    var e: i32 = @intCast(i32, exponent) - 788;
    if (e >= 0) {
        var k: i32 = 0;
        while (k < e) : (k += 1) {
            v = v * 2.0;
        }
    } else {
        var k: i32 = 0;
        while (k < -e) : (k += 1) {
            v = v / 2.0;
        }
    }
    if ((x & 0x80000000) != 0) v = -v;
    return v;
}



// Build the canonical decode table for `cb`. Rejects malformed trees (a length
// > 32, an overspecified/underspecified prefix code); tolerates a single-entry
// codebook whose one used entry has length 1.
pub fn buildDecodeTable(arena: *std.arena.Arena, cb: vs.Codebook) ogg.OggError!DecodeTable {
    var entries_usize: usize = @intCast(usize, cb.entries);
    var raw_codes: [*]u8 = std.arena.alloc(arena, entries_usize * @sizeOf(u32)) catch return error.OutOfMemory;
    var codes: []u32 = @ptrCast([*]u32, raw_codes)[0..entries_usize];
    var i: u32 = 0;
    while (i < cb.entries) : (i += 1) {
        codes[@intCast(usize, i)] = 0;
    }

    // Canonical codeword assignment (libvorbis _make_words): entries are
    // processed in index order and each claims the lowest-valued codeword of
    // its length that does not conflict with an already-claimed node. `marker`
    // is u64 (values stay <= 2^32) so no increment can trap under -fsafe.
    var marker: [33]u64 = undefined;
    var mj: usize = 0;
    while (mj < 33) : (mj += 1) {
        marker[mj] = 0;
    }
    var used: u32 = 0;
    var max_len: u32 = 0;
    var single_sym: i32 = -1;
    i = 0;
    while (i < cb.entries) : (i += 1) {
        var L: u32 = @intCast(u32, cb.lengths[@intCast(usize, i)]);
        if (L == 0) continue;
        if (L > 32) return error.BadVersion;
        var entry: u64 = marker[@intCast(usize, L)];
        if (L < 32) {
            var limit: u64 = 1;
            var t: u32 = 0;
            while (t < L) : (t += 1) {
                limit = limit * 2;
            }
            if (entry >= limit) return error.BadVersion; // overpopulated tree
        }


        codes[@intCast(usize, i)] = @intCast(u32, entry);

        // Advance the shorter markers that now sit above a claimed node.
        var j: u32 = L;
        while (j > 0) {
            if ((marker[@intCast(usize, j)] & 1) == 1) {
                if (j == 1) {
                    marker[1] = marker[1] + 1;
                } else {
                    marker[@intCast(usize, j)] = marker[@intCast(usize, j - 1)] << 1;
                }
                break;
            }
            marker[@intCast(usize, j)] = marker[@intCast(usize, j)] + 1;
            j -= 1;
        }
        // Re-dangle the longer markers from the newly claimed node.
        var kk: u32 = L + 1;
        while (kk <= 32) : (kk += 1) {
            if ((marker[@intCast(usize, kk)] >> 1) == entry) {
                entry = marker[@intCast(usize, kk)];
                marker[@intCast(usize, kk)] = marker[@intCast(usize, kk - 1)] << 1;
            } else {
                break;
            }
        }
        used += 1;
        if (L > max_len) max_len = L;
    }
    if (used == 0) return error.BadVersion;

    if (used == 1) {
        // Single-entry codebooks (spec errata): the one used entry must have
        // length 1; decode always returns it after sinking one bit.
        i = 0;
        while (i < cb.entries) : (i += 1) {
            if (cb.lengths[@intCast(usize, i)] != 0) {
                if (cb.lengths[@intCast(usize, i)] != 1) return error.BadVersion;
                single_sym = @intCast(i32, i);
            }
        }
    } else {
        // Reject an underpopulated tree: marker[i] must be exactly 2^i.
        var ci: u32 = 1;
        while (ci <= 32) : (ci += 1) {
            var m32: u32 = 0xffffffff;
            var sh: u32 = 32 - ci;
            var mask: u64 = @intCast(u64, m32 >> sh);
            if ((marker[@intCast(usize, ci)] & mask) != 0) return error.BadVersion;
        }
    }


    // Decision tree. A full binary tree with `used` leaves has 2*used-1 nodes.
    var nodes: usize = @intCast(usize, used * 2);
    if (nodes < 1) nodes = 1;
    var raw_l: [*]u8 = std.arena.alloc(arena, nodes * @sizeOf(i32)) catch return error.OutOfMemory;
    var raw_r: [*]u8 = std.arena.alloc(arena, nodes * @sizeOf(i32)) catch return error.OutOfMemory;
    var raw_s: [*]u8 = std.arena.alloc(arena, nodes * @sizeOf(i32)) catch return error.OutOfMemory;
    var left: []i32 = @ptrCast([*]i32, raw_l)[0..nodes];
    var right: []i32 = @ptrCast([*]i32, raw_r)[0..nodes];
    var sym: []i32 = @ptrCast([*]i32, raw_s)[0..nodes];
    var nc: usize = 0;
    while (nc < nodes) : (nc += 1) {
        left[nc] = -1;
        right[nc] = -1;
        sym[nc] = -1;
    }

    var node_count: u32 = 1; // node 0 is the root
    i = 0;
    while (i < cb.entries) : (i += 1) {
        var L: u32 = @intCast(u32, cb.lengths[@intCast(usize, i)]);
        if (L == 0) continue;
        var code: u32 = codes[@intCast(usize, i)];
        var node: u32 = 0;
        var b: u32 = 0;
        while (b < L) : (b += 1) {
            var sh: u32 = L - 1 - b;
            var bit: u32 = (code >> sh) & 1;

            if (bit == 0) {
                if (left[@intCast(usize, node)] < 0) {
                    left[@intCast(usize, node)] = @intCast(i32, node_count);
                    node_count += 1;
                }
                node = @intCast(u32, left[@intCast(usize, node)]);
            } else {
                if (right[@intCast(usize, node)] < 0) {
                    right[@intCast(usize, node)] = @intCast(i32, node_count);
                    node_count += 1;
                }
                node = @intCast(u32, right[@intCast(usize, node)]);
            }
        }
        sym[@intCast(usize, node)] = @intCast(i32, i);
    }

    var min_value: f64 = 0.0;
    var delta_value: f64 = 0.0;
    if (cb.lookup_type == 1 or cb.lookup_type == 2) {
        min_value = float32Unpack(cb.min_bits);
        delta_value = float32Unpack(cb.delta_bits);
    }

    return DecodeTable{
        .dimensions = cb.dimensions,
        .entries = cb.entries,
        .lookup_type = cb.lookup_type,
        .value_bits = cb.value_bits,
        .sequence_p = cb.sequence_p,
        .lookup_values = cb.lookup_values,
        .min_value = min_value,
        .delta_value = delta_value,
        .multiplicands = cb.multiplicands,
        .lengths = cb.lengths,
        .codes = codes,
        .left = left,
        .right = right,
        .sym = sym,
        .node_count = node_count,
        .max_len = max_len,
        .used = used,
        .single_sym = single_sym,
    };
}

// Decode one codeword from `bits` and return its entry number, or -1 for a bit
// pattern with no leaf. A read past the end of the packet yields zero bits (the
// Vorbis decoder must tolerate truncated packets), so this never errors.
pub fn decodeScalar(dt: *const DecodeTable, bits: *vs.BitReader) i32 {
    if (dt.used == 1) {
        _ = vs.brRead(bits, 1) catch 0;
        return dt.single_sym;
    }
    var node: u32 = 0;
    var steps: u32 = 0;
    while (steps <= dt.max_len) : (steps += 1) {
        var bit: u32 = vs.brRead(bits, 1) catch 0;
        var nxt: i32 = 0;
        if (bit == 0) {
            nxt = dt.left[@intCast(usize, node)];
        } else {
            nxt = dt.right[@intCast(usize, node)];
        }
        if (nxt < 0) return -1;
        node = @intCast(u32, nxt);
        if (dt.sym[@intCast(usize, node)] >= 0) return dt.sym[@intCast(usize, node)];
    }
    return -1;
}

// Unpack the VQ value vector for `entry` (spec 3.2.1). Type 1 reads
// multiplicands through a base-[lookup_values] index; type 2 reads them
// sequentially. `sequence_p` makes each scalar begin at the running total.
pub fn entryToVector(arena: *std.arena.Arena, dt: *const DecodeTable, entry: u32) ogg.OggError![]f64 {
    if (dt.lookup_type != 1 and dt.lookup_type != 2) return error.BadVersion;
    if (dt.lookup_values == 0) return error.BadVersion;
    var dims: usize = @intCast(usize, dt.dimensions);
    if (dims == 0) return error.BadVersion;
    var raw: [*]u8 = std.arena.alloc(arena, dims * @sizeOf(f64)) catch return error.OutOfMemory;
    var out: []f64 = @ptrCast([*]f64, raw)[0..dims];
    var last: f64 = 0.0;
    var i: u32 = 0;
    if (dt.lookup_type == 1) {
        var divisor: u64 = 1;
        while (i < dt.dimensions) : (i += 1) {
            var off: u64 = (@as(u64, entry) / divisor) % @as(u64, dt.lookup_values);
            var m: f64 = @intToFloat(f64, dt.multiplicands[@intCast(usize, off)]);
            var val: f64 = m * dt.delta_value + dt.min_value + last;
            out[@intCast(usize, i)] = val;
            if (dt.sequence_p) last = val;
            divisor = divisor * @as(u64, dt.lookup_values);
        }
    } else {
        var off: u64 = @as(u64, entry) * @as(u64, dt.dimensions);
        while (i < dt.dimensions) : (i += 1) {
            var m: f64 = @intToFloat(f64, dt.multiplicands[@intCast(usize, off)]);
            var val: f64 = m * dt.delta_value + dt.min_value + last;
            out[@intCast(usize, i)] = val;
            if (dt.sequence_p) last = val;
            off += 1;
        }
    }
    return out;
}

// Decode one codeword from `bits` and return its VQ value vector.
pub fn decodeVector(arena: *std.arena.Arena, dt: *const DecodeTable, bits: *vs.BitReader) ogg.OggError![]f64 {
    var entry: i32 = decodeScalar(dt, bits);
    if (entry < 0) return error.BadVersion;
    return entryToVector(arena, dt, @intCast(u32, entry));
}
