#!/usr/bin/env python3
"""mse_ref.py -- an independent, stdlib-only BitTorrent MSE/PE reference peer.

Implements the Message Stream Encryption / Protocol Encryption handshake as a
RESPONDER (the seeder/server side), plus a matching INITIATOR used only by
``--selftest`` to prove this responder implements the exact byte layout.

Byte layout (all integers big-endian), mirroring ``examples/z98/z9torr/mse.zig``:

    step1 A->B: Ya (96) || PadA (0..512, plaintext)
    step2 B->A: Yb (96) || PadB (0..512, plaintext)
    step3 A->B: HASH('req1'||S)                        (20, plaintext)
                HASH('req2'||SKEY) xor HASH('req3'||S) (20, plaintext)
                ENCRYPT_A( VC(8 x 0) || crypto_provide(u32) ||
                           len(PadC)(u16) || PadC || len(IA)(u16) || IA )
    step4 B->A: ENCRYPT_B( VC(8 x 0) || crypto_select(u32) ||
                           len(PadD)(u16) || PadD ) || ENCRYPT_B(payload)
    step5 A->B: ENCRYPT_A(payload)

    S     = Yb^Xa mod P = Ya^Xb mod P      (96-byte BE)
    keyA  = SHA1("keyA" || S || SKEY)      A encrypts / B decrypts
    keyB  = SHA1("keyB" || S || SKEY)      B encrypts / A decrypts
    SKEY  = info_hash (20 bytes)
    P     = the 768-bit Azureus MSE prime, g = 2
Each RC4 context discards its first 1024 keystream bytes before use.

stdlib only: ``hashlib`` (SHA1), ``pow`` (modexp), a hand-rolled RC4.

Usage:
    python3 mse_ref.py --selftest
    python3 mse_ref.py --serve FILE --info-hash HEX [--port N] [--piece-length N]
"""

import argparse
import hashlib
import os
import socket
import sys
import threading

# --- constants --------------------------------------------------------------

DH_LEN = 96
HASH_LEN = 20
VC_LEN = 8
PAD_MAX = 512
DISCARD = 1024

CRYPTO_PLAINTEXT = 0x01
CRYPTO_RC4 = 0x02

# 768-bit Azureus MSE safe prime (RFC 2409 group 1), generator 2. Byte-for-byte
# identical to mse.DH_PRIME in examples/z98/z9torr/mse.zig.
DH_PRIME = bytes.fromhex(
    "ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd1"
    "29024e088a67cc74020bbea63b139b22514a08798e3404dd"
    "ef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245"
    "e485b576625e7ec6f44c42e9a63a36210000000000090563"
)
assert len(DH_PRIME) == DH_LEN, len(DH_PRIME)

P = int.from_bytes(DH_PRIME, "big")
G = 2


# --- primitives -------------------------------------------------------------

class RC4:
    """RC4 stream cipher (KSA + PRGA); ``process`` advances the context."""

    __slots__ = ("s", "i", "j")

    def __init__(self, key):
        s = list(range(256))
        j = 0
        for i in range(256):
            j = (j + s[i] + key[i % len(key)]) & 0xFF
            s[i], s[j] = s[j], s[i]
        self.s = s
        self.i = 0
        self.j = 0

    def clone(self):
        c = RC4.__new__(RC4)
        c.s = list(self.s)
        c.i = self.i
        c.j = self.j
        return c

    def process(self, data):
        out = bytearray(len(data))
        s = self.s
        i = self.i
        j = self.j
        for k in range(len(data)):
            i = (i + 1) & 0xFF
            j = (j + s[i]) & 0xFF
            s[i], s[j] = s[j], s[i]
            out[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF]
        self.i = i
        self.j = j
        return bytes(out)

    def discard(self, n):
        self.process(bytes(n))


def sha1(*parts):
    h = hashlib.sha1()
    for p in parts:
        h.update(p)
    return h.digest()


def xor20(a, b):
    return bytes(x ^ y for x, y in zip(a, b))


