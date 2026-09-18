// std_crypto.zig — Z98 std lib L5: streaming hashes + CRC-32.
//
// Contract (blueprint §3 L5): alloc no | errors no | coroutine no. Pure (no
// imports at all). Caller-provided state: every Init returns a value-type
// state, every Update takes *State, every Final writes into a caller array.
// Update may be called any number of times with any chunk sizes. Test vectors
// are RFC/FIPS normative (RFC 3174 SHA-1, FIPS 180-4 SHA-256, RFC 1321 MD5,
// IEEE 802.3 CRC-32).
//
// All modular arithmetic uses the explicit wrap operators (`+%`, `*%`) so the
// default -fsafe build does not trap on the (expected) mod-2^32 additions.
// Rotations mask the shifted half first: -fsafe traps on any left shift that
// discards high bits, and a raw `x << s` would discard exactly the bits the
// paired right shift re-inserts.

fn mask(bits: u32) u32 {
    if (bits == 0) return 0;
    if (bits >= 32) return ~@intCast(u32, 0);
    var one: u32 = 1;
    return (one << bits) - 1;
}

fn rotl32(x: u32, n: u32) u32 {
    var s: u32 = n % 32;
    if (s == 0) return x;
    var keep: u32 = x & mask(32 - s);
    return (keep << s) | (x >> (32 - s));
}

fn rotr32(x: u32, n: u32) u32 {
    var s: u32 = n % 32;
    if (s == 0) return x;
    var keep: u32 = x & mask(s);
    return (x >> s) | (keep << (32 - s));
}

// ---------------------------------------------------------------------------
// SHA-1 (RFC 3174)
// ---------------------------------------------------------------------------

pub const Sha1 = struct {
    h0: u32,
    h1: u32,
    h2: u32,
    h3: u32,
    h4: u32,
    buf: [64]u8,
    buf_len: usize,
    total: u64,
};

pub fn sha1Init() Sha1 {
    var s: Sha1 = undefined;
    s.h0 = 0x67452301;
    s.h1 = 0xEFCDAB89;
    s.h2 = 0x98BADCFE;
    s.h3 = 0x10325476;
    s.h4 = 0xC3D2E1F0;
    s.buf_len = 0;
    s.total = 0;
    return s;
}

fn sha1Block(s: *Sha1) void {
    var w: [80]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        w[i] = (@intCast(u32, s.buf[i * 4]) << 24) |
            (@intCast(u32, s.buf[i * 4 + 1]) << 16) |
            (@intCast(u32, s.buf[i * 4 + 2]) << 8) |
            @intCast(u32, s.buf[i * 4 + 3]);
    }
    while (i < 80) : (i += 1) {
        w[i] = rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    var a: u32 = s.h0;
    var b: u32 = s.h1;
    var c: u32 = s.h2;
    var d: u32 = s.h3;
    var e: u32 = s.h4;

    i = 0;
    while (i < 80) : (i += 1) {
        var f: u32 = 0;
        var k: u32 = 0;
        if (i < 20) {
            f = (b & c) | ((~b) & d);
            k = 0x5A827999;
        } else if (i < 40) {
            f = b ^ c ^ d;
            k = 0x6ED9EBA1;
        } else if (i < 60) {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8F1BBCDC;
        } else {
            f = b ^ c ^ d;
            k = 0xCA62C1D6;
        }
        var temp: u32 = rotl32(a, 5) +% f +% e +% k +% w[i];
        e = d;
        d = c;
        c = rotl32(b, 30);
        b = a;
        a = temp;
    }

    s.h0 = s.h0 +% a;
    s.h1 = s.h1 +% b;
    s.h2 = s.h2 +% c;
    s.h3 = s.h3 +% d;
    s.h4 = s.h4 +% e;
}

pub fn sha1Update(s: *Sha1, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        var take: usize = 64 - s.buf_len;
        var remaining: usize = data.len - i;
        if (take > remaining) take = remaining;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            s.buf[s.buf_len + j] = data[i + j];
        }
        s.buf_len += take;
        i += take;
        s.total = s.total +% @intCast(u64, take);
        if (s.buf_len == 64) {
            sha1Block(s);
            s.buf_len = 0;
        }
    }
}

