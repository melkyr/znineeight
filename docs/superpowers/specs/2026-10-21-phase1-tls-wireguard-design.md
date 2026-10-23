# Phase 1 — TLS 1.2/1.3 + WireGuard: Secure Networking Foundation — Design

> Vision (operator): "here is z98 you imagine it, you have it it serves c89 but once you
> are set do modern dev as it will serve the TLS 1.2/1.3 you will likely need for use
> cases." Z98 ships as the era-authentic C89 toolchain on CD/DVD/USB; the moment it is
> set up, modern networking work — real HTTPS, a real VPN — is possible without a
> package manager, because the libraries ship with the compiler, like OpenWatcom /
> mingw / MSVC6 shipped their runtime and networking packages.

Blueprint sources: `examples/roadmap.txt` (Phase 1 = TLS + WireGuard) and
`examples/projects_phase1.txt` (technical blueprint: BearSSL / mbedTLS / picotls /
wireguard-lwip references). Target: **Win9x (98/ME) primary, Linux necessary** (it is
the dev/test environment and the WireGuard far side).

## 1. Ground truth (verified)

- **Win98/ME have TCP/IP v4 built in** — Winsock 2 is integral; DHCP, APIPA, IP
  multicast present (Wikipedia: Windows 98 networking enhancements; Winsock article:
  Winsock 2.1 "integral component of Windows 98"). Nothing to install.
- **Win95**: TCP/IP is an *optional protocol* (install from the CD via Control Panel →
  Network → Add → Protocol → Microsoft → TCP/IP); Winsock 2 is a separate add-on.
  Docs carry an install note; Win95 stays best-effort.
- **IPv6**: never integral on Win9x (Windows 2000 preview; part of Winsock at XP).
  Out of scope, documented as era-correct. Every demo and later blueprint project
  (git client over HTTPS) works over IPv4.
- **No TUN/TAP/Wintun on Win9x.** This is the real gap: modern WireGuard injects
  inner packets into the OS stack via a virtual adapter; Win9x has none. Therefore a
  **userspace IP stack terminates the tunnel side** (the lwIP model, as in
  `wireguard-lwip`). The OS stack serves only the outer UDP socket.
- **No TLS 1.2/1.3 anywhere on Win9x** (Schannel-era at most SSL 3.0/TLS 1.0). The
  library is the product.
- Existing std (verified at v111): `std_crypto` already has SHA-1/SHA-256 (FIPS 180-4
  streaming)/MD5/CRC-32/RC4/modpow with an "alloc no / errors no / pure" contract;
  `std_http` has `Url`/`Header`/`Response`, `parseUrl`, `parseResponse`, `get()`;
  `std_net` has TCP client/server, `udpBind`/`udpSendTo`/`udpRecvFrom`, `resolve`,
  `select`, non-blocking mode; `std_base64`, `std_hex`, `std_rand` (xoshiro256**),
  `std_arena`, `std_async`, `std_time.ticksMs`/`highRes`, `std_math.sqrt` all exist.

## 2. Goals, non-goals, anti-goals

**Goals**

1. `std_tls`: a capable TLS 1.2 then TLS 1.3 **client** library with browser-grade
   X.509 chain validation and hostname checking — usable by later blueprint projects
   (git client), not a demo-shaped handshake.
2. `std_wireguard`: WireGuard **initiator** protocol (NoiseIK + transport + timers).
3. `std_tcpip`: userspace IPv4 + TCP client + UDP + DNS resolver + ICMP echo — the
   "didn't exist on Win9x" tunnel-side stack, in std, self-contained.
4. Two documented demos under `examples/z98/demo/`:
   - `tls_demo`: fetch real web content over HTTPS from the open internet
     (default `https://www.google.com/`; tier also tests `https://example.com/`).
   - `wireguard_demo`: connect to a **real Linux kernel WireGuard server**, then open
     a TCP connection through the tunnel to the repo's `mud_server` and see its
     banner. Same binary drives any endpoint via a config file (LAN box / VPN at the
     live demo).
5. Trust store: a shipped CA store asset (Mozilla `cacert.pem` snapshot) with a
   **Z98 converter tool** and a documented refresh recipe. Everything self-contained.
6. Resource honesty: demos compile and run within **16 MB target / 32 MB hard
   ceiling** (RAM); compiler peak RSS recorded in README + QUICK_REF (pre-flight).

**Non-goals**

- TLS server role; TLS 1.0/1.1; RSA key exchange; CBC modes; RC4/3DES; renegotiation;
  session resumption / tickets; 0-RTT; client certificates; ALPN/HTTP-2; HelloRetryRequest
  (a group mismatch fails cleanly); OCSP/CRL checking; SHA-1 signature verification
  (roots are trusted by fiat; all real intermediates are SHA-256+).
