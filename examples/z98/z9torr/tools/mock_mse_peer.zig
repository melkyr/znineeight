// mock_mse_peer.zig — z9torr M4 test double: a BitTorrent seeder that REQUIRES
// MSE/PE (BitTorrent Protocol Encryption).
//
// Separate Z98 binary (not linked into the client). Accepts ONE connection and:
//   1. responds to the initiator's MSE handshake (steps 1-4 of the MSE/PE spec,
//      `HASH('keyA'||S||info_hash)` / `HASH('keyB'||S||info_hash)` derivation),
//      selecting RC4 (0x02);
//   2. then speaks the normal BitTorrent wire protocol through the RC4 stream:
//      reads the client's 68-byte handshake, replies with its own, sends an
//      unchoke + full bitfield, and serves `request` messages as `piece`s.
//
// The payload/bitfield/serving logic mirrors `tools/mock_peer.zig`; the only
// addition is the MSE responder wrapper and the RC4 transform on every frame.
//
// The responder needs the torrent's info_hash up front (to derive SKEY): pass
// `--info-hash <40 hex>`.
//
// Flags: --port <n>  --file <path>  --piece-length <n>  --info-hash <hex>
//
// Build (binding recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -fsafe -o out tools/mock_mse_peer.zig
//   sh out/build_target.sh linux out/prog

const std = @import("std");
const std_net = @import("std_net");
const std_file = @import("std_file");
const std_crypto = @import("std_crypto");
const mse = @import("../mse.zig");

const DEFAULT_PORT: u32 = 6970;
const DEFAULT_PIECE_LENGTH: u32 = 262144;
const MAX_MESSAGE: usize = 65536;
const MAX_BITFIELD: usize = 8192;

var g_body: [MAX_MESSAGE]u8 = undefined;
var g_out: [MAX_MESSAGE]u8 = undefined;
var g_bits: [MAX_BITFIELD]u8 = undefined;
var g_arena_buf: [65536]u8 = undefined;

fn out(s: []const u8) void {
    std.io.write(s);
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > @intCast(u64, 4294967295)) return null;
    }
    return @intCast(u32, v);
}

fn hexNibble(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn parseHex20(s: []const u8, dst: *[20]u8) bool {
    if (s.len != 40) return false;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const hi = hexNibble(s[i * 2]) orelse return false;
        const lo = hexNibble(s[i * 2 + 1]) orelse return false;
        dst[i] = @intCast(u8, @as(u32, hi) * 16 + @as(u32, lo));
    }
    return true;
}

fn putU32BE(b: []u8, v: u32) void {
    b[0] = @intCast(u8, (v >> 24) & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (v >> 16) & @intCast(u32, 0xFF));
    b[2] = @intCast(u8, (v >> 8) & @intCast(u32, 0xFF));
    b[3] = @intCast(u8, v & @intCast(u32, 0xFF));
}

fn readU32BE(b: []const u8) u32 {
    return (@intCast(u32, b[0]) << 24) | (@intCast(u32, b[1]) << 16) |
        (@intCast(u32, b[2]) << 8) | @intCast(u32, b[3]);
}

fn sendAll(fd: i32, data: []const u8) bool {
    var off: usize = 0;
    while (off < data.len) {
        var chunk: []const u8 = data[off..];
        const n = std_net.send(fd, chunk.ptr, @intCast(i32, chunk.len));
        if (n <= 0) return false;
        off += @intCast(usize, n);
    }
    return true;
}

fn recvExact(fd: i32, buf: []u8, want: usize) bool {
    var off: usize = 0;
    while (off < want) {
        var chunk: []u8 = buf[off..want];
        const n = std_net.recv(fd, chunk.ptr, @intCast(i32, chunk.len));
        if (n <= 0) return false;
        off += @intCast(usize, n);
    }
    return true;
}