pub fn sha1Final(s: *Sha1, out: *[20]u8) void {
    var bitlen: u64 = s.total *% 8;
    s.buf[s.buf_len] = 0x80;
    s.buf_len += 1;
    if (s.buf_len > 56) {
        while (s.buf_len < 64) {
            s.buf[s.buf_len] = 0;
            s.buf_len += 1;
        }
        sha1Block(s);
        s.buf_len = 0;
    }
    while (s.buf_len < 56) {
        s.buf[s.buf_len] = 0;
        s.buf_len += 1;
    }
    s.buf[56] = @intCast(u8, bitlen >> 56);
    s.buf[57] = @intCast(u8, (bitlen >> 48) & 0xFF);
    s.buf[58] = @intCast(u8, (bitlen >> 40) & 0xFF);
    s.buf[59] = @intCast(u8, (bitlen >> 32) & 0xFF);
    s.buf[60] = @intCast(u8, (bitlen >> 24) & 0xFF);
    s.buf[61] = @intCast(u8, (bitlen >> 16) & 0xFF);
    s.buf[62] = @intCast(u8, (bitlen >> 8) & 0xFF);
    s.buf[63] = @intCast(u8, bitlen & 0xFF);
    sha1Block(s);

    out[0] = @intCast(u8, s.h0 >> 24);
    out[1] = @intCast(u8, (s.h0 >> 16) & 0xFF);
    out[2] = @intCast(u8, (s.h0 >> 8) & 0xFF);
    out[3] = @intCast(u8, s.h0 & 0xFF);
    out[4] = @intCast(u8, s.h1 >> 24);
    out[5] = @intCast(u8, (s.h1 >> 16) & 0xFF);
    out[6] = @intCast(u8, (s.h1 >> 8) & 0xFF);
    out[7] = @intCast(u8, s.h1 & 0xFF);
    out[8] = @intCast(u8, s.h2 >> 24);
    out[9] = @intCast(u8, (s.h2 >> 16) & 0xFF);
    out[10] = @intCast(u8, (s.h2 >> 8) & 0xFF);
    out[11] = @intCast(u8, s.h2 & 0xFF);
    out[12] = @intCast(u8, s.h3 >> 24);
    out[13] = @intCast(u8, (s.h3 >> 16) & 0xFF);
    out[14] = @intCast(u8, (s.h3 >> 8) & 0xFF);
    out[15] = @intCast(u8, s.h3 & 0xFF);
    out[16] = @intCast(u8, s.h4 >> 24);
    out[17] = @intCast(u8, (s.h4 >> 16) & 0xFF);
    out[18] = @intCast(u8, (s.h4 >> 8) & 0xFF);
    out[19] = @intCast(u8, s.h4 & 0xFF);
}

// ---------------------------------------------------------------------------
// SHA-256 (FIPS 180-4)
// ---------------------------------------------------------------------------

pub const Sha256 = struct {
    h: [8]u32,
    buf: [64]u8,
    buf_len: usize,
    total: u64,
};

pub fn sha256Init() Sha256 {
    var s: Sha256 = undefined;
    s.h[0] = 0x6A09E667;
    s.h[1] = 0xBB67AE85;
    s.h[2] = 0x3C6EF372;
    s.h[3] = 0xA54FF53A;
    s.h[4] = 0x510E527F;
    s.h[5] = 0x9B05688C;
    s.h[6] = 0x1F83D9AB;
    s.h[7] = 0x5BE0CD19;
    s.buf_len = 0;
    s.total = 0;
    return s;
}

fn sha256Block(s: *Sha256) void {
    const k = [_]u32{
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    };

    var w: [64]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        w[i] = (@intCast(u32, s.buf[i * 4]) << 24) |
            (@intCast(u32, s.buf[i * 4 + 1]) << 16) |
            (@intCast(u32, s.buf[i * 4 + 2]) << 8) |
            @intCast(u32, s.buf[i * 4 + 3]);
    }
    while (i < 64) : (i += 1) {
        var s0: u32 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        var s1: u32 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
    }

    var a: u32 = s.h[0];
    var b: u32 = s.h[1];
    var c: u32 = s.h[2];
    var d: u32 = s.h[3];
    var e: u32 = s.h[4];
    var f: u32 = s.h[5];
    var g: u32 = s.h[6];
    var h: u32 = s.h[7];

    i = 0;
    while (i < 64) : (i += 1) {
        var big_s1: u32 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
        var ch: u32 = (e & f) ^ ((~e) & g);
        var t1: u32 = h +% big_s1 +% ch +% k[i] +% w[i];
        var big_s0: u32 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
        var maj: u32 = (a & b) ^ (a & c) ^ (b & c);
        var t2: u32 = big_s0 +% maj;
        h = g;
        g = f;
        f = e;
        e = d +% t1;
        d = c;
        c = b;
        b = a;
        a = t1 +% t2;
    }

    s.h[0] = s.h[0] +% a;
    s.h[1] = s.h[1] +% b;
    s.h[2] = s.h[2] +% c;
    s.h[3] = s.h[3] +% d;
    s.h[4] = s.h[4] +% e;
    s.h[5] = s.h[5] +% f;
    s.h[6] = s.h[6] +% g;
    s.h[7] = s.h[7] +% h;
}

