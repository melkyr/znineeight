// std_crypto.zig — Z98 std lib L5: streaming hashes + CRC-32 + RC4 + modexp.
//
// Contract (blueprint §3 L5): alloc no | errors no | coroutine no. Pure (no
// imports at all). Caller-provided state: every Init returns a value-type
// state, every Update takes *State, every Final writes into a caller array.
// Update may be called any number of times with any chunk sizes. Test vectors
// are RFC/FIPS normative (RFC 3174 SHA-1, FIPS 180-4 SHA-256, RFC 1321 MD5,
// IEEE 802.3 CRC-32, RFC 6229 RC4). RC4 (`rc4Init`/`rc4Apply`) and modular
// exponentiation (`modpow`, fixed 32-bit limbs sized for the MSE 768-bit DH
// prime) support the MSE/PE encrypted handshake.
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

// ---------------------------------------------------------------------------
// RC4 (RFC 6229; used by the MSE/PE encrypted handshake)
// ---------------------------------------------------------------------------
//
// rc4Init runs the standard key-scheduling algorithm (KSA) over the caller's
// key; rc4Apply runs the pseudo-random generation algorithm (PRGA) XORed in
// place over a caller buffer. The MSE/PE layer discards the first 1024
// keystream bytes itself (not this primitive) before using the stream.

pub const Rc4 = struct {
    s: [256]u8,
    i: u8,
    j: u8,
};

pub fn rc4Init(key: []const u8, out: *Rc4) void {
    var x: usize = 0;
    while (x < 256) : (x += 1) {
        out.s[x] = @intCast(u8, x);
    }
    var j: usize = 0;
    var k: usize = 0;
    var y: usize = 0;
    while (y < 256) : (y += 1) {
        var keybyte: u8 = 0;
        if (key.len != 0) {
            keybyte = key[k];
            k += 1;
            if (k == key.len) k = 0;
        }
        j = (j + @intCast(usize, out.s[y]) + @intCast(usize, keybyte)) & 255;
        var tmp: u8 = out.s[y];
        out.s[y] = out.s[j];
        out.s[j] = tmp;
    }
    out.i = 0;
    out.j = 0;
}

pub fn rc4Apply(ctx: *Rc4, buf: []u8) void {
    var i: u8 = ctx.i;
    var j: u8 = ctx.j;
    var n: usize = 0;
    while (n < buf.len) : (n += 1) {
        i = i +% 1;
        var si: usize = @intCast(usize, i);
        j = j +% ctx.s[si];
        var sj: usize = @intCast(usize, j);
        var tmp: u8 = ctx.s[si];
        ctx.s[si] = ctx.s[sj];
        ctx.s[sj] = tmp;
        var k: u8 = ctx.s[si] +% ctx.s[sj];
        var sk: usize = @intCast(usize, k);
        buf[n] = buf[n] ^ ctx.s[sk];
    }
    ctx.i = i;
    ctx.j = j;
}

// ---------------------------------------------------------------------------
// Modular exponentiation (big-endian byte slices, fixed 32-bit limbs)
// ---------------------------------------------------------------------------
//
// Width is sized for the MSE/PE Diffie-Hellman 768-bit prime (96-byte
// modulus, big-endian).  Limbs are little-endian u32 words; the modulus may
// be any non-zero length up to 96 bytes, and is not required to be odd (the
// reducer is generic).  The exponent is a big-endian byte slice of any length
// (the MSE handshake uses up to a 96-byte secret).  `out` must be the same
// byte length as `modulus`; it receives base^exp mod modulus big-endian.
// Square-and-multiply over exponent bits (MSB first); each modular multiply
// is a left-to-right binary double-and-add over the multiplier bits, so all
// reduction is by conditional subtraction of the modulus.

const MpMaxBytes: usize = 96;
const MpMaxWords: usize = 24;

fn mpCmp(a: []const u32, b: []const u32, nw: usize) i32 {
    var i: usize = nw;
    while (i > 0) {
        i -= 1;
        if (a[i] > b[i]) return 1;
        if (a[i] < b[i]) return -1;
    }
    return 0;
}

fn mpSub(a: []u32, b: []const u32, nw: usize) void {
    var borrow: u32 = 0;
    var i: usize = 0;
    while (i < nw) : (i += 1) {
        var av: u64 = @intCast(u64, a[i]);
        var bv: u64 = @intCast(u64, b[i]) + @intCast(u64, borrow);
        a[i] = @intCast(u32, (av -% bv) & 0xFFFFFFFF);
        if (av < bv) borrow = 1 else borrow = 0;
    }
}

fn mpDouble(x: []u32, m: []const u32, nw: usize) void {
    var carry: u32 = 0;
    var i: usize = 0;
    while (i < nw) : (i += 1) {
        var v: u64 = (@intCast(u64, x[i]) << 1) | @intCast(u64, carry);
        x[i] = @intCast(u32, v & 0xFFFFFFFF);
        carry = @intCast(u32, v >> 32);
    }
    if (carry != 0) {
        mpSub(x, m, nw);
    } else if (mpCmp(x, m, nw) >= 0) {
        mpSub(x, m, nw);
    }
}

fn mpAddSmall(x: []u32, m: []const u32, nw: usize, add: u32) void {
    var carry: u64 = @intCast(u64, add);
    var i: usize = 0;
    while (i < nw and carry != 0) : (i += 1) {
        var v: u64 = @intCast(u64, x[i]) + carry;
        x[i] = @intCast(u32, v & 0xFFFFFFFF);
        carry = v >> 32;
    }
    if (mpCmp(x, m, nw) >= 0) {
        mpSub(x, m, nw);
    }
}

