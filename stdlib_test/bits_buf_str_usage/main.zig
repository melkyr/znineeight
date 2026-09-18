// stdlib_test/bits_buf_str_usage — Plan A Task 7 (R7b) usage program.
//
// Composes std_bits (L0) + std_buf (L2) + std_str (L2) into one intended
// workflow: pack three small integer fields into a single header word with
// std_bits, serialize that word (plus a checksum) into a byte buffer with
// std_buf, then shape the text payload with std_str (trim -> split -> join)
// and append the shaped result back into the buffer.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   packed: 11217674
//   pop: 11
//   trimmed: alpha,beta,gamma
//   joined: alpha:beta:gamma
//   bits_buf_str ok
// A mismatch increments g_fail and calls @panic; the final line is
// `bits_buf_str ok` only when g_fail == 0.
const std = @import("std");

var g_backing: [4096]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn printU32(tag: []const u8, n: u32) void {
    std.io.write(tag);
    std.io.printInt(@intCast(i32, n));
    std.io.write("\n");
}

fn printStr(tag: []const u8, s: []const u8) void {
    std.io.write(tag);
    std.io.write(s);
    std.io.write("\n");
}

pub fn main() void {
    // --- std_bits: pack three fields into one header word ------------------
    // `packed` is a Z98 keyword (packed struct/union), so the local is `hdr`.
    var hdr: u32 = 0;
    hdr = std.bits.insert(hdr, @intCast(u32, 0xA), 0, 4); // a = 10
    hdr = std.bits.insert(hdr, @intCast(u32, 0x2B), 8, 6); // b = 43
    hdr = std.bits.insert(hdr, @intCast(u32, 0xAB), 16, 8); // c = 171

    // Round-trip each field back out (extract/insert compose).
    ck(std.bits.extract(hdr, 0, 4) == @intCast(u32, 0xA), "extract a");
    ck(std.bits.extract(hdr, 8, 6) == @intCast(u32, 0x2B), "extract b");
    ck(std.bits.extract(hdr, 16, 8) == @intCast(u32, 0xAB), "extract c");
    ck(std.bits.popcount32(hdr) == @intCast(u32, 11), "popcount header");

    var pop: u32 = std.bits.popcount32(hdr);

    // --- std_str: trim -> split -> join the text payload -------------------
    var text: []const u8 = "  alpha,beta,gamma  ";
    var trimmed: []const u8 = std.str.trim(text);
    ck(std.str.eql(trimmed, "alpha,beta,gamma"), "trim");

    var parts = std.str.split(&g_arena, trimmed, ',') catch {
        g_fail += 1;
        @panic("split");
    };
    ck(parts.len == 3, "split count");
    ck(std.str.eql(parts[0], "alpha"), "split[0]");
    ck(std.str.eql(parts[1], "beta"), "split[1]");
    ck(std.str.eql(parts[2], "gamma"), "split[2]");

    var joined = std.str.join(&g_arena, parts, ":") catch {
        g_fail += 1;
        @panic("join");
    };
    ck(std.str.eql(joined, "alpha:beta:gamma"), "join");

    // --- std_buf: serialize a little record --------------------------------
    // [u32 BE header][u16 BE checksum][shaped payload]
    var b = std.buf.init(&g_arena);
    std.buf.appendU32BE(&b, hdr) catch {
        g_fail += 1;
    };
    std.buf.appendU16BE(&b, @intCast(u16, pop)) catch {
        g_fail += 1;
    };
    std.buf.append(&b, joined) catch {
        g_fail += 1;
    };

    var s = std.buf.slice(&b);
    ck(s.len == 22, "record length");
    ck(s[0] == 0x00 and s[1] == 0xAB and s[2] == 0x2B and s[3] == 0x0A, "u32 BE header");
    ck(s[4] == 0x00 and s[5] == 0x0B, "u16 BE checksum");
    ck(std.str.eql(s[6..s.len], joined), "payload == joined");

    // --- stdout contract ----------------------------------------------------
    printU32("packed: ", hdr);
    printU32("pop: ", pop);
    printStr("trimmed: ", trimmed);
    printStr("joined: ", joined);

    if (g_fail == 0) {
        std.io.write("bits_buf_str ok\n");
    } else {
        std.io.write("bits_buf_str FAIL\n");
    }
}
