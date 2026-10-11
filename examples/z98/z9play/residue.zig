// residue.zig — Vorbis residue decode (z9play M3 Task 3).
//
// Vorbis codes the fine structure of each channel's spectrum as a *residue*
// vector, using cascaded (multi-pass) vector quantization. A residue
// configuration (spec 8.6.1) names a spectral sub-range [begin, end), a
// partition size, a classbook (which codes the per-partition "classification"),
// a cascade bitmap and, per classification and pass, a VQ codebook. Decode
// (spec 8.6.2) walks up to eight passes; within a pass, each partition of each
// affected channel is decoded from the class's stage codebook and *added* into
// the channel's spectral vector.
//
// The three residue types differ only in how a partition's decoded values are
// scattered into the vector (spec 8.3/8.4/8.5, 8.6.3/8.6.4/8.6.5):
//   type 0 — interleaved: value entry[j] of the i-th codeword goes to
//            offset + i + j*step (step = partition_size / dimension).
//   type 1 — sequential: each codeword's values are placed contiguously.
//   type 2 — the ch channel vectors are flattened/interleaved into one length
//            ch*n vector which is decoded as type 1, then deinterleaved
//            (output[j][i] = v[i*ch + j]); if all channels are 'do not
//            decode' it is skipped, otherwise *all* channels are decoded.
//
// Output convention (binding for the M3 Task 4 packet decoder):
//   out is [][]f64 indexed [channel][spectral_index]; out.len is the number of
//   vectors in this submap bundle and must equal doNotDecode.len. Each row is
//   `spectral_len` long (the current block size / 2, i.e. the number of
//   spectral coefficients dsp.imdct consumes). Every row is zeroed on entry
//   (spec 8.6.2 step 1; even 'do not decode' vectors), then the decoded residue
//   is placed/additively accumulated exactly within the capped [limit_begin,
//   limit_end) sub-range; values outside stay zero. For type 2, begin/end/
//   partition_size apply to the interleaved length ch*spectral_len vector
//   (spec 8.6.2), and the final deinterleave lands in the per-channel rows.
//
// Type-0/-1 end-of-packet handshake: the residue decode reads one classbook
// codeword per channel for each group of `classbook.dimensions` partitions.
// The very first such read (the first vector's classification codeword) gates
// the whole decode: if it encounters end-of-packet, or a classword outside the
// valid class space, decode stops and returns the (zero/partial) vectors —
// exactly libvorbis's `_01inverse` `goto eopbreak`. This module detects a
// genuine end-of-packet (a codeword whose bits are not all present) rather
// than treating past-end bits as zeros, matching the reference
// `decode_packed_entry_number`; see decodeScalarEop.
//
// Pure Z98: free functions, no generics/anytype/@Type, strict @intCast, no
// @cImport, no switch. Ported from the Vorbis I specification section 8.6 and
// cross-checked against xiph/vorbis lib/res0.c and lib/codebook.c.

const std = @import("std");
const vs = @import("vorbis_setup.zig");
const cbk = @import("codebook.zig");

// Residue decode fails only on a structurally impossible/malformed
// configuration (BadVersion) or an exhausted arena (OutOfMemory). An
// end-of-packet during packet decode is nominal (spec 8.6.2) and is reported by
// simply returning with the vectors as decoded so far.
pub const ResidueError = error{ BadVersion, OutOfMemory };

