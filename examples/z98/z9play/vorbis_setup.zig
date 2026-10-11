// vorbis_setup.zig — Vorbis setup-header parser (z9play M1, Tasks 1-3).
//
// Parses the setup header packet (packet type 5, "\x05vorbis"): the codebook
// list (8-bit count + 1; per codebook the "BCV" sync pattern 0x564342,
// dimensions (16-bit), entries (24-bit), ordered/unordered and sparse flags,
// raw code lengths, and the type-1/2 VQ lookup tail), then the time-domain
// transform count, the floors (types 0 and 1), the residues (types 0/1/2), the
// channel mappings (coupling + submaps + mux), and the modes, ending on the
// framing bit. Everything is stored in concrete Setup structs as raw integers;
// the Huffman decode tables are built separately in codebook.zig.
//
// Byte/bit order follows the Vorbis I specification (bit packing is LSB-first
// within each byte). The lookup-type tail of each codebook (types 1/2) is
// consumed so the parser can reach the next codebook; its values are retained
// for the Task 2 decode tables.
//
// Pure Z98: free functions, no generics/@Type/@cImport, strict @intCast, no
// switch. The parser returns OggError (Truncated on a short read, BadVersion
// on a bad signature/sync or an out-of-range field, OutOfMemory when the
// caller's arena is exhausted).

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


// One floor configuration (Task 3). Floors are concrete (no unions): a floor of
// type 0 fills the `floor0_*` fields, a floor of type 1 fills the partition /
// class / X fields. The unused family stays zero / empty (arena-owned, never
// null). `subclass_books` stores the spec's read-8-minus-one values, so an
// unused slot is -1; it is indexed [class*8 + subclass].
pub const Floor = struct {
    floor_type: u16,
    order: u8,
    rate: u16,
    bark_map_size: u16,
    amplitude_bits: u8,
    amplitude_offset: u8,
    floor0_book_count: u32,
    floor0_books: []u8,
    partition_count: u32,
    partition_class: []u8,
    class_dimensions: []u8,
    class_subclasses: []u8,
    class_masterbooks: []u8,
    subclass_books: []i16,
    multiplier: u8,
    rangebits: u8,
    x_list: []u32,
};

// One residue configuration (Task 3). `cascade` has one byte per classification
// (the spec's 8-bit cascade bitmap); `books` is [classifications*8] with -1 in
// every slot the cascade does not set, else the read 8-bit codebook number.
pub const Residue = struct {
    residue_type: u16,
    begin: u32,
    end: u32,
    partition_size: u32,
    classifications: u32,
    classbook: u8,
    cascade: []u8,
    books: []i16,
};

// One channel mapping (Task 3). `coupling_magnitude`/`coupling_angle` are the
// square-polar channel pairs; `mux` is one submap index per channel (empty when
// there is a single submap); `submap_floor`/`submap_residue` name the floor and
// residue instance used by each submap.
pub const Mapping = struct {
    mapping_type: u16,
    submaps: u32,
    coupling_steps: u32,
    coupling_magnitude: []u8,
    coupling_angle: []u8,
    mux: []u8,
    submap_floor: []u8,
    submap_residue: []u8,
};

// One mode (Task 3): block size selector plus the mapping it uses. In Vorbis I
// `window_type`/`transform_type` are always 0.
// The mode struct is named `VorbisMode` (not `Mode`) because @sizeOf("Mode")
// inside this module resolves to an unrelated same-named type elsewhere in the
// program (the std_file.Mode enum, whose size is 4); that mis-sized the mode
// array and let its tail write into the next arena allocation. `Mode` remains
// as a public alias for API compatibility.
pub const VorbisMode = struct {
    blockflag: bool,
    window_type: u16,
    transform_type: u16,
    mapping: u8,
};

pub const Mode = VorbisMode;

