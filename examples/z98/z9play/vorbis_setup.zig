// vorbis_setup.zig — Vorbis setup-header skeleton (z9play M1, Task 1).
//
// Parses the setup header packet (packet type 5, "\x05vorbis") far enough to
// read the codebook list: the codebook count (8-bit count + 1) and, per
// codebook, the "BCV" sync pattern (0x564342), dimensions (16-bit), entries
// (24-bit), the ordered/unordered and sparse flags, and the raw code lengths.
// The full Huffman decode tables (and floors/residues/mappings/modes) are
// later milestones; Task 1 stores only the dimensions and the length list.
//
// Byte/bit order follows the Vorbis I specification (bit packing is LSB-first
// within each byte). The lookup-type tail of each codebook (types 1/2) is
// consumed so the parser can reach the next codebook; its values are not kept.
//
// Pure Z98: free functions, no generics/@Type/@cImport, strict @intCast, no
// switch. The parser returns OggError (Truncated on a short read, BadVersion
// on a bad signature/sync, OutOfMemory when the caller's arena is exhausted).

const std = @import("std");
const ogg = @import("ogg.zig");

// One codebook header. `lengths` is arena-owned and has one entry per codebook
// entry: the raw 1-based code length, or 0 for an unused (sparse) entry.
// `ordered`/`sparse` record how the lengths were encoded (needed by the Task 2
// Huffman builder). `dimensions` and `entries` are the canonical fields.
//
// The VQ lookup fields are retained for the Task 2 decode tables. `lookup_type`
// is 0 (scalar only), 1 (lattice/tessellation) or 2 (explicit/sequence). Types
// 1/2 also carry `min_bits`/`delta_bits` (raw packed Vorbis float32),
// `value_bits`, `sequence_p`, `lookup_values`, and that many `multiplicands`.
pub const Codebook = struct {
    dimensions: u16,
    entries: u32,
    ordered: bool,
    sparse: bool,
    lengths: []u8,
    lookup_type: u32,
    value_bits: u32,
    sequence_p: bool,
    min_bits: u32,
    delta_bits: u32,
    lookup_values: u32,
    multiplicands: []u32,
};


// Parsed setup header. Task 3 grows this with floors/residues/mappings/modes.
pub const Setup = struct {
    codebooks: []Codebook,
};

// LSB-first bit reader over a Vorbis packet (the setup tail or, later, an
// audio packet). `nbits` is the total readable bit count; any read or skip past
// it reports Truncated. Decode codebooks and later milestones share it.
pub const BitReader = struct {
    data: []const u8,
    nbits: usize,
    pos: usize,
};

pub fn brInit(data: []const u8) BitReader {
    return BitReader{ .data = data, .nbits = data.len * 8, .pos = 0 };
}


// Read `n` bits (n <= 32) LSB-first. Returns Truncated on a short packet.
pub fn brRead(br: *BitReader, n: u32) ogg.OggError!u32 {

    if (br.pos + @intCast(usize, n) > br.nbits) return error.Truncated;
    var v: u32 = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var byte32: u32 = @intCast(u32, br.data[br.pos >> 3]);
        var shift: u32 = @intCast(u32, br.pos & 7);
        var bit: u32 = (byte32 >> shift) & 1;
        var sh2: u32 = i;
        v |= bit << sh2;
        br.pos += 1;
    }
    return v;
}

// Advance `n` bits without materializing them. Truncated on a short packet.
pub fn brSkip(br: *BitReader, n: u32) ogg.OggError!void {
    if (br.pos + @intCast(usize, n) > br.nbits) return error.Truncated;
    br.pos += @intCast(usize, n);
}


// Number of bits needed to represent `x` (0 -> 0, 1 -> 1, 2/3 -> 2, ...).
// Matches the Vorbis `ilog` used to size the ordered-codebook run counts.
fn ilog(x: u32) u32 {
    var n: u32 = 0;
    var v: u32 = x;
    while (v > 0) : (v = v >> 1) {
        n += 1;
    }
    return n;
}

// lookup1_values(entries, dimensions): the largest integer r with
// r^dimensions <= entries. Uses u64 partial products that stop as soon as they
// exceed `entries`, so no multiplication can overflow (entries < 2^24).
fn lookup1Values(entries: u32, dimensions: u32) u32 {
    var r: u32 = 0;
    while (r < entries) {
        var prod: u64 = 1;
        var base: u64 = @intCast(u64, r + 1);
        var i: u32 = 0;
        while (i < dimensions) : (i += 1) {
            prod = prod * base;
            if (prod > @intCast(u64, entries)) break;
        }
        if (prod > @intCast(u64, entries)) break;
        r += 1;
    }
    return r;
}