fn mpAddMod(r: []u32, a: []const u32, m: []const u32, nw: usize) void {
    var carry: u64 = 0;
    var i: usize = 0;
    while (i < nw) : (i += 1) {
        var v: u64 = @intCast(u64, r[i]) + @intCast(u64, a[i]) + carry;
        r[i] = @intCast(u32, v & 0xFFFFFFFF);
        carry = v >> 32;
    }
    if (carry != 0) {
        mpSub(r, m, nw);
    } else if (mpCmp(r, m, nw) >= 0) {
        mpSub(r, m, nw);
    }
}

fn mpBytesToWords(src: []const u8, dst: []u32, nw: usize) void {
    var i: usize = 0;
    while (i < nw) : (i += 1) {
        dst[i] = 0;
    }
    var b: usize = 0;
    while (b < src.len) : (b += 1) {
        var from_lsb: usize = src.len - 1 - b;
        var word: usize = from_lsb / 4;
        var sh: u32 = @intCast(u32, (from_lsb % 4) * 8);
        dst[word] = dst[word] | (@intCast(u32, src[b]) << sh);
    }
}

fn mpWordsToBytes(src: []const u32, nw: usize, dst: []u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = 0;
    }
    var b: usize = 0;
    while (b < dst.len) : (b += 1) {
        var from_lsb: usize = dst.len - 1 - b;
        var word: usize = from_lsb / 4;
        var sh: u32 = @intCast(u32, (from_lsb % 4) * 8);
        if (word < nw) {
            dst[b] = @intCast(u8, (src[word] >> sh) & 0xFF);
        }
    }
}

fn mpReduceBytes(src: []const u8, m: []const u32, nw: usize, out: []u32) void {
    var i: usize = 0;
    while (i < nw) : (i += 1) out[i] = 0;
    var bi: usize = 0;
    while (bi < src.len) : (bi += 1) {
        var k: u32 = 0;
        while (k < 8) : (k += 1) {
            mpDouble(out, m, nw);
            var bit: u32 = (@intCast(u32, src[bi]) >> (7 - k)) & 1;
            if (bit != 0) mpAddSmall(out, m, nw, 1);
        }
    }
}

fn mpMulMod(a: []const u32, b: []const u32, m: []const u32, nw: usize, out: []u32) void {
    var r: [MpMaxWords]u32 = undefined;
    var i: usize = 0;
    while (i < nw) : (i += 1) r[i] = 0;
    var wi: usize = nw;
    while (wi > 0) {
        wi -= 1;
        var k: u32 = 32;
        while (k > 0) {
            k -= 1;
            mpDouble(r[0..], m, nw);
            var bit: u32 = (b[wi] >> k) & 1;
            if (bit != 0) mpAddMod(r[0..], a, m, nw);
        }
    }
    i = 0;
    while (i < nw) : (i += 1) out[i] = r[i];
}

pub fn modpow(base: []const u8, exp: []const u8, modulus: []const u8, out: []u8) void {
    if (modulus.len == 0 or modulus.len > MpMaxBytes or out.len != modulus.len) {
        var z: usize = 0;
        while (z < out.len) : (z += 1) out[z] = 0;
        return;
    }
    var nw: usize = (modulus.len + 3) / 4;
    var m: [MpMaxWords]u32 = undefined;
    var i: usize = 0;
    while (i < nw) : (i += 1) m[i] = 0;
    mpBytesToWords(modulus, m[0..], nw);

    var bm: [MpMaxWords]u32 = undefined;
    mpReduceBytes(base, m[0..], nw, bm[0..]);

    var res: [MpMaxWords]u32 = undefined;
    i = 0;
    while (i < nw) : (i += 1) res[i] = 0;
    res[0] = 1;
    if (mpCmp(res[0..], m[0..], nw) >= 0) mpSub(res[0..], m[0..], nw);

    var tmp: [MpMaxWords]u32 = undefined;
    var ei: usize = 0;
    while (ei < exp.len) : (ei += 1) {
        var k: u32 = 0;
        while (k < 8) : (k += 1) {
            mpMulMod(res[0..], res[0..], m[0..], nw, tmp[0..]);
            var q: usize = 0;
            while (q < nw) : (q += 1) res[q] = tmp[q];
            if (((@intCast(u32, exp[ei]) >> (7 - k)) & 1) != 0) {
                mpMulMod(res[0..], bm[0..], m[0..], nw, tmp[0..]);
                q = 0;
                while (q < nw) : (q += 1) res[q] = tmp[q];
            }
        }
    }
    mpWordsToBytes(res[0..], nw, out);
}

fn mask64(bits: u64) u64 {
    if (bits == 0) return 0;
    if (bits >= 64) return ~@intCast(u64, 0);
    var one: u64 = 1;
    return (one << bits) - 1;
}

fn rotl64(x: u64, n: u64) u64 {
    var s: u64 = n % 64;
    if (s == 0) return x;
    var keep: u64 = x & mask64(64 - s);
    return (keep << s) | (x >> (64 - s));
}

fn rotr64(x: u64, n: u64) u64 {
    var s: u64 = n % 64;
    if (s == 0) return x;
    var keep: u64 = x & mask64(s);
    return (x >> s) | (keep << (64 - s));
}

pub const Sha384 = struct {
    h: [8]u64,
    buf: [128]u8,
    buf_len: usize,
    total: u64,
};

pub const Sha512 = struct {
    h: [8]u64,
    buf: [128]u8,
    buf_len: usize,
    total: u64,
};

