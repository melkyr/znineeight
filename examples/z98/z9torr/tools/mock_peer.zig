// mock_peer.zig — z9torr M2 test double: a single-peer BitTorrent seeder.
//
// Separate Z98 binary (not linked into the client). Accepts ONE connection,
// reads the 68-byte handshake, then (normal mode):
//   1. replies with a handshake echoing the client's info_hash;
//   2. sends an unchoke;
//   3. sends a `bitfield` with every piece bit set (`ceil(n_pieces/8)` bytes,
//      spare bits 1);
//   4. loops: on `request{index,begin,length}` it reads those bytes from
//      --file and sends `piece{index,begin,bytes}`.
//
// Every outgoing message is framed with a 4-byte big-endian length prefix
// (length excludes itself; length 0 = keep-alive).
//
// Modes:
//   normal                serve requests until the peer closes
//   choke-after-N         after N received messages, send `choke` and close
//   disconnect-after-N    after N received messages, close
//   bad-bitfield-length   send a bitfield one byte too long
//   wrong-info-hash       reply-handshake with one mutated info_hash byte, close
//
// Flags: --port <n>  --file <path>  --piece-length <n>  --mode <mode>
// Determinism: Z9TORR_SEED (env) seeds the generated peer_id.
//
// Build (binding recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o out tools/mock_peer.zig
//   sh out/build_target.sh linux out/prog

const std = @import("std");
const std_net = @import("std_net");
const std_file = @import("std_file");

const DEFAULT_PORT: u32 = 6970;
const DEFAULT_PIECE_LENGTH: u32 = 262144;
const MAX_MESSAGE: usize = 65536;
const MAX_BITFIELD: usize = 8192;

const M_NORMAL: u8 = 0;
const M_CHOKE: u8 = 1;
const M_DISCONNECT: u8 = 2;
const M_BAD_BITFIELD: u8 = 3;
const M_WRONG_INFO: u8 = 4;

var g_body: [MAX_MESSAGE]u8 = undefined;
var g_out: [MAX_MESSAGE]u8 = undefined;
var g_bits: [MAX_BITFIELD]u8 = undefined;
var g_bits_bad: [MAX_BITFIELD + 1]u8 = undefined;
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

