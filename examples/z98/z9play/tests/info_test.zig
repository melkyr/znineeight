// info_test.zig — deterministic unit harness for the z9play Vorbis
// identification header (vorbis_info.parseId).
//
// Asserts, against the committed fixture
// examples/z98/z9play/testdata/sine_stereo_44100.ogg, that packet 0 parses to
// the exact field values in the golden (channels 2, 44100 Hz, blocksize
// exponents 8/11), and that malformed framing / version / capture are errors.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/info_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const vi = @import("../vorbis_info.zig");

// Backing store for the read/reassembly arena; module-global so it does not
// sit on the 32-bit stack.
var arena_buf: [4 * 1024 * 1024]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "info_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// True when parseId rejects `pkt` (the malformed cases).
fn parseFails(pkt: []const u8) bool {
    var r: vi.IdHeader = vi.parseId(pkt) catch return true;
    _ = r;
    return false;
}

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

// True when parseComment rejects `pkt` (the malformed cases).
fn commentFails(arena: *std.arena.Arena, pkt: []const u8) bool {
    var r: vi.Comment = vi.parseComment(arena, pkt) catch return true;
    _ = r;
    return false;
}

// The value for `key` (already uppercase) among `tags`, or "" when absent.
fn tagValue(tags: []vi.Tag, key: []const u8) []const u8 {
    var i: usize = 0;
    while (i < tags.len) : (i += 1) {
        if (std.str.eql(tags[i].key, key)) return tags[i].value;
    }
    var empty: []const u8 = "";
    return empty;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    var arena = std.arena.init(arena_buf[0..]);
    var path: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture sine_stereo_44100.ogg");
        return;
    };
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble failed");
        return;
    };
    if (packets.len < 1) fail("no reassembled packets");

    // Exact identification-header fields for sine_stereo_44100.ogg.
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("parseId failed on packet 0");
        return;
    };
    if (id.version != 0) fail("version != 0");
    if (id.channels != 2) fail("channels != 2");
    if (id.sample_rate != 44100) fail("sample_rate != 44100");
    if (id.bitrate_max != 0) fail("bitrate_max != 0");
    if (id.bitrate_nom != 112000) fail("bitrate_nom != 112000");
    if (id.bitrate_min != 0) fail("bitrate_min != 0");
    if (id.blocksize_0 != 8) fail("blocksize_0 != 8");
    if (id.blocksize_1 != 11) fail("blocksize_1 != 11");

    if (packets[0].bytes.len < 30) fail("packet 0 shorter than 30 bytes");

    // Malformed: framing bit cleared.
    var bad: [30]u8 = undefined;
    copyInto(bad[0..], packets[0].bytes[0..30]);
    bad[29] = bad[29] & 0xFE;
    if (!parseFails(bad[0..])) fail("accepted cleared framing bit");

    // Malformed: non-zero version.
    var bad2: [30]u8 = undefined;
    copyInto(bad2[0..], packets[0].bytes[0..30]);
    bad2[7] = 1;
    if (!parseFails(bad2[0..])) fail("accepted non-zero version");

    // Malformed: bad capture signature byte.
    var bad3: [30]u8 = undefined;
    copyInto(bad3[0..], packets[0].bytes[0..30]);
    bad3[1] = 'X';
    if (!parseFails(bad3[0..])) fail("accepted bad capture signature");

    // --- Task 3: comment header (tags) for tagged_unicode.ogg packet 1. ---
    // The fixture carries real UTF-8 tag bytes; expectations are spelled with
    // \x escapes so the source stays byte-exact regardless of encoding.
    var exp_vendor: []const u8 = "Xiph.Org libVorbis I 20200704 (Reducing Environment)";
    var exp_title: []const u8 = "Caf\xc3\xa9 d\xc3\xa9j\xc3\xa0 vu";
    var exp_artist: []const u8 = "Na\xc3\xafve \xe6\x97\xa5\xe6\x9c\xac";
    var exp_album: []const u8 = "\xc3\x9cn\xc3\xafcod\xc3\xa9";

    var tpath: []const u8 = "examples/z98/z9play/testdata/tagged_unicode.ogg";
    var tdata: []u8 = filemod.readAll(&arena, tpath) catch {
        fail("cannot read fixture tagged_unicode.ogg");
        return;
    };
    var tpackets: []ogg.Packet = ogg.reassemble(&arena, tdata) catch {
        fail("reassemble(tagged_unicode) failed");
        return;
    };
    if (tpackets.len < 2) fail("tagged_unicode has fewer than 2 packets");

    var c: vi.Comment = vi.parseComment(&arena, tpackets[1].bytes) catch {
        fail("parseComment failed on packet 1");
        return;
    };
    if (!std.str.eql(c.vendor, exp_vendor)) fail("comment vendor mismatch");
    if (c.tags.len != 3) fail("comment tag count != 3");
    if (!std.str.eql(tagValue(c.tags, "TITLE"), exp_title)) fail("TITLE mismatch");
    if (!std.str.eql(tagValue(c.tags, "ARTIST"), exp_artist)) fail("ARTIST mismatch");
    if (!std.str.eql(tagValue(c.tags, "ALBUM"), exp_album)) fail("ALBUM mismatch");

    // Malformed: wrong packet-type signature (0x02).
    var cbad: []const u8 = "\x02vorbis\x00\x00\x00\x00\x00\x00\x00\x00\x01";
    if (!commentFails(&arena, cbad)) fail("accepted bad comment signature");

    // Malformed: framing bit clear.
    var cbad2: []const u8 = "\x03vorbis\x00\x00\x00\x00\x00\x00\x00\x00\x00";
    if (!commentFails(&arena, cbad2)) fail("accepted cleared comment framing bit");

    // Malformed: truncated before the vendor length.
    var cbad3: []const u8 = "\x03vorbis\x00\x00\x00";
    if (!commentFails(&arena, cbad3)) fail("accepted truncated comment header");

    // Malformed: comment count overflow (0xFFFFFFFF).
    var cbad4: []const u8 = "\x03vorbis\x00\x00\x00\x00\xff\xff\xff\xff\x01";
    if (!commentFails(&arena, cbad4)) fail("accepted overflowing comment count");

    // Malformed: comment length overflow (0xFFFFFFFF).
    var cbad5: []const u8 = "\x03vorbis\x00\x00\x00\x00\x01\x00\x00\x00\xff\xff\xff\xff\x01";
    if (!commentFails(&arena, cbad5)) fail("accepted overflowing comment length");

    var ok: []const u8 = "info_test: PASS channels=2 sample_rate=44100 blocksize_0=8 blocksize_1=11\n";
    std.io.write(ok);
    std.os.exit(0);
}