fn sha512Block(h: []u64, buf: []const u8) void {
    const k = [_]u64{
        0x428A2F98D728AE22, 0x7137449123EF65CD, 0xB5C0FBCFEC4D3B2F, 0xE9B5DBA58189DBBC,
        0x3956C25BF348B538, 0x59F111F1B605D019, 0x923F82A4AF194F9B, 0xAB1C5ED5DA6D8118,
        0xD807AA98A3030242, 0x12835B0145706FBE, 0x243185BE4EE4B28C, 0x550C7DC3D5FFB4E2,
        0x72BE5D74F27B896F, 0x80DEB1FE3B1696B1, 0x9BDC06A725C71235, 0xC19BF174CF692694,
        0xE49B69C19EF14AD2, 0xEFBE4786384F25E3, 0x0FC19DC68B8CD5B5, 0x240CA1CC77AC9C65,
        0x2DE92C6F592B0275, 0x4A7484AA6EA6E483, 0x5CB0A9DCBD41FBD4, 0x76F988DA831153B5,
        0x983E5152EE66DFAB, 0xA831C66D2DB43210, 0xB00327C898FB213F, 0xBF597FC7BEEF0EE4,
        0xC6E00BF33DA88FC2, 0xD5A79147930AA725, 0x06CA6351E003826F, 0x142929670A0E6E70,
        0x27B70A8546D22FFC, 0x2E1B21385C26C926, 0x4D2C6DFC5AC42AED, 0x53380D139D95B3DF,
        0x650A73548BAF63DE, 0x766A0ABB3C77B2A8, 0x81C2C92E47EDAEE6, 0x92722C851482353B,
        0xA2BFE8A14CF10364, 0xA81A664BBC423001, 0xC24B8B70D0F89791, 0xC76C51A30654BE30,
        0xD192E819D6EF5218, 0xD69906245565A910, 0xF40E35855771202A, 0x106AA07032BBD1B8,
        0x19A4C116B8D2D0C8, 0x1E376C085141AB53, 0x2748774CDF8EEB99, 0x34B0BCB5E19B48A8,
        0x391C0CB3C5C95A63, 0x4ED8AA4AE3418ACB, 0x5B9CCA4F7763E373, 0x682E6FF3D6B2B8A3,
        0x748F82EE5DEFB2FC, 0x78A5636F43172F60, 0x84C87814A1F0AB72, 0x8CC702081A6439EC,
        0x90BEFFFA23631E28, 0xA4506CEBDE82BDE9, 0xBEF9A3F7B2C67915, 0xC67178F2E372532B,
        0xCA273ECEEA26619C, 0xD186B8C721C0C207, 0xEADA7DD6CDE0EB1E, 0xF57D4F7FEE6ED178,
        0x06F067AA72176FBA, 0x0A637DC5A2C898A6, 0x113F9804BEF90DAE, 0x1B710B35131C471B,
        0x28DB77F523047D84, 0x32CAAB7B40C72493, 0x3C9EBE0A15C9BEBC, 0x431D67C49C100D4C,
        0x4CC5D4BECB3E42B6, 0x597F299CFC657E2A, 0x5FCB6FAB3AD6FAEC, 0x6C44198C4A475817,
    };

    var w: [80]u64 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        w[i] = (@intCast(u64, buf[i * 8]) << 56) |
            (@intCast(u64, buf[i * 8 + 1]) << 48) |
            (@intCast(u64, buf[i * 8 + 2]) << 40) |
            (@intCast(u64, buf[i * 8 + 3]) << 32) |
            (@intCast(u64, buf[i * 8 + 4]) << 24) |
            (@intCast(u64, buf[i * 8 + 5]) << 16) |
            (@intCast(u64, buf[i * 8 + 6]) << 8) |
            @intCast(u64, buf[i * 8 + 7]);
    }
    while (i < 80) : (i += 1) {
        var s0: u64 = rotr64(w[i - 15], 1) ^ rotr64(w[i - 15], 8) ^ (w[i - 15] >> 7);
        var s1: u64 = rotr64(w[i - 2], 19) ^ rotr64(w[i - 2], 61) ^ (w[i - 2] >> 6);
        w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
    }

    var a: u64 = h[0];
    var b: u64 = h[1];
    var c: u64 = h[2];
    var d: u64 = h[3];
    var e: u64 = h[4];
    var f: u64 = h[5];
    var g: u64 = h[6];
    var hh: u64 = h[7];

    i = 0;
    while (i < 80) : (i += 1) {
        var big_s1: u64 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41);
        var ch: u64 = (e & f) ^ ((~e) & g);
        var t1: u64 = hh +% big_s1 +% ch +% k[i] +% w[i];
        var big_s0: u64 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39);
        var maj: u64 = (a & b) ^ (a & c) ^ (b & c);
        var t2: u64 = big_s0 +% maj;
        hh = g;
        g = f;
        f = e;
        e = d +% t1;
        d = c;
        c = b;
        b = a;
        a = t1 +% t2;
    }

    h[0] = h[0] +% a;
    h[1] = h[1] +% b;
    h[2] = h[2] +% c;
    h[3] = h[3] +% d;
    h[4] = h[4] +% e;
    h[5] = h[5] +% f;
    h[6] = h[6] +% g;
    h[7] = h[7] +% hh;
}

pub fn sha384Init() Sha384 {
    var s: Sha384 = undefined;
    s.h[0] = 0xCBBB9D5DC1059ED8;
    s.h[1] = 0x629A292A367CD507;
    s.h[2] = 0x9159015A3070DD17;
    s.h[3] = 0x152FECD8F70E5939;
    s.h[4] = 0x67332667FFC00B31;
    s.h[5] = 0x8EB44A8768581511;
    s.h[6] = 0xDB0C2E0D64F98FA7;
    s.h[7] = 0x47B5481DBEFA4FA4;
    s.buf_len = 0;
    s.total = 0;
    return s;
}