- WireGuard responder role; multiple simultaneous peers in the demo (protocol keeps a
  peer table, demo uses one); cookie-reply generation (consumption yes).
- IPv6 anywhere; inner-stack TCP *server* role; IP fragmentation reassembly (fixed
  MSS ~1400, never fragment); GRE/bridging; a TUN/Wintun-style OS driver.
- Package manager, dynamic linking, downloads at runtime. Distribution is the disc.
- HTTP: only GET, HTTP/1.1, `identity` + `chunked` bodies; no gzip (we never ask), no
  redirects (single request).

**Anti-goals**

- A "TLS-shaped" demo that cannot validate a real certificate chain — pinning-only
  shortcuts are not acceptable for the library (they are acceptable only as an
  explicitly named test mode).
- Anything that pulls `libm`, C99, compiler builtins, or `malloc` into the shipped
  code path (no-CRT Win9x must stay linkable: KERNEL32+WINMM/WSOCK32 only).
- Loading a whole audio/video-sized file or the whole web page into RAM; all I/O is
  bounded-buffer or streamed.

## 3. Constraints

- Z98 subset only (no new language features); emitted C89 must build with mingw
  (`-m32`), MSVC6, OpenWatcom per existing emitted-script surface; no-CRT default for
  `-osw`.
- Library memory discipline: **fixed-size state, caller-provided arenas, no heap** in
  all new modules (the existing `std_crypto` contract: "alloc no | errors no |
  coroutine no"). Crypto is constant-time where required (no data-dependent branches
  or table indices in Poly1305/X25519/P-256 scalar paths).
- Determinism/R6: std never reads clock/env. Randomness enters via an explicit
  `seed: u64` / caller-owned xoshiro256\*\* state (TLS client keygen, WireGuard
  ephemerals). Timers use `std_time.ticksMs`/`highRes` values *passed in* by the
  driver.
- **Sans-I/O** protocol engines (TLS, WireGuard, TCP/IP core): take bytes in, produce
  bytes out plus an action; `std.async`-style drivers own the sockets. Testable
  against canned transcripts; the same binary runs on Linux and Win9x.
- Demo RAM: 32 MB hard ceiling (enforced with `ulimit -v` + measured peak RSS),
  16 MB the stretch target. Compiler peak RSS for building these is measured and
  recorded in README/QUICK_REF.
- Self-contained distribution: the CA-store converter is a Z98 program; the store is
  an asset file; docs say where to get `cacert.pem` and how to refresh.
- Testing: existing `scripts/stdlib/verify_stdlib.sh` + `run_crosscheck.sh` harness
  for std modules (fixtures, C89 refs, `.in`/`.expected` vectors); integration tiers
  (`tier_tls.sh`, `tier_wireguard.sh`) for real-server runs; Wine tier for `-osw`.
  No silent skips. Defects go to `examples/torrent_example_defects.md` (next free
  slot). Seed rotation at each milestone closeout (std file count grows; fixed point
  `45158dcede81125a39a2c2c58478e21e` must not move — std is outside self-emission).

## 4. Architecture — what is std, what is demo

```
                 examples/z98/demo/tls_demo          examples/z98/demo/wireguard_demo
                 (HTTPS fetch, CA store asset,        (config file, mud banner through
                  resource meters, docs)               tunnel, resource meters, docs)
                              |                                    |
        +---------------------+---------------------+--------------+
        |                     |                     |              |
   std_http (GET over    std_tls (1.2/1.3)    std_wireguard   std_tcpip
   any transport)              |              (NoiseIK init,   (IPv4, TCP client,
        |                std_x509/std_asn1     transport,       UDP, DNS, ICMP)
        |                (chain + hostname)    timers)              |
        |                     |                     |              |
        +---------------------+----------+----------+--------------+
                                        |
                        std_crypto += SHA-384/512, HMAC-SHA256, HKDF, BLAKE2s,
                                      RSA PKCS#1 v1.5/PSS verify
                        std_cipher = ChaCha20, Poly1305, ChaCha20-Poly1305,
                                     AES-128-GCM (T-tables, GHASH)
                        std_ecc = X25519, P-256 ECDH + ECDSA verify,
                                  P-384 ECDSA verify
                                        |
              existing: std_net (OS sockets/DNS), std_arena, std_async, std_rand,
                        std_time, std_base64, std_hex, std_math, std_mem, std_str
```

