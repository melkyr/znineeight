// setup_test.zig — deterministic unit harness for the z9play Vorbis setup
// header skeleton (vorbis_setup.parseSetup).
//
// Asserts, for the committed fixtures, the codebook count and the first
// codebook's dimensions/entries, plus the ordered and lookup-type-2 codebook
// paths (which the fixtures do not exercise).
//
// Expected values were derived INDEPENDENTLY of vorbis_setup.zig by a small
// python3 bit-reader over packet index 2 (the "\x05vorbis" setup packet) of
// each fixture, implementing the Vorbis I codebook decode (spec 3.2.1) with
// LSB-first bit order and skipping the lookup-type tail exactly as the spec
// prescribes:
//   sine_stereo_44100.ogg -> count 38, cb0 dims 1 entries 64
//   sine_mono_44100.ogg   -> count 35, cb0 dims 1 entries 64
//   sine_stereo_48000.ogg -> count 38, cb0 dims 1 entries 64
//   tagged_unicode.ogg    -> count 38, cb0 dims 1 entries 64
//   short.ogg             -> count 35, cb0 dims 1 entries 64
// The python reader parses all codebooks to completion (every "BCV" sync
// pattern re-verified), so the counts are the whole codebook list, not a
// prefix. (ogginfo -v does not dump codebooks, so it could not be used.)
//
// The two synthetic packets below were emitted by an independent python
// bit-writer; their bytes are embedded verbatim:
//   pOrdered  -> 1 codebook, ordered, dims 4, entries 3, lengths [2,2,3]
//   pLookup2  -> 2 codebooks: cb0 unordered dims 1 entries 2 with lookup
//                type 2, cb1 unordered dims 7 entries 5; asserts the
//                lookup-2 skip lands cb1's "BCV" sync on the right bit.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/setup_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const vs = @import("../vorbis_setup.zig");
const cbk = @import("../codebook.zig");
const vi = @import("../vorbis_info.zig");


// Backing store for the read/reassembly/parse arena; module-global so it does
// not sit on the 32-bit stack. 4 MiB is far above these fixtures' needs.
var arena_buf: [4 * 1024 * 1024]u8 = undefined;
// A separate backing store for the per-fixture codebook round-trip arena, so
// those parses cannot clobber the main arena's synthetic-parse results.
var cb_arena_buf: [4 * 1024 * 1024]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "setup_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// True when parseSetup rejects `pkt` (the malformed cases).
fn setupFails(arena: *std.arena.Arena, pkt: []const u8) bool {
    var s: vs.Setup = vs.parseSetup(arena, pkt, 1) catch return true;
    _ = s;
    return false;
}


// True when parseSetup rejects `pkt` specifically with OutOfMemory (used by the
// crafted overflow-header test, so a truncated-packet error cannot pass it).
fn setupOutOfMemory(arena: *std.arena.Arena, pkt: []const u8) bool {
    var s: vs.Setup = vs.parseSetup(arena, pkt, 1) catch |err| return err == error.OutOfMemory;
    _ = s;
    return false;
}



// Reassemble `path`, parse its setup packet (index 2), and assert the codebook
// count and the first codebook's dimensions/entries. A fresh arena per fixture
// keeps one parse's allocations from accumulating on the next.
fn checkFixture(path: []const u8, want_count: usize, want_dims: u16, want_entries: u32) void {
    var arena = std.arena.init(arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture");
        return;
    };
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble failed");
        return;
    };
    if (packets.len < 3) {
        fail("fewer than 3 packets (no setup header)");
        return;
    }
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("cannot parse identification header");
        return;
    };
    var setup: vs.Setup = vs.parseSetup(&arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
        fail("parseSetup failed");
        return;
    };
    if (setup.codebooks.len != want_count) {
        fail("codebook count mismatch");
        return;
    }
    if (setup.codebooks[0].dimensions != want_dims) {
        fail("cb0 dimensions mismatch");
        return;
    }
    if (setup.codebooks[0].entries != want_entries) {
        fail("cb0 entries mismatch");
        return;
    }
}
fn approxEq(a: f64, b: f64) bool {
    var d: f64 = a - b;
    if (d < 0.0) d = -d;
    return d < 0.000001;
}

fn checkVec2(v: []f64, a: f64, b: f64) void {
    if (v.len != 2) {
        fail("codebook vector dimension != 2");
        return;
    }
    if (!approxEq(v[0], a)) fail("codebook vector[0] mismatch");
    if (!approxEq(v[1], b)) fail("codebook vector[1] mismatch");
}

