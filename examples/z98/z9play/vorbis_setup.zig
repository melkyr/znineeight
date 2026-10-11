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
pub const Codebook = struct {
    dimensions: u16,
    entries: u32,
    ordered: bool,
    sparse: bool,
    lengths: []u8,
};

// Parsed setup header. Task 3 grows this with floors/residues/mappings/modes.
pub const Setup = struct {
    codebooks: []Codebook,
};

// LSB-first bit reader over the setup packet tail (the bytes after the
// "\x05vorbis" signature). `nbits` is the total readable bit count; any read
// or skip past it reports Truncated.
const BitReader = struct {
    data: []const u8,
    nbits: usize,
    pos: usize,
};

fn brInit(data: []const u8) BitReader {
    return BitReader{ .data = data, .nbits = data.len * 8, .pos = 0 };
}

// Read `n` bits (n <= 32) LSB-first. Returns Truncated on a short packet.
fn brRead(br: *BitReader, n: u32) ogg.OggError!u32 {
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
fn brSkip(br: *BitReader, n: u32) ogg.OggError!void {
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

        // Lookup tail: type 0 is empty; types 1/2 carry two 32-bit floats, a
        // value-bit width, a sequence flag and lookup_values * value_bits.
        var lookup: u32 = try brRead(&br, 4);
        if (lookup == 1 or lookup == 2) {
            try brSkip(&br, 32);
            try brSkip(&br, 32);
            var value_bits: u32 = (try brRead(&br, 4)) + 1;
            _ = try brRead(&br, 1);
            var lv: u32 = 0;
            if (lookup == 1) {
                lv = lookup1Values(entries, dims);
            } else {
                lv = entries * dims;
            }
            try brSkip(&br, value_bits * lv);
        }

        cbs[c] = Codebook{
            .dimensions = @intCast(u16, dims),
            .entries = entries,
            .ordered = ordered,
            .sparse = sparse,
            .lengths = lengths,
        };
    }

    return Setup{ .codebooks = cbs[0..@intCast(usize, count)] };
}