def dh_public(x):
    return pow(G, x, P).to_bytes(DH_LEN, "big")


def dh_shared(y, x):
    return pow(int.from_bytes(y, "big"), x, P).to_bytes(DH_LEN, "big")


def derive_keys(s, info_hash):
    key_a = sha1(b"keyA", s, info_hash)
    key_b = sha1(b"keyB", s, info_hash)
    return key_a, key_b


def make_secret(seed=None):
    """A 20-byte DH private exponent as an int (non-zero)."""
    if seed is None:
        return int.from_bytes(os.urandom(HASH_LEN), "big") or 1
    # Deterministic 20-byte secret from a 32-bit seed (mirrors mse.makeSecret).
    st = seed & 0xFFFFFFFF or 1
    out = bytearray()
    while len(out) < HASH_LEN:
        st = (st * 1664525 + 1013904223) & 0xFFFFFFFF
        out.append((st >> 16) & 0xFF)
    if not any(out):
        out[0] = 1
    return int.from_bytes(bytes(out), "big")


# --- socket stream helpers --------------------------------------------------

def send_all(sock, data):
    sock.sendall(data)


def recv_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("peer closed")
        buf += chunk
    return bytes(buf)


def recv_decrypted(sock, ctx, n):
    """Receive exactly n raw bytes and RC4-decrypt them in stream order."""
    out = bytearray()
    while len(out) < n:
        chunk = sock.recv(n - len(out))
        if not chunk:
            raise ConnectionError("peer closed")
        out += ctx.process(chunk)
    return bytes(out)


# --- responder (server) handshake -------------------------------------------

def responder_handshake(sock, info_hash, secret):
    """Run the responder side; return (dec, enc) RC4 contexts.

    dec decrypts A->B (keyA); enc encrypts B->A (keyB). Both are advanced past
    the 1024-byte discard and the 8-byte VC.
    """
    if len(info_hash) != HASH_LEN:
        raise ValueError("info_hash must be 20 bytes")

    ya = recv_exact(sock, DH_LEN)                 # step 1
    yb = dh_public(secret)                        # step 2
    send_all(sock, yb)

    s = dh_shared(ya, secret)
    req1 = sha1(b"req1", s)

    # step 3a: scan plaintext for HASH('req1'||S) (skips PadA).
    window = b"\x00" * HASH_LEN
    scanned = 0
    found = False
    while scanned < PAD_MAX + HASH_LEN and not found:
        window = (window + recv_exact(sock, 1))[-HASH_LEN:]
        scanned += 1
        if window == req1:
            found = True
    if not found:
        raise ConnectionError("req1 not found (not an MSE peer?)")

    req2x = recv_exact(sock, HASH_LEN)
    expect = xor20(sha1(b"req2", info_hash), sha1(b"req3", s))
    if req2x != expect:
        raise ConnectionError("req2xor mismatch (wrong info_hash?)")

    key_a, key_b = derive_keys(s, info_hash)
    dec = RC4(key_a)                              # A->B decrypt
    enc = RC4(key_b)                              # B->A encrypt
    dec.discard(DISCARD)
    enc.discard(DISCARD)

    # step 3b: ENCRYPT_A(VC || crypto_provide || len(PadC) || PadC ||
    #                     len(IA) || IA)
    vc = recv_decrypted(sock, dec, VC_LEN)
    if vc != b"\x00" * VC_LEN:
        raise ConnectionError("bad VC (sync lost)")
    provide = int.from_bytes(recv_decrypted(sock, dec, 4), "big")
    pad_c = int.from_bytes(recv_decrypted(sock, dec, 2), "big")
    if pad_c:
        recv_decrypted(sock, dec, pad_c)
    ia_len = int.from_bytes(recv_decrypted(sock, dec, 2), "big")
    if ia_len:
        recv_decrypted(sock, dec, ia_len)

    if not (provide & CRYPTO_RC4):
        raise ConnectionError("initiator did not offer RC4")

    # step 4: ENCRYPT_B(VC || crypto_select=RC4 || len(PadD)=0)
    block = b"\x00" * VC_LEN + CRYPTO_RC4.to_bytes(4, "big") + b"\x00\x00"
    send_all(sock, enc.process(block))

    return dec, enc