// True when buildDecodeTable rejects `cb` (a malformed Huffman tree).
fn buildFails(arena: *std.arena.Arena, cb: vs.Codebook) bool {
    var dt = cbk.buildDecodeTable(arena, cb) catch return true;
    _ = dt;
    return false;
}

// Scratch + cursor for the crafted-header negative test (LSB-first bits).
var pk_buf: [64 * 1024]u8 = undefined;
var pk_pos: usize = 0;

// Write `n` bits of `v` LSB-first (Vorbis bitpacking convention).
fn wrBits(n: u32, v: u32) void {
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        var sh: u32 = k;
        var bit: u32 = (v >> sh) & 1;
        if (bit == 1) {
            var shb: u32 = @intCast(u32, pk_pos & 7);
            var b: u32 = @intCast(u32, pk_buf[pk_pos >> 3]);
            b = b | (bit << shb);
            pk_buf[pk_pos >> 3] = @intCast(u8, b & 0xff);
        }
        pk_pos += 1;
    }
}

// Craft a one-codebook setup packet with lookup type 2 whose
// entries*dimensions product overflows u32 (65538 * 65535 > 0xffffffff). The
// parser must reject it before allocating, without a -fsafe overflow trap.
fn buildOverflowPacket() []const u8 {
    var z: usize = 0;
    while (z < 64 * 1024) : (z += 1) {
        pk_buf[z] = 0;
    }
    pk_pos = 0;
    wrBits(8, 5);
    wrBits(8, 'v');
    wrBits(8, 'o');
    wrBits(8, 'r');
    wrBits(8, 'b');
    wrBits(8, 'i');
    wrBits(8, 's');
    wrBits(8, 0); // codebook_count - 1
    wrBits(24, 0x564342); // sync
    wrBits(16, 65535); // dimensions
    wrBits(24, 65538); // entries
    wrBits(1, 0); // ordered
    wrBits(1, 0); // sparse
    var e: u32 = 0;
    while (e < 65538) : (e += 1) {
        wrBits(5, 0); // length 1
    }
    wrBits(4, 2); // lookup type 2
    wrBits(32, 0); // minimum_value
    wrBits(32, 0); // delta_value
    wrBits(4, 3); // value_bits - 1 => 4
    wrBits(1, 0); // sequence_p
    var nbytes: usize = (pk_pos + 7) / 8;
    return pk_buf[0..nbytes];
}

var enc_pos: usize = 0;

// encode the canonical codeword `code` of length `len` MSB-first into the
// LSB-first bit stream `buf` (Vorbis spec 3.2.1: leftmost codeword bit = MSb).
fn encCode(buf: []u8, code: u32, len: u32) void {
    var k: u32 = 0;
    while (k < len) : (k += 1) {
        var sh: u32 = len - 1 - k;
        var bit: u32 = (code >> sh) & 1;
        if (bit == 1) {
            var shift: u32 = @intCast(u32, enc_pos & 7);
            var b: u32 = @intCast(u32, buf[enc_pos >> 3]);
            b = b | (bit << shift);
            buf[enc_pos >> 3] = @intCast(u8, b & 0xff);
        }
        enc_pos += 1;
    }
}

// Build one codebook decode table and round-trip each used entry (encode its
// canonical codeword into a scratch stream, then decode it back); returns the
// number of entries exercised.
fn roundTripCodebook(arena: *std.arena.Arena, cb: vs.Codebook) u32 {
    var dt: cbk.DecodeTable = cbk.buildDecodeTable(arena, cb) catch {
        fail("buildDecodeTable failed");
        return 0;
    };
    var used: u32 = 0;
    var total_bits: u64 = 0;
    var i: u32 = 0;
    while (i < cb.entries) : (i += 1) {
        var L: u8 = cb.lengths[@intCast(usize, i)];
        if (L == 0) continue;
        used += 1;
        total_bits += @intCast(u64, L);
    }
    if (used == 0) return 0;
    var nbytes: usize = @intCast(usize, (total_bits + 7) / 8);
    if (nbytes == 0) nbytes = 1;
    var raw: [*]u8 = std.arena.alloc(arena, nbytes) catch {
        fail("codeword buffer alloc failed");
        return 0;
    };
    var buf: []u8 = raw[0..nbytes];
    var z: usize = 0;
    while (z < nbytes) : (z += 1) {
        buf[z] = 0;
    }
    enc_pos = 0;
    i = 0;
    while (i < cb.entries) : (i += 1) {
        var L: u8 = cb.lengths[@intCast(usize, i)];
        if (L == 0) continue;
        encCode(buf, dt.codes[@intCast(usize, i)], @intCast(u32, L));
    }
    var br: vs.BitReader = vs.brInit(buf);
    i = 0;
    while (i < cb.entries) : (i += 1) {
        var L: u8 = cb.lengths[@intCast(usize, i)];
        if (L == 0) continue;
        var got: i32 = cbk.decodeScalar(&dt, &br);
        if (got != @intCast(i32, i)) {
            fail("canonical Huffman round-trip mismatch");
            return 0;
        }
    }
    return used;
}

