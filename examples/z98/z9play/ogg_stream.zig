// ogg_stream.zig — incremental OGG pages and packets (z9play M9 Task 2).
//
// Pure Z98 free functions. Pages are read one at a time from a bounded
// `stream.BufferedFile`; each page buffer holds only that page (page-local
// offsets, never absolute file offsets, so a >4 GiB file cannot overflow a
// u32). CRC-32 is verified with the existing `ogg.crcOk` on the page-local
// bytes. Packets are reassembled into one fixed 1 MiB buffer; the slice
// returned by `oggStreamNextPacket` is valid until the next call.
//
// `ogg.reassemble` and `ogg.lastGranule` are not used by this module: the
// streaming reader is the production path, the byte-slice functions stay as
// unit-test oracles only.

const std = @import("std");
const std_file = @import("std_file");
const stream = @import("stream.zig");
const ogg = @import("ogg.zig");

// Largest legal page: 27-byte header + 255 segment laces + 255*255 body bytes.
pub const OGG_PAGE_MAX: usize = 27 + 255 + 65025;
// Fixed page buffer (spec §3: 64 KiB, larger than OGG_PAGE_MAX).
pub const OGG_PAGE_BUF: usize = 65536;
// Correctness bound for one packet; larger packets are rejected cleanly.
pub const OGG_PACKET_MAX: usize = 1024 * 1024;
// The duration scan reads this much from EOF first.
pub const TAIL_WINDOW: usize = 256 * 1024;

pub const OggStreamError = error{
    BadCapture,
    BadVersion,
    Truncated,
    Crc,
    OutOfMemory,
    PacketTooLarge,
    SerialMismatch,
};

