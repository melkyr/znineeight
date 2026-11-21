// ogg.zig — OGG container: page framing and packet reassembly (z9play M0).
//
// Pure Z98: free functions, no generics, no @cImport, strict @intCast. The
// container is the subset of RFC 3533 needed by the player: parse the 27-byte
// page header + segment table, walk pages, verify the page CRC, and reassemble
// packets (the Vorbis headers and audio packets) into contiguous arena copies.
//
// The OGG CRC is CRC-32 with polynomial 0x04c11db7, initial value 0, no input
// or output reflection and no final XOR. This is NOT the reflected IEEE 802.3
// CRC-32 that std_crypto exposes (init/xorout 0xFFFFFFFF), so it is implemented
// locally here; the plan anticipates the local-table fallback.

const std = @import("std");

pub const OggError = error{ BadCapture, BadVersion, Truncated, Crc, OutOfMemory };

// A parsed page header. `body_start` is the absolute file offset of the page
// body (immediately after the segment table); `body_len` is the sum of the
// segment table, i.e. the body byte count. The page's own start offset is
// recovered by crcOk (see below).
pub const Page = struct {
    granule: u64,
    serial: u32,
    seq: u32,
    header_type: u8,
    body_start: u32,
    body_len: u32,
};

// A reassembled packet: a contiguous copy of the packet bytes held in the
// caller's arena.
pub const Packet = struct {
    bytes: []const u8,
};

fn rdU32(data: []const u8, off: usize) u32 {
    return @intCast(u32, data[off]) |
        (@intCast(u32, data[off + 1]) << 8) |
        (@intCast(u32, data[off + 2]) << 16) |
        (@intCast(u32, data[off + 3]) << 24);
}

fn rdU64(data: []const u8, off: usize) u64 {
    return @intCast(u64, rdU32(data, off)) |
        (@intCast(u64, rdU32(data, off + 4)) << 32);
}

// Parse the page header at `off`. Verifies the capture pattern and version and
// that the header, segment table and body all lie inside `data`.
pub fn pageAt(data: []const u8, off: usize) OggError!Page {
    if (off + 27 > data.len) return error.Truncated;
    if (data[off] != 'O' or data[off + 1] != 'g' or data[off + 2] != 'g' or data[off + 3] != 'S') {
        return error.BadCapture;
    }
    if (data[off + 4] != 0) return error.BadVersion;
    var nseg: usize = @intCast(usize, data[off + 26]);
    if (off + 27 + nseg > data.len) return error.Truncated;
    var blen: u32 = 0;
    var i: usize = 0;
    while (i < nseg) : (i += 1) {
        blen += @intCast(u32, data[off + 27 + i]);
    }
    var body_start: usize = off + 27 + nseg;
    if (body_start + @intCast(usize, blen) > data.len) return error.Truncated;
    var p = Page{
        .granule = rdU64(data, off + 6),
        .serial = rdU32(data, off + 14),
        .seq = rdU32(data, off + 18),
        .header_type = data[off + 5],
        .body_start = @intCast(u32, body_start),
        .body_len = blen,
    };
    return p;
}

// Offset of the page that follows `page` (the end of its body).
pub fn nextPage(data: []const u8, page: Page) usize {
    _ = data;
    return @intCast(usize, page.body_start) + @intCast(usize, page.body_len);
}

// True when the page's first packet is not a continuation carried over from the
// previous page (header_type continuation flag bit 0 clear). Such a page's
// segment endings describe complete packets without a pending carry-in.
pub fn isCompletePacket(page: Page) bool {
    return (page.header_type & 0x01) == 0;
}

const CRC_POLY: u32 = 0x04c11db7;

// OGG CRC-32 over data[start..end], treating the 4 CRC-field bytes at
// start+22..start+26 as zero (they are replaced by the checksum when stored).
fn oggCrcPage(data: []const u8, start: usize, end: usize) u32 {
    var crc: u32 = 0;
    var i: usize = start;
    while (i < end) : (i += 1) {
        var b: u8 = data[i];
        if (i >= start + 22 and i < start + 26) b = 0;
        crc = crc ^ (@intCast(u32, b) << 24);
        var j: u32 = 0;
        while (j < 8) : (j += 1) {
            if ((crc & 0x80000000) != 0) {
                crc = (crc *% 2) ^ CRC_POLY;
            } else {
                crc = crc *% 2;
            }
        }
    }
    return crc;
}

// Recover a page's start offset from its body position. The page starts at
// body_start - 27 - nseg for the (unknown) segment count nseg in 0..=255; the
// segment table at that candidate must sum to body_len. Returns the first
// candidate whose capture pattern, version and segment sum all agree.
fn pageStartOf(data: []const u8, page: Page) usize {
    var body_start: usize = @intCast(usize, page.body_start);
    var nseg: usize = 0;
    while (nseg <= 255) : (nseg += 1) {
        if (body_start < 27 + nseg) break;
        var ps: usize = body_start - 27 - nseg;
        if (ps + 27 <= data.len) {
            if (data[ps] == 'O' and data[ps + 1] == 'g' and data[ps + 2] == 'g' and data[ps + 3] == 'S') {
                if (data[ps + 4] == 0) {
                    var sum: u32 = 0;
                    var k: usize = 0;
                    while (k < nseg) : (k += 1) {
                        sum += @intCast(u32, data[ps + 27 + k]);
                    }
                    if (sum == page.body_len) return ps;
                }
            }
        }
    }
    return body_start;
}