// Parsed setup header. Task 1/2 filled `codebooks`; Task 3 adds the time-domain
// transform count and the floor/residue/mapping/mode lists. All slices are
// arena-owned.
pub const Setup = struct {
    codebooks: []Codebook,
    time_count: u32,
    floors: []Floor,
    residues: []Residue,
    mappings: []Mapping,
    modes: []VorbisMode,
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

// Parse a floor type 0 configuration (spec 6.2.1) into `f`.
fn parseFloor0(arena: *std.arena.Arena, br: *BitReader, f: *Floor) ogg.OggError!void {
    var order: u32 = try brRead(br, 8);
    var rate: u32 = try brRead(br, 16);
    var bark: u32 = try brRead(br, 16);
    var amp_bits: u32 = try brRead(br, 6);
    var amp_off: u32 = try brRead(br, 8);
    var nbooks: u32 = (try brRead(br, 4)) + 1;
    var raw_b: [*]u8 = std.arena.alloc(arena, @intCast(usize, nbooks)) catch return error.OutOfMemory;
    var books: []u8 = raw_b[0..@intCast(usize, nbooks)];
    var i: u32 = 0;
    while (i < nbooks) : (i += 1) {
        books[@intCast(usize, i)] = @intCast(u8, try brRead(br, 8));
    }
    var raw_e: [*]u8 = std.arena.alloc(arena, 0) catch return error.OutOfMemory;
    var e_u8: []u8 = raw_e[0..0];
    var e_i16: []i16 = @ptrCast([*]i16, raw_e)[0..0];
    var e_u32: []u32 = @ptrCast([*]u32, raw_e)[0..0];
    f.* = Floor{
        .floor_type = 0,
        .order = @intCast(u8, order),
        .rate = @intCast(u16, rate),
        .bark_map_size = @intCast(u16, bark),
        .amplitude_bits = @intCast(u8, amp_bits),
        .amplitude_offset = @intCast(u8, amp_off),
        .floor0_book_count = nbooks,
        .floor0_books = books,
        .partition_count = 0,
        .partition_class = e_u8,
        .class_dimensions = e_u8,
        .class_subclasses = e_u8,
        .class_masterbooks = e_u8,
        .subclass_books = e_i16,
        .multiplier = 0,
        .rangebits = 0,
        .x_list = e_u32,
    };
}

// Parse a floor type 1 configuration (spec 7.2.2) into `f`. The per-class
// metadata is read in a single pass (dimensions, subclasses, optional
// masterbook, then 2^subclasses subclass books, each stored minus one). The
// X list is capped at 65 entries and required to be unique (spec 7.2.2).
fn parseFloor1(arena: *std.arena.Arena, br: *BitReader, f: *Floor) ogg.OggError!void {
    var partitions: u32 = try brRead(br, 5);
    var raw_pc: [*]u8 = std.arena.alloc(arena, @intCast(usize, partitions)) catch return error.OutOfMemory;
    var pclass: []u8 = raw_pc[0..@intCast(usize, partitions)];
    var i: u32 = 0;
    var maxclass: i32 = -1;
    while (i < partitions) : (i += 1) {
        var v: u32 = try brRead(br, 4);
        pclass[@intCast(usize, i)] = @intCast(u8, v);
        if (@intCast(i32, v) > maxclass) maxclass = @intCast(i32, v);
    }
    var nclass: usize = 0;
    if (maxclass >= 0) nclass = @intCast(usize, maxclass + 1);
    var raw_cd: [*]u8 = std.arena.alloc(arena, nclass) catch return error.OutOfMemory;
    var raw_cs: [*]u8 = std.arena.alloc(arena, nclass) catch return error.OutOfMemory;
    var raw_cm: [*]u8 = std.arena.alloc(arena, nclass) catch return error.OutOfMemory;
    var cdim: []u8 = raw_cd[0..nclass];
    var csub: []u8 = raw_cs[0..nclass];
    var cmaster: []u8 = raw_cm[0..nclass];
    var raw_sb: [*]u8 = std.arena.alloc(arena, nclass * 8 * @sizeOf(i16)) catch return error.OutOfMemory;
    var sb: []i16 = @ptrCast([*]i16, raw_sb)[0 .. nclass * 8];
    var z: usize = 0;
    while (z < nclass * 8) : (z += 1) sb[z] = -1;
    i = 0;
    while (i < nclass) : (i += 1) {
        var d: u32 = (try brRead(br, 3)) + 1;
        var sc: u32 = try brRead(br, 2);
        cdim[i] = @intCast(u8, d);
        csub[i] = @intCast(u8, sc);
        cmaster[i] = 0;
        if (sc > 0) cmaster[i] = @intCast(u8, try brRead(br, 8));
        var nb: u32 = @intCast(u32, 1) << sc;
        var k: u32 = 0;
        while (k < nb) : (k += 1) {
            var bv: u32 = try brRead(br, 8);
            sb[@intCast(usize, i) * 8 + @intCast(usize, k)] = @intCast(i16, @intCast(i32, bv) - 1);
        }
    }
    var mult: u32 = (try brRead(br, 2)) + 1;
    var rangebits: u32 = try brRead(br, 4);
    var xcount: u32 = 2;
    i = 0;
    while (i < partitions) : (i += 1) {
        var cls: u8 = pclass[@intCast(usize, i)];
        xcount += @intCast(u32, cdim[@intCast(usize, cls)]);
    }
    if (xcount > 65) return error.BadVersion;
    var raw_x: [*]u8 = std.arena.alloc(arena, @intCast(usize, xcount) * @sizeOf(u32)) catch return error.OutOfMemory;
    var xs: []u32 = @ptrCast([*]u32, raw_x)[0..@intCast(usize, xcount)];
    xs[0] = 0;
    xs[1] = @intCast(u32, 1) << rangebits;
    var xi: u32 = 2;
    i = 0;
    while (i < partitions) : (i += 1) {
        var cls: u8 = pclass[@intCast(usize, i)];
        var cd: u8 = cdim[@intCast(usize, cls)];
        var j: u32 = 0;
        while (j < cd) : (j += 1) {
            xs[@intCast(usize, xi)] = try brRead(br, rangebits);
            xi += 1;
        }
    }
    var a: u32 = 0;
    while (a < xcount) : (a += 1) {
        var b: u32 = a + 1;
        while (b < xcount) : (b += 1) {
            if (xs[@intCast(usize, a)] == xs[@intCast(usize, b)]) return error.BadVersion;
        }
    }
    var raw_e: [*]u8 = std.arena.alloc(arena, 0) catch return error.OutOfMemory;
    var e_u8: []u8 = raw_e[0..0];
    f.* = Floor{
        .floor_type = 1,
        .order = 0,
        .rate = 0,
        .bark_map_size = 0,
        .amplitude_bits = 0,
        .amplitude_offset = 0,
        .floor0_book_count = 0,
        .floor0_books = e_u8,
        .partition_count = partitions,
        .partition_class = pclass,
        .class_dimensions = cdim,
        .class_subclasses = csub,
        .class_masterbooks = cmaster,
        .subclass_books = sb,
        .multiplier = @intCast(u8, mult),
        .rangebits = @intCast(u8, rangebits),
        .x_list = xs,
    };
}

// Parse one residue configuration (spec 8.6.1) into `r`. `rtype` is the already
// read 16-bit residue type (0, 1 or 2); all three share this header layout.
fn parseResidue(arena: *std.arena.Arena, br: *BitReader, r: *Residue, rtype: u16) ogg.OggError!void {
    var begin: u32 = try brRead(br, 24);
    var end: u32 = try brRead(br, 24);
    var psize: u32 = (try brRead(br, 24)) + 1;
    var classes: u32 = (try brRead(br, 6)) + 1;
    var classbook: u32 = try brRead(br, 8);
    var raw_cas: [*]u8 = std.arena.alloc(arena, @intCast(usize, classes)) catch return error.OutOfMemory;
    var cas: []u8 = raw_cas[0..@intCast(usize, classes)];
    var i: u32 = 0;
    while (i < classes) : (i += 1) {
        var low: u32 = try brRead(br, 3);
        var bitflag: u32 = try brRead(br, 1);
        var high: u32 = 0;
        if (bitflag != 0) high = try brRead(br, 5);
        cas[@intCast(usize, i)] = @intCast(u8, high * 8 + low);
    }
    var raw_bk: [*]u8 = std.arena.alloc(arena, @intCast(usize, classes) * 8 * @sizeOf(i16)) catch return error.OutOfMemory;
    var bk: []i16 = @ptrCast([*]i16, raw_bk)[0 .. @intCast(usize, classes) * 8];
    var z: usize = 0;
    while (z < @intCast(usize, classes) * 8) : (z += 1) bk[z] = -1;
    i = 0;
    while (i < classes) : (i += 1) {
        var j: u32 = 0;
        while (j < 8) : (j += 1) {
            var mask: u32 = @intCast(u32, 1) << j;
            if ((@intCast(u32, cas[@intCast(usize, i)]) & mask) != 0) {
                var bv: u32 = try brRead(br, 8);
                bk[@intCast(usize, i) * 8 + @intCast(usize, j)] = @intCast(i16, bv);
            }
        }
    }
    r.* = Residue{
        .residue_type = rtype,
        .begin = begin,
        .end = end,
        .partition_size = psize,
        .classifications = classes,
        .classbook = @intCast(u8, classbook),
        .cascade = cas,
        .books = bk,
    };
}

// Parse one channel mapping (spec 4.2.4, mapping type 0) into `m`. `channels`
// sizes the mux list and the coupling channel-number width; `floor_count` /
// `residue_count` bound the submap floor/residue indices.
fn parseMapping(arena: *std.arena.Arena, br: *BitReader, m: *Mapping, channels: u32, floor_count: u32, residue_count: u32) ogg.OggError!void {
    var mtype: u32 = try brRead(br, 16);
    if (mtype != 0) return error.BadVersion;
    var submaps: u32 = 1;
    if ((try brRead(br, 1)) != 0) submaps = (try brRead(br, 4)) + 1;
    var steps: u32 = 0;
    var raw_mag: [*]u8 = std.arena.alloc(arena, 0) catch return error.OutOfMemory;
    var raw_ang: [*]u8 = std.arena.alloc(arena, 0) catch return error.OutOfMemory;
    var mag: []u8 = raw_mag[0..0];
    var ang: []u8 = raw_ang[0..0];
    if ((try brRead(br, 1)) != 0) {
        steps = (try brRead(br, 8)) + 1;
        var rm: [*]u8 = std.arena.alloc(arena, @intCast(usize, steps)) catch return error.OutOfMemory;
        var ra: [*]u8 = std.arena.alloc(arena, @intCast(usize, steps)) catch return error.OutOfMemory;
        mag = rm[0..@intCast(usize, steps)];
        ang = ra[0..@intCast(usize, steps)];
        var cbits: u32 = ilog(channels - 1);
        var i: u32 = 0;
        while (i < steps) : (i += 1) {
            var mv: u32 = try brRead(br, cbits);
            var av: u32 = try brRead(br, cbits);
            if (mv >= channels or av >= channels or mv == av) return error.BadVersion;
            mag[@intCast(usize, i)] = @intCast(u8, mv);
            ang[@intCast(usize, i)] = @intCast(u8, av);
        }
    }
    if ((try brRead(br, 2)) != 0) return error.BadVersion;
    var raw_mux: [*]u8 = std.arena.alloc(arena, 0) catch return error.OutOfMemory;
    var mux: []u8 = raw_mux[0..0];
    if (submaps > 1) {
        var rx: [*]u8 = std.arena.alloc(arena, @intCast(usize, channels)) catch return error.OutOfMemory;
        mux = rx[0..@intCast(usize, channels)];
        var j: u32 = 0;
        while (j < channels) : (j += 1) {
            var v: u32 = try brRead(br, 4);
            if (v >= submaps) return error.BadVersion;
            mux[@intCast(usize, j)] = @intCast(u8, v);
        }
    }
    var raw_sf: [*]u8 = std.arena.alloc(arena, @intCast(usize, submaps)) catch return error.OutOfMemory;
    var raw_sr: [*]u8 = std.arena.alloc(arena, @intCast(usize, submaps)) catch return error.OutOfMemory;
    var sf: []u8 = raw_sf[0..@intCast(usize, submaps)];
    var sr: []u8 = raw_sr[0..@intCast(usize, submaps)];
    var k: u32 = 0;
    while (k < submaps) : (k += 1) {
        _ = try brRead(br, 8);
        var fl: u32 = try brRead(br, 8);
        if (fl >= floor_count) return error.BadVersion;
        var re: u32 = try brRead(br, 8);
        if (re >= residue_count) return error.BadVersion;
        sf[@intCast(usize, k)] = @intCast(u8, fl);
        sr[@intCast(usize, k)] = @intCast(u8, re);
    }
    m.* = Mapping{
        .mapping_type = 0,
        .submaps = submaps,
        .coupling_steps = steps,
        .coupling_magnitude = mag,
        .coupling_angle = ang,
        .mux = mux,
        .submap_floor = sf,
        .submap_residue = sr,
    };
}

// Parse one mode (spec 4.2.4) into `m`. Vorbis I requires both the window type
// and the transform type to be 0.
fn parseMode(br: *BitReader, m: *VorbisMode) ogg.OggError!void {
    var bf: u32 = try brRead(br, 1);
    var wt: u32 = try brRead(br, 16);
    var tt: u32 = try brRead(br, 16);
    var mp: u32 = try brRead(br, 8);
    if (wt != 0 or tt != 0) return error.BadVersion;
    m.* = VorbisMode{
        .blockflag = (bf == 1),
        .window_type = @intCast(u16, wt),
        .transform_type = @intCast(u16, tt),
        .mapping = @intCast(u8, mp),
    };
}

// Parse the Vorbis setup header packet `packet` (type 5, "\x05vorbis"). Reads
// the codebook count and, for each codebook, dimensions/entries/flags/lengths,
// skipping the lookup tail; then the time-domain transform count, floors,
// residues, mappings (sized by `channels`) and modes, ending on the framing
// bit. All returned storage is arena-owned.
pub fn parseSetup(arena: *std.arena.Arena, packet: []const u8, channels: u32) ogg.OggError!Setup {
    if (packet.len < 7) return error.Truncated;
    if (packet[0] != 5) return error.BadVersion;
    if (channels < 1) return error.BadVersion;
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

    // --- time-domain transforms (placeholders in Vorbis I) ---
    var time_count: u32 = (try brRead(&br, 6)) + 1;
    var ti: u32 = 0;
    while (ti < time_count) : (ti += 1) {
        if ((try brRead(&br, 16)) != 0) return error.BadVersion;
    }

    // --- floors ---
    var floor_count: u32 = (try brRead(&br, 6)) + 1;
    var raw_fl: [*]u8 = std.arena.alloc(arena, @intCast(usize, floor_count) * @sizeOf(Floor)) catch return error.OutOfMemory;
    var floors: [*]Floor = @ptrCast([*]Floor, raw_fl);
    var fi: u32 = 0;
    while (fi < floor_count) : (fi += 1) {
        var ftype: u32 = try brRead(&br, 16);
        if (ftype == 0) {
            try parseFloor0(arena, &br, &floors[fi]);
        } else if (ftype == 1) {
            try parseFloor1(arena, &br, &floors[fi]);
        } else {
            return error.BadVersion;
        }
    }

    // --- residues ---
    var residue_count: u32 = (try brRead(&br, 6)) + 1;
    var raw_rs: [*]u8 = std.arena.alloc(arena, @intCast(usize, residue_count) * @sizeOf(Residue)) catch return error.OutOfMemory;
    var residues: [*]Residue = @ptrCast([*]Residue, raw_rs);
    var ri: u32 = 0;
    while (ri < residue_count) : (ri += 1) {
        var rtype: u32 = try brRead(&br, 16);
        if (rtype > 2) return error.BadVersion;
        try parseResidue(arena, &br, &residues[ri], @intCast(u16, rtype));
    }

    // --- mappings ---
    var mapping_count: u32 = (try brRead(&br, 6)) + 1;
    var raw_mp: [*]u8 = std.arena.alloc(arena, @intCast(usize, mapping_count) * @sizeOf(Mapping)) catch return error.OutOfMemory;
    var mappings: [*]Mapping = @ptrCast([*]Mapping, raw_mp);
    var mi: u32 = 0;
    while (mi < mapping_count) : (mi += 1) {
        try parseMapping(arena, &br, &mappings[mi], channels, floor_count, residue_count);
    }

    // --- modes, then the framing bit ---
    var mode_count: u32 = (try brRead(&br, 6)) + 1;
    var raw_mo: [*]u8 = std.arena.alloc(arena, @intCast(usize, mode_count) * @sizeOf(VorbisMode)) catch return error.OutOfMemory;
    var modes: [*]VorbisMode = @ptrCast([*]VorbisMode, raw_mo);
    var moi: u32 = 0;
    while (moi < mode_count) : (moi += 1) {
        try parseMode(&br, &modes[moi]);
        if (@intCast(u32, modes[moi].mapping) >= mapping_count) return error.BadVersion;
    }
    if ((try brRead(&br, 1)) != 1) return error.BadVersion;

    return Setup{
        .codebooks = cbs[0..@intCast(usize, count)],
        .time_count = time_count,
        .floors = floors[0..@intCast(usize, floor_count)],
        .residues = residues[0..@intCast(usize, residue_count)],
        .mappings = mappings[0..@intCast(usize, mapping_count)],
        .modes = modes[0..@intCast(usize, mode_count)],
    };
}