# --- initiator handshake (selftest only) ------------------------------------

def initiator_handshake(sock, info_hash, secret):
    """Run the initiator side; return (out, in) RC4 contexts.

    out encrypts A->B (keyA); in decrypts B->A (keyB). Mirrors mse.mseConnect,
    including the raw scan for ENCRYPT_B(VC).
    """
    if len(info_hash) != HASH_LEN:
        raise ValueError("info_hash must be 20 bytes")

    send_all(sock, dh_public(secret))             # step 1 (PadA empty)
    yb = recv_exact(sock, DH_LEN)                 # step 2
    s = dh_shared(yb, secret)

    key_a, key_b = derive_keys(s, info_hash)
    out = RC4(key_a)                              # A->B encrypt
    inp = RC4(key_b)                              # B->A decrypt
    out.discard(DISCARD)
    inp.discard(DISCARD)

    # step 3: req1, req2xor, ENCRYPT_A(VC, RC4, 0, 0).
    send_all(sock, sha1(b"req1", s))
    send_all(sock, xor20(sha1(b"req2", info_hash), sha1(b"req3", s)))
    block = b"\x00" * VC_LEN + CRYPTO_RC4.to_bytes(4, "big") + b"\x00\x00\x00\x00"
    send_all(sock, out.process(block))

    # step 4: scan raw B->A bytes for ENCRYPT_B(VC) (skips PadB).
    enc_vc = inp.clone().process(b"\x00" * VC_LEN)
    window = b"\x00" * VC_LEN
    scanned = 0
    found = False
    while scanned < PAD_MAX + VC_LEN and not found:
        window = (window + recv_exact(sock, 1))[-VC_LEN:]
        scanned += 1
        if window == enc_vc:
            found = True
    if not found:
        raise ConnectionError("ENCRYPT_B(VC) not found")

    inp.process(b"\x00" * VC_LEN)                 # advance past VC
    select = int.from_bytes(recv_decrypted(sock, inp, 4), "big")
    if select != CRYPTO_RC4:
        raise ConnectionError("responder selected method %d" % select)
    pad_d = int.from_bytes(recv_decrypted(sock, inp, 2), "big")
    if pad_d:
        recv_decrypted(sock, inp, pad_d)

    return out, inp


# --- selftest ---------------------------------------------------------------

def _selftest_round_trip():
    info_hash = sha1(b"mse_ref selftest info hash")
    payload = bytes((i * 7 + 3) & 0xFF for i in range(4096))
    server_error = []

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]

    def server():
        try:
            conn, _ = srv.accept()
            try:
                dec, enc = responder_handshake(conn, info_hash, make_secret())
                got = recv_decrypted(conn, dec, len(payload))
                if got != payload:
                    raise AssertionError("responder received wrong payload")
                send_all(conn, enc.process(got))     # echo back
            finally:
                conn.close()
        except Exception as exc:  # noqa: BLE001 - surface in the main thread
            server_error.append(exc)

    t = threading.Thread(target=server, daemon=True)
    t.start()

    conn = socket.create_connection(("127.0.0.1", port), timeout=10)
    try:
        out, inp = initiator_handshake(conn, info_hash, make_secret())
        send_all(conn, out.process(payload))
        back = recv_decrypted(conn, inp, len(payload))
        if back != payload:
            raise AssertionError("initiator received wrong payload")
    finally:
        conn.close()
        srv.close()
        t.join(timeout=10)

    if server_error:
        raise server_error[0]


def cmd_selftest():
    _selftest_round_trip()
    print("mse_ref selftest: OK (responder+initiator handshake + 4096B round-trip)")
    return 0


# --- minimal seeder (BitTorrent over the encrypted stream) ------------------