fn hasPrefix(s: []const u8, p: []const u8) bool {
    if (s.len < p.len) return false;
    var i: usize = 0;
    while (i < p.len) : (i += 1) {
        if (s[i] != p[i]) return false;
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

fn parseMode(s: []const u8, kind: *u8, n: *u32) bool {
    if (eq(s, "normal")) { kind.* = M_NORMAL; n.* = 0; return true; }
    if (eq(s, "wrong-info-hash")) { kind.* = M_WRONG_INFO; n.* = 0; return true; }
    if (eq(s, "bad-bitfield-length")) { kind.* = M_BAD_BITFIELD; n.* = 0; return true; }
    var cp: []const u8 = "choke-after-";
    if (hasPrefix(s, cp)) {
        kind.* = M_CHOKE;
        var rest: []const u8 = s[cp.len..];
        if (parseU32(rest)) |v| { n.* = v; return true; }
        return false;
    }
    var dp: []const u8 = "disconnect-after-";
    if (hasPrefix(s, dp)) {
        kind.* = M_DISCONNECT;
        var rest2: []const u8 = s[dp.len..];
        if (parseU32(rest2)) |v2| { n.* = v2; return true; }
        return false;
    }
    return false;
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
    var prefix: []const u8 = "-Z9TM01-";
    var i: usize = 0;
    while (i < prefix.len and i < dst.len) : (i += 1) {
        dst[i] = prefix[i];
    }
    var st: u32 = seed_in;
    if (st == 0) st = 1;
    while (i < dst.len) : (i += 1) {
        st = st * @intCast(u32, 1664525) + @intCast(u32, 1013904223);
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

fn sendSimple(fd: i32, id: u8) bool {
    var b: [5]u8 = undefined;
    putU32BE(b[0..], @intCast(u32, 1));
    b[4] = id;
    return sendAll(fd, b[0..]);
}

fn sendBitfield(fd: i32, bits: []const u8) bool {
    var hdr: [5]u8 = undefined;
    putU32BE(hdr[0..], @intCast(u32, 1 + bits.len));
    hdr[4] = 5;
    if (!sendAll(fd, hdr[0..])) return false;
    return sendAll(fd, bits);
}

fn sendPiece(fd: i32, index: u32, begin: u32, data: []const u8) bool {
    var hdr: [13]u8 = undefined;
    putU32BE(hdr[0..], @intCast(u32, 9 + data.len));
    hdr[4] = 7;
    putU32BE(hdr[5..], index);
    putU32BE(hdr[9..], begin);
    if (!sendAll(fd, hdr[0..])) return false;
    return sendAll(fd, data);
}

fn serve(fd: i32, f: *std_file.File, piece_length: u32, bits: []const u8,
         mode_kind: u8, mode_n: u32, peer_id: []const u8) void {
    var hs: [68]u8 = undefined;
    if (!recvExact(fd, hs[0..], 68)) return;

    var info: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        info[i] = hs[28 + i];
    }

    if (mode_kind == M_WRONG_INFO) {
        info[0] = info[0] ^ @intCast(u8, 0xFF);
        _ = writeHandshake(fd, info[0..], peer_id);
        return;
    }

    if (!writeHandshake(fd, info[0..], peer_id)) return;
    if (!sendBitfield(fd, bits)) return;
    if (!sendSimple(fd, 1)) return; // unchoke

    var count: u32 = 0;
    while (true) {
        var ph: [4]u8 = undefined;
        if (!recvExact(fd, ph[0..], 4)) return;
        const mlen: u32 = readU32BE(ph[0..]);
        if (mlen == 0) {
            count += 1;
            if (mode_kind == M_DISCONNECT and count >= mode_n) return;
            if (mode_kind == M_CHOKE and count >= mode_n) {
                _ = sendSimple(fd, 0);
                return;
            }
            continue;
        }
        if (mlen > MAX_MESSAGE) return;
        const mlen_us: usize = @intCast(usize, mlen);
        if (!recvExact(fd, g_body[0..mlen_us], mlen_us)) return;

        const id: u8 = g_body[0];
        if (id == 6 and mlen >= 13) {
            const idx: u32 = readU32BE(g_body[1..5]);
            const begin: u32 = readU32BE(g_body[5..9]);
            const blen: u32 = readU32BE(g_body[9..13]);
            if (blen <= MAX_MESSAGE) {
                const blen_us: usize = @intCast(usize, blen);
                const off: u64 = @intCast(u64, idx) * @intCast(u64, piece_length) + @intCast(u64, begin);
                if (fileReadAt(f, @intCast(i64, off), g_out[0..blen_us])) {
                    _ = sendPiece(fd, idx, begin, g_out[0..blen_us]);
                }
            }
        }

        count += 1;
        if (mode_kind == M_DISCONNECT and count >= mode_n) return;
        if (mode_kind == M_CHOKE and count >= mode_n) {
            _ = sendSimple(fd, 0);
            return;
        }
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var port: u32 = DEFAULT_PORT;
    var file_path: []const u8 = "";
    var piece_length: u32 = DEFAULT_PIECE_LENGTH;
    var mode_kind: u8 = M_NORMAL;
    var mode_n: u32 = 0;

    const n: usize = @intCast(usize, argc);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--port")) {
            i += 1;
            if (i >= n) { out("mock_peer: --port needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv| {
                port = pv;
            } else {
                out("mock_peer: bad --port\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--file")) {
            i += 1;
            if (i >= n) { out("mock_peer: --file needs a value\n"); std.os.exit(1); return; }
            file_path = argAt(argv, i);
        } else if (eq(tok, "--piece-length")) {
            i += 1;
            if (i >= n) { out("mock_peer: --piece-length needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv2| {
                if (pv2 == 0) { out("mock_peer: --piece-length must be > 0\n"); std.os.exit(1); return; }
                piece_length = pv2;
            } else {
                out("mock_peer: bad --piece-length\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--mode")) {
            i += 1;
            if (i >= n) { out("mock_peer: --mode needs a value\n"); std.os.exit(1); return; }
            if (!parseMode(argAt(argv, i), &mode_kind, &mode_n)) {
                out("mock_peer: unknown --mode\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--help") or eq(tok, "-h")) {
            var u: []const u8 = "usage: mock_peer --file F [--port N] [--piece-length N] [--mode M]\n";
            out(u);
            std.os.exit(0);
            return;
        } else {
            // Ignore unknown tokens.
        }
    }

    if (file_path.len == 0) {
        out("mock_peer: --file is required\n");
        std.os.exit(1);
        return;
    }
    if (port > 65535) {
        out("mock_peer: port out of range\n");
        std.os.exit(1);
        return;
    }

    var seed: u32 = 0;
    if (std.os.env("Z9TORR_SEED")) |sv| {
        if (parseU32(sv)) |sval| seed = sval;
    }

    var peer_id: [20]u8 = undefined;
    makePeerId(seed, peer_id[0..]);

    var arena = std.arena.init(g_arena_buf[0..]);
    var f: std_file.File = std_file.open(&arena, file_path, std_file.Mode.Read) catch {
        out("mock_peer: cannot open --file\n");
        std.os.exit(1);
        return;
    };
    const fsize: i64 = std_file.size(&f) catch {
        out("mock_peer: cannot size --file\n");
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
        out("mock_peer: too many pieces\n");
        std.os.exit(1);
        return;
    }

    var b: usize = 0;
    while (b < MAX_BITFIELD) : (b += 1) {
        g_bits[b] = @intCast(u8, 0xFF);
    }
    b = 0;
    while (b < MAX_BITFIELD + 1) : (b += 1) {
        g_bits_bad[b] = @intCast(u8, 0xFF);
    }

    var bits_send: []const u8 = g_bits[0..bf_len];
    if (mode_kind == M_BAD_BITFIELD) {
        bits_send = g_bits_bad[0 .. bf_len + 1];
    }

    if (std_net.init() != 0) {
        out("mock_peer: socket init failed\n");
        return;
    }
    const srv = std_net.createTcpServer(@intCast(u16, port));
    if (srv < 0) {
        out("mock_peer: createTcpServer failed\n");
        return;
    }
    if (std_net.bindListen(srv, 8) < 0) {
        out("mock_peer: listen failed\n");
        std_net.close(srv);
        return;
    }

    var l1: []const u8 = "mock_peer listening\n";
    out(l1);

    const c = std_net.accept(srv);
    if (c >= 0) {
        serve(c, &f, piece_length, bits_send, mode_kind, mode_n, peer_id[0..]);
        std_net.close(c);
    }

    std_net.close(srv);
    std_file.close(&f);
    std_net.cleanup();
}