// `page_body` is a page-local offset into `page`: the next body byte described
// by the current segment lace. `page_seg` indexes the segment table. A zero
// `page_len` means no page is loaded. `pending` is true when a 255 lace left a
// packet open at the end of the previous page.
pub const OggStream = struct {
    bf: stream.BufferedFile,
    page: []u8,
    page_len: usize,
    page_seg: usize,
    page_body: usize,
    nseg: usize,
    packet: []u8,
    packet_len: usize,
    serial: u32,
    have_serial: bool,
    pending: bool,
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

// Read one page into `s.page`. Returns false only at a clean EOF (no bytes of a
// new page). Every short read inside a page is `Truncated`. Validation order is
// capture/version, exact length, CRC, serial, then the continuation contract.
fn loadPage(s: *OggStream) OggStreamError!bool {
    var got: usize = stream.bufferedFileRead(&s.bf, s.page[0..27]) catch return error.Truncated;
    if (got == 0) return false;
    if (got != 27) return error.Truncated;
    if (s.page[0] != 'O' or s.page[1] != 'g' or s.page[2] != 'g' or s.page[3] != 'S') {
        return error.BadCapture;
    }
    if (s.page[4] != 0) return error.BadVersion;

    var nseg: usize = @intCast(usize, s.page[26]);
    if (27 + nseg > OGG_PAGE_BUF) return error.Truncated;
    got = stream.bufferedFileRead(&s.bf, s.page[27 .. 27 + nseg]) catch return error.Truncated;
    if (got != nseg) return error.Truncated;

    var body_len: usize = 0;
    var i: usize = 0;
    while (i < nseg) : (i += 1) {
        body_len += @intCast(usize, s.page[27 + i]);
    }
    var total: usize = 27 + nseg + body_len;
    if (total > OGG_PAGE_BUF) return error.Truncated;
    got = stream.bufferedFileRead(&s.bf, s.page[27 + nseg .. total]) catch return error.Truncated;
    if (got != body_len) return error.Truncated;

    // Page-local offsets only. OGG_PAGE_BUF < 2^16, so these u32 casts are
    // exact regardless of the page's absolute file position.
    var lp = ogg.Page{
        .granule = rdU64(s.page[0..], 6),
        .serial = rdU32(s.page[0..], 14),
        .seq = rdU32(s.page[0..], 18),
        .header_type = s.page[5],
        .body_start = @intCast(u32, 27 + nseg),
        .body_len = @intCast(u32, body_len),
    };
    if (!ogg.crcOk(s.page[0..total], lp)) return error.Crc;

    if (!s.have_serial) {
        s.serial = lp.serial;
        s.have_serial = true;
    } else if (lp.serial != s.serial) {
        return error.SerialMismatch;
    }

    var cont: bool = (s.page[5] & 0x01) != 0;
    if (s.pending and !cont) return error.Truncated;
    if (!s.pending and cont) return error.Truncated;

    s.page_len = total;
    s.nseg = nseg;
    s.page_seg = 0;
    s.page_body = 27 + nseg;
    return true;
}

// Open the file and allocate the two fixed buffers from `arena`. The arena and
// the returned stream must outlive each other; close is idempotent.
pub fn oggStreamOpen(arena: *std.arena.Arena, path: []const u8) OggStreamError!OggStream {
    var bf = stream.bufferedFileOpen(arena, path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.Truncated;
    };
    var raw_page: [*]u8 = std.arena.alloc(arena, OGG_PAGE_BUF) catch {
        stream.bufferedFileClose(&bf);
        return error.OutOfMemory;
    };
    var raw_packet: [*]u8 = std.arena.alloc(arena, OGG_PACKET_MAX) catch {
        stream.bufferedFileClose(&bf);
        return error.OutOfMemory;
    };
    return OggStream{
        .bf = bf,
        .page = raw_page[0..OGG_PAGE_BUF],
        .page_len = 0,
        .page_seg = 0,
        .page_body = 0,
        .nseg = 0,
        .packet = raw_packet[0..OGG_PACKET_MAX],
        .packet_len = 0,
        .serial = 0,
        .have_serial = false,
        .pending = false,
    };
}

pub fn oggStreamClose(s: *OggStream) void {
    stream.bufferedFileClose(&s.bf);
}

// Return the next complete packet, or null at a clean end of stream. The
// returned slice points into the stream's fixed packet buffer and remains valid
// only until the next `oggStreamNextPacket` call.
//
// A lacing value < 255 terminates the packet; 255 leaves it open across the
// rest of the page and any continuation pages. A page boundary may only be
// crossed by a packet when the next page sets the continuation flag, and a
// continuation page is only legal when a packet is already open.
pub fn oggStreamNextPacket(s: *OggStream) OggStreamError!?[]const u8 {
    while (true) {
        if (s.page_len == 0) {
            var more: bool = try loadPage(s);
            if (!more) {
                if (s.pending or s.packet_len != 0) return error.Truncated;
                return null;
            }
        }

        if (s.page_seg >= s.nseg) {
            s.pending = s.packet_len != 0;
            s.page_len = 0;
            continue;
        }

        var lace: usize = @intCast(usize, s.page[27 + s.page_seg]);
        if (s.packet_len + lace > OGG_PACKET_MAX) return error.PacketTooLarge;
        var i: usize = 0;
        while (i < lace) : (i += 1) {
            s.packet[s.packet_len + i] = s.page[s.page_body + i];
        }
        s.packet_len += lace;
        s.page_body += lace;
        s.page_seg += 1;
        if (lace < 255) {
            var out: []const u8 = s.packet[0..s.packet_len];
            s.packet_len = 0;
            s.pending = false;
            return out;
        }
    }
    return null;
}

// Parse a page at page-local offset `off` in `buf` and return its granule only
// when the page is complete, CRC-valid, for `serial`, and ends at `buf.len`.
// Used by the tail scan so an "OggS" inside a page body cannot masquerade as
// the final page.
fn finalPageGranule(buf: []const u8, off: usize, serial: u32) ?u64 {
    if (off + 27 > buf.len) return null;
    if (buf[off] != 'O' or buf[off + 1] != 'g' or buf[off + 2] != 'g' or buf[off + 3] != 'S') {
        return null;
    }
    if (buf[off + 4] != 0) return null;
    var nseg: usize = @intCast(usize, buf[off + 26]);
    if (off + 27 + nseg > buf.len) return null;
    var body_len: usize = 0;
    var i: usize = 0;
    while (i < nseg) : (i += 1) {
        body_len += @intCast(usize, buf[off + 27 + i]);
    }
    var total: usize = 27 + nseg + body_len;
    if (off + total != buf.len) return null;
    var lp = ogg.Page{
        .granule = rdU64(buf, off + 6),
        .serial = rdU32(buf, off + 14),
        .seq = rdU32(buf, off + 18),
        .header_type = buf[off + 5],
        .body_start = @intCast(u32, off + 27 + nseg),
        .body_len = @intCast(u32, body_len),
    };
    if (lp.serial != serial) return null;
    if (!ogg.crcOk(buf[0 .. off + total], lp)) return null;
    return lp.granule;
}

fn scanTail(buf: []const u8, serial: u32) ?u64 {
    if (buf.len < 4) return null;
    var i: usize = buf.len - 4;
    while (true) {
        if (buf[i] == 'O' and buf[i + 1] == 'g' and buf[i + 2] == 'g' and buf[i + 3] == 'S') {
            if (finalPageGranule(buf, i, serial)) |g| return g;
        }
        if (i == 0) break;
        i -= 1;
    }
    return null;
}

fn readTailInto(arena: *std.arena.Arena, path: []const u8, cap: usize) OggStreamError![]u8 {
    var f = std_file.open(arena, path, .Read) catch return error.Truncated;
    var raw: [*]u8 = std.arena.alloc(arena, cap) catch {
        std_file.close(&f);
        return error.OutOfMemory;
    };
    var buf: []u8 = raw[0..cap];
    var sz: i64 = std_file.size(&f) catch {
        std_file.close(&f);
        return error.Truncated;
    };
    if (sz < 0) {
        std_file.close(&f);
        return error.Truncated;
    }
    var size: u64 = @intCast(u64, sz);
    var start: u64 = size - @intCast(u64, cap);
    _ = std_file.seek(&f, @intCast(i64, start), .Set) catch {
        std_file.close(&f);
        return error.Truncated;
    };
    var total: usize = 0;
    while (total < cap) {
        var got: usize = std_file.read(&f, buf[total..]) catch {
            std_file.close(&f);
            return error.Truncated;
        };
        if (got == 0) break;
        total += got;
    }
    std_file.close(&f);
    if (total != cap) return error.Truncated;
    return buf;
}

// Tail-only duration scan. Opens its own handle, reads at most the last
// TAIL_WINDOW bytes, and never touches a decode stream cursor. If the final
// page straddles that window, one bounded expansion backwards by
// OGG_PAGE_MAX bytes is attempted. An empty file returns 0; a non-empty file
// with no complete final page for `serial` is `Truncated`.
pub fn oggStreamLastGranule(arena: *std.arena.Arena, path: []const u8, serial: u32) OggStreamError!u64 {
    var f = std_file.open(arena, path, .Read) catch return error.Truncated;
    var sz: i64 = std_file.size(&f) catch {
        std_file.close(&f);
        return error.Truncated;
    };
    std_file.close(&f);
    if (sz < 0) return error.Truncated;
    var size: u64 = @intCast(u64, sz);
    if (size == 0) return 0;

    var cap64: u64 = TAIL_WINDOW;
    if (size < cap64) cap64 = size;
    var cap: usize = @intCast(usize, cap64);
    var buf: []u8 = try readTailInto(arena, path, cap);
    if (scanTail(buf, serial)) |g| return g;

    // The final page may start just before the window. The largest legal page
    // is OGG_PAGE_MAX, so one bounded expansion is sufficient.
    if (cap64 < size) {
        var cap2_64: u64 = cap64 + @intCast(u64, OGG_PAGE_MAX);
        if (cap2_64 > size) cap2_64 = size;
        var cap2: usize = @intCast(usize, cap2_64);
        var buf2: []u8 = try readTailInto(arena, path, cap2);
        if (scanTail(buf2, serial)) |g| return g;
    }
    return error.Truncated;
}
