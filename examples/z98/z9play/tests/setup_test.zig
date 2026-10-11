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

// Backing store for the read/reassembly/parse arena; module-global so it does
// not sit on the 32-bit stack. 4 MiB is far above these fixtures' needs.
var arena_buf: [4 * 1024 * 1024]u8 = undefined;

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
    var s: vs.Setup = vs.parseSetup(arena, pkt) catch return true;
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
    var setup: vs.Setup = vs.parseSetup(&arena, packets[2].bytes) catch {
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

    // --- synthetic: ordered codebook (no fixture has one). ---
    var p_ordered: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x04\x00\x03\x00\x00\x83\x01";
    var so: vs.Setup = vs.parseSetup(&arena, p_ordered) catch {
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
    var p_lookup2: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x01\x42\x43\x56\x01\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x03\x40\x68\xc8\xea\x00\xa0\x00\x00\x00\x00\x00\x00\x00";
    var sl: vs.Setup = vs.parseSetup(&arena, p_lookup2) catch {
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

    var ok: []const u8 = "setup_test: PASS fixtures=5 stereo_codebooks=38 mono_codebooks=35 cb0_dim=1 cb0_entries=64 ordered=ok lookup2=ok\n";
    std.io.write(ok);
    std.os.exit(0);
}