pub fn sha512Init() Sha512 {
    var s: Sha512 = undefined;
    s.h[0] = 0x6A09E667F3BCC908;
    s.h[1] = 0xBB67AE8584CAA73B;
    s.h[2] = 0x3C6EF372FE94F82B;
    s.h[3] = 0xA54FF53A5F1D36F1;
    s.h[4] = 0x510E527FADE682D1;
    s.h[5] = 0x9B05688C2B3E6C1F;
    s.h[6] = 0x1F83D9ABFB41BD6B;
    s.h[7] = 0x5BE0CD19137E2179;
    s.buf_len = 0;
    s.total = 0;
    return s;
}

pub fn sha384Update(s: *Sha384, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        var take: usize = 128 - s.buf_len;
        var remaining: usize = data.len - i;
        if (take > remaining) take = remaining;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            s.buf[s.buf_len + j] = data[i + j];
        }
        s.buf_len += take;
        i += take;
        s.total = s.total +% @intCast(u64, take);
        if (s.buf_len == 128) {
            sha512Block(s.h[0..], s.buf[0..]);
            s.buf_len = 0;
        }
    }
}

pub fn sha512Update(s: *Sha512, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        var take: usize = 128 - s.buf_len;
        var remaining: usize = data.len - i;
        if (take > remaining) take = remaining;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            s.buf[s.buf_len + j] = data[i + j];
        }
        s.buf_len += take;
        i += take;
        s.total = s.total +% @intCast(u64, take);
        if (s.buf_len == 128) {
            sha512Block(s.h[0..], s.buf[0..]);
            s.buf_len = 0;
        }
    }
}

fn sha512Pad(h: []u64, buf: []u8, buf_len_start: usize, total: u64) void {
    var buf_len: usize = buf_len_start;
    var bitlen: u64 = total *% 8;
    buf[buf_len] = 0x80;
    buf_len += 1;
    if (buf_len > 112) {
        while (buf_len < 128) {
            buf[buf_len] = 0;
            buf_len += 1;
        }
        sha512Block(h, buf);
        buf_len = 0;
    }
    while (buf_len < 112) {
        buf[buf_len] = 0;
        buf_len += 1;
    }
    buf[112] = 0;
    buf[113] = 0;
    buf[114] = 0;
    buf[115] = 0;
    buf[116] = 0;
    buf[117] = 0;
    buf[118] = 0;
    buf[119] = 0;
    buf[120] = @intCast(u8, bitlen >> 56);
    buf[121] = @intCast(u8, (bitlen >> 48) & 0xFF);
    buf[122] = @intCast(u8, (bitlen >> 40) & 0xFF);
    buf[123] = @intCast(u8, (bitlen >> 32) & 0xFF);
    buf[124] = @intCast(u8, (bitlen >> 24) & 0xFF);
    buf[125] = @intCast(u8, (bitlen >> 16) & 0xFF);
    buf[126] = @intCast(u8, (bitlen >> 8) & 0xFF);
    buf[127] = @intCast(u8, bitlen & 0xFF);
    sha512Block(h, buf);
}

pub fn sha384Final(s: *Sha384, out: *[48]u8) void {
    sha512Pad(s.h[0..], s.buf[0..], s.buf_len, s.total);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        out[i * 8] = @intCast(u8, s.h[i] >> 56);
        out[i * 8 + 1] = @intCast(u8, (s.h[i] >> 48) & 0xFF);
        out[i * 8 + 2] = @intCast(u8, (s.h[i] >> 40) & 0xFF);
        out[i * 8 + 3] = @intCast(u8, (s.h[i] >> 32) & 0xFF);
        out[i * 8 + 4] = @intCast(u8, (s.h[i] >> 24) & 0xFF);
        out[i * 8 + 5] = @intCast(u8, (s.h[i] >> 16) & 0xFF);
        out[i * 8 + 6] = @intCast(u8, (s.h[i] >> 8) & 0xFF);
        out[i * 8 + 7] = @intCast(u8, s.h[i] & 0xFF);
    }
}

pub fn sha512Final(s: *Sha512, out: *[64]u8) void {
    sha512Pad(s.h[0..], s.buf[0..], s.buf_len, s.total);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        out[i * 8] = @intCast(u8, s.h[i] >> 56);
        out[i * 8 + 1] = @intCast(u8, (s.h[i] >> 48) & 0xFF);
        out[i * 8 + 2] = @intCast(u8, (s.h[i] >> 40) & 0xFF);
        out[i * 8 + 3] = @intCast(u8, (s.h[i] >> 32) & 0xFF);
        out[i * 8 + 4] = @intCast(u8, (s.h[i] >> 24) & 0xFF);
        out[i * 8 + 5] = @intCast(u8, (s.h[i] >> 16) & 0xFF);
        out[i * 8 + 6] = @intCast(u8, (s.h[i] >> 8) & 0xFF);
        out[i * 8 + 7] = @intCast(u8, s.h[i] & 0xFF);
    }
}

pub const HmacSha256 = struct {
    inner: Sha256,
    outer: Sha256,
};

pub fn hmacSha256Init(key: []const u8) HmacSha256 {
    var k: [64]u8 = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) k[i] = 0;
    if (key.len > 64) {
        var kh: [32]u8 = undefined;
        var ks = sha256Init();
        sha256Update(&ks, key);
        sha256Final(&ks, &kh);
        i = 0;
        while (i < 32) : (i += 1) k[i] = kh[i];
    } else {
        i = 0;
        while (i < key.len) : (i += 1) k[i] = key[i];
    }

    var s: HmacSha256 = undefined;
    s.inner = sha256Init();
    s.outer = sha256Init();
    var pad: [64]u8 = undefined;
    i = 0;
    while (i < 64) : (i += 1) pad[i] = k[i] ^ 0x36;
    sha256Update(&s.inner, pad[0..]);
    i = 0;
    while (i < 64) : (i += 1) pad[i] = k[i] ^ 0x5c;
    sha256Update(&s.outer, pad[0..]);
    return s;
}