// Verify the page CRC: recompute the OGG CRC-32 over the whole page with the
// CRC field zeroed and compare against the stored field.
pub fn crcOk(data: []const u8, page: Page) bool {
    var ps: usize = pageStartOf(data, page);
    var end: usize = @intCast(usize, page.body_start) + @intCast(usize, page.body_len);
    if (ps + 27 > data.len or end > data.len) return false;
    var stored: u32 = rdU32(data, ps + 22);
    var computed: u32 = oggCrcPage(data, ps, end);
    return stored == computed;
}

// Reassemble every packet in the logical stream. A packet is the concatenation
// of consecutive segment bodies; a segment length < 255 terminates the packet,
// and 255 means the packet continues (possibly onto the next page). Packet
// bytes are copied segment-by-segment into one contiguous arena block, so
// packets that span pages do not pick up the interstitial page headers. A
// stream that ends with an unterminated (still-open) packet is malformed and
// returns error.Truncated; the copy pass is additionally bounded so it can
// never write past the allocation.
pub fn reassemble(arena: *std.arena.Arena, data: []const u8) OggError![]Packet {
    // Pass 1: count packets and total packet bytes.
    var count: usize = 0;
    var total: usize = 0;
    {
        var off: usize = 0;
        var cur: usize = 0;
        while (off < data.len) {
            var page = try pageAt(data, off);
            var nseg: usize = @intCast(usize, page.body_start) - off - 27;
            var i: usize = 0;
            while (i < nseg) : (i += 1) {
                var lace: usize = @intCast(usize, data[off + 27 + i]);
                cur += lace;
                if (lace < 255) {
                    count += 1;
                    total += cur;
                    cur = 0;
                }
            }
            off = nextPage(data, page);
        }
        // A packet still open at EOF (the stream ended on a 255 lace with no
        // <255 terminator) is malformed; reject it before any allocation so the
        // copy pass below can never write past `total`.
        if (cur != 0) return error.Truncated;
    }

    var raw_p: [*]u8 = std.arena.alloc(arena, count * @sizeOf(Packet)) catch return error.OutOfMemory;
    var packets: [*]Packet = @ptrCast([*]Packet, raw_p);
    var blob: [*]u8 = std.arena.alloc(arena, total) catch return error.OutOfMemory;

    // Pass 2: copy each segment body, closing a packet on a segment < 255.
    var off2: usize = 0;
    var pi: usize = 0;
    var pstart: usize = 0;
    var w: usize = 0;
    while (off2 < data.len) {
        var page = try pageAt(data, off2);
        var nseg: usize = @intCast(usize, page.body_start) - off2 - 27;
        var seg_off: usize = off2 + 27;
        var body_off: usize = @intCast(usize, page.body_start);
        var i: usize = 0;
        while (i < nseg) : (i += 1) {
            var lace: usize = @intCast(usize, data[seg_off + i]);
            var k: usize = 0;
            while (k < lace) : (k += 1) {
                // Defensive bound: never write past the allocation sized for
                // terminated packets (pass 1 already rejected an unterminated
                // tail, so this is unreachable for accepted input).
                if (w >= total) return error.Truncated;
                blob[w] = data[body_off + k];
                w += 1;
            }
            body_off += lace;
            if (lace < 255) {
                packets[pi].bytes = blob[pstart..w];
                pi += 1;
                pstart = w;
            }
        }
        off2 = nextPage(data, page);
    }
    return packets[0..count];
}

// True when the page's first packet body begins with `prefix`. Valid for a
// page whose first packet starts at its bodystart (no carry-in from a previous
// page) — i.e. a BOS page such as the Vorbis identification page.
fn pageStartsWith(data: []const u8, page: Page, prefix: []const u8) bool {
    var bs: usize = @intCast(usize, page.body_start);
    if (bs + prefix.len > data.len) return false;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        if (data[bs + i] != prefix[i]) return false;
    }
    return true;
}

// Duration in milliseconds of a stream with `last_granule` audio samples at
// `sample_rate` Hz. The Vorbis granule is the count of samples in the logical
// stream, so duration = granule / sample_rate seconds; integer math truncates
// toward zero. A zero rate (malformed id header) yields 0, never a trap.
pub fn durationMs(last_granule: u64, sample_rate: u32) u64 {
    if (sample_rate == 0) return 0;
    return last_granule * 1000 / @intCast(u64, sample_rate);
}

// Highest granule position among the pages of the Vorbis (audio) logical
// stream — the end-of-stream sample count used to derive the duration. The
// audio serial is the one whose BOS page carries the Vorbis identification
// header (`\x01vorbis`). Chained/multiplexed OGG is out of scope, but
// restricting to that serial keeps a stray non-audio logical stream from
// inflating the result. The arena is reserved for a future streaming form; the
// scan is currently allocation-free.
pub fn lastGranule(arena: *std.arena.Arena, data: []const u8) OggError!u64 {
    _ = arena;
    var id: []const u8 = "\x01vorbis";
    var serial: u32 = 0;
    var found: bool = false;
    var off: usize = 0;
    while (off < data.len) {
        var page = try pageAt(data, off);
        if (!found and (page.header_type & 0x02) != 0 and pageStartsWith(data, page, id)) {
            serial = page.serial;
            found = true;
        }
        off = nextPage(data, page);
    }
    if (!found) return error.BadCapture;

    var max_granule: u64 = 0;
    var off2: usize = 0;
    while (off2 < data.len) {
        var page2 = try pageAt(data, off2);
        if (page2.serial == serial and page2.granule != 0xFFFFFFFFFFFFFFFF and page2.granule > max_granule) {
            max_granule = page2.granule;
        }
        off2 = nextPage(data, page2);
    }
    return max_granule;
}