// Receive exactly `want` bytes, RC4-decrypting each chunk as it arrives (stream
// order). `ctx` is the A->B decrypt context.
fn recvDecExact(fd: i32, ctx: *std_crypto.Rc4, buf: []u8, want: usize) bool {
    var off: usize = 0;
    while (off < want) {
        var chunk: []u8 = buf[off..want];
        const n = std_net.recv(fd, chunk.ptr, @intCast(i32, chunk.len));
        if (n <= 0) return false;
        const got: usize = @intCast(usize, n);
        std_crypto.rc4Apply(ctx, buf[off .. off + got]);
        off += got;
    }
    return true;
}

// Read one decrypted frame body into `body`; returns length (0 = keep-alive),
// or -1 on error/oversize.
fn recvFrame(fd: i32, dec: *std_crypto.Rc4, body: []u8) i32 {
    var ph: [4]u8 = undefined;
    if (!recvDecExact(fd, dec, ph[0..], 4)) return -1;
    const mlen: u32 = readU32BE(ph[0..]);
    if (mlen == 0) return 0;
    if (mlen > MAX_MESSAGE) return -1;
    const mu: usize = @intCast(usize, mlen);
    if (mu > body.len) return -1;
    if (!recvDecExact(fd, dec, body[0..mu], mu)) return -1;
    return mlen;
}

fn fileReadAt(f: *std_file.File, offset: i64, dst: []u8) bool {
    _ = std_file.seek(f, offset, std_file.SeekWhence.Set) catch {
        return false;
    };
    var off: usize = 0;
    while (off < dst.len) {
        var chunk: []u8 = dst[off..];
        const got = std_file.read(f, chunk) catch {
            return false;
        };
        if (got == 0) return false;
        off += got;
    }
    return true;
}

fn makePeerId(seed_in: u32, dst: []u8) void {
    var prefix: []const u8 = "-Z9TS01-";
    var i: usize = 0;
    while (i < prefix.len and i < dst.len) : (i += 1) {
        dst[i] = prefix[i];
    }
    var st: u32 = seed_in;
    if (st == 0) st = 1;
    while (i < dst.len) : (i += 1) {
        st = st *% @intCast(u32, 1664525) +% @intCast(u32, 1013904223);
        dst[i] = @intCast(u8, (st >> 16) & @intCast(u32, 0xFF));
    }
}

fn writeHandshake(fd: i32, info_hash: []const u8, peer_id: []const u8) bool {
    var h: [68]u8 = undefined;
    h[0] = 19;
    var pstr: []const u8 = "BitTorrent protocol";
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        h[1 + i] = pstr[i];
    }
    i = 0;
    while (i < 8) : (i += 1) {
        h[20 + i] = 0;
    }
    i = 0;
    while (i < 20) : (i += 1) {
        h[28 + i] = info_hash[i];
    }
    i = 0;
    while (i < 20) : (i += 1) {
        h[48 + i] = peer_id[i];
    }
    return sendAll(fd, h[0..]);
}

fn writeHandshakeEnc(fd: i32, enc: *std_crypto.Rc4, info_hash: []const u8, peer_id: []const u8) bool {
    var h: [68]u8 = undefined;
    h[0] = 19;
    var pstr: []const u8 = "BitTorrent protocol";
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        h[1 + i] = pstr[i];
    }
    i = 0;
    while (i < 8) : (i += 1) {
        h[20 + i] = 0;
    }
    i = 0;
    while (i < 20) : (i += 1) {
        h[28 + i] = info_hash[i];
    }
    i = 0;
    while (i < 20) : (i += 1) {
        h[48 + i] = peer_id[i];
    }
    std_crypto.rc4Apply(enc, h[0..]);
    return sendAll(fd, h[0..]);
}

fn sendSimpleEnc(fd: i32, enc: *std_crypto.Rc4, id: u8) bool {
    var b: [5]u8 = undefined;
    putU32BE(b[0..], @intCast(u32, 1));
    b[4] = id;
    std_crypto.rc4Apply(enc, b[0..]);
    return sendAll(fd, b[0..]);
}