**Std ("the super upgrade")** — reusable, fixture-tested, shipped with the compiler:
`std_crypto` extensions, `std_cipher`, `std_ecc`, `std_asn1`, `std_x509` (+ trust
store format/loader), `std_tls`, `std_wireguard`, `std_tcpip`, and `std_http` gaining
a pluggable transport so HTTPS is a std capability.

**Demo layer only** — `examples/z98/demo/{tls_demo,wireguard_demo}/` (harnesses,
config readers, resource meters, docs) and the Z98 CA converter tool
(`examples/z98/demo/tls_demo/caconv/`). The far side (kernel WireGuard + mud_server +
openssl s_server) is test infrastructure on Linux, not shipped code.

Leverage as-is: `std_net` sockets/`resolve`/`select` for outer transport;
`std_http.parseUrl`/`parseResponse`; `std_crypto` SHA-256 as the TLS transcript hash;
`std_rand` xoshiro256\*\* for all nonce/key generation; `std_base64` for PEM decoding
in the converter; `std_arena` for per-connection scratch; `std_time` for timers.

## 5. Module contracts

Signatures below are binding shape; bodies are the implementer's. All modules follow
house naming (`std_<name>.zig`, camelCase) and the L5-style purity contract unless
stated.

### 5.1 `std_crypto` additions (hash/PRF/RSA family)

```zig
pub fn hmacSha256(key: []const u8, msg: []const u8, out: *[32]u8) void
pub const HmacSha256 = struct { ... };           // streaming: init(key)/update/final
pub fn hkdfExtract(salt: []const u8, ikm: []const u8, out: *[32]u8) void   // RFC 5869
pub fn hkdfExpand(prk: *const [32]u8, info: []const u8, out: []u8) !void
pub const Blake2s = struct { ... };              // RFC 7693; keyed + unkeyed
pub fn blake2sInit(key: []const u8, out_len: u32) Blake2s
pub fn blake2sUpdate(s: *Blake2s, data: []const u8) void
pub fn blake2sFinal(s: *Blake2s, out: []u8) void
pub fn hmacBlake2s(key: []const u8, msg: []const u8, out: []u8) void       // WG MACs
pub const Sha384 = struct { ... };               // FIPS 180-4 streaming
pub const Sha512 = struct { ... };
pub fn sha384Init() Sha384 ;  sha384Update ;  sha384Final(out: *[48]u8)
pub fn sha512Init() Sha512 ;  sha512Update ;  sha512Final(out: *[64]u8)
// RSA verify only (no signing) — new generic modexp up to 4096-bit n with fixed
// scratch; the existing MSE-sized modpow (768-bit) is too small for this.
pub fn rsaVerifyPkcs1v15(n: []const u8, e: u32, hash_alg: HashAlg,
    hash: []const u8, sig: []const u8) !void      // RFC 8017 §8.2.2
pub fn rsaVerifyPss(n: []const u8, e: u32, hash_alg: HashAlg,
    hash: []const u8, salt_len: u32, sig: []const u8) !void   // RFC 8017 §8.1.2 + MGF1
```

Vectors: RFC 4231 (HMAC-SHA256), RFC 5869 (HKDF), RFC 7693 appendix (BLAKE2s),
FIPS 180-4 / NIST CAVP (SHA-384/512), NIST CAVP RSA + RFC 8017 (PKCS#1 v1.5 and
PSS/MGF1). Errors: `error.{BadSignature, UnsupportedAlgorithm, Corrupt}`.

### 5.2 `std_cipher` (symmetric; constant-time)

```zig
pub fn chacha20Init(key: *const [32]u8, nonce: *const [12]u8, counter: u32) ChaCha20
pub fn chacha20Xor(s: *ChaCha20, dst: []u8, src: []const u8) void
pub fn poly1305Init(key: *const [32]u8) Poly1305        // donna 5x26-bit limbs
pub fn poly1305Update(s: *Poly1305, data: []const u8) void
pub fn poly1305Final(s: *Poly1305, out: *[16]u8) void
pub fn chacha20Poly1305Seal(key: *const [32]u8, nonce: *const [12]u8,
    ad: []const u8, pt: []const u8, ct: []u8, tag: *[16]u8) !void          // RFC 8439
pub fn chacha20Poly1305Open(key: *const [32]u8, nonce: *const [12]u8,
    ad: []const u8, ct: []const u8, tag: *const [16]u8, pt: []u8) !void    // error.AuthenticationFailed
pub const Aes128 = struct { ... };                     // T-tables: 4 KB const, rodata
pub fn aes128Init(key: *const [16]u8) Aes128
pub fn aes128EncryptBlock(a: *const Aes128, in: *const [16]u8, out: *[16]u8) void
pub fn aes128GcmSeal(..., iv: *const [12]u8, ad, pt, ct, tag: *[16]u8) !void  // SP800-38D
pub fn aes128GcmOpen(..., tag: *const [16]u8, pt) !void                       // error.AuthenticationFailed
```

