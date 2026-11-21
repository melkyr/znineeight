// main.zig — caconv: PEM CA bundle -> pinned Z98 trust store (§5.5).
//
// usage: caconv <cacert.pem> <ca_store.bin>
//
// Scans the PEM bundle for `BEGIN CERTIFICATE` blocks in file order, strips
// whitespace from each base64 body (std_base64.decode accepts canonical padded
// input only), decodes it, parses the certificate with std_x509, and writes
// every certificate as a trust anchor. Output is deterministic: the same PEM
// bytes always produce the same store bytes.
//
// Store format (spec §5.5, little-endian):
//   "Z98CA100" | u32 anchor_count | u32 file_total_len
//   entry: u16 subject_len, u16 spki_len, u32 not_before, u32 not_after,
//          subject_der, spki_der
//
// Build (seed compiler; its sibling lib/ carries the std modules):
//   mkdir -p out
//   <seed>/zig1_5_clean -fsafe -o out main.zig
//   sh out/build_target.sh linux out/caconv
//   out/caconv cacert.pem ca_store.bin

const std = @import("std");
const b64 = @import("std_base64.zig");
const x509 = @import("std_x509.zig");
const filemod = @import("std_file.zig");

const ARENA_SIZE: usize = 8 * 1024 * 1024;
const MAX_ANCHORS: usize = 512;

var g_buf: [ARENA_SIZE]u8 = undefined;
var g_arena = std.arena.init(g_buf[0..]);

const Anchor = struct {
    subject: []const u8,
    spki: []const u8,
    not_before: i64,
    not_after: i64,
};

var g_anchors: [MAX_ANCHORS]Anchor = undefined;

fn out(s: []const u8) void {
    std.io.write(s);
}

fn fail(msg: []const u8) noreturn {
    out("caconv: ");
    out(msg);
    out("\n");
    std.os.exit(1);
}

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn matchAt(hay: []const u8, off: usize, needle: []const u8) bool {
    if (off + needle.len > hay.len) return false;
    var i: usize = 0;
    while (i < needle.len) : (i += 1) {
        if (hay[off + i] != needle[i]) return false;
    }
    return true;
}

fn findSub(hay: []const u8, needle: []const u8, from: usize) ?usize {
    if (needle.len == 0) return from;
    if (from > hay.len) return null;
    if (hay.len - from < needle.len) return null;
    var i: usize = from;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (matchAt(hay, i, needle)) return i;
    }
    return null;
}

fn findSubOrFail(hay: []const u8, needle: []const u8, from: usize, msg: []const u8) usize {
    if (findSub(hay, needle, from)) |v| return v;
    fail(msg);
    return 0;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

// Copy the base64 body without whitespace; std_base64.decode is strict.
fn compact(arena: *std.arena.Arena, src: []const u8) ![]u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        if (!isSpace(src[i])) n += 1;
    }
    const raw = std.arena.alloc(arena, n) catch return error.OutOfMemory;
    var op: usize = 0;
    i = 0;
    while (i < src.len) : (i += 1) {
        if (!isSpace(src[i])) {
            raw[op] = src[i];
            op += 1;
        }
    }
    return raw[0..n];
}

fn writeU16(dst: []u8, off: usize, v: u16) void {
    dst[off] = @intCast(u8, v & 0xFF);
    dst[off + 1] = @intCast(u8, v >> 8);
}

fn writeU32(dst: []u8, off: usize, v: u32) void {
    dst[off] = @intCast(u8, v & 0xFF);
    dst[off + 1] = @intCast(u8, (v >> 8) & 0xFF);
    dst[off + 2] = @intCast(u8, (v >> 16) & 0xFF);
    dst[off + 3] = @intCast(u8, v >> 24);
}

fn checkedTime(v: i64, msg: []const u8) u32 {
    if (v < 0) fail(msg);
    if (v > @intCast(i64, 4294967295)) fail(msg);
    return @intCast(u32, v);
}

fn pemToStore(arena: *std.arena.Arena, pem: []const u8, store: *[]u8) usize {
    var begin_mark: []const u8 = "-----BEGIN CERTIFICATE-----";
    var end_mark: []const u8 = "-----END CERTIFICATE-----";
    var count: usize = 0;
    var pos: usize = 0;

    while (true) {
        const b = findSub(pem, begin_mark, pos) orelse break;
        const body_start = b + begin_mark.len;
        const e = findSubOrFail(pem, end_mark, body_start, "unterminated PEM block");
        const body = pem[body_start..e];
        const b64text = compact(arena, body) catch {
            fail("out of memory");
            return 0;
        };
        const der = b64.decode(arena, b64text) catch {
            fail("invalid base64 in PEM block");
            return 0;
        };
        var cert: x509.Cert = undefined;
        x509.x509Parse(der, &cert) catch {
            fail("invalid certificate DER");
            return 0;
        };
        if (count >= MAX_ANCHORS) fail("too many certificates");
        _ = checkedTime(cert.not_before, "notBefore outside u32 range");
        _ = checkedTime(cert.not_after, "notAfter outside u32 range");
        if (cert.subject.len > 65535 or cert.spki.len > 65535) fail("certificate name/key too large");
        g_anchors[count] = Anchor{
            .subject = cert.subject,
            .spki = cert.spki,
            .not_before = cert.not_before,
            .not_after = cert.not_after,
        };
        count += 1;
        pos = e + end_mark.len;
    }

    var total: usize = 16;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        total += 12 + g_anchors[i].subject.len + g_anchors[i].spki.len;
    }
    if (total > 4294967295) fail("store exceeds u32 size");
    const raw = std.arena.alloc(arena, total) catch {
        fail("out of memory");
        return 0;
    };
    var dst: []u8 = raw[0..total];
    dst[0] = 'Z';
    dst[1] = '9';
    dst[2] = '8';
    dst[3] = 'C';
    dst[4] = 'A';
    dst[5] = '1';
    dst[6] = '0';
    dst[7] = '0';
    writeU32(dst, 8, @intCast(u32, count));
    writeU32(dst, 12, @intCast(u32, total));

    var off: usize = 16;
    i = 0;
    while (i < count) : (i += 1) {
        const a = g_anchors[i];
        const nb = checkedTime(a.not_before, "notBefore outside u32 range");
        const na = checkedTime(a.not_after, "notAfter outside u32 range");
        writeU16(dst, off, @intCast(u16, a.subject.len));
        writeU16(dst, off + 2, @intCast(u16, a.spki.len));
        writeU32(dst, off + 4, nb);
        writeU32(dst, off + 8, na);
        off += 12;
        var j: usize = 0;
        while (j < a.subject.len) : (j += 1) dst[off + j] = a.subject[j];
        off += a.subject.len;
        j = 0;
        while (j < a.spki.len) : (j += 1) dst[off + j] = a.spki[j];
        off += a.spki.len;
    }
    store.* = dst;
    return count;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n != 3) {
        out("usage: caconv <cacert.pem> <ca_store.bin>\n");
        std.os.exit(2);
        return;
    }
    var in_path: []const u8 = argAt(argv, 1);
    var out_path: []const u8 = argAt(argv, 2);
    const pem = filemod.readAll(&g_arena, in_path) catch {
        fail("cannot read input PEM");
        return;
    };
    var store: []u8 = undefined;
    const count = pemToStore(&g_arena, pem, &store);
    filemod.writeAll(out_path, store) catch {
        fail("cannot write store");
        return;
    };

    var msg: []const u8 = "wrote ";
    out(msg);
    std.io.printInt(@intCast(i32, count));
    out(" anchors\n");
}