// Reassemble `path`, parse its setup packet, and round-trip every codebook.
// A fresh arena per fixture keeps one codebook's allocations from accumulating.
fn roundTripFixture(path: []const u8) u32 {
    var arena = std.arena.init(cb_arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture (codebook)");
        return 0;
    };
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble failed (codebook)");
        return 0;
    };
    if (packets.len < 3) {
        fail("no setup packet (codebook)");
        return 0;
    }
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("cannot parse identification header (codebook)");
        return 0;
    };
    var setup: vs.Setup = vs.parseSetup(&arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
        fail("parseSetup failed (codebook)");
        return 0;
    };
    var used: u32 = 0;
    var c: usize = 0;
    while (c < setup.codebooks.len) : (c += 1) {
        used += roundTripCodebook(&arena, setup.codebooks[c]);
    }
    return used;
}

// Reassemble `path`, parse its setup packet, and assert the Task 3 structures
// (floor/residue/mapping/mode) against independently derived expectations.
// Every fixture shares: one time transform, two floor-1s, two residues, two
// mappings, two modes with blockflags [0,1] and framing 1. `want_res_type` is
// the shared residue type; `want_coupling` the per-mapping coupling-step count;
// `want_end0`/`want_end1` the two residue band ends.
fn checkFixtureSetup(path: []const u8, want_res_type: u16, want_coupling: u32, want_end0: u32, want_end1: u32) void {
    var arena = std.arena.init(arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture (setup)");
        return;
    };
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble failed (setup)");
        return;
    };
    if (packets.len < 3) {
        fail("no setup packet (setup)");
        return;
    }
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("cannot parse identification header (setup)");
        return;
    };
    var s: vs.Setup = vs.parseSetup(&arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
        fail("parseSetup failed (setup)");
        return;
    };
    if (s.time_count != 1) {
        fail("time_count != 1");
        return;
    }
    if (s.floors.len != 2) {
        fail("floor count != 2");
        return;
    }
    if (s.floors[0].floor_type != 1 or s.floors[1].floor_type != 1) {
        fail("fixture floor type != 1");
        return;
    }
    if (s.floors[0].multiplier != 4 or s.floors[1].multiplier != 2) {
        fail("floor multiplier mismatch");
        return;
    }
    if (s.floors[0].rangebits != 7 or s.floors[1].rangebits != 10) {
        fail("floor rangebits mismatch");
        return;
    }
    if (s.floors[0].partition_count != 2 or s.floors[1].partition_count != 8) {
        fail("floor partition count mismatch");
        return;
    }
    if (s.residues.len != 2) {
        fail("residue count != 2");
        return;
    }
    if (s.residues[0].residue_type != want_res_type or s.residues[1].residue_type != want_res_type) {
        fail("residue type mismatch");
        return;
    }
    if (s.residues[0].partition_size != 16 or s.residues[1].partition_size != 32) {
        fail("residue partition_size mismatch");
        return;
    }
    if (s.residues[0].end != want_end0 or s.residues[1].end != want_end1) {
        fail("residue end mismatch");
        return;
    }
    if (s.mappings.len != 2) {
        fail("mapping count != 2");
        return;
    }
    if (s.mappings[0].submaps != 1 or s.mappings[1].submaps != 1) {
        fail("mapping submaps != 1");
        return;
    }
    if (s.mappings[0].coupling_steps != want_coupling or s.mappings[1].coupling_steps != want_coupling) {
        fail("mapping coupling_steps mismatch");
        return;
    }
    if (want_coupling == 1) {
        if (s.mappings[0].coupling_magnitude[0] != 0 or s.mappings[0].coupling_angle[0] != 1) {
            fail("mapping coupling pair mismatch");
            return;
        }
    }
    if (s.mappings[0].submap_floor[0] != 0 or s.mappings[1].submap_floor[0] != 1) {
        fail("mapping submap floor mismatch");
        return;
    }
    if (s.mappings[0].submap_residue[0] != 0 or s.mappings[1].submap_residue[0] != 1) {
        fail("mapping submap residue mismatch");
        return;
    }
    if (s.modes.len != 2) {
        fail("mode count != 2");
        return;
    }
    if (s.modes[0].blockflag) {
        fail("mode[0].blockflag set");
        return;
    }
    if (!s.modes[1].blockflag) {
        fail("mode[1].blockflag clear");
        return;
    }
}


pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    var arena = std.arena.init(arena_buf[0..]);

    // --- committed fixtures: codebook count + cb0 dimensions/entries. ---
    var f_stereo: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
    var f_mono: []const u8 = "examples/z98/z9play/testdata/sine_mono_44100.ogg";
    var f_48000: []const u8 = "examples/z98/z9play/testdata/sine_stereo_48000.ogg";
    var f_tagged: []const u8 = "examples/z98/z9play/testdata/tagged_unicode.ogg";
    var f_short: []const u8 = "examples/z98/z9play/testdata/short.ogg";
    checkFixture(f_stereo, 38, 1, 64);
    checkFixture(f_mono, 35, 1, 64);
    checkFixture(f_48000, 38, 1, 64);
    checkFixture(f_tagged, 38, 1, 64);
    checkFixture(f_short, 35, 1, 64);

    // --- committed fixtures: Task 3 floors/residues/mappings/modes. ---
    // Expected values derived independently of vorbis_setup.zig by a python3
    // LSB-first setup-header reader (spec 4.2.4 / 6.2.1 / 7.2.2 / 8.6.1) over
    // packet index 2 of each fixture; cross-checked against libvorbis
    // res0_unpack / floor1_unpack / mapping0_unpack and spec errata.
    //   mono (sine_mono_44100, short): residue type 1, no coupling,
    //     residue ends 112 / 800.
    //   stereo (sine_stereo_44100, sine_stereo_48000, tagged_unicode):
    //     residue type 2, 1 coupling step (0,1), residue ends 208 / 1600
    //     (48000: 192 / 1472).
    checkFixtureSetup(f_mono, 1, 0, 112, 800);
    checkFixtureSetup(f_short, 1, 0, 112, 800);
    checkFixtureSetup(f_stereo, 2, 1, 208, 1600);
    checkFixtureSetup(f_tagged, 2, 1, 208, 1600);
    checkFixtureSetup(f_48000, 2, 1, 192, 1472);

    // --- synthetic: ordered codebook (no fixture has one). ---
    var p_ordered: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x04\x00\x03\x00\x00\x83\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10";
    var so: vs.Setup = vs.parseSetup(&arena, p_ordered, 1) catch {
        fail("synthetic ordered parse failed");
        return;
    };
    if (so.codebooks.len != 1) fail("ordered: count != 1");
    if (so.codebooks[0].dimensions != 4) fail("ordered: dims != 4");
    if (so.codebooks[0].entries != 3) fail("ordered: entries != 3");
    if (!so.codebooks[0].ordered) fail("ordered: flag not set");
    if (so.codebooks[0].lengths.len != 3) fail("ordered: lengths len != 3");
    if (so.codebooks[0].lengths[0] != 2) fail("ordered: lengths[0] != 2");
    if (so.codebooks[0].lengths[2] != 3) fail("ordered: lengths[2] != 3");

    // --- synthetic: lookup type 2 followed by a second codebook. ---
    var p_lookup2: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x01\x42\x43\x56\x01\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x03\x40\x68\xc8\xea\x00\xa0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08";
    var sl: vs.Setup = vs.parseSetup(&arena, p_lookup2, 1) catch {
        fail("synthetic lookup2 parse failed");
        return;
    };
    if (sl.codebooks.len != 2) fail("lookup2: count != 2");
    if (sl.codebooks[0].dimensions != 1) fail("lookup2: cb0 dims != 1");
    if (sl.codebooks[0].entries != 2) fail("lookup2: cb0 entries != 2");
    if (sl.codebooks[1].dimensions != 7) fail("lookup2: cb1 dims != 7");
    if (sl.codebooks[1].entries != 5) fail("lookup2: cb1 entries != 5");

    // --- malformed cases are clean errors, not crashes. ---
    var bad_type: []const u8 = "\x01vorbis\x00\x42\x43\x56";
    if (!setupFails(&arena, bad_type)) fail("accepted wrong packet type");
    var short_hdr: []const u8 = "\x05vorbis";
    if (!setupFails(&arena, short_hdr)) fail("accepted 7-byte setup packet");
    var bad_sync: []const u8 = "\x05vorbis\x00\x00\x00\x00";
    if (!setupFails(&arena, bad_sync)) fail("accepted bad codebook sync");
    // --- codebook construction (Task 2) -------------------------------------
    // (a) canonical codeword assignment vs the spec 3.2.1 worked example:
    //     lengths [2,4,4,4,4,2,3,3] -> codes [0,4,5,6,7,2,6,7].
    var ex_raw: [*]u8 = std.arena.alloc(&arena, 8) catch {
        fail("spec example: alloc failed");
        return;
    };
    var ex_lens: []u8 = ex_raw[0..8];
    ex_lens[0] = 2;
    ex_lens[1] = 4;
    ex_lens[2] = 4;
    ex_lens[3] = 4;
    ex_lens[4] = 4;
    ex_lens[5] = 2;
    ex_lens[6] = 3;
    ex_lens[7] = 3;
    var ex_mraw: [*]u8 = std.arena.alloc(&arena, 0) catch {
        fail("spec example: alloc failed");
        return;
    };
    var ex_mult: []u32 = @ptrCast([*]u32, ex_mraw)[0..0];
    var ex_cb: vs.Codebook = vs.Codebook{
        .dimensions = 1,
        .entries = 8,
        .ordered = false,
        .sparse = false,
        .lengths = ex_lens,
        .lookup_type = 0,
        .value_bits = 0,
        .sequence_p = false,
        .min_bits = 0,
        .delta_bits = 0,
        .lookup_values = 0,
        .multiplicands = ex_mult,
    };
    var ex_dt: cbk.DecodeTable = cbk.buildDecodeTable(&arena, ex_cb) catch {
        fail("spec example: buildDecodeTable failed");
        return;
    };
    var ex_want: [8]u32 = [8]u32{ 0, 4, 5, 6, 7, 2, 6, 7 };
    var eq: usize = 0;
    while (eq < 8) : (eq += 1) {
        if (ex_dt.codes[eq] != ex_want[eq]) fail("spec example: canonical codeword mismatch");
    }

    // (b) canonical Huffman round-trip (encode -> decode) for every codebook
    //     of every committed fixture.
    var rt_total: u32 = 0;
    rt_total += roundTripFixture(f_stereo);
    rt_total += roundTripFixture(f_mono);
    rt_total += roundTripFixture(f_48000);
    rt_total += roundTripFixture(f_tagged);
    rt_total += roundTripFixture(f_short);
    if (rt_total == 0) fail("fixture codebook round-trip used no entries");

    // (c) malformed Huffman trees are rejected: the synthetic ordered book has
    //     lengths [2,2,3] (underspecified) and the lookup-2 second book has
    //     five length-1 codewords (overspecified); the first lookup-2 book
    //     ([1,1]) is a valid tree and round-trips.
    if (!buildFails(&arena, so.codebooks[0])) fail("underspecified ordered codebook was accepted");
    if (!buildFails(&arena, sl.codebooks[1])) fail("overspecified lookup2 codebook was accepted");
    var rt_l2a: u32 = roundTripCodebook(&arena, sl.codebooks[0]);
    if (rt_l2a != 2) fail("lookup2 cb0 round-trip used != 2");


    // (d) lookup type 1 VQ vector unpack (fixtures are all lookup 0).
    //     synth: dims 2, entries 4 (all len 2), lookup 1, min 0, delta 1,
    //     multiplicands [5,9] -> entry e = [m[e%2], m[(e/2)%2]].
    var p_type1: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x02\x00\x04\x00\x00\x84\x10\x42\x00\x00\x00\x00\x04\x00\x00\x8a\x8d\x4a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40";
    var s1: vs.Setup = vs.parseSetup(&arena, p_type1, 1) catch {
        fail("type1: parseSetup failed");
        return;
    };
    if (s1.codebooks.len != 1) fail("type1: count != 1");
    var cb1: vs.Codebook = s1.codebooks[0];
    if (cb1.lookup_type != 1) fail("type1: lookup_type != 1");
    if (cb1.value_bits != 4) fail("type1: value_bits != 4");
    if (cb1.sequence_p) fail("type1: sequence_p set");
    if (cb1.lookup_values != 2) fail("type1: lookup_values != 2");
    if (cb1.multiplicands.len != 2) fail("type1: multiplicands len != 2");
    if (cb1.multiplicands[0] != 5) fail("type1: multiplicands[0] != 5");
    if (cb1.multiplicands[1] != 9) fail("type1: multiplicands[1] != 9");
    var dt1: cbk.DecodeTable = cbk.buildDecodeTable(&arena, cb1) catch {
        fail("type1: buildDecodeTable failed");
        return;
    };
    var vbuf: [4]u8 = [4]u8{ 0, 0, 0, 0 };
    enc_pos = 0;
    encCode(vbuf[0..], dt1.codes[3], 2);
    var vbr: vs.BitReader = vs.brInit(vbuf[0..]);
    var vec3: []f64 = cbk.decodeVector(&arena, &dt1, &vbr) catch {
        fail("type1: decodeVector failed");
        return;
    };
    checkVec2(vec3, 9.0, 9.0);
    var v0: []f64 = cbk.entryToVector(&arena, &dt1, 0) catch {
        fail("type1: entryToVector(0) failed");
        return;
    };
    checkVec2(v0, 5.0, 5.0);
    var v1: []f64 = cbk.entryToVector(&arena, &dt1, 1) catch {
        fail("type1: entryToVector(1) failed");
        return;
    };
    checkVec2(v1, 9.0, 5.0);
    var v2: []f64 = cbk.entryToVector(&arena, &dt1, 2) catch {
        fail("type1: entryToVector(2) failed");
        return;
    };
    checkVec2(v2, 5.0, 9.0);

    // (e) lookup type 2 sequence VQ vector unpack.
    //     synth: dims 2, entries 2 (all len 1), lookup 2, min 0, delta 1,
    //     sequence_p set, multiplicands [1,2,3,4] -> entry 0 [1,3], 1 [3,7].
    var p_type2: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x02\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x01\x00\x80\x62\x33\x64\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10";
    var s2: vs.Setup = vs.parseSetup(&arena, p_type2, 1) catch {
        fail("type2: parseSetup failed");
        return;
    };
    if (s2.codebooks.len != 1) fail("type2: count != 1");
    var cb2: vs.Codebook = s2.codebooks[0];
    if (cb2.lookup_type != 2) fail("type2: lookup_type != 2");
    if (!cb2.sequence_p) fail("type2: sequence_p not set");
    if (cb2.lookup_values != 4) fail("type2: lookup_values != 4");
    var dt2: cbk.DecodeTable = cbk.buildDecodeTable(&arena, cb2) catch {
        fail("type2: buildDecodeTable failed");
        return;
    };
    var g0: []f64 = cbk.entryToVector(&arena, &dt2, 0) catch {
        fail("type2: entryToVector(0) failed");
        return;
    };
    checkVec2(g0, 1.0, 3.0);
    var g1: []f64 = cbk.entryToVector(&arena, &dt2, 1) catch {
        fail("type2: entryToVector(1) failed");
        return;
    };
    checkVec2(g1, 3.0, 7.0);

    // A crafted lookup-type-2 header whose entries*dimensions overflows u32
    // must be a clean error, never a -fsafe trap (Task 2 amendment).
    if (!setupOutOfMemory(&arena, buildOverflowPacket())) fail("overflow lookup-2 header was not rejected as OutOfMemory");

    // --- synthetic Task 3: floor type 0 + residue type 0 (no fixture uses
    //     either; fixtures are floor 1 / residue 1 or 2). The packet was
    //     emitted by an independent python3 LSB-first bit-writer. ---
    var p_floor0: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x01\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x80\x02\x32\x00\x64\x00\xe3\x20\x00\x00\x00\x00\x80\x00\x00\x00\x01\x00\x00\x01\x00\x80\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40";
    var sf0: vs.Setup = vs.parseSetup(&arena, p_floor0, 1) catch {
        fail("floor0: parseSetup failed");
        return;
    };
    if (sf0.floors.len != 1) fail("floor0: floor count != 1");
    if (sf0.floors[0].floor_type != 0) fail("floor0: type != 0");
    if (sf0.floors[0].order != 5) fail("floor0: order != 5");
    if (sf0.floors[0].rate != 100) fail("floor0: rate != 100");
    if (sf0.floors[0].bark_map_size != 200) fail("floor0: bark_map_size != 200");
    if (sf0.floors[0].amplitude_bits != 6) fail("floor0: amplitude_bits != 6");
    if (sf0.floors[0].amplitude_offset != 7) fail("floor0: amplitude_offset != 7");
    if (sf0.floors[0].floor0_book_count != 2) fail("floor0: book_count != 2");
    if (sf0.floors[0].floor0_books[0] != 0) fail("floor0: books[0] != 0");
    if (sf0.floors[0].floor0_books[1] != 0) fail("floor0: books[1] != 0");
    if (sf0.residues.len != 1) fail("floor0: residue count != 1");
    if (sf0.residues[0].residue_type != 0) fail("floor0: residue type != 0");
    if (sf0.residues[0].begin != 1) fail("floor0: residue begin != 1");
    if (sf0.residues[0].end != 2) fail("floor0: residue end != 2");
    if (sf0.residues[0].partition_size != 3) fail("floor0: residue partition_size != 3");
    if (sf0.residues[0].classifications != 2) fail("floor0: classifications != 2");
    if (sf0.residues[0].classbook != 0) fail("floor0: classbook != 0");
    if (sf0.residues[0].cascade[0] != 0) fail("floor0: cascade[0] != 0");
    if (sf0.residues[0].cascade[1] != 1) fail("floor0: cascade[1] != 1");
    if (sf0.residues[0].books[8] != 0) fail("floor0: books[1][0] != 0");
    if (sf0.modes.len != 1) fail("floor0: mode count != 1");
    if (sf0.modes[0].blockflag) fail("floor0: mode blockflag set");

    // --- synthetic Task 3: 2-submap mapping with mux and one coupling step
    //     (fixtures only exercise single-submap mappings). ---
    var p_mux: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x01\x42\x43\x56\x01\x00\x01\x00\x00\x00\x10\x1a\xb2\x0a\x00\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04\x28\x00\x50\x00\x08\x03\x00\x00\x00\x00\x00\x00\x00\x10\x00\x00\x0c\x00\x00\x00\x00\x00\x00\x00\x8c\x00\x02\x01\x00\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x08\x00\x00\x00\x00\x10";
    var sm: vs.Setup = vs.parseSetup(&arena, p_mux, 2) catch {
        fail("mux: parseSetup failed");
        return;
    };
    if (sm.mappings.len != 1) fail("mux: mapping count != 1");
    if (sm.mappings[0].submaps != 2) fail("mux: submaps != 2");
    if (sm.mappings[0].coupling_steps != 1) fail("mux: coupling_steps != 1");
    if (sm.mappings[0].coupling_magnitude[0] != 0) fail("mux: coupling_magnitude[0] != 0");
    if (sm.mappings[0].coupling_angle[0] != 1) fail("mux: coupling_angle[0] != 1");
    if (sm.mappings[0].mux[0] != 0) fail("mux: mux[0] != 0");
    if (sm.mappings[0].mux[1] != 1) fail("mux: mux[1] != 1");
    if (sm.mappings[0].submap_floor[1] != 0) fail("mux: submap_floor[1] != 0");
    if (sm.mappings[0].submap_residue[1] != 0) fail("mux: submap_residue[1] != 0");
    if (sm.modes.len != 2) fail("mux: mode count != 2");

    // --- synthetic Task 3 negatives: an illegal floor type and a nonzero
    //     mapping reserved field are BadVersion, not crashes. ---
    var p_badfloor: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x01\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00";
    if (!setupFails(&arena, p_badfloor)) fail("accepted floor type 2");
    var p_badmap: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x01\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x80\x00\x05\x00\x0a\x00\x61\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x80\x01\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x04";
    if (!setupFails(&arena, p_badmap)) fail("accepted nonzero mapping reserved field");


    var ok: []const u8 = "setup_test: PASS fixtures=5 stereo_codebooks=38 mono_codebooks=35 cb0_dim=1 cb0_entries=64 ordered=ok lookup2=ok cbtables=ok setup=ok\n";
    std.io.write(ok);
    std.os.exit(0);
}
