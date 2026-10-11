// vorbis_info.zig — Vorbis identification header parser (z9play M0).
//
// Pure Z98: free functions, no generics, no @cImport, strict @intCast. Parses
// the 30-byte Vorbis identification header (packet type 1) exposed by the OGG
// reassembler in ogg.zig:
//
//   0        packet type 0x01
//   1..7     "vorbis"
//   7..11    version          (u32 LE)
//   11       channels         (u8)
//   12..16   sample_rate      (u32 LE)
//   16..20   bitrate_max      (i32 LE)
//   20..24   bitrate_nom      (i32 LE)
//   24..28   bitrate_min      (i32 LE)
//   28       blocksize byte   (low nibble = exponent 0, high = exponent 1)
//   29       framing flag     (bit 0 set)
//
// This module owns the identification header (parseId) and the comment header
// (parseComment: vendor + uppercased tags).

const std = @import("std");
const ogg = @import("ogg.zig");

// Parsed Vorbis identification header. Bitrates are signed per the Vorbis
// spec; a value of 0 means "unset". Blocksizes are stored as exponents (the
// actual sizes are 1 << exponent).
pub const IdHeader = struct {
    version: u32,
    channels: u8,
    sample_rate: u32,
    bitrate_max: i32,
    bitrate_nom: i32,
    bitrate_min: i32,
    blocksize_0: u8,
    blocksize_1: u8,
};

fn rdU32(data: []const u8, off: usize) u32 {
    return @intCast(u32, data[off]) |
        (@intCast(u32, data[off + 1]) << 8) |
        (@intCast(u32, data[off + 2]) << 16) |
        (@intCast(u32, data[off + 3]) << 24);
}

// Parse the identification packet `packet`. Returns BadVersion when the packet
// type / "vorbis" signature / version / framing bit are wrong, and Truncated
// when fewer than 30 bytes are present.
pub fn parseId(packet: []const u8) ogg.OggError!IdHeader {
    if (packet.len < 30) return error.Truncated;
    if (packet[0] != 1) return error.BadVersion;
    var sig: []const u8 = "vorbis";
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        if (packet[1 + i] != sig[i]) return error.BadVersion;
    }
    var version: u32 = rdU32(packet, 7);
    if (version != 0) return error.BadVersion;
    if ((packet[29] & 0x01) == 0) return error.BadVersion;

    var bs: u8 = packet[28];
    return IdHeader{
        .version = version,
        .channels = packet[11],
        .sample_rate = rdU32(packet, 12),
        .bitrate_max = @bitCast(i32, rdU32(packet, 16)),
        .bitrate_nom = @bitCast(i32, rdU32(packet, 20)),
        .bitrate_min = @bitCast(i32, rdU32(packet, 24)),
        .blocksize_0 = bs & 0x0F,
        .blocksize_1 = bs >> 4,
    };
}

// One Vorbis comment field: an uppercased key and its raw value bytes (UTF-8
// per the Vorbis convention; not normalized here).
pub const Tag = struct {
    key: []const u8,
    value: []const u8,
};

// Parsed comment header (packet type 3): the encoder vendor string and the tag
// list. The vendor slice and every tag key/value slice are arena-owned.
pub const Comment = struct {
    vendor: []const u8,
    tags: []Tag,
};

// Copy `src` into arena storage and return the fresh mutable slice, so the
// parser never aliases the caller's packet bytes.
fn dupBytes(arena: *std.arena.Arena, src: []const u8) ogg.OggError![]u8 {
    var p: [*]u8 = std.arena.alloc(arena, src.len) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < src.len) : (i += 1) p[i] = src[i];
    return p[0..src.len];
}

// Parse the comment packet `packet` (type 3, "\x03vorbis"): packet type +
// signature; vendor length (u32 LE) + bytes; comment count (u32 LE); each
// comment as length (u32 LE) + "key=value" bytes; then the framing bit (set).
// Tag keys are uppercased per the Vorbis convention; all returned slices are
// allocated from `arena`. Bad signature / missing '=' / framing clear return
// BadVersion, out-of-range reads Truncated, and allocation failures
// OutOfMemory.
pub fn parseComment(arena: *std.arena.Arena, packet: []const u8) ogg.OggError!Comment {
    if (packet.len < 11) return error.Truncated;
    if (packet[0] != 3) return error.BadVersion;
    var sig: []const u8 = "vorbis";
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        if (packet[1 + i] != sig[i]) return error.BadVersion;
    }

    var off: usize = 7;
    var vlen: usize = @intCast(usize, rdU32(packet, off));
    off += 4;
    if (vlen > packet.len - off) return error.Truncated;
    var vendor: []u8 = try dupBytes(arena, packet[off .. off + vlen]);
    off += vlen;

    if (off + 4 > packet.len) return error.Truncated;
    var count: usize = @intCast(usize, rdU32(packet, off));
    off += 4;
    // Each comment needs a 4-byte length plus at least "="; bounding `count` by
    // the packet size keeps `count * @sizeOf(Tag)` from overflowing on 32-bit.
    if (count > packet.len) return error.Truncated;

    var raw: [*]u8 = std.arena.alloc(arena, count * @sizeOf(Tag)) catch return error.OutOfMemory;
    var tags: [*]Tag = @ptrCast([*]Tag, raw);
    var n: usize = 0;
    while (n < count) : (n += 1) {
        if (off + 4 > packet.len) return error.Truncated;
        var clen: usize = @intCast(usize, rdU32(packet, off));
        off += 4;
        if (clen > packet.len - off) return error.Truncated;
        var body: []const u8 = packet[off .. off + clen];
        var eq: ?usize = std.str.findChar(body, '=');
        if (eq) |e| {
            var key: []u8 = try dupBytes(arena, body[0..e]);
            std.str.toUpper(key);
            var val: []u8 = try dupBytes(arena, body[e + 1 ..]);
            tags[n] = Tag{ .key = key, .value = val };
        } else {
            return error.BadVersion;
        }
        off += clen;
    }

    if (off >= packet.len) return error.Truncated;
    if ((packet[off] & 0x01) == 0) return error.BadVersion;

    return Comment{ .vendor = vendor, .tags = tags[0..count] };
}