pub fn sha256Update(s: *Sha256, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        var take: usize = 64 - s.buf_len;
        var remaining: usize = data.len - i;
        if (take > remaining) take = remaining;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            s.buf[s.buf_len + j] = data[i + j];
        }
        s.buf_len += take;
        i += take;
        s.total = s.total +% @intCast(u64, take);
        if (s.buf_len == 64) {
            sha256Block(s);
            s.buf_len = 0;
        }
    }
}

pub fn sha256Final(s: *Sha256, out: *[32]u8) void {
    var bitlen: u64 = s.total *% 8;
    s.buf[s.buf_len] = 0x80;
    s.buf_len += 1;
    if (s.buf_len > 56) {
        while (s.buf_len < 64) {
            s.buf[s.buf_len] = 0;
            s.buf_len += 1;
        }
        sha256Block(s);
        s.buf_len = 0;
    }
    while (s.buf_len < 56) {
        s.buf[s.buf_len] = 0;
        s.buf_len += 1;
    }
    s.buf[56] = @intCast(u8, bitlen >> 56);
    s.buf[57] = @intCast(u8, (bitlen >> 48) & 0xFF);
    s.buf[58] = @intCast(u8, (bitlen >> 40) & 0xFF);
    s.buf[59] = @intCast(u8, (bitlen >> 32) & 0xFF);
    s.buf[60] = @intCast(u8, (bitlen >> 24) & 0xFF);
    s.buf[61] = @intCast(u8, (bitlen >> 16) & 0xFF);
    s.buf[62] = @intCast(u8, (bitlen >> 8) & 0xFF);
    s.buf[63] = @intCast(u8, bitlen & 0xFF);
    sha256Block(s);

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        out[i * 4] = @intCast(u8, s.h[i] >> 24);
        out[i * 4 + 1] = @intCast(u8, (s.h[i] >> 16) & 0xFF);
        out[i * 4 + 2] = @intCast(u8, (s.h[i] >> 8) & 0xFF);
        out[i * 4 + 3] = @intCast(u8, s.h[i] & 0xFF);
    }
}

// ---------------------------------------------------------------------------
// MD5 (RFC 1321)
// ---------------------------------------------------------------------------

pub const Md5 = struct {
    h0: u32,
    h1: u32,
    h2: u32,
    h3: u32,
    buf: [64]u8,
    buf_len: usize,
    total: u64,
};

pub fn md5Init() Md5 {
    var s: Md5 = undefined;
    s.h0 = 0x67452301;
    s.h1 = 0xEFCDAB89;
    s.h2 = 0x98BADCFE;
    s.h3 = 0x10325476;
    s.buf_len = 0;
    s.total = 0;
    return s;
}