pub fn hmacSha256Update(s: *HmacSha256, data: []const u8) void {
    sha256Update(&s.inner, data);
}

pub fn hmacSha256Final(s: *HmacSha256, out: *[32]u8) void {
    var inner: [32]u8 = undefined;
    sha256Final(&s.inner, &inner);
    sha256Update(&s.outer, inner[0..]);
    sha256Final(&s.outer, out);
}

pub fn hmacSha256(key: []const u8, msg: []const u8, out: *[32]u8) void {
    var s = hmacSha256Init(key);
    hmacSha256Update(&s, msg);
    hmacSha256Final(&s, out);
}

pub fn hkdfExtract(salt: []const u8, ikm: []const u8, out: *[32]u8) void {
    hmacSha256(salt, ikm, out);
}

pub fn hkdfExpand(prk: *const [32]u8, info: []const u8, out: []u8) !void {
    if (out.len > 255 * 32) return error.Corrupt;
    var t: [32]u8 = undefined;
    var tlen: usize = 0;
    var off: usize = 0;
    var counter: u8 = 1;
    while (off < out.len) {
        var s = hmacSha256Init(prk[0..]);
        hmacSha256Update(&s, t[0..tlen]);
        hmacSha256Update(&s, info);
        var cb: [1]u8 = undefined;
        cb[0] = counter;
        hmacSha256Update(&s, cb[0..]);
        hmacSha256Final(&s, &t);
        tlen = 32;
        var take: usize = out.len - off;
        if (take > 32) take = 32;
        var i: usize = 0;
        while (i < take) : (i += 1) out[off + i] = t[i];
        off += take;
        counter = counter +% 1;
    }
}

pub const Blake2s = struct {
    h: [8]u32,
    t: u64,
    buf: [64]u8,
    buf_len: usize,
    out_len: u32,
    key_len: u32,
};

fn blake2sG(v: []u32, a: usize, b: usize, c: usize, d: usize, x: u32, y: u32) void {
    v[a] = v[a] +% v[b] +% x;
    v[d] = rotr32(v[d] ^ v[a], 16);
    v[c] = v[c] +% v[d];
    v[b] = rotr32(v[b] ^ v[c], 12);
    v[a] = v[a] +% v[b] +% y;
    v[d] = rotr32(v[d] ^ v[a], 8);
    v[c] = v[c] +% v[d];
    v[b] = rotr32(v[b] ^ v[c], 7);
}

fn blake2sCompress(s: *Blake2s, final: bool) void {
    const sigma = [_]u8{
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
        11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
        7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
        9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
        2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
        12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
        13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
        6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
        10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
    };
    const iv = [_]u32{
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    };
    var m: [16]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        m[i] = @intCast(u32, s.buf[i * 4]) |
            (@intCast(u32, s.buf[i * 4 + 1]) << 8) |
            (@intCast(u32, s.buf[i * 4 + 2]) << 16) |
            (@intCast(u32, s.buf[i * 4 + 3]) << 24);
    }
    var v: [16]u32 = undefined;
    i = 0;
    while (i < 8) : (i += 1) {
        v[i] = s.h[i];
        v[i + 8] = iv[i];
    }
    v[12] = v[12] ^ @intCast(u32, s.t & 0xFFFFFFFF);
    v[13] = v[13] ^ @intCast(u32, s.t >> 32);
    if (final) v[14] = ~v[14];

    var r: usize = 0;
    while (r < 10) : (r += 1) {
        var o: usize = r * 16;
        blake2sG(v[0..], 0, 4, 8, 12, m[sigma[o + 0]], m[sigma[o + 1]]);
        blake2sG(v[0..], 1, 5, 9, 13, m[sigma[o + 2]], m[sigma[o + 3]]);
        blake2sG(v[0..], 2, 6, 10, 14, m[sigma[o + 4]], m[sigma[o + 5]]);
        blake2sG(v[0..], 3, 7, 11, 15, m[sigma[o + 6]], m[sigma[o + 7]]);
        blake2sG(v[0..], 0, 5, 10, 15, m[sigma[o + 8]], m[sigma[o + 9]]);
        blake2sG(v[0..], 1, 6, 11, 12, m[sigma[o + 10]], m[sigma[o + 11]]);
        blake2sG(v[0..], 2, 7, 8, 13, m[sigma[o + 12]], m[sigma[o + 13]]);
        blake2sG(v[0..], 3, 4, 9, 14, m[sigma[o + 14]], m[sigma[o + 15]]);
    }
    i = 0;
    while (i < 8) : (i += 1) s.h[i] = s.h[i] ^ v[i] ^ v[i + 8];
}

pub fn blake2sInit(key: []const u8, out_len: u32) Blake2s {
    var s: Blake2s = undefined;
    s.h[0] = 0x6A09E667;
    s.h[1] = 0xBB67AE85;
    s.h[2] = 0x3C6EF372;
    s.h[3] = 0xA54FF53A;
    s.h[4] = 0x510E527F;
    s.h[5] = 0x9B05688C;
    s.h[6] = 0x1F83D9AB;
    s.h[7] = 0x5BE0CD19;
    s.t = 0;
    s.buf_len = 0;
    s.out_len = out_len;
    var klen: u32 = @intCast(u32, key.len);
    if (klen > 32) klen = 32;
    s.key_len = klen;
    s.h[0] = s.h[0] ^ (0x01010000 ^ (klen << 8) ^ out_len);
    if (klen > 0) {
        var i: usize = 0;
        while (i < 64) : (i += 1) s.buf[i] = 0;
        i = 0;
        while (i < @intCast(usize, klen)) : (i += 1) s.buf[i] = key[i];
        s.buf_len = 64;
    }
    return s;
}

