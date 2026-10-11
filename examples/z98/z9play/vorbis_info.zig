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
// This module owns the id header only; the comment header lands in Task 3.

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
