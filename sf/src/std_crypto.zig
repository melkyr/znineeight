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
        var x: u32 = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
        var keep: u32 = x & 0x7FFFFFFF;
        w[i] = (keep << 1) | (x >> 31);
    }

    var a: u32 = s.h0;
    var b: u32 = s.h1;
    var c: u32 = s.h2;
    var d: u32 = s.h3;
    var e: u32 = s.h4;

    // Constant rotations are inlined: at -O0 the generic rotl32/mask helpers
    // were 37% of local CPU, and -fsafe still needs the shifted half masked.
    i = 0;
    while (i < 20) : (i += 1) {
        var f: u32 = (b & c) | ((~b) & d);
        var ak: u32 = a & 0x07FFFFFF;
        var bk: u32 = b & 0x00000003;
        var temp: u32 = ((ak << 5) | (a >> 27)) +% f +% e +% 0x5A827999 +% w[i];
        e = d;
        d = c;
        c = (bk << 30) | (b >> 2);
        b = a;
        a = temp;
    }
    while (i < 40) : (i += 1) {
        var f: u32 = b ^ c ^ d;
        var ak: u32 = a & 0x07FFFFFF;
        var bk: u32 = b & 0x00000003;
        var temp: u32 = ((ak << 5) | (a >> 27)) +% f +% e +% 0x6ED9EBA1 +% w[i];
        e = d;
        d = c;
        c = (bk << 30) | (b >> 2);
        b = a;
        a = temp;
    }
    while (i < 60) : (i += 1) {
        var f: u32 = (b & c) | (b & d) | (c & d);
        var ak: u32 = a & 0x07FFFFFF;
        var bk: u32 = b & 0x00000003;
        var temp: u32 = ((ak << 5) | (a >> 27)) +% f +% e +% 0x8F1BBCDC +% w[i];
        e = d;
        d = c;
        c = (bk << 30) | (b >> 2);
        b = a;
        a = temp;
    }
    while (i < 80) : (i += 1) {
        var f: u32 = b ^ c ^ d;
        var ak: u32 = a & 0x07FFFFFF;
        var bk: u32 = b & 0x00000003;
        var temp: u32 = ((ak << 5) | (a >> 27)) +% f +% e +% 0xCA62C1D6 +% w[i];
        e = d;
        d = c;
        c = (bk << 30) | (b >> 2);
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

const Sha256K = [_]u32{
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
};

fn sha256Block(s: *Sha256) void {
    var x: [16]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        x[i] = (@intCast(u32, s.buf[i * 4]) << 24) |
            (@intCast(u32, s.buf[i * 4 + 1]) << 16) |
            (@intCast(u32, s.buf[i * 4 + 2]) << 8) |
            @intCast(u32, s.buf[i * 4 + 3]);
    }

    var a: u32 = s.h[0];
    var b: u32 = s.h[1];
    var c: u32 = s.h[2];
    var d: u32 = s.h[3];
    var e: u32 = s.h[4];
    var f: u32 = s.h[5];
    var g: u32 = s.h[6];
    var hh: u32 = s.h[7];
    var t1: u32 = 0;
    var t2: u32 = 0;

    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[0] +% x[0];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[1] +% x[1];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[2] +% x[2];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[3] +% x[3];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[4] +% x[4];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[5] +% x[5];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[6] +% x[6];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[7] +% x[7];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[8] +% x[8];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[9] +% x[9];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[10] +% x[10];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[11] +% x[11];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[12] +% x[12];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[13] +% x[13];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[14] +% x[14];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[15] +% x[15];
    t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;

    var grp: usize = 1;
    while (grp < 4) : (grp += 1) {
        var kb: usize = grp * 16;
        x[0] = x[0] +% (((x[1] >> 7) | ((x[1] & 0x7F) << 25)) ^ ((x[1] >> 18) | ((x[1] & 0x3FFFF) << 14)) ^ (x[1] >> 3)) +% x[9] +% (((x[14] >> 17) | ((x[14] & 0x1FFFF) << 15)) ^ ((x[14] >> 19) | ((x[14] & 0x7FFFF) << 13)) ^ (x[14] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb] +% x[0];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[1] = x[1] +% (((x[2] >> 7) | ((x[2] & 0x7F) << 25)) ^ ((x[2] >> 18) | ((x[2] & 0x3FFFF) << 14)) ^ (x[2] >> 3)) +% x[10] +% (((x[15] >> 17) | ((x[15] & 0x1FFFF) << 15)) ^ ((x[15] >> 19) | ((x[15] & 0x7FFFF) << 13)) ^ (x[15] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 1] +% x[1];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[2] = x[2] +% (((x[3] >> 7) | ((x[3] & 0x7F) << 25)) ^ ((x[3] >> 18) | ((x[3] & 0x3FFFF) << 14)) ^ (x[3] >> 3)) +% x[11] +% (((x[0] >> 17) | ((x[0] & 0x1FFFF) << 15)) ^ ((x[0] >> 19) | ((x[0] & 0x7FFFF) << 13)) ^ (x[0] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 2] +% x[2];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[3] = x[3] +% (((x[4] >> 7) | ((x[4] & 0x7F) << 25)) ^ ((x[4] >> 18) | ((x[4] & 0x3FFFF) << 14)) ^ (x[4] >> 3)) +% x[12] +% (((x[1] >> 17) | ((x[1] & 0x1FFFF) << 15)) ^ ((x[1] >> 19) | ((x[1] & 0x7FFFF) << 13)) ^ (x[1] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 3] +% x[3];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[4] = x[4] +% (((x[5] >> 7) | ((x[5] & 0x7F) << 25)) ^ ((x[5] >> 18) | ((x[5] & 0x3FFFF) << 14)) ^ (x[5] >> 3)) +% x[13] +% (((x[2] >> 17) | ((x[2] & 0x1FFFF) << 15)) ^ ((x[2] >> 19) | ((x[2] & 0x7FFFF) << 13)) ^ (x[2] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 4] +% x[4];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[5] = x[5] +% (((x[6] >> 7) | ((x[6] & 0x7F) << 25)) ^ ((x[6] >> 18) | ((x[6] & 0x3FFFF) << 14)) ^ (x[6] >> 3)) +% x[14] +% (((x[3] >> 17) | ((x[3] & 0x1FFFF) << 15)) ^ ((x[3] >> 19) | ((x[3] & 0x7FFFF) << 13)) ^ (x[3] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 5] +% x[5];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[6] = x[6] +% (((x[7] >> 7) | ((x[7] & 0x7F) << 25)) ^ ((x[7] >> 18) | ((x[7] & 0x3FFFF) << 14)) ^ (x[7] >> 3)) +% x[15] +% (((x[4] >> 17) | ((x[4] & 0x1FFFF) << 15)) ^ ((x[4] >> 19) | ((x[4] & 0x7FFFF) << 13)) ^ (x[4] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 6] +% x[6];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[7] = x[7] +% (((x[8] >> 7) | ((x[8] & 0x7F) << 25)) ^ ((x[8] >> 18) | ((x[8] & 0x3FFFF) << 14)) ^ (x[8] >> 3)) +% x[0] +% (((x[5] >> 17) | ((x[5] & 0x1FFFF) << 15)) ^ ((x[5] >> 19) | ((x[5] & 0x7FFFF) << 13)) ^ (x[5] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 7] +% x[7];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[8] = x[8] +% (((x[9] >> 7) | ((x[9] & 0x7F) << 25)) ^ ((x[9] >> 18) | ((x[9] & 0x3FFFF) << 14)) ^ (x[9] >> 3)) +% x[1] +% (((x[6] >> 17) | ((x[6] & 0x1FFFF) << 15)) ^ ((x[6] >> 19) | ((x[6] & 0x7FFFF) << 13)) ^ (x[6] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 8] +% x[8];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[9] = x[9] +% (((x[10] >> 7) | ((x[10] & 0x7F) << 25)) ^ ((x[10] >> 18) | ((x[10] & 0x3FFFF) << 14)) ^ (x[10] >> 3)) +% x[2] +% (((x[7] >> 17) | ((x[7] & 0x1FFFF) << 15)) ^ ((x[7] >> 19) | ((x[7] & 0x7FFFF) << 13)) ^ (x[7] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 9] +% x[9];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[10] = x[10] +% (((x[11] >> 7) | ((x[11] & 0x7F) << 25)) ^ ((x[11] >> 18) | ((x[11] & 0x3FFFF) << 14)) ^ (x[11] >> 3)) +% x[3] +% (((x[8] >> 17) | ((x[8] & 0x1FFFF) << 15)) ^ ((x[8] >> 19) | ((x[8] & 0x7FFFF) << 13)) ^ (x[8] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 10] +% x[10];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[11] = x[11] +% (((x[12] >> 7) | ((x[12] & 0x7F) << 25)) ^ ((x[12] >> 18) | ((x[12] & 0x3FFFF) << 14)) ^ (x[12] >> 3)) +% x[4] +% (((x[9] >> 17) | ((x[9] & 0x1FFFF) << 15)) ^ ((x[9] >> 19) | ((x[9] & 0x7FFFF) << 13)) ^ (x[9] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 11] +% x[11];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[12] = x[12] +% (((x[13] >> 7) | ((x[13] & 0x7F) << 25)) ^ ((x[13] >> 18) | ((x[13] & 0x3FFFF) << 14)) ^ (x[13] >> 3)) +% x[5] +% (((x[10] >> 17) | ((x[10] & 0x1FFFF) << 15)) ^ ((x[10] >> 19) | ((x[10] & 0x7FFFF) << 13)) ^ (x[10] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 12] +% x[12];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[13] = x[13] +% (((x[14] >> 7) | ((x[14] & 0x7F) << 25)) ^ ((x[14] >> 18) | ((x[14] & 0x3FFFF) << 14)) ^ (x[14] >> 3)) +% x[6] +% (((x[11] >> 17) | ((x[11] & 0x1FFFF) << 15)) ^ ((x[11] >> 19) | ((x[11] & 0x7FFFF) << 13)) ^ (x[11] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 13] +% x[13];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[14] = x[14] +% (((x[15] >> 7) | ((x[15] & 0x7F) << 25)) ^ ((x[15] >> 18) | ((x[15] & 0x3FFFF) << 14)) ^ (x[15] >> 3)) +% x[7] +% (((x[12] >> 17) | ((x[12] & 0x1FFFF) << 15)) ^ ((x[12] >> 19) | ((x[12] & 0x7FFFF) << 13)) ^ (x[12] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 14] +% x[14];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[15] = x[15] +% (((x[0] >> 7) | ((x[0] & 0x7F) << 25)) ^ ((x[0] >> 18) | ((x[0] & 0x3FFFF) << 14)) ^ (x[0] >> 3)) +% x[8] +% (((x[13] >> 17) | ((x[13] & 0x1FFFF) << 15)) ^ ((x[13] >> 19) | ((x[13] & 0x7FFFF) << 13)) ^ (x[13] >> 10));
        t1 = hh +% (((e >> 6) | ((e & 0x3F) << 26)) ^ ((e >> 11) | ((e & 0x7FF) << 21)) ^ ((e >> 25) | ((e & 0x1FFFFFF) << 7))) +% ((e & f) ^ ((~e) & g)) +% Sha256K[kb + 15] +% x[15];
        t2 = (((a >> 2) | ((a & 0x3) << 30)) ^ ((a >> 13) | ((a & 0x1FFF) << 19)) ^ ((a >> 22) | ((a & 0x3FFFFF) << 10))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    }

    s.h[0] = s.h[0] +% a;
    s.h[1] = s.h[1] +% b;
    s.h[2] = s.h[2] +% c;
    s.h[3] = s.h[3] +% d;
    s.h[4] = s.h[4] +% e;
    s.h[5] = s.h[5] +% f;
    s.h[6] = s.h[6] +% g;
    s.h[7] = s.h[7] +% hh;
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

const Md5K = [_]u32{
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

fn md5Block(s: *Md5) void {
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

    a = a +% ((b & c) | ((~b) & d)) +% m[0] +% Md5K[0];
    a = ((a & 0x1FFFFFF) << 7) | (a >> 25);
    a = a +% b;
    d = d +% ((a & b) | ((~a) & c)) +% m[1] +% Md5K[1];
    d = ((d & 0xFFFFF) << 12) | (d >> 20);
    d = d +% a;
    c = c +% ((d & a) | ((~d) & b)) +% m[2] +% Md5K[2];
    c = ((c & 0x7FFF) << 17) | (c >> 15);
    c = c +% d;
    b = b +% ((c & d) | ((~c) & a)) +% m[3] +% Md5K[3];
    b = ((b & 0x3FF) << 22) | (b >> 10);
    b = b +% c;
    a = a +% ((b & c) | ((~b) & d)) +% m[4] +% Md5K[4];
    a = ((a & 0x1FFFFFF) << 7) | (a >> 25);
    a = a +% b;
    d = d +% ((a & b) | ((~a) & c)) +% m[5] +% Md5K[5];
    d = ((d & 0xFFFFF) << 12) | (d >> 20);
    d = d +% a;
    c = c +% ((d & a) | ((~d) & b)) +% m[6] +% Md5K[6];
    c = ((c & 0x7FFF) << 17) | (c >> 15);
    c = c +% d;
    b = b +% ((c & d) | ((~c) & a)) +% m[7] +% Md5K[7];
    b = ((b & 0x3FF) << 22) | (b >> 10);
    b = b +% c;
    a = a +% ((b & c) | ((~b) & d)) +% m[8] +% Md5K[8];
    a = ((a & 0x1FFFFFF) << 7) | (a >> 25);
    a = a +% b;
    d = d +% ((a & b) | ((~a) & c)) +% m[9] +% Md5K[9];
    d = ((d & 0xFFFFF) << 12) | (d >> 20);
    d = d +% a;
    c = c +% ((d & a) | ((~d) & b)) +% m[10] +% Md5K[10];
    c = ((c & 0x7FFF) << 17) | (c >> 15);
    c = c +% d;
    b = b +% ((c & d) | ((~c) & a)) +% m[11] +% Md5K[11];
    b = ((b & 0x3FF) << 22) | (b >> 10);
    b = b +% c;
    a = a +% ((b & c) | ((~b) & d)) +% m[12] +% Md5K[12];
    a = ((a & 0x1FFFFFF) << 7) | (a >> 25);
    a = a +% b;
    d = d +% ((a & b) | ((~a) & c)) +% m[13] +% Md5K[13];
    d = ((d & 0xFFFFF) << 12) | (d >> 20);
    d = d +% a;
    c = c +% ((d & a) | ((~d) & b)) +% m[14] +% Md5K[14];
    c = ((c & 0x7FFF) << 17) | (c >> 15);
    c = c +% d;
    b = b +% ((c & d) | ((~c) & a)) +% m[15] +% Md5K[15];
    b = ((b & 0x3FF) << 22) | (b >> 10);
    b = b +% c;

    a = a +% ((b & d) | (c & (~d))) +% m[1] +% Md5K[16];
    a = ((a & 0x7FFFFFF) << 5) | (a >> 27);
    a = a +% b;
    d = d +% ((a & c) | (b & (~c))) +% m[6] +% Md5K[17];
    d = ((d & 0x7FFFFF) << 9) | (d >> 23);
    d = d +% a;
    c = c +% ((d & b) | (a & (~b))) +% m[11] +% Md5K[18];
    c = ((c & 0x3FFFF) << 14) | (c >> 18);
    c = c +% d;
    b = b +% ((c & a) | (d & (~a))) +% m[0] +% Md5K[19];
    b = ((b & 0xFFF) << 20) | (b >> 12);
    b = b +% c;
    a = a +% ((b & d) | (c & (~d))) +% m[5] +% Md5K[20];
    a = ((a & 0x7FFFFFF) << 5) | (a >> 27);
    a = a +% b;
    d = d +% ((a & c) | (b & (~c))) +% m[10] +% Md5K[21];
    d = ((d & 0x7FFFFF) << 9) | (d >> 23);
    d = d +% a;
    c = c +% ((d & b) | (a & (~b))) +% m[15] +% Md5K[22];
    c = ((c & 0x3FFFF) << 14) | (c >> 18);
    c = c +% d;
    b = b +% ((c & a) | (d & (~a))) +% m[4] +% Md5K[23];
    b = ((b & 0xFFF) << 20) | (b >> 12);
    b = b +% c;
    a = a +% ((b & d) | (c & (~d))) +% m[9] +% Md5K[24];
    a = ((a & 0x7FFFFFF) << 5) | (a >> 27);
    a = a +% b;
    d = d +% ((a & c) | (b & (~c))) +% m[14] +% Md5K[25];
    d = ((d & 0x7FFFFF) << 9) | (d >> 23);
    d = d +% a;
    c = c +% ((d & b) | (a & (~b))) +% m[3] +% Md5K[26];
    c = ((c & 0x3FFFF) << 14) | (c >> 18);
    c = c +% d;
    b = b +% ((c & a) | (d & (~a))) +% m[8] +% Md5K[27];
    b = ((b & 0xFFF) << 20) | (b >> 12);
    b = b +% c;
    a = a +% ((b & d) | (c & (~d))) +% m[13] +% Md5K[28];
    a = ((a & 0x7FFFFFF) << 5) | (a >> 27);
    a = a +% b;
    d = d +% ((a & c) | (b & (~c))) +% m[2] +% Md5K[29];
    d = ((d & 0x7FFFFF) << 9) | (d >> 23);
    d = d +% a;
    c = c +% ((d & b) | (a & (~b))) +% m[7] +% Md5K[30];
    c = ((c & 0x3FFFF) << 14) | (c >> 18);
    c = c +% d;
    b = b +% ((c & a) | (d & (~a))) +% m[12] +% Md5K[31];
    b = ((b & 0xFFF) << 20) | (b >> 12);
    b = b +% c;

    a = a +% (b ^ c ^ d) +% m[5] +% Md5K[32];
    a = ((a & 0xFFFFFFF) << 4) | (a >> 28);
    a = a +% b;
    d = d +% (a ^ b ^ c) +% m[8] +% Md5K[33];
    d = ((d & 0x1FFFFF) << 11) | (d >> 21);
    d = d +% a;
    c = c +% (d ^ a ^ b) +% m[11] +% Md5K[34];
    c = ((c & 0xFFFF) << 16) | (c >> 16);
    c = c +% d;
    b = b +% (c ^ d ^ a) +% m[14] +% Md5K[35];
    b = ((b & 0x1FF) << 23) | (b >> 9);
    b = b +% c;
    a = a +% (b ^ c ^ d) +% m[1] +% Md5K[36];
    a = ((a & 0xFFFFFFF) << 4) | (a >> 28);
    a = a +% b;
    d = d +% (a ^ b ^ c) +% m[4] +% Md5K[37];
    d = ((d & 0x1FFFFF) << 11) | (d >> 21);
    d = d +% a;
    c = c +% (d ^ a ^ b) +% m[7] +% Md5K[38];
    c = ((c & 0xFFFF) << 16) | (c >> 16);
    c = c +% d;
    b = b +% (c ^ d ^ a) +% m[10] +% Md5K[39];
    b = ((b & 0x1FF) << 23) | (b >> 9);
    b = b +% c;
    a = a +% (b ^ c ^ d) +% m[13] +% Md5K[40];
    a = ((a & 0xFFFFFFF) << 4) | (a >> 28);
    a = a +% b;
    d = d +% (a ^ b ^ c) +% m[0] +% Md5K[41];
    d = ((d & 0x1FFFFF) << 11) | (d >> 21);
    d = d +% a;
    c = c +% (d ^ a ^ b) +% m[3] +% Md5K[42];
    c = ((c & 0xFFFF) << 16) | (c >> 16);
    c = c +% d;
    b = b +% (c ^ d ^ a) +% m[6] +% Md5K[43];
    b = ((b & 0x1FF) << 23) | (b >> 9);
    b = b +% c;
    a = a +% (b ^ c ^ d) +% m[9] +% Md5K[44];
    a = ((a & 0xFFFFFFF) << 4) | (a >> 28);
    a = a +% b;
    d = d +% (a ^ b ^ c) +% m[12] +% Md5K[45];
    d = ((d & 0x1FFFFF) << 11) | (d >> 21);
    d = d +% a;
    c = c +% (d ^ a ^ b) +% m[15] +% Md5K[46];
    c = ((c & 0xFFFF) << 16) | (c >> 16);
    c = c +% d;
    b = b +% (c ^ d ^ a) +% m[2] +% Md5K[47];
    b = ((b & 0x1FF) << 23) | (b >> 9);
    b = b +% c;

    a = a +% (c ^ (b | (~d))) +% m[0] +% Md5K[48];
    a = ((a & 0x3FFFFFF) << 6) | (a >> 26);
    a = a +% b;
    d = d +% (b ^ (a | (~c))) +% m[7] +% Md5K[49];
    d = ((d & 0x3FFFFF) << 10) | (d >> 22);
    d = d +% a;
    c = c +% (a ^ (d | (~b))) +% m[14] +% Md5K[50];
    c = ((c & 0x1FFFF) << 15) | (c >> 17);
    c = c +% d;
    b = b +% (d ^ (c | (~a))) +% m[5] +% Md5K[51];
    b = ((b & 0x7FF) << 21) | (b >> 11);
    b = b +% c;
    a = a +% (c ^ (b | (~d))) +% m[12] +% Md5K[52];
    a = ((a & 0x3FFFFFF) << 6) | (a >> 26);
    a = a +% b;
    d = d +% (b ^ (a | (~c))) +% m[3] +% Md5K[53];
    d = ((d & 0x3FFFFF) << 10) | (d >> 22);
    d = d +% a;
    c = c +% (a ^ (d | (~b))) +% m[10] +% Md5K[54];
    c = ((c & 0x1FFFF) << 15) | (c >> 17);
    c = c +% d;
    b = b +% (d ^ (c | (~a))) +% m[1] +% Md5K[55];
    b = ((b & 0x7FF) << 21) | (b >> 11);
    b = b +% c;
    a = a +% (c ^ (b | (~d))) +% m[8] +% Md5K[56];
    a = ((a & 0x3FFFFFF) << 6) | (a >> 26);
    a = a +% b;
    d = d +% (b ^ (a | (~c))) +% m[15] +% Md5K[57];
    d = ((d & 0x3FFFFF) << 10) | (d >> 22);
    d = d +% a;
    c = c +% (a ^ (d | (~b))) +% m[6] +% Md5K[58];
    c = ((c & 0x1FFFF) << 15) | (c >> 17);
    c = c +% d;
    b = b +% (d ^ (c | (~a))) +% m[13] +% Md5K[59];
    b = ((b & 0x7FF) << 21) | (b >> 11);
    b = b +% c;
    a = a +% (c ^ (b | (~d))) +% m[4] +% Md5K[60];
    a = ((a & 0x3FFFFFF) << 6) | (a >> 26);
    a = a +% b;
    d = d +% (b ^ (a | (~c))) +% m[11] +% Md5K[61];
    d = ((d & 0x3FFFFF) << 10) | (d >> 22);
    d = d +% a;
    c = c +% (a ^ (d | (~b))) +% m[2] +% Md5K[62];
    c = ((c & 0x1FFFF) << 15) | (c >> 17);
    c = c +% d;
    b = b +% (d ^ (c | (~a))) +% m[9] +% Md5K[63];
    b = ((b & 0x7FF) << 21) | (b >> 11);
    b = b +% c;

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
const Crc32Table = [256]u32{
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
    0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
    0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
    0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
    0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
    0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
    0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
    0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
    0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
    0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
    0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
    0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
    0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
    0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
    0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
    0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
    0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
    0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
    0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
    0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
    0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
    0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
};
const Crc32Braid = [4][256]u32{
    [256]u32{
        0x00000000, 0x65673B46, 0xCACE768C, 0xAFA94DCA, 0x4EEDEB59, 0x2B8AD01F, 0x84239DD5, 0xE144A693,
        0x9DDBD6B2, 0xF8BCEDF4, 0x5715A03E, 0x32729B78, 0xD3363DEB, 0xB65106AD, 0x19F84B67, 0x7C9F7021,
        0xE0C6AB25, 0x85A19063, 0x2A08DDA9, 0x4F6FE6EF, 0xAE2B407C, 0xCB4C7B3A, 0x64E536F0, 0x01820DB6,
        0x7D1D7D97, 0x187A46D1, 0xB7D30B1B, 0xD2B4305D, 0x33F096CE, 0x5697AD88, 0xF93EE042, 0x9C59DB04,
        0x1AFC500B, 0x7F9B6B4D, 0xD0322687, 0xB5551DC1, 0x5411BB52, 0x31768014, 0x9EDFCDDE, 0xFBB8F698,
        0x872786B9, 0xE240BDFF, 0x4DE9F035, 0x288ECB73, 0xC9CA6DE0, 0xACAD56A6, 0x03041B6C, 0x6663202A,
        0xFA3AFB2E, 0x9F5DC068, 0x30F48DA2, 0x5593B6E4, 0xB4D71077, 0xD1B02B31, 0x7E1966FB, 0x1B7E5DBD,
        0x67E12D9C, 0x028616DA, 0xAD2F5B10, 0xC8486056, 0x290CC6C5, 0x4C6BFD83, 0xE3C2B049, 0x86A58B0F,
        0x35F8A016, 0x509F9B50, 0xFF36D69A, 0x9A51EDDC, 0x7B154B4F, 0x1E727009, 0xB1DB3DC3, 0xD4BC0685,
        0xA82376A4, 0xCD444DE2, 0x62ED0028, 0x078A3B6E, 0xE6CE9DFD, 0x83A9A6BB, 0x2C00EB71, 0x4967D037,
        0xD53E0B33, 0xB0593075, 0x1FF07DBF, 0x7A9746F9, 0x9BD3E06A, 0xFEB4DB2C, 0x511D96E6, 0x347AADA0,
        0x48E5DD81, 0x2D82E6C7, 0x822BAB0D, 0xE74C904B, 0x060836D8, 0x636F0D9E, 0xCCC64054, 0xA9A17B12,
        0x2F04F01D, 0x4A63CB5B, 0xE5CA8691, 0x80ADBDD7, 0x61E91B44, 0x048E2002, 0xAB276DC8, 0xCE40568E,
        0xB2DF26AF, 0xD7B81DE9, 0x78115023, 0x1D766B65, 0xFC32CDF6, 0x9955F6B0, 0x36FCBB7A, 0x539B803C,
        0xCFC25B38, 0xAAA5607E, 0x050C2DB4, 0x606B16F2, 0x812FB061, 0xE4488B27, 0x4BE1C6ED, 0x2E86FDAB,
        0x52198D8A, 0x377EB6CC, 0x98D7FB06, 0xFDB0C040, 0x1CF466D3, 0x79935D95, 0xD63A105F, 0xB35D2B19,
        0x6BF1402C, 0x0E967B6A, 0xA13F36A0, 0xC4580DE6, 0x251CAB75, 0x407B9033, 0xEFD2DDF9, 0x8AB5E6BF,
        0xF62A969E, 0x934DADD8, 0x3CE4E012, 0x5983DB54, 0xB8C77DC7, 0xDDA04681, 0x72090B4B, 0x176E300D,
        0x8B37EB09, 0xEE50D04F, 0x41F99D85, 0x249EA6C3, 0xC5DA0050, 0xA0BD3B16, 0x0F1476DC, 0x6A734D9A,
        0x16EC3DBB, 0x738B06FD, 0xDC224B37, 0xB9457071, 0x5801D6E2, 0x3D66EDA4, 0x92CFA06E, 0xF7A89B28,
        0x710D1027, 0x146A2B61, 0xBBC366AB, 0xDEA45DED, 0x3FE0FB7E, 0x5A87C038, 0xF52E8DF2, 0x9049B6B4,
        0xECD6C695, 0x89B1FDD3, 0x2618B019, 0x437F8B5F, 0xA23B2DCC, 0xC75C168A, 0x68F55B40, 0x0D926006,
        0x91CBBB02, 0xF4AC8044, 0x5B05CD8E, 0x3E62F6C8, 0xDF26505B, 0xBA416B1D, 0x15E826D7, 0x708F1D91,
        0x0C106DB0, 0x697756F6, 0xC6DE1B3C, 0xA3B9207A, 0x42FD86E9, 0x279ABDAF, 0x8833F065, 0xED54CB23,
        0x5E09E03A, 0x3B6EDB7C, 0x94C796B6, 0xF1A0ADF0, 0x10E40B63, 0x75833025, 0xDA2A7DEF, 0xBF4D46A9,
        0xC3D23688, 0xA6B50DCE, 0x091C4004, 0x6C7B7B42, 0x8D3FDDD1, 0xE858E697, 0x47F1AB5D, 0x2296901B,
        0xBECF4B1F, 0xDBA87059, 0x74013D93, 0x116606D5, 0xF022A046, 0x95459B00, 0x3AECD6CA, 0x5F8BED8C,
        0x23149DAD, 0x4673A6EB, 0xE9DAEB21, 0x8CBDD067, 0x6DF976F4, 0x089E4DB2, 0xA7370078, 0xC2503B3E,
        0x44F5B031, 0x21928B77, 0x8E3BC6BD, 0xEB5CFDFB, 0x0A185B68, 0x6F7F602E, 0xC0D62DE4, 0xA5B116A2,
        0xD92E6683, 0xBC495DC5, 0x13E0100F, 0x76872B49, 0x97C38DDA, 0xF2A4B69C, 0x5D0DFB56, 0x386AC010,
        0xA4331B14, 0xC1542052, 0x6EFD6D98, 0x0B9A56DE, 0xEADEF04D, 0x8FB9CB0B, 0x201086C1, 0x4577BD87,
        0x39E8CDA6, 0x5C8FF6E0, 0xF326BB2A, 0x9641806C, 0x770526FF, 0x12621DB9, 0xBDCB5073, 0xD8AC6B35,
    },
    [256]u32{
        0x00000000, 0xD7E28058, 0x74B406F1, 0xA35686A9, 0xE9680DE2, 0x3E8A8DBA, 0x9DDC0B13, 0x4A3E8B4B,
        0x09A11D85, 0xDE439DDD, 0x7D151B74, 0xAAF79B2C, 0xE0C91067, 0x372B903F, 0x947D1696, 0x439F96CE,
        0x13423B0A, 0xC4A0BB52, 0x67F63DFB, 0xB014BDA3, 0xFA2A36E8, 0x2DC8B6B0, 0x8E9E3019, 0x597CB041,
        0x1AE3268F, 0xCD01A6D7, 0x6E57207E, 0xB9B5A026, 0xF38B2B6D, 0x2469AB35, 0x873F2D9C, 0x50DDADC4,
        0x26847614, 0xF166F64C, 0x523070E5, 0x85D2F0BD, 0xCFEC7BF6, 0x180EFBAE, 0xBB587D07, 0x6CBAFD5F,
        0x2F256B91, 0xF8C7EBC9, 0x5B916D60, 0x8C73ED38, 0xC64D6673, 0x11AFE62B, 0xB2F96082, 0x651BE0DA,
        0x35C64D1E, 0xE224CD46, 0x41724BEF, 0x9690CBB7, 0xDCAE40FC, 0x0B4CC0A4, 0xA81A460D, 0x7FF8C655,
        0x3C67509B, 0xEB85D0C3, 0x48D3566A, 0x9F31D632, 0xD50F5D79, 0x02EDDD21, 0xA1BB5B88, 0x7659DBD0,
        0x4D08EC28, 0x9AEA6C70, 0x39BCEAD9, 0xEE5E6A81, 0xA460E1CA, 0x73826192, 0xD0D4E73B, 0x07366763,
        0x44A9F1AD, 0x934B71F5, 0x301DF75C, 0xE7FF7704, 0xADC1FC4F, 0x7A237C17, 0xD975FABE, 0x0E977AE6,
        0x5E4AD722, 0x89A8577A, 0x2AFED1D3, 0xFD1C518B, 0xB722DAC0, 0x60C05A98, 0xC396DC31, 0x14745C69,
        0x57EBCAA7, 0x80094AFF, 0x235FCC56, 0xF4BD4C0E, 0xBE83C745, 0x6961471D, 0xCA37C1B4, 0x1DD541EC,
        0x6B8C9A3C, 0xBC6E1A64, 0x1F389CCD, 0xC8DA1C95, 0x82E497DE, 0x55061786, 0xF650912F, 0x21B21177,
        0x622D87B9, 0xB5CF07E1, 0x16998148, 0xC17B0110, 0x8B458A5B, 0x5CA70A03, 0xFFF18CAA, 0x28130CF2,
        0x78CEA136, 0xAF2C216E, 0x0C7AA7C7, 0xDB98279F, 0x91A6ACD4, 0x46442C8C, 0xE512AA25, 0x32F02A7D,
        0x716FBCB3, 0xA68D3CEB, 0x05DBBA42, 0xD2393A1A, 0x9807B151, 0x4FE53109, 0xECB3B7A0, 0x3B5137F8,
        0x9A11D850, 0x4DF35808, 0xEEA5DEA1, 0x39475EF9, 0x7379D5B2, 0xA49B55EA, 0x07CDD343, 0xD02F531B,
        0x93B0C5D5, 0x4452458D, 0xE704C324, 0x30E6437C, 0x7AD8C837, 0xAD3A486F, 0x0E6CCEC6, 0xD98E4E9E,
        0x8953E35A, 0x5EB16302, 0xFDE7E5AB, 0x2A0565F3, 0x603BEEB8, 0xB7D96EE0, 0x148FE849, 0xC36D6811,
        0x80F2FEDF, 0x57107E87, 0xF446F82E, 0x23A47876, 0x699AF33D, 0xBE787365, 0x1D2EF5CC, 0xCACC7594,
        0xBC95AE44, 0x6B772E1C, 0xC821A8B5, 0x1FC328ED, 0x55FDA3A6, 0x821F23FE, 0x2149A557, 0xF6AB250F,
        0xB534B3C1, 0x62D63399, 0xC180B530, 0x16623568, 0x5C5CBE23, 0x8BBE3E7B, 0x28E8B8D2, 0xFF0A388A,
        0xAFD7954E, 0x78351516, 0xDB6393BF, 0x0C8113E7, 0x46BF98AC, 0x915D18F4, 0x320B9E5D, 0xE5E91E05,
        0xA67688CB, 0x71940893, 0xD2C28E3A, 0x05200E62, 0x4F1E8529, 0x98FC0571, 0x3BAA83D8, 0xEC480380,
        0xD7193478, 0x00FBB420, 0xA3AD3289, 0x744FB2D1, 0x3E71399A, 0xE993B9C2, 0x4AC53F6B, 0x9D27BF33,
        0xDEB829FD, 0x095AA9A5, 0xAA0C2F0C, 0x7DEEAF54, 0x37D0241F, 0xE032A447, 0x436422EE, 0x9486A2B6,
        0xC45B0F72, 0x13B98F2A, 0xB0EF0983, 0x670D89DB, 0x2D330290, 0xFAD182C8, 0x59870461, 0x8E658439,
        0xCDFA12F7, 0x1A1892AF, 0xB94E1406, 0x6EAC945E, 0x24921F15, 0xF3709F4D, 0x502619E4, 0x87C499BC,
        0xF19D426C, 0x267FC234, 0x8529449D, 0x52CBC4C5, 0x18F54F8E, 0xCF17CFD6, 0x6C41497F, 0xBBA3C927,
        0xF83C5FE9, 0x2FDEDFB1, 0x8C885918, 0x5B6AD940, 0x1154520B, 0xC6B6D253, 0x65E054FA, 0xB202D4A2,
        0xE2DF7966, 0x353DF93E, 0x966B7F97, 0x4189FFCF, 0x0BB77484, 0xDC55F4DC, 0x7F037275, 0xA8E1F22D,
        0xEB7E64E3, 0x3C9CE4BB, 0x9FCA6212, 0x4828E24A, 0x02166901, 0xD5F4E959, 0x76A26FF0, 0xA140EFA8,
    },
    [256]u32{
        0x00000000, 0xEF52B6E1, 0x05D46B83, 0xEA86DD62, 0x0BA8D706, 0xE4FA61E7, 0x0E7CBC85, 0xE12E0A64,
        0x1751AE0C, 0xF80318ED, 0x1285C58F, 0xFDD7736E, 0x1CF9790A, 0xF3ABCFEB, 0x192D1289, 0xF67FA468,
        0x2EA35C18, 0xC1F1EAF9, 0x2B77379B, 0xC425817A, 0x250B8B1E, 0xCA593DFF, 0x20DFE09D, 0xCF8D567C,
        0x39F2F214, 0xD6A044F5, 0x3C269997, 0xD3742F76, 0x325A2512, 0xDD0893F3, 0x378E4E91, 0xD8DCF870,
        0x5D46B830, 0xB2140ED1, 0x5892D3B3, 0xB7C06552, 0x56EE6F36, 0xB9BCD9D7, 0x533A04B5, 0xBC68B254,
        0x4A17163C, 0xA545A0DD, 0x4FC37DBF, 0xA091CB5E, 0x41BFC13A, 0xAEED77DB, 0x446BAAB9, 0xAB391C58,
        0x73E5E428, 0x9CB752C9, 0x76318FAB, 0x9963394A, 0x784D332E, 0x971F85CF, 0x7D9958AD, 0x92CBEE4C,
        0x64B44A24, 0x8BE6FCC5, 0x616021A7, 0x8E329746, 0x6F1C9D22, 0x804E2BC3, 0x6AC8F6A1, 0x859A4040,
        0xBA8D7060, 0x55DFC681, 0xBF591BE3, 0x500BAD02, 0xB125A766, 0x5E771187, 0xB4F1CCE5, 0x5BA37A04,
        0xADDCDE6C, 0x428E688D, 0xA808B5EF, 0x475A030E, 0xA674096A, 0x4926BF8B, 0xA3A062E9, 0x4CF2D408,
        0x942E2C78, 0x7B7C9A99, 0x91FA47FB, 0x7EA8F11A, 0x9F86FB7E, 0x70D44D9F, 0x9A5290FD, 0x7500261C,
        0x837F8274, 0x6C2D3495, 0x86ABE9F7, 0x69F95F16, 0x88D75572, 0x6785E393, 0x8D033EF1, 0x62518810,
        0xE7CBC850, 0x08997EB1, 0xE21FA3D3, 0x0D4D1532, 0xEC631F56, 0x0331A9B7, 0xE9B774D5, 0x06E5C234,
        0xF09A665C, 0x1FC8D0BD, 0xF54E0DDF, 0x1A1CBB3E, 0xFB32B15A, 0x146007BB, 0xFEE6DAD9, 0x11B46C38,
        0xC9689448, 0x263A22A9, 0xCCBCFFCB, 0x23EE492A, 0xC2C0434E, 0x2D92F5AF, 0xC71428CD, 0x28469E2C,
        0xDE393A44, 0x316B8CA5, 0xDBED51C7, 0x34BFE726, 0xD591ED42, 0x3AC35BA3, 0xD04586C1, 0x3F173020,
        0xAE6BE681, 0x41395060, 0xABBF8D02, 0x44ED3BE3, 0xA5C33187, 0x4A918766, 0xA0175A04, 0x4F45ECE5,
        0xB93A488D, 0x5668FE6C, 0xBCEE230E, 0x53BC95EF, 0xB2929F8B, 0x5DC0296A, 0xB746F408, 0x581442E9,
        0x80C8BA99, 0x6F9A0C78, 0x851CD11A, 0x6A4E67FB, 0x8B606D9F, 0x6432DB7E, 0x8EB4061C, 0x61E6B0FD,
        0x97991495, 0x78CBA274, 0x924D7F16, 0x7D1FC9F7, 0x9C31C393, 0x73637572, 0x99E5A810, 0x76B71EF1,
        0xF32D5EB1, 0x1C7FE850, 0xF6F93532, 0x19AB83D3, 0xF88589B7, 0x17D73F56, 0xFD51E234, 0x120354D5,
        0xE47CF0BD, 0x0B2E465C, 0xE1A89B3E, 0x0EFA2DDF, 0xEFD427BB, 0x0086915A, 0xEA004C38, 0x0552FAD9,
        0xDD8E02A9, 0x32DCB448, 0xD85A692A, 0x3708DFCB, 0xD626D5AF, 0x3974634E, 0xD3F2BE2C, 0x3CA008CD,
        0xCADFACA5, 0x258D1A44, 0xCF0BC726, 0x205971C7, 0xC1777BA3, 0x2E25CD42, 0xC4A31020, 0x2BF1A6C1,
        0x14E696E1, 0xFBB42000, 0x1132FD62, 0xFE604B83, 0x1F4E41E7, 0xF01CF706, 0x1A9A2A64, 0xF5C89C85,
        0x03B738ED, 0xECE58E0C, 0x0663536E, 0xE931E58F, 0x081FEFEB, 0xE74D590A, 0x0DCB8468, 0xE2993289,
        0x3A45CAF9, 0xD5177C18, 0x3F91A17A, 0xD0C3179B, 0x31ED1DFF, 0xDEBFAB1E, 0x3439767C, 0xDB6BC09D,
        0x2D1464F5, 0xC246D214, 0x28C00F76, 0xC792B997, 0x26BCB3F3, 0xC9EE0512, 0x2368D870, 0xCC3A6E91,
        0x49A02ED1, 0xA6F29830, 0x4C744552, 0xA326F3B3, 0x4208F9D7, 0xAD5A4F36, 0x47DC9254, 0xA88E24B5,
        0x5EF180DD, 0xB1A3363C, 0x5B25EB5E, 0xB4775DBF, 0x555957DB, 0xBA0BE13A, 0x508D3C58, 0xBFDF8AB9,
        0x670372C9, 0x8851C428, 0x62D7194A, 0x8D85AFAB, 0x6CABA5CF, 0x83F9132E, 0x697FCE4C, 0x862D78AD,
        0x7052DCC5, 0x9F006A24, 0x7586B746, 0x9AD401A7, 0x7BFA0BC3, 0x94A8BD22, 0x7E2E6040, 0x917CD6A1,
    },
    [256]u32{
        0x00000000, 0x87A6CB43, 0xD43C90C7, 0x539A5B84, 0x730827CF, 0xF4AEEC8C, 0xA734B708, 0x20927C4B,
        0xE6104F9E, 0x61B684DD, 0x322CDF59, 0xB58A141A, 0x95186851, 0x12BEA312, 0x4124F896, 0xC68233D5,
        0x1751997D, 0x90F7523E, 0xC36D09BA, 0x44CBC2F9, 0x6459BEB2, 0xE3FF75F1, 0xB0652E75, 0x37C3E536,
        0xF141D6E3, 0x76E71DA0, 0x257D4624, 0xA2DB8D67, 0x8249F12C, 0x05EF3A6F, 0x567561EB, 0xD1D3AAA8,
        0x2EA332FA, 0xA905F9B9, 0xFA9FA23D, 0x7D39697E, 0x5DAB1535, 0xDA0DDE76, 0x899785F2, 0x0E314EB1,
        0xC8B37D64, 0x4F15B627, 0x1C8FEDA3, 0x9B2926E0, 0xBBBB5AAB, 0x3C1D91E8, 0x6F87CA6C, 0xE821012F,
        0x39F2AB87, 0xBE5460C4, 0xEDCE3B40, 0x6A68F003, 0x4AFA8C48, 0xCD5C470B, 0x9EC61C8F, 0x1960D7CC,
        0xDFE2E419, 0x58442F5A, 0x0BDE74DE, 0x8C78BF9D, 0xACEAC3D6, 0x2B4C0895, 0x78D65311, 0xFF709852,
        0x5D4665F4, 0xDAE0AEB7, 0x897AF533, 0x0EDC3E70, 0x2E4E423B, 0xA9E88978, 0xFA72D2FC, 0x7DD419BF,
        0xBB562A6A, 0x3CF0E129, 0x6F6ABAAD, 0xE8CC71EE, 0xC85E0DA5, 0x4FF8C6E6, 0x1C629D62, 0x9BC45621,
        0x4A17FC89, 0xCDB137CA, 0x9E2B6C4E, 0x198DA70D, 0x391FDB46, 0xBEB91005, 0xED234B81, 0x6A8580C2,
        0xAC07B317, 0x2BA17854, 0x783B23D0, 0xFF9DE893, 0xDF0F94D8, 0x58A95F9B, 0x0B33041F, 0x8C95CF5C,
        0x73E5570E, 0xF4439C4D, 0xA7D9C7C9, 0x207F0C8A, 0x00ED70C1, 0x874BBB82, 0xD4D1E006, 0x53772B45,
        0x95F51890, 0x1253D3D3, 0x41C98857, 0xC66F4314, 0xE6FD3F5F, 0x615BF41C, 0x32C1AF98, 0xB56764DB,
        0x64B4CE73, 0xE3120530, 0xB0885EB4, 0x372E95F7, 0x17BCE9BC, 0x901A22FF, 0xC380797B, 0x4426B238,
        0x82A481ED, 0x05024AAE, 0x5698112A, 0xD13EDA69, 0xF1ACA622, 0x760A6D61, 0x259036E5, 0xA236FDA6,
        0xBA8CCBE8, 0x3D2A00AB, 0x6EB05B2F, 0xE916906C, 0xC984EC27, 0x4E222764, 0x1DB87CE0, 0x9A1EB7A3,
        0x5C9C8476, 0xDB3A4F35, 0x88A014B1, 0x0F06DFF2, 0x2F94A3B9, 0xA83268FA, 0xFBA8337E, 0x7C0EF83D,
        0xADDD5295, 0x2A7B99D6, 0x79E1C252, 0xFE470911, 0xDED5755A, 0x5973BE19, 0x0AE9E59D, 0x8D4F2EDE,
        0x4BCD1D0B, 0xCC6BD648, 0x9FF18DCC, 0x1857468F, 0x38C53AC4, 0xBF63F187, 0xECF9AA03, 0x6B5F6140,
        0x942FF912, 0x13893251, 0x401369D5, 0xC7B5A296, 0xE727DEDD, 0x6081159E, 0x331B4E1A, 0xB4BD8559,
        0x723FB68C, 0xF5997DCF, 0xA603264B, 0x21A5ED08, 0x01379143, 0x86915A00, 0xD50B0184, 0x52ADCAC7,
        0x837E606F, 0x04D8AB2C, 0x5742F0A8, 0xD0E43BEB, 0xF07647A0, 0x77D08CE3, 0x244AD767, 0xA3EC1C24,
        0x656E2FF1, 0xE2C8E4B2, 0xB152BF36, 0x36F47475, 0x1666083E, 0x91C0C37D, 0xC25A98F9, 0x45FC53BA,
        0xE7CAAE1C, 0x606C655F, 0x33F63EDB, 0xB450F598, 0x94C289D3, 0x13644290, 0x40FE1914, 0xC758D257,
        0x01DAE182, 0x867C2AC1, 0xD5E67145, 0x5240BA06, 0x72D2C64D, 0xF5740D0E, 0xA6EE568A, 0x21489DC9,
        0xF09B3761, 0x773DFC22, 0x24A7A7A6, 0xA3016CE5, 0x839310AE, 0x0435DBED, 0x57AF8069, 0xD0094B2A,
        0x168B78FF, 0x912DB3BC, 0xC2B7E838, 0x4511237B, 0x65835F30, 0xE2259473, 0xB1BFCFF7, 0x361904B4,
        0xC9699CE6, 0x4ECF57A5, 0x1D550C21, 0x9AF3C762, 0xBA61BB29, 0x3DC7706A, 0x6E5D2BEE, 0xE9FBE0AD,
        0x2F79D378, 0xA8DF183B, 0xFB4543BF, 0x7CE388FC, 0x5C71F4B7, 0xDBD73FF4, 0x884D6470, 0x0FEBAF33,
        0xDE38059B, 0x599ECED8, 0x0A04955C, 0x8DA25E1F, 0xAD302254, 0x2A96E917, 0x790CB293, 0xFEAA79D0,
        0x38284A05, 0xBF8E8146, 0xEC14DAC2, 0x6BB21181, 0x4B206DCA, 0xCC86A689, 0x9F1CFD0D, 0x18BA364E,
    },
};

fn crc32Word(data: u32) u32 {
    var v: u32 = data;
    v = (v >> 8) ^ Crc32Table[@intCast(usize, v & 0xFF)];
    v = (v >> 8) ^ Crc32Table[@intCast(usize, v & 0xFF)];
    v = (v >> 8) ^ Crc32Table[@intCast(usize, v & 0xFF)];
    v = (v >> 8) ^ Crc32Table[@intCast(usize, v & 0xFF)];
    return v;
}

pub fn crc32Init() u32 {
    return 0xFFFFFFFF;
}

pub fn crc32Update(state: u32, data: []const u8) u32 {
    var crc: u32 = state;
    var i: usize = 0;

    // Braided (N=5, W=4) path: five independent CRC lanes over 20-byte
    // blocks, combined at the end (Kadatch-Jenkins, as in zlib).
    if (data.len >= 20) {
        var blocks: usize = data.len / 20;
        var c0: u32 = crc;
        var c1: u32 = 0;
        var c2: u32 = 0;
        var c3: u32 = 0;
        var c4: u32 = 0;
        while (blocks > 1) {
            blocks -= 1;
            var w0: u32 = c0 ^ (@intCast(u32, data[i]) | (@intCast(u32, data[i + 1]) << 8) | (@intCast(u32, data[i + 2]) << 16) | (@intCast(u32, data[i + 3]) << 24));
            var w1: u32 = c1 ^ (@intCast(u32, data[i + 4]) | (@intCast(u32, data[i + 5]) << 8) | (@intCast(u32, data[i + 6]) << 16) | (@intCast(u32, data[i + 7]) << 24));
            var w2: u32 = c2 ^ (@intCast(u32, data[i + 8]) | (@intCast(u32, data[i + 9]) << 8) | (@intCast(u32, data[i + 10]) << 16) | (@intCast(u32, data[i + 11]) << 24));
            var w3: u32 = c3 ^ (@intCast(u32, data[i + 12]) | (@intCast(u32, data[i + 13]) << 8) | (@intCast(u32, data[i + 14]) << 16) | (@intCast(u32, data[i + 15]) << 24));
            var w4: u32 = c4 ^ (@intCast(u32, data[i + 16]) | (@intCast(u32, data[i + 17]) << 8) | (@intCast(u32, data[i + 18]) << 16) | (@intCast(u32, data[i + 19]) << 24));
            i += 20;
            c0 = Crc32Braid[0][@intCast(usize, w0 & 0xFF)] ^ Crc32Braid[1][@intCast(usize, (w0 >> 8) & 0xFF)] ^ Crc32Braid[2][@intCast(usize, (w0 >> 16) & 0xFF)] ^ Crc32Braid[3][@intCast(usize, (w0 >> 24) & 0xFF)];
            c1 = Crc32Braid[0][@intCast(usize, w1 & 0xFF)] ^ Crc32Braid[1][@intCast(usize, (w1 >> 8) & 0xFF)] ^ Crc32Braid[2][@intCast(usize, (w1 >> 16) & 0xFF)] ^ Crc32Braid[3][@intCast(usize, (w1 >> 24) & 0xFF)];
            c2 = Crc32Braid[0][@intCast(usize, w2 & 0xFF)] ^ Crc32Braid[1][@intCast(usize, (w2 >> 8) & 0xFF)] ^ Crc32Braid[2][@intCast(usize, (w2 >> 16) & 0xFF)] ^ Crc32Braid[3][@intCast(usize, (w2 >> 24) & 0xFF)];
            c3 = Crc32Braid[0][@intCast(usize, w3 & 0xFF)] ^ Crc32Braid[1][@intCast(usize, (w3 >> 8) & 0xFF)] ^ Crc32Braid[2][@intCast(usize, (w3 >> 16) & 0xFF)] ^ Crc32Braid[3][@intCast(usize, (w3 >> 24) & 0xFF)];
            c4 = Crc32Braid[0][@intCast(usize, w4 & 0xFF)] ^ Crc32Braid[1][@intCast(usize, (w4 >> 8) & 0xFF)] ^ Crc32Braid[2][@intCast(usize, (w4 >> 16) & 0xFF)] ^ Crc32Braid[3][@intCast(usize, (w4 >> 24) & 0xFF)];
        }
        crc = crc32Word(c0 ^ (@intCast(u32, data[i]) | (@intCast(u32, data[i + 1]) << 8) | (@intCast(u32, data[i + 2]) << 16) | (@intCast(u32, data[i + 3]) << 24)));
        crc = crc32Word(c1 ^ (@intCast(u32, data[i + 4]) | (@intCast(u32, data[i + 5]) << 8) | (@intCast(u32, data[i + 6]) << 16) | (@intCast(u32, data[i + 7]) << 24)) ^ crc);
        crc = crc32Word(c2 ^ (@intCast(u32, data[i + 8]) | (@intCast(u32, data[i + 9]) << 8) | (@intCast(u32, data[i + 10]) << 16) | (@intCast(u32, data[i + 11]) << 24)) ^ crc);
        crc = crc32Word(c3 ^ (@intCast(u32, data[i + 12]) | (@intCast(u32, data[i + 13]) << 8) | (@intCast(u32, data[i + 14]) << 16) | (@intCast(u32, data[i + 15]) << 24)) ^ crc);
        crc = crc32Word(c4 ^ (@intCast(u32, data[i + 16]) | (@intCast(u32, data[i + 17]) << 8) | (@intCast(u32, data[i + 18]) << 16) | (@intCast(u32, data[i + 19]) << 24)) ^ crc);
        i += 20;
    }

    while (i < data.len) : (i += 1) {
        crc = (crc >> 8) ^ Crc32Table[@intCast(usize, (crc ^ @intCast(u32, data[i])) & 0xFF)];
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

const Sha512K = [_]u64{
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

fn sha512Block(h: []u64, buf: []const u8) void {
    var x: [16]u64 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        x[i] = (@intCast(u64, buf[i * 8]) << 56) |
            (@intCast(u64, buf[i * 8 + 1]) << 48) |
            (@intCast(u64, buf[i * 8 + 2]) << 40) |
            (@intCast(u64, buf[i * 8 + 3]) << 32) |
            (@intCast(u64, buf[i * 8 + 4]) << 24) |
            (@intCast(u64, buf[i * 8 + 5]) << 16) |
            (@intCast(u64, buf[i * 8 + 6]) << 8) |
            @intCast(u64, buf[i * 8 + 7]);
    }

    var a: u64 = h[0];
    var b: u64 = h[1];
    var c: u64 = h[2];
    var d: u64 = h[3];
    var e: u64 = h[4];
    var f: u64 = h[5];
    var g: u64 = h[6];
    var hh: u64 = h[7];
    var t1: u64 = 0;
    var t2: u64 = 0;

    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[0] +% x[0];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[1] +% x[1];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[2] +% x[2];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[3] +% x[3];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[4] +% x[4];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[5] +% x[5];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[6] +% x[6];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[7] +% x[7];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[8] +% x[8];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[9] +% x[9];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[10] +% x[10];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[11] +% x[11];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[12] +% x[12];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[13] +% x[13];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[14] +% x[14];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[15] +% x[15];
    t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;

    var grp: usize = 1;
    while (grp < 5) : (grp += 1) {
        var kb: usize = grp * 16;
        x[0] = x[0] +% (((x[1] >> 1) | ((x[1] & 0x1) << 63)) ^ ((x[1] >> 8) | ((x[1] & 0xFF) << 56)) ^ (x[1] >> 7)) +% x[9] +% (((x[14] >> 19) | ((x[14] & 0x7FFFF) << 45)) ^ ((x[14] >> 61) | ((x[14] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[14] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb] +% x[0];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[1] = x[1] +% (((x[2] >> 1) | ((x[2] & 0x1) << 63)) ^ ((x[2] >> 8) | ((x[2] & 0xFF) << 56)) ^ (x[2] >> 7)) +% x[10] +% (((x[15] >> 19) | ((x[15] & 0x7FFFF) << 45)) ^ ((x[15] >> 61) | ((x[15] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[15] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 1] +% x[1];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[2] = x[2] +% (((x[3] >> 1) | ((x[3] & 0x1) << 63)) ^ ((x[3] >> 8) | ((x[3] & 0xFF) << 56)) ^ (x[3] >> 7)) +% x[11] +% (((x[0] >> 19) | ((x[0] & 0x7FFFF) << 45)) ^ ((x[0] >> 61) | ((x[0] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[0] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 2] +% x[2];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[3] = x[3] +% (((x[4] >> 1) | ((x[4] & 0x1) << 63)) ^ ((x[4] >> 8) | ((x[4] & 0xFF) << 56)) ^ (x[4] >> 7)) +% x[12] +% (((x[1] >> 19) | ((x[1] & 0x7FFFF) << 45)) ^ ((x[1] >> 61) | ((x[1] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[1] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 3] +% x[3];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[4] = x[4] +% (((x[5] >> 1) | ((x[5] & 0x1) << 63)) ^ ((x[5] >> 8) | ((x[5] & 0xFF) << 56)) ^ (x[5] >> 7)) +% x[13] +% (((x[2] >> 19) | ((x[2] & 0x7FFFF) << 45)) ^ ((x[2] >> 61) | ((x[2] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[2] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 4] +% x[4];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[5] = x[5] +% (((x[6] >> 1) | ((x[6] & 0x1) << 63)) ^ ((x[6] >> 8) | ((x[6] & 0xFF) << 56)) ^ (x[6] >> 7)) +% x[14] +% (((x[3] >> 19) | ((x[3] & 0x7FFFF) << 45)) ^ ((x[3] >> 61) | ((x[3] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[3] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 5] +% x[5];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[6] = x[6] +% (((x[7] >> 1) | ((x[7] & 0x1) << 63)) ^ ((x[7] >> 8) | ((x[7] & 0xFF) << 56)) ^ (x[7] >> 7)) +% x[15] +% (((x[4] >> 19) | ((x[4] & 0x7FFFF) << 45)) ^ ((x[4] >> 61) | ((x[4] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[4] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 6] +% x[6];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[7] = x[7] +% (((x[8] >> 1) | ((x[8] & 0x1) << 63)) ^ ((x[8] >> 8) | ((x[8] & 0xFF) << 56)) ^ (x[8] >> 7)) +% x[0] +% (((x[5] >> 19) | ((x[5] & 0x7FFFF) << 45)) ^ ((x[5] >> 61) | ((x[5] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[5] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 7] +% x[7];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[8] = x[8] +% (((x[9] >> 1) | ((x[9] & 0x1) << 63)) ^ ((x[9] >> 8) | ((x[9] & 0xFF) << 56)) ^ (x[9] >> 7)) +% x[1] +% (((x[6] >> 19) | ((x[6] & 0x7FFFF) << 45)) ^ ((x[6] >> 61) | ((x[6] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[6] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 8] +% x[8];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[9] = x[9] +% (((x[10] >> 1) | ((x[10] & 0x1) << 63)) ^ ((x[10] >> 8) | ((x[10] & 0xFF) << 56)) ^ (x[10] >> 7)) +% x[2] +% (((x[7] >> 19) | ((x[7] & 0x7FFFF) << 45)) ^ ((x[7] >> 61) | ((x[7] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[7] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 9] +% x[9];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[10] = x[10] +% (((x[11] >> 1) | ((x[11] & 0x1) << 63)) ^ ((x[11] >> 8) | ((x[11] & 0xFF) << 56)) ^ (x[11] >> 7)) +% x[3] +% (((x[8] >> 19) | ((x[8] & 0x7FFFF) << 45)) ^ ((x[8] >> 61) | ((x[8] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[8] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 10] +% x[10];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[11] = x[11] +% (((x[12] >> 1) | ((x[12] & 0x1) << 63)) ^ ((x[12] >> 8) | ((x[12] & 0xFF) << 56)) ^ (x[12] >> 7)) +% x[4] +% (((x[9] >> 19) | ((x[9] & 0x7FFFF) << 45)) ^ ((x[9] >> 61) | ((x[9] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[9] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 11] +% x[11];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[12] = x[12] +% (((x[13] >> 1) | ((x[13] & 0x1) << 63)) ^ ((x[13] >> 8) | ((x[13] & 0xFF) << 56)) ^ (x[13] >> 7)) +% x[5] +% (((x[10] >> 19) | ((x[10] & 0x7FFFF) << 45)) ^ ((x[10] >> 61) | ((x[10] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[10] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 12] +% x[12];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[13] = x[13] +% (((x[14] >> 1) | ((x[14] & 0x1) << 63)) ^ ((x[14] >> 8) | ((x[14] & 0xFF) << 56)) ^ (x[14] >> 7)) +% x[6] +% (((x[11] >> 19) | ((x[11] & 0x7FFFF) << 45)) ^ ((x[11] >> 61) | ((x[11] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[11] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 13] +% x[13];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[14] = x[14] +% (((x[15] >> 1) | ((x[15] & 0x1) << 63)) ^ ((x[15] >> 8) | ((x[15] & 0xFF) << 56)) ^ (x[15] >> 7)) +% x[7] +% (((x[12] >> 19) | ((x[12] & 0x7FFFF) << 45)) ^ ((x[12] >> 61) | ((x[12] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[12] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 14] +% x[14];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
        x[15] = x[15] +% (((x[0] >> 1) | ((x[0] & 0x1) << 63)) ^ ((x[0] >> 8) | ((x[0] & 0xFF) << 56)) ^ (x[0] >> 7)) +% x[8] +% (((x[13] >> 19) | ((x[13] & 0x7FFFF) << 45)) ^ ((x[13] >> 61) | ((x[13] & 0x1FFFFFFFFFFFFFFF) << 3)) ^ (x[13] >> 6));
        t1 = hh +% (((e >> 14) | ((e & 0x3FFF) << 50)) ^ ((e >> 18) | ((e & 0x3FFFF) << 46)) ^ ((e >> 41) | ((e & 0x1FFFFFFFFFF) << 23))) +% ((e & f) ^ ((~e) & g)) +% Sha512K[kb + 15] +% x[15];
        t2 = (((a >> 28) | ((a & 0x0FFFFFFF) << 36)) ^ ((a >> 34) | ((a & 0x3FFFFFFFF) << 30)) ^ ((a >> 39) | ((a & 0x7FFFFFFFFF) << 25))) +% ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
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

const Blake2sSigma = [_]u8{
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

const Blake2sIV = [_]u32{
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
};

fn blake2sCompress(s: *Blake2s, final: bool) void {
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
        v[i + 8] = Blake2sIV[i];
    }
    v[12] = v[12] ^ @intCast(u32, s.t & 0xFFFFFFFF);
    v[13] = v[13] ^ @intCast(u32, s.t >> 32);
    if (final) v[14] = ~v[14];

    var r: usize = 0;
    while (r < 10) : (r += 1) {
        var o: usize = r * 16;

        v[0] = v[0] +% v[4] +% m[Blake2sSigma[o + 0]];
        v[12] = ((v[12] ^ v[0]) >> 16) | (((v[12] ^ v[0]) & 0xFFFF) << 16);
        v[8] = v[8] +% v[12];
        v[4] = ((v[4] ^ v[8]) >> 12) | (((v[4] ^ v[8]) & 0xFFF) << 20);
        v[0] = v[0] +% v[4] +% m[Blake2sSigma[o + 1]];
        v[12] = ((v[12] ^ v[0]) >> 8) | (((v[12] ^ v[0]) & 0xFF) << 24);
        v[8] = v[8] +% v[12];
        v[4] = ((v[4] ^ v[8]) >> 7) | (((v[4] ^ v[8]) & 0x7F) << 25);

        v[1] = v[1] +% v[5] +% m[Blake2sSigma[o + 2]];
        v[13] = ((v[13] ^ v[1]) >> 16) | (((v[13] ^ v[1]) & 0xFFFF) << 16);
        v[9] = v[9] +% v[13];
        v[5] = ((v[5] ^ v[9]) >> 12) | (((v[5] ^ v[9]) & 0xFFF) << 20);
        v[1] = v[1] +% v[5] +% m[Blake2sSigma[o + 3]];
        v[13] = ((v[13] ^ v[1]) >> 8) | (((v[13] ^ v[1]) & 0xFF) << 24);
        v[9] = v[9] +% v[13];
        v[5] = ((v[5] ^ v[9]) >> 7) | (((v[5] ^ v[9]) & 0x7F) << 25);

        v[2] = v[2] +% v[6] +% m[Blake2sSigma[o + 4]];
        v[14] = ((v[14] ^ v[2]) >> 16) | (((v[14] ^ v[2]) & 0xFFFF) << 16);
        v[10] = v[10] +% v[14];
        v[6] = ((v[6] ^ v[10]) >> 12) | (((v[6] ^ v[10]) & 0xFFF) << 20);
        v[2] = v[2] +% v[6] +% m[Blake2sSigma[o + 5]];
        v[14] = ((v[14] ^ v[2]) >> 8) | (((v[14] ^ v[2]) & 0xFF) << 24);
        v[10] = v[10] +% v[14];
        v[6] = ((v[6] ^ v[10]) >> 7) | (((v[6] ^ v[10]) & 0x7F) << 25);

        v[3] = v[3] +% v[7] +% m[Blake2sSigma[o + 6]];
        v[15] = ((v[15] ^ v[3]) >> 16) | (((v[15] ^ v[3]) & 0xFFFF) << 16);
        v[11] = v[11] +% v[15];
        v[7] = ((v[7] ^ v[11]) >> 12) | (((v[7] ^ v[11]) & 0xFFF) << 20);
        v[3] = v[3] +% v[7] +% m[Blake2sSigma[o + 7]];
        v[15] = ((v[15] ^ v[3]) >> 8) | (((v[15] ^ v[3]) & 0xFF) << 24);
        v[11] = v[11] +% v[15];
        v[7] = ((v[7] ^ v[11]) >> 7) | (((v[7] ^ v[11]) & 0x7F) << 25);

        v[0] = v[0] +% v[5] +% m[Blake2sSigma[o + 8]];
        v[15] = ((v[15] ^ v[0]) >> 16) | (((v[15] ^ v[0]) & 0xFFFF) << 16);
        v[10] = v[10] +% v[15];
        v[5] = ((v[5] ^ v[10]) >> 12) | (((v[5] ^ v[10]) & 0xFFF) << 20);
        v[0] = v[0] +% v[5] +% m[Blake2sSigma[o + 9]];
        v[15] = ((v[15] ^ v[0]) >> 8) | (((v[15] ^ v[0]) & 0xFF) << 24);
        v[10] = v[10] +% v[15];
        v[5] = ((v[5] ^ v[10]) >> 7) | (((v[5] ^ v[10]) & 0x7F) << 25);

        v[1] = v[1] +% v[6] +% m[Blake2sSigma[o + 10]];
        v[12] = ((v[12] ^ v[1]) >> 16) | (((v[12] ^ v[1]) & 0xFFFF) << 16);
        v[11] = v[11] +% v[12];
        v[6] = ((v[6] ^ v[11]) >> 12) | (((v[6] ^ v[11]) & 0xFFF) << 20);
        v[1] = v[1] +% v[6] +% m[Blake2sSigma[o + 11]];
        v[12] = ((v[12] ^ v[1]) >> 8) | (((v[12] ^ v[1]) & 0xFF) << 24);
        v[11] = v[11] +% v[12];
        v[6] = ((v[6] ^ v[11]) >> 7) | (((v[6] ^ v[11]) & 0x7F) << 25);

        v[2] = v[2] +% v[7] +% m[Blake2sSigma[o + 12]];
        v[13] = ((v[13] ^ v[2]) >> 16) | (((v[13] ^ v[2]) & 0xFFFF) << 16);
        v[8] = v[8] +% v[13];
        v[7] = ((v[7] ^ v[8]) >> 12) | (((v[7] ^ v[8]) & 0xFFF) << 20);
        v[2] = v[2] +% v[7] +% m[Blake2sSigma[o + 13]];
        v[13] = ((v[13] ^ v[2]) >> 8) | (((v[13] ^ v[2]) & 0xFF) << 24);
        v[8] = v[8] +% v[13];
        v[7] = ((v[7] ^ v[8]) >> 7) | (((v[7] ^ v[8]) & 0x7F) << 25);

        v[3] = v[3] +% v[4] +% m[Blake2sSigma[o + 14]];
        v[14] = ((v[14] ^ v[3]) >> 16) | (((v[14] ^ v[3]) & 0xFFFF) << 16);
        v[9] = v[9] +% v[14];
        v[4] = ((v[4] ^ v[9]) >> 12) | (((v[4] ^ v[9]) & 0xFFF) << 20);
        v[3] = v[3] +% v[4] +% m[Blake2sSigma[o + 15]];
        v[14] = ((v[14] ^ v[3]) >> 8) | (((v[14] ^ v[3]) & 0xFF) << 24);
        v[9] = v[9] +% v[14];
        v[4] = ((v[4] ^ v[9]) >> 7) | (((v[4] ^ v[9]) & 0x7F) << 25);
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
    if (sl > em.len) return false;
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