pub fn blake2sUpdate(s: *Blake2s, data: []const u8) void {
    var i: usize = 0;
    if (s.buf_len == 64 and data.len > 0) {
        s.t = s.t +% 64;
        blake2sCompress(s, false);
        s.buf_len = 0;
    }
    while (i < data.len) {
        if (s.buf_len == 64) {
            s.t = s.t +% 64;
            blake2sCompress(s, false);
            s.buf_len = 0;
        }
        var take: usize = 64 - s.buf_len;
        var remaining: usize = data.len - i;
        if (take > remaining) take = remaining;
        var j: usize = 0;
        while (j < take) : (j += 1) {
            s.buf[s.buf_len + j] = data[i + j];
        }
        s.buf_len += take;
        i += take;
    }
}

pub fn blake2sFinal(s: *Blake2s, out: []u8) void {
    s.t = s.t +% @intCast(u64, s.buf_len);
    while (s.buf_len < 64) {
        s.buf[s.buf_len] = 0;
        s.buf_len += 1;
    }
    blake2sCompress(s, true);
    var n: usize = out.len;
    if (n > 32) n = 32;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var w: usize = i / 4;
        var sh: u32 = @intCast(u32, (i % 4) * 8);
        out[i] = @intCast(u8, (s.h[w] >> sh) & 0xFF);
    }
}

pub fn hmacBlake2s(key: []const u8, msg: []const u8, out: []u8) void {
    if (out.len == 0 or out.len > 32) return;
    var s = blake2sInit(key, @intCast(u32, out.len));
    blake2sUpdate(&s, msg);
    blake2sFinal(&s, out);
}

pub const HashAlg = enum {
    sha256,
    sha384,
    sha512,
};

fn hashAlgLen(alg: HashAlg) usize {
    if (alg == HashAlg.sha256) return 32;
    if (alg == HashAlg.sha384) return 48;
    return 64;
}

fn hashData(alg: HashAlg, data: []const u8, out: []u8) void {
    var i: usize = 0;
    if (alg == HashAlg.sha256) {
        var s = sha256Init();
        sha256Update(&s, data);
        var d: [32]u8 = undefined;
        sha256Final(&s, &d);
        while (i < 32 and i < out.len) : (i += 1) out[i] = d[i];
    } else if (alg == HashAlg.sha384) {
        var s = sha384Init();
        sha384Update(&s, data);
        var d: [48]u8 = undefined;
        sha384Final(&s, &d);
        while (i < 48 and i < out.len) : (i += 1) out[i] = d[i];
    } else {
        var s = sha512Init();
        sha512Update(&s, data);
        var d: [64]u8 = undefined;
        sha512Final(&s, &d);
        while (i < 64 and i < out.len) : (i += 1) out[i] = d[i];
    }
}

const BigMaxBytes: usize = 512;
const BigMaxWords: usize = 128;

fn bigFromBytes(src: []const u8, dst: []u32) void {
    var i: usize = 0;
    while (i < BigMaxWords) : (i += 1) dst[i] = 0;
    var b: usize = 0;
    while (b < src.len) : (b += 1) {
        var from_lsb: usize = src.len - 1 - b;
        var word: usize = from_lsb / 4;
        var sh: u32 = @intCast(u32, (from_lsb % 4) * 8);
        if (word < BigMaxWords) {
            dst[word] = dst[word] | (@intCast(u32, src[b]) << sh);
        }
    }
}

fn bigToBytes(src: []const u32, dst: []u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) dst[i] = 0;
    var b: usize = 0;
    while (b < dst.len) : (b += 1) {
        var from_lsb: usize = dst.len - 1 - b;
        var word: usize = from_lsb / 4;
        var sh: u32 = @intCast(u32, (from_lsb % 4) * 8);
        if (word < BigMaxWords) {
            dst[b] = @intCast(u8, (src[word] >> sh) & 0xFF);
        }
    }
}

fn bigCmp(a: []const u32, b: []const u32) i32 {
    var i: usize = BigMaxWords;
    while (i > 0) {
        i -= 1;
        if (a[i] > b[i]) return 1;
        if (a[i] < b[i]) return -1;
    }
    return 0;
}

fn bigSub(a: []u32, b: []const u32) void {
    var borrow: u32 = 0;
    var i: usize = 0;
    while (i < BigMaxWords) : (i += 1) {
        var av: u64 = @intCast(u64, a[i]);
        var bv: u64 = @intCast(u64, b[i]) + @intCast(u64, borrow);
        a[i] = @intCast(u32, (av -% bv) & 0xFFFFFFFF);
        if (av < bv) {
            borrow = 1;
        } else {
            borrow = 0;
        }
    }
}

fn bigDoubleMod(x: []u32, n: []const u32) void {
    var carry: u32 = 0;
    var i: usize = 0;
    while (i < BigMaxWords) : (i += 1) {
        var v: u64 = (@intCast(u64, x[i]) << 1) | @intCast(u64, carry);
        x[i] = @intCast(u32, v & 0xFFFFFFFF);
        carry = @intCast(u32, v >> 32);
    }
    if (carry != 0 or bigCmp(x, n) >= 0) {
        bigSub(x, n);
    }
}