fn md5Block(s: *Md5) void {
    const k = [_]u32{
        0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE,
        0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501,
        0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE,
        0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821,
        0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA,
        0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
        0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED,
        0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A,
        0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C,
        0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70,
        0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05,
        0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
        0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039,
        0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1,
        0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1,
        0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391,
    };
    const sh = [_]u32{
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    };

    var m: [16]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        m[i] = @intCast(u32, s.buf[i * 4]) |
            (@intCast(u32, s.buf[i * 4 + 1]) << 8) |
            (@intCast(u32, s.buf[i * 4 + 2]) << 16) |
            (@intCast(u32, s.buf[i * 4 + 3]) << 24);
    }

    var a: u32 = s.h0;
    var b: u32 = s.h1;
    var c: u32 = s.h2;
    var d: u32 = s.h3;

    i = 0;
    while (i < 64) : (i += 1) {
        var f: u32 = 0;
        var g: usize = 0;
        if (i < 16) {
            f = (b & c) | ((~b) & d);
            g = i;
        } else if (i < 32) {
            f = (b & d) | (c & (~d));
            g = (5 * i + 1) % 16;
        } else if (i < 48) {
            f = b ^ c ^ d;
            g = (3 * i + 5) % 16;
        } else {
            f = c ^ (b | (~d));
            g = (7 * i) % 16;
        }
        var tmp: u32 = d;
        d = c;
        c = b;
        b = b +% rotl32(a +% f +% k[i] +% m[g], sh[i]);
        a = tmp;
    }

    s.h0 = s.h0 +% a;
    s.h1 = s.h1 +% b;
    s.h2 = s.h2 +% c;
    s.h3 = s.h3 +% d;
}

pub fn md5Update(s: *Md5, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        var take: usize = 64 - s.buf_len;
        var remaining: usize = data.len - i;
        if (take > remaining) take = remaining;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            s.buf[s.buf_len + j] = data[i + j];
        }
        s.buf_len += take;
        i += take;
        s.total = s.total +% @intCast(u64, take);
        if (s.buf_len == 64) {
            md5Block(s);
            s.buf_len = 0;
        }
    }
}

pub fn md5Final(s: *Md5, out: *[16]u8) void {
    var bitlen: u64 = s.total *% 8;
    s.buf[s.buf_len] = 0x80;
    s.buf_len += 1;
    if (s.buf_len > 56) {
        while (s.buf_len < 64) {
            s.buf[s.buf_len] = 0;
            s.buf_len += 1;
        }
        md5Block(s);
        s.buf_len = 0;
    }
    while (s.buf_len < 56) {
        s.buf[s.buf_len] = 0;
        s.buf_len += 1;
    }
    s.buf[56] = @intCast(u8, bitlen & 0xFF);
    s.buf[57] = @intCast(u8, (bitlen >> 8) & 0xFF);
    s.buf[58] = @intCast(u8, (bitlen >> 16) & 0xFF);
    s.buf[59] = @intCast(u8, (bitlen >> 24) & 0xFF);
    s.buf[60] = @intCast(u8, (bitlen >> 32) & 0xFF);
    s.buf[61] = @intCast(u8, (bitlen >> 40) & 0xFF);
    s.buf[62] = @intCast(u8, (bitlen >> 48) & 0xFF);
    s.buf[63] = @intCast(u8, bitlen >> 56);
    md5Block(s);

    out[0] = @intCast(u8, s.h0 & 0xFF);
    out[1] = @intCast(u8, (s.h0 >> 8) & 0xFF);
    out[2] = @intCast(u8, (s.h0 >> 16) & 0xFF);
    out[3] = @intCast(u8, s.h0 >> 24);
    out[4] = @intCast(u8, s.h1 & 0xFF);
    out[5] = @intCast(u8, (s.h1 >> 8) & 0xFF);
    out[6] = @intCast(u8, (s.h1 >> 16) & 0xFF);
    out[7] = @intCast(u8, s.h1 >> 24);
    out[8] = @intCast(u8, s.h2 & 0xFF);
    out[9] = @intCast(u8, (s.h2 >> 8) & 0xFF);
    out[10] = @intCast(u8, (s.h2 >> 16) & 0xFF);
    out[11] = @intCast(u8, s.h2 >> 24);
    out[12] = @intCast(u8, s.h3 & 0xFF);
    out[13] = @intCast(u8, (s.h3 >> 8) & 0xFF);
    out[14] = @intCast(u8, (s.h3 >> 16) & 0xFF);
    out[15] = @intCast(u8, s.h3 >> 24);
}

// ---------------------------------------------------------------------------
// CRC-32 (IEEE 802.3)
// ---------------------------------------------------------------------------

pub fn crc32Init() u32 {
    return 0xFFFFFFFF;
}

pub fn crc32Update(state: u32, data: []const u8) u32 {
    var crc: u32 = state;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        crc = crc ^ @intCast(u32, data[i]);
        var j: u32 = 0;
        while (j < 8) : (j += 1) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc = crc >> 1;
            }
        }
    }
    return crc;
}

pub fn crc32Final(state: u32) u32 {
    return state ^ 0xFFFFFFFF;
}