GHASH uses 4-bit tables (16 entries) per BearSSL practice — no carry-less multiply
intrinsic. Vectors: RFC 8439, NIST GCM test vectors (at least 2 per case class).

### 5.3 `std_ecc`

```zig
pub fn x25519(scalar: *const [32]u8, u: *const [32]u8, out: *[32]u8) !void  // RFC 7748
pub fn x25519Base(scalar: *const [32]u8, out: *[32]u8) !void               // clamp included
pub fn p256Generate(rng: *std_rand.Xoshiro256, priv: *[32]u8, pub_out: *[65]u8) void
pub fn p256Ecdh(priv: *const [32]u8, peer_pub: *const [65]u8, out: *[32]u8) !void
pub fn p256EcdsaVerify(pub_uncompressed: *const [65]u8, hash32: *const [32]u8,
    r: *const [32]u8, s: *const [32]u8) bool
pub fn p384EcdsaVerify(pub_uncompressed: *const [97]u8, hash48: *const [48]u8,
    r: *const [48]u8, s: *const [48]u8) bool     // verify-only: chain auth (§5.4)
```

X25519: ref10-style 26-bit limbs (PORTABLE), constant-time ladder, all-zero output
rejected (`error.WeakPublicKey`). P-256: p256-m portable C path ported (32-bit limbs,
constant-time); **never written from scratch**. P-384 is **verify-only** (no
keygen/ECDH: client ECDHE groups stay x25519 + secp256r1) and ports the BearSSL
portable P-384 verify path — p256-m covers only P-256; the shared-limb generic EC
engine is the alternative if the implementer prefers one engine for both curves.
ECDSA verify takes a caller-supplied hash (SHA-256 for P-256, SHA-384 for P-384).
Vectors: RFC 7748, NIST CAVP P-256 ECDH/ECDSA, NIST CAVP P-384 ECDSA verify.

### 5.4 `std_asn1` / `std_x509`

```zig
// std_asn1: streaming DER reader, no alloc; slices point into the input buffer.
pub const Asn1Reader = struct { data: []const u8, pos: usize, ... };
pub fn asn1ReadTlv(r: *Asn1Reader) !Tlv        // error.Corrupt on malformed
// std_x509:
pub const Cert = struct { subject: []const u8, issuer: []const u8,
    spki: []const u8, sig: []const u8, sig_alg: SigAlg, pk_alg: PkAlg,
    not_before: i64, not_after: i64, is_ca: bool, san_dns: []const []const u8, ... };
pub fn x509Parse(der: []const u8, out: *Cert) !void
pub const TrustAnchor = struct { subject: []const u8, spki: []const u8,
    not_before: i64, not_after: i64 };                 // arena-owned copies
pub const TrustStore = struct { anchors: []TrustAnchor };
pub fn trustStoreLoad(arena: *std_arena.Arena, bytes: []const u8, out: *TrustStore) !void
pub fn x509VerifyChain(arena: *std_arena.Arena, leaf_der: []const u8,
    intermediates: []const []const u8, store: *TrustStore,
    hostname: []const u8, now_unix: i64) !void
```