fn bigInvWord(a: u32) u32 {
    var x: u32 = a;
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        x = x *% (2 -% (a *% x));
    }
    return x;
}

fn bigMontMul(a: []const u32, b: []const u32, n: []const u32, n0inv: u32, out: []u32) void {
    var t: [BigMaxWords + 2]u32 = undefined;
    var i: usize = 0;
    while (i < BigMaxWords + 2) : (i += 1) t[i] = 0;

    i = 0;
    while (i < BigMaxWords) : (i += 1) {
        var carry: u64 = 0;
        var j: usize = 0;
        while (j < BigMaxWords) : (j += 1) {
            var uv: u64 = @intCast(u64, t[j]) + @intCast(u64, a[j]) * @intCast(u64, b[i]) + carry;
            t[j] = @intCast(u32, uv & 0xFFFFFFFF);
            carry = uv >> 32;
        }
        var uv2: u64 = @intCast(u64, t[BigMaxWords]) + carry;
        t[BigMaxWords] = @intCast(u32, uv2 & 0xFFFFFFFF);
        t[BigMaxWords + 1] = @intCast(u32, uv2 >> 32);

        var m: u32 = t[0] *% n0inv;
        carry = 0;
        j = 0;
        while (j < BigMaxWords) : (j += 1) {
            var uv: u64 = @intCast(u64, t[j]) + @intCast(u64, m) * @intCast(u64, n[j]) + carry;
            if (j > 0) t[j - 1] = @intCast(u32, uv & 0xFFFFFFFF);
            carry = uv >> 32;
        }
        var uv3: u64 = @intCast(u64, t[BigMaxWords]) + carry;
        t[BigMaxWords - 1] = @intCast(u32, uv3 & 0xFFFFFFFF);
        var top: u64 = @intCast(u64, t[BigMaxWords + 1]) + (uv3 >> 32);
        t[BigMaxWords] = @intCast(u32, top & 0xFFFFFFFF);
    }

    i = 0;
    while (i < BigMaxWords) : (i += 1) out[i] = t[i];
    if (t[BigMaxWords] != 0 or bigCmp(out, n) >= 0) {
        bigSub(out, n);
    }
}

fn rsaPublicDecrypt(n: []const u8, e: u32, sig: []const u8, out: []u8) bool {
    if (n.len == 0 or n.len > BigMaxBytes or sig.len != n.len or out.len != n.len) return false;

    var nl: [BigMaxWords]u32 = undefined;
    bigFromBytes(n, nl[0..]);
    if ((nl[0] & 1) == 0) return false;

    var sl: [BigMaxWords]u32 = undefined;
    bigFromBytes(sig, sl[0..]);
    if (bigCmp(sl[0..], nl[0..]) >= 0) return false;

    var inv: u32 = bigInvWord(nl[0]);
    var zero: u32 = 0;
    var n0inv: u32 = zero -% inv;

    var rmod: [BigMaxWords]u32 = undefined;
    var i: usize = 0;
    while (i < BigMaxWords) : (i += 1) rmod[i] = 0;
    rmod[0] = 1;
    i = 0;
    while (i < 32 * BigMaxWords) : (i += 1) {
        bigDoubleMod(rmod[0..], nl[0..]);
    }

    var r2: [BigMaxWords]u32 = undefined;
    i = 0;
    while (i < BigMaxWords) : (i += 1) r2[i] = rmod[i];
    i = 0;
    while (i < 32 * BigMaxWords) : (i += 1) {
        bigDoubleMod(r2[0..], nl[0..]);
    }

    var ym: [BigMaxWords]u32 = undefined;
    bigMontMul(sl[0..], r2[0..], nl[0..], n0inv, ym[0..]);

    var acc: [BigMaxWords]u32 = undefined;
    i = 0;
    while (i < BigMaxWords) : (i += 1) acc[i] = rmod[i];

    var base: [BigMaxWords]u32 = undefined;
    i = 0;
    while (i < BigMaxWords) : (i += 1) base[i] = ym[i];

    var ee: u32 = e;
    while (ee != 0) {
        if ((ee & 1) != 0) {
            bigMontMul(acc[0..], base[0..], nl[0..], n0inv, acc[0..]);
        }
        ee = ee >> 1;
        if (ee != 0) {
            bigMontMul(base[0..], base[0..], nl[0..], n0inv, base[0..]);
        }
    }

    var one: [BigMaxWords]u32 = undefined;
    i = 0;
    while (i < BigMaxWords) : (i += 1) one[i] = 0;
    one[0] = 1;
    var res: [BigMaxWords]u32 = undefined;
    bigMontMul(acc[0..], one[0..], nl[0..], n0inv, res[0..]);
    bigToBytes(res[0..], out);
    return true;
}

fn eqRange(a: []const u8, start: usize, b: []const u8) bool {
    if (start + b.len > a.len) return false;
    var i: usize = 0;
    while (i < b.len) : (i += 1) {
        if (a[start + i] != b[i]) return false;
    }
    return true;
}

fn pkcs1Check(alg: HashAlg, hash: []const u8, em: []const u8) bool {
    if (em.len < 11) return false;
    if (em[0] != 0 or em[1] != 1) return false;
    var idx: usize = 2;
    var ff: usize = 0;
    while (idx < em.len and em[idx] == 0xFF) {
        idx += 1;
        ff += 1;
    }
    if (ff < 8) return false;
    if (idx >= em.len or em[idx] != 0) return false;
    idx += 1;

    if (alg == HashAlg.sha256) {
        var p = [_]u8{ 0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20 };
        if (!eqRange(em, idx, p[0..])) return false;
        idx += 19;
    } else if (alg == HashAlg.sha384) {
        var p = [_]u8{ 0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30 };
        if (!eqRange(em, idx, p[0..])) return false;
        idx += 19;
    } else {
        var p = [_]u8{ 0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40 };
        if (!eqRange(em, idx, p[0..])) return false;
        idx += 19;
    }
    if (idx + hash.len != em.len) return false;
    return eqRange(em, idx, hash);
}