fn sendBitfieldEnc(fd: i32, enc: *std_crypto.Rc4, bits: []const u8) bool {
    var hdr: [5]u8 = undefined;
    putU32BE(hdr[0..], @intCast(u32, 1 + bits.len));
    hdr[4] = 5;
    std_crypto.rc4Apply(enc, hdr[0..]);
    if (!sendAll(fd, hdr[0..])) return false;
    // Encrypt a copy of the bitfield (stream order: header then body).
    var i: usize = 0;
    while (i < bits.len) {
        g_out[i] = bits[i];
        i += 1;
    }
    std_crypto.rc4Apply(enc, g_out[0..bits.len]);
    return sendAll(fd, g_out[0..bits.len]);
}

fn sendPieceEnc(fd: i32, enc: *std_crypto.Rc4, index: u32, begin: u32, data: []u8) bool {
    var hdr: [13]u8 = undefined;
    putU32BE(hdr[0..], @intCast(u32, 9 + data.len));
    hdr[4] = 7;
    putU32BE(hdr[5..], index);
    putU32BE(hdr[9..], begin);
    std_crypto.rc4Apply(enc, hdr[0..]);
    if (!sendAll(fd, hdr[0..])) return false;
    std_crypto.rc4Apply(enc, data);
    return sendAll(fd, data);
}

// --- MSE responder ----------------------------------------------------------

fn eq20(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn respondMse(fd: i32, info_hash: []const u8, seed: u32, dec_out: *std_crypto.Rc4, enc_out: *std_crypto.Rc4) bool {
    // step 1: read Ya.
    var ya: [mse.DH_LEN]u8 = undefined;
    if (!recvExact(fd, ya[0..], mse.DH_LEN)) return false;

    // step 2: send Yb + PadB(0).
    var xb: [mse.HASH_LEN]u8 = undefined;
    mse.makeSecret(seed, xb[0..]);
    var yb: [mse.DH_LEN]u8 = undefined;
    mse.dhPublic(xb[0..], yb[0..]);
    if (!sendAll(fd, yb[0..])) return false;

    var s: [mse.DH_LEN]u8 = undefined;
    mse.dhShared(ya[0..], xb[0..], s[0..]);

    // sync on HASH('req1'||S): scan the plaintext stream (skip PadA).
    var req1: [mse.HASH_LEN]u8 = undefined;
    mse.hash2("req1", s[0..], &req1);
    var win: [mse.HASH_LEN]u8 = undefined;
    var cnt: usize = 0;
    var found: bool = false;
    var scanned: u32 = 0;
    while (scanned < 532 and !found) : (scanned += 1) {
        var b: [1]u8 = undefined;
        if (!recvExact(fd, b[0..], 1)) return false;
        var k: usize = 0;
        while (k + 1 < mse.HASH_LEN) : (k += 1) win[k] = win[k + 1];
        win[mse.HASH_LEN - 1] = b[0];
        cnt += 1;
        if (cnt >= mse.HASH_LEN and eq20(win[0..], req1[0..])) found = true;
    }
    if (!found) return false;

    // read HASH('req2'||SKEY) xor HASH('req3'||S) (we know SKEY).
    var req2x: [mse.HASH_LEN]u8 = undefined;
    if (!recvExact(fd, req2x[0..], mse.HASH_LEN)) return false;

    // keys: decB decrypts A->B with keyA; encB encrypts B->A with keyB.
    var key_a: [mse.HASH_LEN]u8 = undefined;
    var key_b: [mse.HASH_LEN]u8 = undefined;
    mse.deriveKeys(s[0..], info_hash, &key_a, &key_b);
    std_crypto.rc4Init(key_a[0..], dec_out);
    std_crypto.rc4Init(key_b[0..], enc_out);
    burn(dec_out);
    burn(enc_out);

    // decrypt VC + crypto_provide + len(PadC) + PadC + len(IA) + IA.
    var vc: [8]u8 = undefined;
    if (!recvDecExactLocal(fd, dec_out, vc[0..], 8)) return false;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (vc[i] != 0) return false;
    }
    var cp: [4]u8 = undefined;
    if (!recvDecExactLocal(fd, dec_out, cp[0..], 4)) return false;
    const provide: u32 = readU32BE(cp[0..]);
    var pcl: [2]u8 = undefined;
    if (!recvDecExactLocal(fd, dec_out, pcl[0..], 2)) return false;
    const pad_c_len: u32 = @intCast(u32, (@intCast(u16, pcl[0]) << 8) | @intCast(u16, pcl[1]));
    var pc: u32 = 0;
    while (pc < pad_c_len) : (pc += 1) {
        var one: [1]u8 = undefined;
        if (!recvDecExactLocal(fd, dec_out, one[0..], 1)) return false;
    }
    var ial: [2]u8 = undefined;
    if (!recvDecExactLocal(fd, dec_out, ial[0..], 2)) return false;
    const ia_len: u32 = @intCast(u32, (@intCast(u16, ial[0]) << 8) | @intCast(u16, ial[1]));
    var ia: u32 = 0;
    while (ia < ia_len) : (ia += 1) {
        var one2: [1]u8 = undefined;
        if (!recvDecExactLocal(fd, dec_out, one2[0..], 1)) return false;
    }

    // select RC4 if offered.
    if ((provide & mse.CRYPTO_RC4) == 0) return false;

    // step 4: ENCRYPT_B(VC, crypto_select, len(PadD)=0).
    var resp: [8 + 4 + 2]u8 = undefined;
    i = 0;
    while (i < 8) : (i += 1) resp[i] = 0;
    putU32BE(resp[8..12], mse.CRYPTO_RC4);
    resp[12] = 0;
    resp[13] = 0;
    std_crypto.rc4Apply(enc_out, resp[0..]);
    if (!sendAll(fd, resp[0..])) return false;
    return true;
}