def _read_frame(sock, dec):
    hdr = recv_decrypted(sock, dec, 4)
    mlen = int.from_bytes(hdr, "big")
    if mlen == 0:
        return b""
    return recv_decrypted(sock, dec, mlen)


def _make_peer_id():
    return b"-MR0001-" + os.urandom(12)


def _dbg(msg):
    if os.environ.get("MSE_REF_DEBUG"):
        sys.stderr.write("mse_ref: %s\n" % msg)
        sys.stderr.flush()


def serve_connection(conn, file_path, piece_length, info_hash, seed=None):
    """Run the responder handshake, then serve a single-file torrent."""
    dec, enc = responder_handshake(conn, info_hash, make_secret(seed))
    _dbg("MSE handshake done")

    hs = recv_decrypted(conn, dec, 68)
    if hs[0] != 19 or hs[1:20] != b"BitTorrent protocol":
        raise ConnectionError("bad BT handshake")
    if hs[28:48] != info_hash:
        raise ConnectionError("BT handshake info_hash mismatch")
    _dbg("BT handshake received")

    with open(file_path, "rb") as f:
        data = f.read()
    size = len(data)
    n_pieces = (size + piece_length - 1) // piece_length if size else 0
    bits = bytearray((n_pieces + 7) // 8)
    for i in range(n_pieces):
        bits[i // 8] |= 1 << (7 - (i % 8))

    peer_id = _make_peer_id()
    reply = bytes([19]) + b"BitTorrent protocol" + b"\x00" * 8 + info_hash + peer_id
    send_all(conn, enc.process(reply))
    send_all(conn, enc.process((1 + len(bits)).to_bytes(4, "big") + b"\x05" + bytes(bits)))
    send_all(conn, enc.process((1).to_bytes(4, "big") + b"\x01"))  # unchoke
    _dbg("sent handshake+bitfield(%d pieces)+unchoke" % n_pieces)

    while True:
        try:
            body = _read_frame(conn, dec)
        except ConnectionError:
            _dbg("peer closed")
            return
        if not body:
            continue
        _dbg("frame id=%d len=%d" % (body[0], len(body)))
        if body[0] == 6 and len(body) >= 13:  # request
            index = int.from_bytes(body[1:5], "big")
            begin = int.from_bytes(body[5:9], "big")
            length = int.from_bytes(body[9:13], "big")
            off = index * piece_length + begin
            chunk = data[off:off + length]
            hdr = (9 + len(chunk)).to_bytes(4, "big") + b"\x07" + \
                index.to_bytes(4, "big") + begin.to_bytes(4, "big")
            send_all(conn, enc.process(hdr + chunk))
            _dbg("sent piece idx=%d begin=%d len=%d" % (index, begin, len(chunk)))


def cmd_serve(args):
    info_hash = bytes.fromhex(args.info_hash)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    sys.stderr.write("mse_ref seeder listening on 127.0.0.1:%d\n" % args.port)
    sys.stderr.flush()
    conn, _ = srv.accept()
    try:
        serve_connection(conn, args.serve, args.piece_length, info_hash, args.seed)
    finally:
        conn.close()
        srv.close()
    return 0


# --- CLI --------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description="stdlib-only MSE/PE reference peer")
    ap.add_argument("--selftest", action="store_true",
                    help="run an in-process initiator+responder round-trip")
    ap.add_argument("--serve", metavar="FILE",
                    help="seed FILE once (requires --info-hash)")
    ap.add_argument("--info-hash", help="40 hex chars")
    ap.add_argument("--port", type=int, default=6990)
    ap.add_argument("--piece-length", type=int, default=262144)
    ap.add_argument("--seed", type=int, default=None)
    args = ap.parse_args(argv)

    if args.selftest:
        return cmd_selftest()
    if args.serve:
        if not args.info_hash:
            ap.error("--serve requires --info-hash")
        return cmd_serve(args)
    ap.error("nothing to do: pass --selftest or --serve FILE")
    return 2


if __name__ == "__main__":
    sys.exit(main())