fn mgf1(alg: HashAlg, seed: []const u8, out: []u8) void {
    var hlen: usize = hashAlgLen(alg);
    var buf: [68]u8 = undefined;
    var t: [64]u8 = undefined;
    var counter: u32 = 0;
    var off: usize = 0;
    while (off < out.len) {
        var i: usize = 0;
        while (i < seed.len) : (i += 1) buf[i] = seed[i];
        buf[seed.len] = @intCast(u8, (counter >> 24) & 0xFF);
        buf[seed.len + 1] = @intCast(u8, (counter >> 16) & 0xFF);
        buf[seed.len + 2] = @intCast(u8, (counter >> 8) & 0xFF);
        buf[seed.len + 3] = @intCast(u8, counter & 0xFF);
        hashData(alg, buf[0 .. seed.len + 4], t[0..hlen]);
        var take: usize = out.len - off;
        if (take > hlen) take = hlen;
        i = 0;
        while (i < take) : (i += 1) out[off + i] = t[i];
        off += take;
        counter += 1;
    }
}

fn pssCheck(alg: HashAlg, hash: []const u8, salt_len: u32, em: []const u8, em_bits: usize) bool {
    var hlen: usize = hashAlgLen(alg);
    var sl: usize = @intCast(usize, salt_len);
    if (em.len < hlen + sl + 2) return false;
    if (em[em.len - 1] != 0xbc) return false;

    var db_len: usize = em.len - hlen - 1;
    var unused: usize = 8 * em.len - em_bits;
    if (unused > 8) return false;
    if (unused > 0) {
        var shift: u32 = @intCast(u32, 8 - unused);
        var wide: u32 = @intCast(u32, 0xFF) << shift;
        var topmask: u8 = @intCast(u8, wide & 0xFF);
        if ((em[0] & topmask) != 0) return false;
    }

    var db: [BigMaxBytes]u8 = undefined;
    mgf1(alg, em[db_len .. db_len + hlen], db[0..db_len]);
    var i: usize = 0;
    while (i < db_len) : (i += 1) db[i] = db[i] ^ em[i];
    if (unused > 0) {
        var shift_clear: u32 = @intCast(u32, unused);
        var wide_clear: u32 = @intCast(u32, 0xFF) >> shift_clear;
        var clearmask: u8 = @intCast(u8, wide_clear & 0xFF);
        db[0] = db[0] & clearmask;
    }

    var ps_len: usize = db_len - sl - 1;
    i = 0;
    while (i < ps_len) : (i += 1) {
        if (db[i] != 0) return false;
    }
    if (db[ps_len] != 0x01) return false;

    var mp: [8 + 64 + BigMaxBytes]u8 = undefined;
    i = 0;
    while (i < 8) : (i += 1) mp[i] = 0;
    i = 0;
    while (i < hlen) : (i += 1) mp[8 + i] = hash[i];
    i = 0;
    while (i < sl) : (i += 1) mp[8 + hlen + i] = db[ps_len + 1 + i];

    var hp: [64]u8 = undefined;
    hashData(alg, mp[0 .. 8 + hlen + sl], hp[0..hlen]);
    return eqRange(hp[0..hlen], 0, em[db_len .. db_len + hlen]);
}

fn modulusBits(n: []const u8) usize {
    var i: usize = 0;
    while (i < n.len and n[i] == 0) : (i += 1) {}
    if (i >= n.len) return 0;
    var bits: usize = (n.len - i - 1) * 8;
    var v: u8 = n[i];
    while (v != 0) {
        bits += 1;
        v = v >> 1;
    }
    return bits;
}

pub fn rsaVerifyPkcs1v15(n: []const u8, e: u32, hash_alg: HashAlg, hash: []const u8, sig: []const u8) !void {
    var hlen: usize = hashAlgLen(hash_alg);
    if (hash.len != hlen) return error.Corrupt;
    if (n.len == 0 or n.len > BigMaxBytes or sig.len != n.len) return error.Corrupt;
    var em: [BigMaxBytes]u8 = undefined;
    if (!rsaPublicDecrypt(n, e, sig, em[0..n.len])) return error.BadSignature;
    if (!pkcs1Check(hash_alg, hash, em[0..n.len])) return error.BadSignature;
}

pub fn rsaVerifyPss(n: []const u8, e: u32, hash_alg: HashAlg, hash: []const u8, salt_len: u32, sig: []const u8) !void {
    var hlen: usize = hashAlgLen(hash_alg);
    if (hash.len != hlen) return error.Corrupt;
    if (n.len == 0 or n.len > BigMaxBytes or sig.len != n.len) return error.Corrupt;
    var mbits: usize = modulusBits(n);
    if (mbits < 2) return error.Corrupt;
    var em_bits: usize = mbits - 1;
    var em_len: usize = (em_bits + 7) / 8;
    if (em_len > n.len or em_len == 0) return error.Corrupt;
    var full: [BigMaxBytes]u8 = undefined;
    if (!rsaPublicDecrypt(n, e, sig, full[0..n.len])) return error.BadSignature;
    var start: usize = n.len - em_len;
    var i: usize = 0;
    while (i < start) : (i += 1) {
        if (full[i] != 0) return error.BadSignature;
    }
    if (!pssCheck(hash_alg, hash, salt_len, full[start..n.len], em_bits)) return error.BadSignature;
}