// Decode one codeword from `bits`, returning its entry number, or -1 when the
// packet ends before the codeword's bits are all present or when the bit
// pattern has no leaf. Unlike codebook.decodeScalar (which reads every past-
// end bit as 0), this requires each codeword bit to exist, so a truncated
// packet aborts residue decode exactly as libvorbis decode_packed_entry_number
// does. The tree walk itself is the same MSb-first canonical decode.
fn decodeScalarEop(dt: *const cbk.DecodeTable, bits: *vs.BitReader) i32 {
    if (dt.used == 1) {
        if (bits.pos >= bits.nbits) return -1;
        _ = vs.brRead(bits, 1) catch 0;
        return dt.single_sym;
    }
    var node: u32 = 0;
    var steps: u32 = 0;
    while (steps <= dt.max_len) : (steps += 1) {
        if (bits.pos >= bits.nbits) return -1;
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

// True when a stage codebook has a value mapping and a non-zero VQ size. The
// spec (8.6.1) requires every book in residue_books to have a value mapping
// (maptype != 0); checking it up front lets the partition loop assume
// entryToVector can only fail with OutOfMemory.
fn bookHasValues(dt: *const cbk.DecodeTable) bool {
    if (dt.lookup_type != 1 and dt.lookup_type != 2) return false;
    if (dt.dimensions == 0) return false;
    if (dt.lookup_values == 0) return false;
    return true;
}

// Residue type 0 partition scatter (spec 8.6.3): step = partition_size / dim
// codewords are read atomically (a failed read adds nothing, like libvorbis
// vorbis_book_decodevs_add), then value entry[j] of codeword i is added at
// row[offset + i + j*step]. Returns false on end-of-packet/no-leaf.
fn placeFormat0(arena: *std.arena.Arena, dt: *const cbk.DecodeTable, bits: *vs.BitReader, row: []f64, offset: u32, part_size: u32) ResidueError!bool {
    var dim: u32 = @intCast(u32, dt.dimensions);
    var step: u32 = part_size / dim;
    if (step == 0) return true;
    var raw: [*]u8 = std.arena.alloc(arena, @intCast(usize, step) * @sizeOf(u32)) catch return error.OutOfMemory;
    var entries: []u32 = @ptrCast([*]u32, raw)[0..@intCast(usize, step)];
    var i: u32 = 0;
    while (i < step) : (i += 1) {
        var e: i32 = decodeScalarEop(dt, bits);
        if (e < 0) return false;
        entries[@intCast(usize, i)] = @intCast(u32, e);
    }
    var j: u32 = 0;
    while (j < step) : (j += 1) {
        var vec: []f64 = cbk.entryToVector(arena, dt, entries[@intCast(usize, j)]) catch return error.OutOfMemory;
        var d: u32 = 0;
        while (d < dim) : (d += 1) {
            var idx: u64 = @intCast(u64, offset) + @intCast(u64, d) * @intCast(u64, step) + @intCast(u64, j);
            if (idx < @intCast(u64, row.len)) {
                row[@intCast(usize, idx)] = row[@intCast(usize, idx)] + vec[@intCast(usize, d)];
            }
        }
    }
    return true;
}

// Residue type 1 partition scatter (spec 8.6.4): codewords are read and their
// values placed contiguously from offset until partition_size scalars are
// filled. Incremental like libvorbis vorbis_book_decodev_add (a mid-partition
// end-of-packet leaves the earlier adds). Returns false on end-of-packet.
fn placeFormat1(arena: *std.arena.Arena, dt: *const cbk.DecodeTable, bits: *vs.BitReader, row: []f64, offset: u32, part_size: u32) ResidueError!bool {
    var dim: u32 = @intCast(u32, dt.dimensions);
    var i: u32 = 0;
    while (i < part_size) {
        var e: i32 = decodeScalarEop(dt, bits);
        if (e < 0) return false;
        var vec: []f64 = cbk.entryToVector(arena, dt, @intCast(u32, e)) catch return error.OutOfMemory;
        var j: u32 = 0;
        while (i < part_size and j < dim) {
            var idx: u64 = @intCast(u64, offset) + @intCast(u64, i);
            if (idx < @intCast(u64, row.len)) {
                row[@intCast(usize, idx)] = row[@intCast(usize, idx)] + vec[@intCast(usize, j)];
            }
            i += 1;
            j += 1;
        }
    }
    return true;
}

// Residue type 2 scatter (spec 8.6.5): type 1 decode over the interleaved
// length ch*n vector, deinterleaved on the fly so interleaved index L lands in
// out[L % ch][L / ch]. Incremental like libvorbis vorbis_book_decodevv_add.
// Returns false on end-of-packet.
fn placeFormat2(arena: *std.arena.Arena, dt: *const cbk.DecodeTable, bits: *vs.BitReader, out: [][]f64, offset: u32, part_size: u32, ch: usize) ResidueError!bool {
    var dim: u32 = @intCast(u32, dt.dimensions);
    var l: u32 = offset;
    var end: u64 = @intCast(u64, offset) + @intCast(u64, part_size);
    while (@intCast(u64, l) < end) {
        var e: i32 = decodeScalarEop(dt, bits);
        if (e < 0) return false;
        var vec: []f64 = cbk.entryToVector(arena, dt, @intCast(u32, e)) catch return error.OutOfMemory;
        var j: u32 = 0;
        while (@intCast(u64, l) < end and j < dim) {
            var cu: u64 = @intCast(u64, l);
            var c: usize = @intCast(usize, cu % @intCast(u64, ch));
            var pos: u64 = cu / @intCast(u64, ch);
            if (pos < @intCast(u64, out[c].len)) {
                out[c][@intCast(usize, pos)] = out[c][@intCast(usize, pos)] + vec[@intCast(usize, j)];
            }
            l += 1;
            j += 1;
        }
    }
    return true;
}

// Decode the residue vectors for one submap bundle. `tables[k]` is the built
// decode table for codebook k in setup order. See the file header for the
// output convention. Returns on success, a malformed configuration
// (BadVersion), an exhausted arena (OutOfMemory), or — for a nominal
// end-of-packet — with the vectors as decoded so far.
pub fn decodeResidue(arena: *std.arena.Arena, tables: []const cbk.DecodeTable, bits: *vs.BitReader, residue: vs.Residue, doNotDecode: []bool, spectral_len: u32, out: [][]f64) ResidueError!void {
    var ch: usize = out.len;
    if (doNotDecode.len != ch) return error.BadVersion;
    if (residue.residue_type > 2) return error.BadVersion;
    if (residue.partition_size == 0) return error.BadVersion;
    if (residue.classifications == 0) return error.BadVersion;
    if (residue.books.len < @intCast(usize, residue.classifications) * 8) return error.BadVersion;

    // Zero every returned vector (spec 8.6.2 step 1), even 'do not decode'.
    var z: usize = 0;
    while (z < ch) : (z += 1) {
        if (out[z].len < @intCast(usize, spectral_len)) return error.BadVersion;
        var k: usize = 0;
        while (k < @intCast(usize, spectral_len)) : (k += 1) {
            out[z][k] = 0.0;
        }
    }

    // actual_size and the capped coding range (spec 8.6.2).
    var actual_size: u32 = spectral_len;
    if (residue.residue_type == 2) {
        var a64: u64 = @intCast(u64, spectral_len) * @intCast(u64, ch);
        if (a64 > 0xffffffff) return error.BadVersion;
        actual_size = @intCast(u32, a64);
    }
    var limit_begin: u32 = residue.begin;
    if (limit_begin > actual_size) limit_begin = actual_size;
    var limit_end: u32 = residue.end;
    if (limit_end > actual_size) limit_end = actual_size;

    var n_to_read: u32 = 0;
    if (limit_end > limit_begin) n_to_read = limit_end - limit_begin;
    if (n_to_read == 0) return; // nothing to decode (spec 8.6.2 step 2)

    var part_size: u32 = residue.partition_size;
    var partitions_to_read: u32 = n_to_read / part_size;
    if (partitions_to_read == 0) return;

    // Type 2 treats the ch channel vectors as ONE interleaved logical vector
    // (spec 8.6.5): it is decoded as a single type-1 vector and deinterleaved.
    // It is skipped only when *every* channel is marked 'do not decode';
    // otherwise all channels are decoded.
    var nvec: usize = ch;
    var v2_active: bool = false;
    if (residue.residue_type == 2) {
        nvec = 1;
        var a: usize = 0;
        while (a < ch) : (a += 1) {
            if (!doNotDecode[a]) v2_active = true;
        }
    }

    // Classbook: its dimensions give the number of classifications carried by
    // one codeword (classwords_per_codeword, spec 8.6.2).
    var cbi: usize = @intCast(usize, residue.classbook);
    if (cbi >= tables.len) return error.BadVersion;
    var cdt: *const cbk.DecodeTable = &tables[cbi];
    var class_dim: u32 = @intCast(u32, cdt.dimensions);
    if (class_dim == 0) return error.BadVersion;
    var classes: u32 = residue.classifications;

    // class_space = classifications ^ dimensions must not exceed the classbook
    // entry count (spec 8.6.1); the early exit avoids any u64 overflow.
    var class_space: u64 = 1;
    var ce: u32 = 0;
    while (ce < class_dim) : (ce += 1) {
        class_space = class_space * @intCast(u64, classes);
        if (class_space > @intCast(u64, cdt.entries)) return error.BadVersion;
    }

    // One classification row per logical residue vector; type 2 has a single
    // interleaved vector (spec 8.6.5). Read once at pass 0, reused later.
    var cls_count: u64 = @intCast(u64, nvec) * @intCast(u64, partitions_to_read);
    if (cls_count > 0xffffffff) return error.BadVersion;
    var cls_raw: [*]u8 = std.arena.alloc(arena, @intCast(usize, cls_count)) catch return error.OutOfMemory;
    var cls: []u8 = cls_raw[0..@intCast(usize, cls_count)];

    var stage: u32 = 0;
    while (stage < 8) : (stage += 1) {
        var pc: u32 = 0;
        while (pc < partitions_to_read) {
            // Pass 0 reads one classword per channel for this group of
            // class_dim partitions; later passes reuse the stored classes.
            if (stage == 0) {
                var j: usize = 0;
                while (j < nvec) : (j += 1) {
                    var skip: bool = false;
                    if (residue.residue_type == 2) {
                        if (!v2_active) skip = true;
                    } else {
                        skip = doNotDecode[j];
                    }
                    if (!skip) {
                        var cw: i32 = decodeScalarEop(cdt, bits);
                        if (cw < 0) return; // end-of-packet: nominal stop
                        if (@intCast(u64, cw) >= class_space) return; // bad classword
                        var val: u32 = @intCast(u32, cw);
                        var di: u32 = class_dim;
                        while (di > 0) {
                            di -= 1;
                            var d: u32 = val % classes;
                            val = val / classes;
                            var gi: u64 = @intCast(u64, pc) + @intCast(u64, di);
                            if (gi < @intCast(u64, partitions_to_read)) {
                                cls[j * @intCast(usize, partitions_to_read) + @intCast(usize, gi)] = @intCast(u8, d);
                            }
                        }
                    }
                }
            }
            var k: u32 = 0;
            while (k < class_dim and pc < partitions_to_read) {
                var j: usize = 0;
                while (j < nvec) : (j += 1) {
                    var skip: bool = false;
                    if (residue.residue_type == 2) {
                        if (!v2_active) skip = true;
                    } else {
                        skip = doNotDecode[j];
                    }
                    if (!skip) {
                        var vqc: u32 = @intCast(u32, cls[j * @intCast(usize, partitions_to_read) + @intCast(usize, pc)]);
                        var book_idx: i16 = residue.books[@intCast(usize, vqc) * 8 + @intCast(usize, stage)];
                        if (book_idx >= 0) {
                            var bi: usize = @intCast(usize, book_idx);
                            if (bi >= tables.len) return error.BadVersion;
                            var vdt: *const cbk.DecodeTable = &tables[bi];
                            if (!bookHasValues(vdt)) return error.BadVersion;
                            var offset: u32 = limit_begin + pc * part_size;
                            var ok: bool = false;
                            if (residue.residue_type == 0) {
                                ok = try placeFormat0(arena, vdt, bits, out[j], offset, part_size);
                            } else if (residue.residue_type == 1) {
                                ok = try placeFormat1(arena, vdt, bits, out[j], offset, part_size);
                            } else {
                                ok = try placeFormat2(arena, vdt, bits, out, offset, part_size, ch);
                            }
                            if (!ok) return; // end-of-packet: nominal stop
                        }
                    }
                }
                pc += 1;
                k += 1;
            }
        }
    }
}

