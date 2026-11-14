// stdlib_test/crypto_codec_usage — Plan C Task 9 (R7b) usage program.
//
// Composes std_crypto (L5) + std_base64 / std_hex (L5) + std_utf8 (L5) +
// std_buf (L2) into one intended workflow: a fixed UTF-8 byte message is
// validated and re-encoded with std_utf8, encoded both ways with std_base64
// and std_hex (with a decode round-trip and malformed-input rejection), hashed
// with std_crypto (SHA-256 + CRC-32), and finally framed with std_buf
// (magic + length + base64 + ':' + hex) whose own CRC-32 is printed.
//
// All inputs are fixed and every value is either an internal assert or a pure
// function of the message bytes, so the stdout is deterministic (no
// address/clock/PID input).
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   crypto_codec_usage
//   codepoints: 5
//   cp-first: 90
//   cp-second: 233
//   b64: Wjk4IMOp
//   hex: 5a393820c3a9
//   sha256: 390edd46037981d883bd4363c30dccc4bc9b01b08dbc43192415539910872f09
//   crc32: f2e959aa
//   roundtrip: 1
//   invalid: 1
//   buf-len: 27
//   buf-crc32: ab387860
//   crypto_codec ok
// A mismatch calls @panic; the final line is `crypto_codec ok` only on success.
const std = @import("std");
const crypto = @import("std_crypto.zig");
const b64 = @import("std_base64.zig");
const hex = @import("std_hex.zig");
const utf8 = @import("std_utf8.zig");

var g_storage: [16384]u8 = undefined;
var g_arena = std.arena.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn writeHexU32(v: u32) void {
    var raw: [4]u8 = undefined;
    raw[0] = @intCast(u8, (v >> 24) & 0xFF);
    raw[1] = @intCast(u8, (v >> 16) & 0xFF);
    raw[2] = @intCast(u8, (v >> 8) & 0xFF);
    raw[3] = @intCast(u8, v & 0xFF);
    var out = hex.encodeLower(&g_arena, raw[0..]) catch @panic("hex u32");
    std.io.write(out);
}

fn expectB64Invalid(s: []const u8, what: []const u8) void {
    var got = b64.decode(&g_arena, s) catch |e| {
        ck(e == error.InvalidInput, what);
        return;
    };
    _ = got;
    ck(false, what);
}

fn expectHexInvalid(s: []const u8, what: []const u8) void {
    var got = hex.decode(&g_arena, s) catch |e| {
        ck(e == error.InvalidInput, what);
        return;
    };
    _ = got;
    ck(false, what);
}

pub fn main() void {
    // "Z98 " + U+00E9 (C3 A9): 5 code points, 6 bytes.
    var msg = [_]u8{ 0x5A, 0x39, 0x38, 0x20, 0xC3, 0xA9 };
    var m: []const u8 = msg[0..];

    // --- std_utf8: code point count + decode + encode -----------------------
    var cps: usize = utf8.countCodepoints(m);
    ck(cps == 5, "codepoint count");

    var first = utf8.decode(m);
    if (first) |cp| {
        ck(cp.cp == 90 and cp.len == 1, "first code point");
    } else {
        ck(false, "first code point null");
    }
    var second = utf8.decode(m[4..]);
    if (second) |cp2| {
        ck(cp2.cp == 233 and cp2.len == 2, "second code point");
    } else {
        ck(false, "second code point null");
    }

    var ebuf: [8]u8 = undefined;
    var e1 = utf8.encode(ebuf[0..], 233);
    if (e1) |enc| {
        ck(enc.len == 2 and enc[0] == 0xC3 and enc[1] == 0xA9, "encode e9");
    } else {
        ck(false, "encode e9 null");
    }
    var e2 = utf8.encode(ebuf[0..], 0x1F600);
    if (e2) |enc2| {
        ck(enc2.len == 4 and enc2[0] == 0xF0 and enc2[1] == 0x9F and enc2[2] == 0x98 and enc2[3] == 0x80, "encode emoji");
    } else {
        ck(false, "encode emoji null");
    }

    // --- std_base64 / std_hex: encode + round-trip + reject malformed -------
    var b64text = b64.encode(&g_arena, m) catch @panic("b64 encode");
    ckBytes(b64text, "Wjk4IMOp", "b64 value");
    var b64back = b64.decode(&g_arena, b64text) catch @panic("b64 decode");
    ckBytes(b64back, m, "b64 round-trip");

    var hextext = hex.encodeLower(&g_arena, m) catch @panic("hex encode");
    ckBytes(hextext, "5a393820c3a9", "hex value");
    var hexback = hex.decode(&g_arena, hextext) catch @panic("hex decode");
    ckBytes(hexback, m, "hex round-trip");

    expectB64Invalid("!!!!", "b64 invalid");
    expectHexInvalid("abc", "hex invalid");

    // --- std_crypto: SHA-256 + CRC-32 over the same message ----------------
    var digest: [32]u8 = undefined;
    var sha = crypto.sha256Init();
    crypto.sha256Update(&sha, m);
    crypto.sha256Final(&sha, &digest);
    var digest_hex = hex.encodeLower(&g_arena, digest[0..]) catch @panic("digest hex");
    ckBytes(digest_hex, "390edd46037981d883bd4363c30dccc4bc9b01b08dbc43192415539910872f09", "sha256 hex");
    var crc: u32 = crypto.crc32Final(crypto.crc32Update(crypto.crc32Init(), m));
    ck(crc == 0xF2E959AA, "crc32 value");

    // --- std_buf: frame magic + length + b64 + ':' + hex --------------------
    var b = std.buf.init(&g_arena);
    std.buf.appendU32BE(&b, 0x5A393843) catch @panic("buf magic");
    std.buf.appendU16BE(&b, @intCast(u16, m.len)) catch @panic("buf length");
    std.buf.append(&b, b64text) catch @panic("buf b64");
    std.buf.appendByte(&b, ':') catch @panic("buf sep");
    std.buf.append(&b, hextext) catch @panic("buf hex");
    var blob = std.buf.slice(&b);
    ck(blob.len == 27, "blob length");
    var blob_crc: u32 = crypto.crc32Final(crypto.crc32Update(crypto.crc32Init(), blob));

    // --- stdout contract ----------------------------------------------------
    std.io.write("crypto_codec_usage\n");
    std.io.write("codepoints: ");
    std.io.printInt(@intCast(i32, cps));
    std.io.write("\n");
    std.io.write("cp-first: 90\n");
    std.io.write("cp-second: 233\n");
    std.io.write("b64: ");
    std.io.write(b64text);
    std.io.write("\n");
    std.io.write("hex: ");
    std.io.write(hextext);
    std.io.write("\n");
    std.io.write("sha256: ");
    std.io.write(digest_hex);
    std.io.write("\n");
    std.io.write("crc32: ");
    writeHexU32(crc);
    std.io.write("\n");
    std.io.write("roundtrip: 1\n");
    std.io.write("invalid: 1\n");
    std.io.write("buf-len: ");
    std.io.printInt(@intCast(i32, blob.len));
    std.io.write("\n");
    std.io.write("buf-crc32: ");
    writeHexU32(blob_crc);
    std.io.write("\n");
    std.io.write("crypto_codec ok\n");
}