fn burn(ctx: *std_crypto.Rc4) void {
    var b: [1024]u8 = undefined;
    var i: usize = 0;
    while (i < 1024) : (i += 1) b[i] = 0;
    std_crypto.rc4Apply(ctx, b[0..]);
}

fn recvDecExactLocal(fd: i32, ctx: *std_crypto.Rc4, buf: []u8, want: usize) bool {
    return recvDecExact(fd, ctx, buf, want);
}

fn serve(fd: i32, f: *std_file.File, piece_length: u32, bits: []const u8,
         info_hash: []const u8, seed: u32, peer_id: []const u8) void {
    var dec: std_crypto.Rc4 = undefined;
    var enc: std_crypto.Rc4 = undefined;
    if (!respondMse(fd, info_hash, seed, &dec, &enc)) return;

    // Read the client's BT handshake through the encrypted stream.
    var hs: [68]u8 = undefined;
    if (!recvDecExact(fd, &dec, hs[0..], 68)) return;

    // Reply with our handshake, bitfield, unchoke (all encrypted).
    if (!writeHandshakeEnc(fd, &enc, info_hash, peer_id)) return;
    if (!sendBitfieldEnc(fd, &enc, bits)) return;
    if (!sendSimpleEnc(fd, &enc, 1)) return; // unchoke

    while (true) {
        const mlen = recvFrame(fd, &dec, g_body[0..]);
        if (mlen < 0) return;
        if (mlen == 0) continue;
        const id: u8 = g_body[0];
        if (id == 6 and mlen >= 13) {
            const idx: u32 = readU32BE(g_body[1..5]);
            const begin: u32 = readU32BE(g_body[5..9]);
            const blen: u32 = readU32BE(g_body[9..13]);
            if (blen <= MAX_MESSAGE) {
                const blen_us: usize = @intCast(usize, blen);
                const off: u64 = @intCast(u64, idx) * @intCast(u64, piece_length) + @intCast(u64, begin);
                if (fileReadAt(f, @intCast(i64, off), g_out[0..blen_us])) {
                    _ = sendPieceEnc(fd, &enc, idx, begin, g_out[0..blen_us]);
                }
            }
        }
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var port: u32 = DEFAULT_PORT;
    var file_path: []const u8 = "";
    var piece_length: u32 = DEFAULT_PIECE_LENGTH;
    var info_hex: []const u8 = "";

    const n: usize = @intCast(usize, argc);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--port")) {
            i += 1;
            if (i >= n) { out("mock_mse_peer: --port needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv| {
                port = pv;
            } else {
                out("mock_mse_peer: bad --port\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--file")) {
            i += 1;
            if (i >= n) { out("mock_mse_peer: --file needs a value\n"); std.os.exit(1); return; }
            file_path = argAt(argv, i);
        } else if (eq(tok, "--piece-length")) {
            i += 1;
            if (i >= n) { out("mock_mse_peer: --piece-length needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv2| {
                if (pv2 == 0) { out("mock_mse_peer: --piece-length must be > 0\n"); std.os.exit(1); return; }
                piece_length = pv2;
            } else {
                out("mock_mse_peer: bad --piece-length\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--info-hash")) {
            i += 1;
            if (i >= n) { out("mock_mse_peer: --info-hash needs a value\n"); std.os.exit(1); return; }
            info_hex = argAt(argv, i);
        } else if (eq(tok, "--help") or eq(tok, "-h")) {
            var u: []const u8 = "usage: mock_mse_peer --file F --info-hash H [--port N] [--piece-length N]\n";
            out(u);
            std.os.exit(0);
            return;
        } else {
            // ignore unknown tokens
        }
    }

    if (file_path.len == 0) {
        out("mock_mse_peer: --file is required\n");
        std.os.exit(1);
        return;
    }
    var info_hash: [20]u8 = undefined;
    if (!parseHex20(info_hex, &info_hash)) {
        out("mock_mse_peer: --info-hash must be 40 hex chars\n");
        std.os.exit(1);
        return;
    }
    if (port > 65535) {
        out("mock_mse_peer: port out of range\n");
        std.os.exit(1);
        return;
    }

    var seed: u32 = 0;
    if (std.os.env("Z9TORR_SEED")) |sv| {
        if (parseU32(sv)) |sval| seed = sval;
    }
    if (seed == 0) seed = 0x5EED1234;

    var peer_id: [20]u8 = undefined;
    makePeerId(seed, peer_id[0..]);

    var arena = std.arena.init(g_arena_buf[0..]);
    var f: std_file.File = std_file.open(&arena, file_path, std_file.Mode.Read) catch {
        out("mock_mse_peer: cannot open --file\n");
        std.os.exit(1);
        return;
    };
    const fsize: i64 = std_file.size(&f) catch {
        out("mock_mse_peer: cannot size --file\n");
        std.os.exit(1);
        return;
    };

    var n_pieces: u32 = 0;
    if (fsize > 0) {
        const fs_u: u64 = @intCast(u64, fsize);
        const pl_u: u64 = @intCast(u64, piece_length);
        n_pieces = @intCast(u32, (fs_u + pl_u - 1) / pl_u);
    }
    const bf_len: usize = (@intCast(usize, n_pieces) + 7) / 8;
    if (bf_len > MAX_BITFIELD) {
        out("mock_mse_peer: too many pieces\n");
        std.os.exit(1);
        return;
    }
    var b: usize = 0;
    while (b < MAX_BITFIELD) : (b += 1) {
        g_bits[b] = @intCast(u8, 0xFF);
    }

    if (std_net.init() != 0) {
        out("mock_mse_peer: socket init failed\n");
        return;
    }
    const srv = std_net.createTcpServer(@intCast(u16, port));
    if (srv < 0) {
        out("mock_mse_peer: createTcpServer failed\n");
        return;
    }
    if (std_net.bindListen(srv, 8) < 0) {
        out("mock_mse_peer: listen failed\n");
        std_net.close(srv);
        return;
    }

    var l1: []const u8 = "mock_mse_peer listening\n";
    out(l1);

    const c = std_net.accept(srv);
    if (c >= 0) {
        serve(c, &f, piece_length, g_bits[0..bf_len], info_hash[0..], seed, peer_id[0..]);
        std_net.close(c);
    }

    std_net.close(srv);
    std_file.close(&f);
    std_net.cleanup();
}