Validation policy (browser-grade, BearSSL-shaped): path build leaf→anchor by
subject/issuer name equality (depth ≤ 8); verify each signature (ECDSA P-256/384
SHA-256/384; RSA PKCS#1 v1.5 SHA-256/384/512, keys ≥ 2048); validity window vs
`now_unix` (caller supplies time — R6); `basicConstraints` CA flag for CAs;
hostname match = **SAN dNSName only** (exact, case-insensitive; single-leftmost-label
wildcard `*.example.com`; no CN fallback, no IP SANs). Errors:
`error.{CertificateExpired, CertificateNotYetValid, UnknownIssuer, HostnameMismatch,
BadSignature, ChainTooLong, Corrupt, UnsupportedAlgorithm}`.

### 5.5 Trust store asset + `caconv`

Binary asset format (pinned; little-endian; one file, e.g. `ca_store.bin`):

```
offset 0 : magic "Z98CA100" (8 bytes ASCII)
offset 8 : u32 anchor_count
offset 12: u32 file_total_len (self-check)
offset 16: anchor_count entries, each:
           u16 subject_der_len, u16 spki_der_len, u32 not_before, u32 not_after,
           subject_der bytes, spki_der bytes
```

`caconv` (Z98 program, `examples/z98/demo/tls_demo/caconv/`):
`caconv <cacert.pem> <ca_store.bin>` — decodes PEM via `std_base64`, parses each
certificate with `std_x509`, writes the format above in PEM file order. Deterministic
output; prints `wrote N anchors`. Docs carry the refresh recipe (download current
`cacert.pem` from curl.se, re-run caconv, note snapshot date). `trustStoreLoad`
streams entry-by-entry; raw DER is discarded after extraction (anchors hold only
subject + SPKI + validity), keeping resident cost ~30 KB for ~150 anchors.

### 5.6 `std_tls` (sans-I/O)

```zig
pub const TlsAction = union(enum) { send: []const u8, recv: usize, wait: u32, established: void, closed: void };
pub const TlsConfig = struct { hostname: []const u8, store: *TrustStore,
    rng: *std_rand.Xoshiro256, now_unix: i64, min_version: u16, max_version: u16 };
pub const TlsSession = struct { ...fixed-size state... };       // caller-allocated
pub fn tlsInit(sess: *TlsSession, cfg: *TlsConfig) void
pub fn tlsStep(sess: *TlsSession, input: []const u8, output: []u8) !TlsAction
pub fn tlsRead(sess: *TlsSession, out: []u8) !usize             // app data, post-handshake
pub fn tlsWrite(sess: *TlsSession, data: []const u8, output: []u8) !usize  // returns bytes in output
```

`now_unix` is the wall clock at session start (seconds since epoch); cert validity is
checked against it (R6: the driver supplies time — `std_time`-derived in the demos,
config `clock_override_unix` for dead-RTC Win9x machines; with no valid clock and no
override the demo fails cleanly `cert: time`).

Record layer: 5-byte header, `TLS_MAX_RECORD = 16384`, AEAD per suite
(`TLS_ECDHE_{ECDSA,RSA}_WITH_{AES_128_GCM_SHA256, CHACHA20_POLY1305_SHA256}`),
explicit-nonce/seq handling per RFC 5288/7905; buffer `memmove` is acceptable (the
circular-buffer optimization is a later concern).

TLS 1.2 handshake: the blueprint's explicit state machine
(`SendClientHello … Established`); ECDHE with **secp256r1 + x25519** groups (P-256
mandatory, x25519 offered); SNI required; transcript hash = existing `std_crypto`
SHA-256 fed every handshake message; `Finished` = PRF_SHA256 12-byte verify_data.
ServerKeyExchange signature checked (ECDSA or RSA per cert). `ECDHE-RSA` suites are
in scope despite the blueprint's minimal table — real internet (google) uses both.

TLS 1.3 (milestone 5): X25519 group, suites `TLS_AES_128_GCM_SHA256` +
`TLS_CHACHA20_POLY1305_SHA256`; HKDF-Expand-Label key schedule; EncryptedExtensions /
Certificate / CertificateVerify / Finished; no PSK, no 0-RTT, no HRR (group mismatch
= `error.UnsupportedGroup`). RSA-cert servers authenticate with **RSA-PSS**
(RFC 8446 §4.4.3 — PKCS#1 v1.5 is forbidden in CertificateVerify; the §5.1
`rsaVerifyPss` + MGF1 primitive serves this). Reference structure: picotls.

### 5.7 `std_wireguard` (sans-I/O, initiator)

```zig
pub const WgPeer = struct { static_priv: [32]u8, remote_static_pub: [32]u8,
    endpoint_ip: u32, endpoint_port: u16, allowed_ips: [N]...,
    rx_key: [32]u8, tx_key: [32]u8, ...timers, replay window, cookie... };
pub const WgDevice = struct { iface_priv: [32]u8, iface_pub: [32]u8, peers: []WgPeer, ... };
pub fn wgInit(dev: *WgDevice, iface_priv: *const [32]u8) void
pub fn wgAddPeer(dev: *WgDevice, peer: *WgPeer) !void
pub const WgAction = union(enum) { none, send_handshake: usize,
    send_keepalive: usize, session_up: void, inner_packet: usize, dropped_replay: void };
pub fn wgTick(dev: *WgDevice, now_ms: u64, wall_unix_ns: u64, out: []u8) !WgAction
pub fn wgReceive(dev: *WgDevice, now_ms: u64, udp_payload: []const u8, out: []u8) !WgAction
pub fn wgSend(dev: *WgDevice, now_ms: u64, wall_unix_ns: u64, inner_ip: []const u8,
    out: []u8) !usize          // transport data; requires a live session, else error.NoSession; wgTick owns handshake initiation
```

`wall_unix_ns` (Unix time in nanoseconds; second-resolution callers pass `sec * 1e9`)
feeds the TAI64N timestamp in handshake initiations. **Never derive it from `now_ms`**:
a monotonic-derived TAI64N makes the kernel far side reject later initiations as
replays after a client restart (silent interop failure). The two time bases are
distinct: `now_ms` = monotonic for timers, `wall_unix_ns` = wall clock for the wire.

NoiseIK initiator per the blueprint (§2.3 of `projects_phase1.txt`): handshake
initiation/response construction, KDF = HKDF-BLAKE2s (WireGuard paper §5.4), AEAD =
ChaCha20-Poly1305. Timers: `REKEY_AFTER_TIME 120 s`, `REJECT_AFTER_TIME 180 s`,
`REKEY_TIMEOUT 5 s + jitter`, `KEEPALIVE_TIMEOUT 10 s` — driven by `wgTick` polls
(never `sleep`). Cookie reply consumption (mac2 = keyed BLAKE2s-128) required;
generation not required. Transport counters with sliding replay window (2048-bit).
Rekey continuity: while a session is live, a new initiation is prepared as pending
state (local index, ephemeral key, hash, chaining key) without disturbing the active
tx/rx keys, session indices, counters, or replay window; `wgSend` keeps using the
active session. A successful response installs the pending session atomically and
returns `session_up`; the previous session remains usable until that point.
All wire integers little-endian via explicit load/store helpers. Reference:
`wireguard-lwip` (malloc-free C). Errors: `error.{Corrupt, AuthenticationFailed,
NoSession, SessionExpired, OutputTooSmall}`.

### 5.8 `std_tcpip` (userspace stack; client-only)

```zig
pub const TcpipConfig = struct { ip: u32, netmask: u32, gateway: u32, mtu: u16,   // default 1400
    dns_server: u32, max_sockets: u32 };
pub const TcpipStack = struct { ... };        // arena-allocated at init
pub fn tcpipInit(arena: *std_arena.Arena, cfg: *TcpipConfig) !*TcpipStack
pub const TcpipAction = union(enum) { send_pkt: []const u8, wait: u32,
    connected: u32, data: u32, closed: u32, failed: u32, done: void };
pub fn tcpipPoll(s: *TcpipStack, now_ms: u64, rx_ip: ?[]const u8, out: []u8) !TcpipAction
pub fn tcpConnect(s: *TcpipStack, dst_ip: u32, dst_port: u16) !u32   // returns sock id
pub fn tcpSend(s: *TcpipStack, sock: u32, data: []const u8) !usize
pub fn tcpRecv(s: *TcpipStack, sock: u32, out: []u8) !usize
pub fn tcpClose(s: *TcpipStack, sock: u32) !void
pub fn udpOpen(s: *TcpipStack, local_port: u16) !u32
pub fn udpSendTo(s: *TcpipStack, sock: u32, ip: u32, port: u16, data: []const u8) !void
pub fn udpRecvFrom(s: *TcpipStack, sock: u32, out: []u8, ip: *u32, port: *u16) !usize
pub fn dnsResolve(s: *TcpipStack, name: []const u8, out_ip: *u32) !void   // A records
pub fn icmpPing(s: *TcpipStack, ip: u32, now_ms: u64) !u32                // echo, RTT ms
```

IPv4 only. TCP client only (no listen/accept): 3-way handshake, seq/ack, fixed 8 KB
receive window, retransmit with Karn's algorithm (simplified RTO), minimal Reno
(slow start + AIMD; no SACK, no window scaling — window < 64 KB). MSS 1400, never
fragment, inbound fragments dropped. DNS = UDP A-record query with timeout/retry to
`cfg.dns_server`. ICMP = echo request/reply client. The stack emits/receives raw IPv4
datagrams through `tcpipPoll` — the WireGuard layer encrypts those datagrams in the
demo. `tickMs`/`highRes` values come from the driver.

### 5.9 `std_http` transport pluggability

Existing `get(arena, url, timeout_ms)` stays for plain HTTP. Add a transport vtable
(house fn-ptr pattern, no generics):

```zig
pub const HttpTransport = struct { state: *void,
    read_fn: fn (*void, []u8) !usize, write_fn: fn (*void, []const u8) !usize,
    close_fn: fn (*void) void };
pub fn httpGetOver(arena: *std_arena.Arena, t: *HttpTransport, url: []const u8,
    out: *Response) !void     // GET, HTTP/1.1, identity + chunked decode
```

`tls_demo` builds a transport wrapping `std_net` TCP + `std_tls`; the future git
client and HTTPS-through-tunnel reuse the same call. Response body cap is caller-set
(demo streams to a fixed 64 KB buffer or prints as it reads).

## 6. Demos

Both live under `examples/z98/demo/<name>/` with heavy `README.md` (build recipes
for Linux + Win9x (`-fsafe -osw`), config, what to expect, troubleshooting, Win95
install note, resource expectations) and a `NOTES.md` log.

- **`tls_demo`**: `caconv` + `ca_store.bin` asset; `main.zig` fetches the URL (default
  `https://www.google.com/`), prints status line + body (first 4 KB), then a resource
  line `tls_demo ok status=200 bytes=N arena_peak=N rss_peak=N cpu_ms=N`. Failures
  exit non-zero with a precise reason (`cert: HostnameMismatch` etc.). Config (optional
  args/file): URL, store path, `clock_override_unix` for dead-RTC Win9x machines
  (documented; without it, a nonsensical system clock fails cleanly `cert: time`).
- **`wireguard_demo`**: `wg.conf` (hex/base64 keys, endpoint host:port, allowed IPs,
  tunnel local IP, DNS server); drives `std_tcpip` + `std_wireguard` over a
  `std_net` UDP socket; connects TCP to the mud server's tunnel IP, prints the banner,
  sends one command line, prints the reply, quits with the same resource line. The
  far side is a Linux kernel WireGuard server (`wg-quick`) with `mud_server` bound on
  the tunnel network.

## 7. Testing & gates

Per-milestone gates (same discipline as the std-algorithms program):

1. Gate policy (hybrid, Amendment 1): per-task runs use targeted fixtures for the
   touched module and direct consumers, `run_crosscheck.sh` for affected modules,
   and 3× determinism. Full `verify_stdlib.sh` + full `run_crosscheck.sh` is
   mandatory at every milestone closeout and immediately after any change to an
   existing module's functions, shared harness/`expected_dirs.txt`, `std.zig`, or a
   cross-module contract; new independent modules use targeted-only until closeout.
   This is the std harness only: compiler corpus/goldens/examples/pins/markers are
   not run unless compiler source changes.
   Vectors follow `.in`/`.expected`; C89 `ref/` implementations for crypto where a
   portable reference exists — vendored per the LZ4 precedent with BSD attribution.
2. Module tests carry RFC/NIST vectors as fixtures; state-machine tests use canned
   recorded transcripts (e.g. openssl s_server capture) byte-compared.
3. Integration tiers: `tier_tls.sh` (local `openssl s_server` with a test cert +
   internet smoke against google.com/example.com, `Z98_NET=1` gate for the networked
   part), `tier_wireguard.sh` (Linux `wg-quick` netns far side + mud_server through
   the tunnel; skip loud if tools absent — no silent skip), Wine tier for `-osw`.
4. RAM: `/usr/bin/time -v` peak RSS + `ulimit -v 32768` (KB) hard line for demo
   runs; compiler peak RSS for the pre-flight recorded in README/QUICK_REF.
5. Seed rotation at milestone closeout (archive + manifest; fixed point unchanged).
6. `run.err` untouched; no push; commits follow `feat(std_xxx): … (Phase1 M#)` /
   `example(z9play-style)` / `docs(sdd): … report` conventions.

## 8. Milestones (one plan each)

1. **M1 — Pre-flight RSS truth-up** (small): measure compiler peak RSS/arena on the
   standard workload; README + QUICK_REF get the numbers and the measurement recipe;
   demo RAM budget stated. *Output: docs only.*
2. **M2 — Crypto core**: `std_crypto` additions (HMAC-SHA256/HKDF/BLAKE2s,
   SHA-384/SHA-512, RSA PKCS#1 v1.5 + PSS verify over a new generic modexp),
   `std_cipher`, `std_ecc` (X25519, P-256, P-384 ECDSA verify); RFC/NIST vectors +
   crosscheck refs. *Output: three std modules, all fixtures green.*
3. **M3 — X.509 + trust store + converter**: `std_asn1`, `std_x509`, store format +
   `trustStoreLoad`, `caconv` tool, first `ca_store.bin` asset + refresh docs.
   *Output: validation engine + tool + asset.*
4. **M4 — TLS 1.2 + HTTPS demo**: `std_tls` record layer + TLS 1.2 handshake,
   `std_http` transport vtable, `tls_demo`, `tier_tls.sh` (local + internet smoke),
   CA store shipped in the demo. *Output: real HTTPS fetch on Linux and (Wine/`-osw`)
   Win9x build.*
5. **M5 — TLS 1.3**: X25519 + HKDF-Expand-Label key schedule, EncryptedExtensions/
   CertificateVerify/Finished path (RSA-cert auth via RSA-PSS, RFC 8446 §4.4.3);
   suites AES-128-GCM + ChaCha20-Poly1305. *Output: TLS 1.3 clients interop with
   real servers, including RSA-cert ones.*
6. **M6 — WireGuard protocol**: `std_wireguard` NoiseIK initiator + transport +
   timers + cookie consumption; protocol tests vs canned exchanges; build fixtures.
   *Output: handshake/transport proven against the wireguard-lwip reference.*
7. **M7 — TCP/IP stack + wireguard_demo + closeout**: `std_tcpip` (IPv4/TCP/UDP/DNS/
   ICMP), `wireguard_demo`, `tier_wireguard.sh`, docs truth-ups, seed rotation,
   closeout ledger. *Output: mud banner through a real WireGuard tunnel.* (If size
   demands, this splits into 7a stack / 7b demo+closeout — controller call, ledgered.)

Deferred beyond Phase 1: TLS session resumption, RSA key exchange, HTTP redirects/
gzip, inner-stack TCP server role, WireGuard responder, IPv6, OCSP/CRL, and the
`std_tcpip` optimizations (circular buffers, SACK, PMTU discovery).

## 9. Risks & mitigations

- **x87 double-rounding on PII/PIII** (known defect class — lexer f64 work): all
  crypto is integer/limb arithmetic; only final conversions touch f64; no `f64`
  intermediates in ECC. Fixture-pin the edge values.
- **Const-table RAM** (AES T-tables): 4 KB is `const`/rodata, never arena.
- **Compiler arena growth compiling big const arrays**: M1 establishes the RSS
  baseline; every milestone records compiler RSS deltas; if a milestone exceeds the
  ceiling, STOP-present with the measurement.
- **Real-server interop drift** (google's cipher preference, cert chain shapes):
  `tier_tls` pins behavior against both google.com and example.com, and the local
  s_server fixture keeps failures diagnosable offline.
- **Win9x quirks** (Winsock 2 add-on on 95, no TUN): docs carry the install note;
  the userspace stack is the design answer to TUN; Wine tier keeps `-osw` honest;
  hardware runs remain operator-owned.
- **Self-containment drift**: caconv is Z98; the only host tools are for *testing*
  (openssl, wg, lz4-style refs). No shipped code path depends on them.

## 10. Decisions log (operator rulings, binding)

1. TLS first against the open internet; WireGuard second as the privacy layer
   ("undisclosed internet" for a Win9x box).
2. TLS must be **browser-grade**: full X.509 chain validation + hostname checks;
   BearSSL is the structural reference; the library is a foundation for later
   projects (git client), not a demo.
3. Trust store: shipped asset + **Z98 converter** + refresh instructions ("to be
   era-alike it has to be self-contained"); no host-side tooling in the path.
4. Win98/ME: TCP/IP exists (verified) — the gap is TUN, hence `std_tcpip` in std.
   Win95: install note. IPv6: skipped, era-correct.
5. Inner stack is std and does DNS/UDP too ("you imagine it, you have it").
6. HTTPS fetch is a std capability (`std_http` over `std_tls`) — "std will have a
   super upgrade basically".
7. Demos: `examples/z98/demo/tls_demo` + `wireguard_demo`, heavily documented;
   mud_server through the tunnel is the WireGuard proof at every rung (kernel
   WireGuard far side; Wine tier; manual rung = any real endpoint via config).
8. RAM: compiler <16 MB the goal (tracked, slightly over today); demos 16 MB
   target / 32 MB hard ceiling; measured even on Linux.
9. Seven milestones, one plan per milestone.
10. Builder-check ruling (a): SHA-384/SHA-512 + P-384 ECDSA verify + RSA
    PKCS#1 v1.5/PSS verification join the crypto core (M2/M3 grow). Verified live
    2026-10-21: both demo targets chain through `ecdsa-with-SHA384`
    (www.google.com: WE2 signed by GTS Root R4 = secp384r1; example.com: two
    SHA-384 links to its ECC root).
11. Builder-check ruling (a): wall time enters explicitly — `now_unix: i64` on
    `TlsConfig`, `wall_unix_ns: u64` on the WireGuard handshake entry points
    (`wgTick`/`wgSend`); never derived from `now_ms` (TAI64N replay trap). Demo
    policy: `clock_override_unix` config for dead-RTC Win9x machines, clean
    `cert: time` failure otherwise.
12. Builder-check ruling (a): TLS 1.3 RSA-cert authentication uses RSA-PSS
    (RFC 8446 §4.4.3) in M5 — PKCS#1 v1.5 is forbidden there by the RFC.

## 11. What's left to the builder

Exact struct layouts, buffer sizes within the pinned maxima, the `ref/` porting
strategy per primitive, fixture naming, tier scripting details, and the TLS 1.3
message-construction details are implementation choices. The contracts in §5 and the
test/gate policy in §7 bind every task; anything that would change them is a
STOP-present back to the operator.