// Parse the Vorbis setup header packet `packet` (type 5, "\x05vorbis"). Reads
// the codebook count and, for each codebook, dimensions/entries/flags/lengths,
// skipping the lookup tail. All returned storage is arena-owned.
pub fn parseSetup(arena: *std.arena.Arena, packet: []const u8) ogg.OggError!Setup {
    if (packet.len < 7) return error.Truncated;
    if (packet[0] != 5) return error.BadVersion;
    var sig: []const u8 = "vorbis";
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        if (packet[1 + i] != sig[i]) return error.BadVersion;
    }

    var br = brInit(packet[7..]);
    var count: u32 = (try brRead(&br, 8)) + 1;

    var raw_cb: [*]u8 = std.arena.alloc(arena, @intCast(usize, count) * @sizeOf(Codebook)) catch return error.OutOfMemory;
    var cbs: [*]Codebook = @ptrCast([*]Codebook, raw_cb);

    var c: u32 = 0;
    while (c < count) : (c += 1) {
        var sync: u32 = try brRead(&br, 24);
        if (sync != 0x564342) return error.BadVersion;
        var dims: u32 = try brRead(&br, 16);
        var entries: u32 = try brRead(&br, 24);

        var raw_len: [*]u8 = std.arena.alloc(arena, @intCast(usize, entries)) catch return error.OutOfMemory;
        var lengths: []u8 = raw_len[0..@intCast(usize, entries)];

        var ordered: bool = ((try brRead(&br, 1)) == 1);
        var sparse: bool = false;
        if (ordered) {
            // Ordered: initial length (5-bit + 1), then runs of
            // ilog(entries-current_entry)-bit counts of equal-length entries.
            var cur: u32 = (try brRead(&br, 5)) + 1;
            var ce: u32 = 0;
            while (ce < entries) {
                var number: u32 = try brRead(&br, ilog(entries - ce));
                var j: u32 = 0;
                while (j < number) : (j += 1) {
                    if (ce < entries) {
                        if (cur > 255) return error.BadVersion;
                        lengths[ce] = @intCast(u8, cur);
                    }
                    ce += 1;
                }
                cur += 1;
            }
        } else {
            sparse = ((try brRead(&br, 1)) == 1);
            var e: u32 = 0;
            if (sparse) {
                while (e < entries) : (e += 1) {
                    var present: u32 = try brRead(&br, 1);
                    if (present == 1) {
                        lengths[e] = @intCast(u8, (try brRead(&br, 5)) + 1);
                    } else {
                        lengths[e] = 0;
                    }
                }
            } else {
                while (e < entries) : (e += 1) {
                    lengths[e] = @intCast(u8, (try brRead(&br, 5)) + 1);
                }
            }
        }

        // Lookup tail. Type 0 has no VQ table. Types 1/2 carry the two packed
        // 32-bit floats (minimum_value / delta_value), a value-bit width, a
        // sequence flag, and lookup_values multiplicands; decodeVector (Task 2)
        // needs all of them, so they are retained. The lookup count is computed
        // in u64 so a crafted header cannot trap a u32 multiply under -fsafe.
        var lookup: u32 = try brRead(&br, 4);
        if (lookup > 2) return error.BadVersion;
        var value_bits: u32 = 0;
        var sequence_p: bool = false;
        var min_bits: u32 = 0;
        var delta_bits: u32 = 0;
        var lookup_values: u64 = 0;
        var empty_raw: [*]u8 = std.arena.alloc(arena, 0) catch return error.OutOfMemory;
        var multiplicands: []u32 = @ptrCast([*]u32, empty_raw)[0..0];
        if (lookup == 1 or lookup == 2) {
            min_bits = try brRead(&br, 32);
            delta_bits = try brRead(&br, 32);
            value_bits = (try brRead(&br, 4)) + 1;
            sequence_p = ((try brRead(&br, 1)) == 1);
            if (lookup == 1) {
                lookup_values = @intCast(u64, lookup1Values(entries, dims));
            } else {
                var e64: u64 = @intCast(u64, entries);
                var d64: u64 = @intCast(u64, dims);
                lookup_values = e64 * d64;
            }
            // Reject un-representable sizes cleanly (never a @intCast trap)
            // before allocating; a representable but huge count just exhausts
            // the arena and reports OutOfMemory.
            if (lookup_values > 0xffffffff) return error.OutOfMemory;
            var lv: usize = @intCast(usize, lookup_values);
            var mul_raw: [*]u8 = std.arena.alloc(arena, lv * @sizeOf(u32)) catch return error.OutOfMemory;
            multiplicands = @ptrCast([*]u32, mul_raw)[0..lv];
            var mi: u64 = 0;
            while (mi < lookup_values) : (mi += 1) {
                multiplicands[@intCast(usize, mi)] = try brRead(&br, value_bits);
            }
        }

        cbs[c] = Codebook{
            .dimensions = @intCast(u16, dims),
            .entries = entries,
            .ordered = ordered,
            .sparse = sparse,
            .lengths = lengths,
            .lookup_type = lookup,
            .value_bits = value_bits,
            .sequence_p = sequence_p,
            .min_bits = min_bits,
            .delta_bits = delta_bits,
            .lookup_values = @intCast(u32, lookup_values),
            .multiplicands = multiplicands,
        };

    }

    return Setup{ .codebooks = cbs[0..@intCast(usize, count)] };
}
