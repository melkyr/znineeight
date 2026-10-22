# TLS 1.2/1.3 — `std_tls`

| | |
|---|---|
| **Modules** | `std_tls` |
| **Layers** | `L5` — sans-I/O TLS 1.2/1.3 record layer and client handshakes |
| **Import (by path)** | `const std_tls = @import("std_tls.zig");` |
| **Consumes** | `std_cipher` (AES-128-GCM, ChaCha20-Poly1305), `std_crypto` (SHA-256/384, HMAC, HKDF, RSA PKCS#1 v1.5/PSS verify), `std_ecc` (P-256, P-384, X25519, ECDSA verify), `std_rand` (client randomness), `std_asn1`/`std_x509` (certificate parsing and chain verification) |

`std_tls` is not re-exported through `std`; import it by path.

## Module overview

`std_tls` implements the client half of TLS 1.2 and TLS 1.3 from the specification in
`docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.6. It is
**sans-I/O**: there are no sockets, no clock reads, no environment reads, and no
hidden heap. The caller owns the socket and the clock, allocates the fixed-size
`TlsSession`, supplies a seeded `std_rand.Xoshiro256`, and drives the state
machine with `tlsStep`.

The module has two layers:

- **Record layer.** A 5-byte TLS record header is encoded/parsed with a
  **`TLS_MAX_PLAINTEXT_RECORD = 16384`** cap. The six supported suites protect
  records with an AEAD (`AES-128-GCM` or `ChaCha20-Poly1305`). For TLS 1.2 the
  wire layout follows RFC 5288 for AES-GCM (8-byte explicit nonce transmitted in
  the record) and RFC 7905 for ChaCha20-Poly1305 (no explicit nonce; the record
  sequence number is XORed into the fixed IV); the AAD is
  `seq_num || type || version || plaintext_length` (13 bytes). For TLS 1.3 the
  outer content type is always `application_data`, the nonce is
  `static_iv XOR seq_be64`, the AAD is the 5-byte TLSCiphertext header, and the
  AEAD plaintext is the content followed by the real inner content type.
- **Handshake.** The explicit state machine is
  `SendClientHello … Established`. It sends SNI and offers the two TLS 1.3
  suites (+ the four TLS 1.2 suites when the configured range permits 1.2),
  verifies the server certificate chain through
  `std_x509.x509VerifyChain` against the caller's trust store, checks the
  server authentication signature, and verifies `Finished`. TLS 1.2 uses ECDHE
  with `secp256r1`/`x25519`, a ServerKeyExchange signature (ECDSA, RSA PKCS#1
  v1.5, or RSA-PSS), `PRF_SHA256`, and a 12-byte Finished. TLS 1.3 uses an
  x25519 key_share, the HKDF-Expand-Label SHA-256 schedule, CertificateVerify
  (ECDSA P-256/P-384 or RSA-PSS), and a 32-byte Finished. The transcript is
  SHA-256 over every handshake message exactly once; record headers are
  excluded.

**Time policy.** `std_tls` never reads a clock. The caller supplies
`TlsConfig.now_unix` (seconds since the Unix epoch) at session start; it is
passed unchanged to `x509VerifyChain` for every certificate in the path.
Consequently a stale/wrong clock surfaces as `error.CertificateExpired` or
`error.CertificateNotYetValid`, not as a TLS-specific error. The demo driver
(`examples/z98/demo/tls_demo`) uses `std.time.wallClockUnix()` and accepts an
optional `clock_override_unix` for Win9x machines with a dead RTC; when the
system clock is outside 2000-01-01 … 2100-01-01 and no override is supplied it
fails cleanly as `cert: time`.

**Determinism and ownership.** All state lives in the caller's `TlsSession`
(124400 bytes, about 121.5 KiB, including the 64 KiB handshake reassembly
buffer, 32 KiB application buffer, 8 KiB pending output buffer, and 16 KiB
record reader). There is no allocation and no arena parameter. Client
randomness comes only from the caller's RNG, so the same initial RNG state and
the same server flight produce the same client flight.

**Scope.** Exactly six suites (four TLS 1.2, two TLS 1.3), x25519 for TLS 1.3
(plus `secp256r1` for TLS 1.2 ECDHE), SNI required, no renegotiation, no
session resumption/PSK, no 0-RTT, no HelloRetryRequest, no client certificates,
and no TLS 1.3 key update. A clean `close_notify` alert yields
`error.Closed`/`.closed`; a post-handshake TLS 1.3 `KeyUpdate` also yields
`error.Closed` because rekeying is not implemented; all other alerts fail the
handshake. Every pre-`Established` failure path fails closed.

## TLS 1.3

TLS 1.3 is enabled when `TlsConfig.max_version >= TLS_VERSION_13`; setting
`min_version = max_version = TLS_VERSION_13` makes the client 1.3-only, while
the default demo range (`min=1.2`, `max=1.3`) offers both versions and falls
back to TLS 1.2 when the server selects it. The ClientHello offers
`TLS_AES_128_GCM_SHA256` (`0x1301`) and `TLS_CHACHA20_POLY1305_SHA256`
(`0x1303`) in that order, plus a single x25519 `key_share` and the
`supported_versions` extension. There is no PSK/resumption, 0-RTT, or
HelloRetryRequest; a server selecting a non-x25519 key_share fails with
`error.UnsupportedGroup`, and a TLS 1.2 ServerHello carrying the RFC 8446
`DOWNGRD\x01` sentinel fails with `error.HandshakeFailed`.

**Key schedule.** The no-PSK schedule uses the M2 HKDF primitives with SHA-256:
`HKDF-Extract(0,0)` → early secret, `"derived"` → handshake secret, then the
handshake/application traffic secrets via HKDF-Expand-Label. Sequence numbers
reset at each key epoch. The server `EncryptedExtensions`/`Certificate`/
`CertificateVerify`/`Finished` flight and middlebox-compatibility CCS are
handled; `Finished` uses the 32-byte TLS 1.3 `finished_key`.

**Server authentication.** The certificate chain and hostname are validated
unchanged by `std_x509` (SAN dNSName, caller `now_unix`). CertificateVerify
accepts ECDSA P-256/SHA-256 (`0x0403`), ECDSA P-384/SHA-384 (`0x0503`), and
RSA-PSS `rsa_pss_rsae_sha256`/`rsa_pss_rsae_sha384` (`0x0804`/`0x0805`).
PKCS#1 v1.5 schemes are rejected with `error.HandshakeFailed` per RFC 8446
§4.4.3; other schemes fail with `error.UnsupportedAlgorithm`.

**KeyUpdate stance.** Sending is not implemented. Receiving a post-handshake
`KeyUpdate` closes the session (`error.Closed`); `NewSessionTicket` messages are
ignored (no resumption). Application writes still use the inner content type
rule, so each protected record carries one extra plaintext byte.

## Quick start

```zig
const std = @import("std");
const tls = @import("std_tls.zig");
const x509 = @import("std_x509.zig");
const rand = @import("std_rand.zig");

var session: tls.TlsSession = undefined;
var rng = rand.xoshiroInit(1234);
var store: x509.TrustStore = undefined;
// ... load the trust store into `store` ...

var cfg = tls.TlsConfig{
    .hostname = "example.com",
    .store = &store,
    .rng = &rng,
    .now_unix = 1760000000,
    .min_version = tls.TLS_VERSION_12,
    .max_version = tls.TLS_VERSION_13,
};
tls.tlsInit(&session, &cfg);

var out: [16384]u8 = undefined;
while (true) {
    const action = tls.tlsStep(&session, &.{}, out[0..]) catch |err| {
        switch (err) {
            error.CertificateExpired => std.io.write("cert: expired\n"),
            error.HostnameMismatch => std.io.write("cert: hostname\n"),
            else => std.io.write("tls: failed\n"),
        }
        return;
    };
    switch (action) {
        .send => |bytes| {
            // write `bytes` to the socket, then feed the reply back in
            _ = bytes;
        },
        .recv => {
            // read some bytes from the socket and pass them to tlsStep
            break;
        },
        .established => break,
        .closed => return,
        .wait => {},
    }
}
```

The real driver loop passes each socket read into `tlsStep(sess, input, out)`,
writes every `.send` slice, and calls `tlsRead` for application bytes.

## API

### `TLS_MAX_PLAINTEXT_RECORD`

**Purpose** — maximum plaintext fragment in one record.

**Signature** — `pub const TLS_MAX_PLAINTEXT_RECORD: usize = 16384;`

**Gotchas** — this is the 2^14 TLS plaintext cap. `protectRecord`,
`protectRecord13`, and `recordAad` reject a larger plaintext with
`error.RecordTooLarge` (TLS 1.3 records add one inner content-type byte).

### `TLS_MAX_RECORD`

**Purpose** — alias used by the handshake path for the same 16 KiB plaintext
limit.

**Signature** — `pub const TLS_MAX_RECORD: usize = TLS_MAX_PLAINTEXT_RECORD;`

### `TLS_MAX_WIRE_RECORD`

**Purpose** — largest protected fragment on the wire.

**Signature** — `pub const TLS_MAX_WIRE_RECORD: usize = TLS_MAX_PLAINTEXT_RECORD + 8 + 16;`

**Gotchas** — `16384 + 8 + 16 = 16408` covers AES-GCM's explicit nonce plus tag
and ChaCha20-Poly1305's tag. `parseRecordHeader` rejects a larger declared
length with `error.RecordTooLarge`.

### `RECORD_HEADER_LEN`

**Purpose** — TLS record header size.

**Signature** — `pub const RECORD_HEADER_LEN: usize = 5;`

### `TLS_VERSION_12`

**Purpose** — TLS 1.2 protocol version (`0x0303`).

**Signature** — `pub const TLS_VERSION_12: u16 = 0x0303;`

### `TLS_VERSION_13`

**Purpose** — TLS 1.3 protocol version (`0x0304`).

**Signature** — `pub const TLS_VERSION_13: u16 = 0x0304;`

### Content-type constants

**Purpose** — record content types used by the record layer and handshake.

**Signatures**
```zig
pub const content_change_cipher_spec: u8 = 20;
pub const content_alert: u8 = 21;
pub const content_handshake: u8 = 22;
pub const content_application_data: u8 = 23;
```

### `CipherSuite`

**Purpose** — the four TLS 1.2 suites and two TLS 1.3 suites supported by the
client.

**Signature** — `pub const CipherSuite = enum { ecdsa_aes_128_gcm_sha256, rsa_aes_128_gcm_sha256, ecdsa_chacha20_poly1305_sha256, rsa_chacha20_poly1305_sha256, tls13_aes_128_gcm_sha256, tls13_chacha20_poly1305_sha256 };`

| Enum value | IANA name | Wire ID | Server-auth signature | AEAD | Key | Fixed IV | Nonce on the wire |
|---|---|---|---|---|---|---|---|
| `ecdsa_aes_128_gcm_sha256` | `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` | `0xC02B` | ECDSA P-256 / SHA-256 | AES-128-GCM | 16 | 4 | `fixed_iv[4] \|\| seq_be64` (8 explicit bytes) |
| `rsa_aes_128_gcm_sha256` | `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256` | `0xC02F` | RSA PKCS#1 v1.5 / SHA-256 | AES-128-GCM | 16 | 4 | `fixed_iv[4] \|\| seq_be64` (8 explicit bytes) |
| `ecdsa_chacha20_poly1305_sha256` | `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256` | `0xCCA9` | ECDSA P-256 / SHA-256 | ChaCha20-Poly1305 | 32 | 12 | none; nonce = `(0^4 \|\| seq_be64) XOR fixed_iv` |
| `rsa_chacha20_poly1305_sha256` | `TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256` | `0xCCA8` | RSA PKCS#1 v1.5 / SHA-256 | ChaCha20-Poly1305 | 32 | 12 | none; nonce = `(0^4 \|\| seq_be64) XOR fixed_iv` |
| `tls13_aes_128_gcm_sha256` | `TLS_AES_128_GCM_SHA256` | `0x1301` | CertificateVerify: ECDSA P-256/P-384 or RSA-PSS | AES-128-GCM | 16 | 12 | none; nonce = `static_iv XOR seq_be64` |
| `tls13_chacha20_poly1305_sha256` | `TLS_CHACHA20_POLY1305_SHA256` | `0x1303` | CertificateVerify: ECDSA P-256/P-384 or RSA-PSS | ChaCha20-Poly1305 | 32 | 12 | none; nonce = `static_iv XOR seq_be64` |

**Gotchas** — the TLS 1.3 ClientHello offers `0x1301` then `0x1303` (followed
by the four TLS 1.2 suites when 1.2 is enabled). A ServerHello selecting
anything else fails with `error.UnsupportedSuite`. For TLS 1.2 the
server-certificate key type must match the suite's authentication family; a
mismatch fails with `error.UnsupportedAlgorithm`. TLS 1.3 suite selection is
independent of the certificate key type; CertificateVerify picks the auth
scheme.

### `suiteIsAesGcm`

**Purpose** — classifies a suite's AEAD family.

**Signature** — `pub fn suiteIsAesGcm(suite: CipherSuite) bool`

**Returns** — `true` for the three AES-128-GCM suites, `false` for the three
ChaCha20-Poly1305 suites.

### `suiteIsTls13`

**Purpose** — classifies a suite as TLS 1.3.

**Signature** — `pub fn suiteIsTls13(suite: CipherSuite) bool`

**Returns** — `true` for `tls13_aes_128_gcm_sha256` and
`tls13_chacha20_poly1305_sha256`, `false` for the four TLS 1.2 suites.

### `suiteKeyLen`

**Purpose** — AEAD key length for a suite.

**Signature** — `pub fn suiteKeyLen(suite: CipherSuite) usize`

**Returns** — `16` for AES-128-GCM, `32` for ChaCha20-Poly1305.

### `suiteFixedIvLen`

**Purpose** — fixed-IV (salt) length for a suite.

**Signature** — `pub fn suiteFixedIvLen(suite: CipherSuite) usize`

**Returns** — `4` for the TLS 1.2 AES-128-GCM suites (RFC 5288 explicit-nonce
construction), `12` for ChaCha20-Poly1305 and both TLS 1.3 suites.

### `RecordError`

**Purpose** — record-layer error set.

**Signature** — `pub const RecordError = error{ Corrupt, AuthenticationFailed, RecordTooLarge, Closed };`

| Error | Meaning |
|---|---|
| `Corrupt` | malformed/truncated header, bad key/nonce/output length, or an unrepresentable argument. |
| `AuthenticationFailed` | AEAD tag mismatch (tampered ciphertext, wrong sequence number, or wrong key/IV). |
| `RecordTooLarge` | plaintext beyond 16384, wire fragment beyond 16408, a declared length beyond the cap, or reader-buffer overflow. |
| `Closed` | `readerNext` read exactly at a record boundary after `readerMarkClosed`. |

### `RecordHeader`

**Purpose** — parsed 5-byte TLS record header.

**Signature** — `pub const RecordHeader = struct { content_type: u8, version: u16, length: u16 };`

**Gotchas** — `length` is the protected-fragment length, not including the
5-byte header.

### `encodeRecord`

**Purpose** — writes a 5-byte header followed by `payload`.

**Signature** — `pub fn encodeRecord(content_type: u8, version: u16, payload: []const u8, out: []u8) RecordError!usize`

**Parameters** — `content_type` and `version` are written verbatim; `payload` is
the fragment; `out` is the destination.

**Returns** — total bytes written (`5 + payload.len`).

**Errors** — `error.RecordTooLarge` when `payload.len > TLS_MAX_WIRE_RECORD`;
`error.Corrupt` when `out` is shorter than the total.

**Gotchas** — this function only frames bytes. Use `protectRecord` first when
cipher protection is active. Overlapping `out`/`payload` is not supported.

### `parseRecordHeader`

**Purpose** — parses the first 5 bytes of a record.

**Signature** — `pub fn parseRecordHeader(raw: []const u8) RecordError!RecordHeader`

**Returns** — the header fields; only `raw[0..5]` is read.

**Errors** — `error.Corrupt` when fewer than 5 bytes are available;
`error.RecordTooLarge` when the declared fragment length exceeds
`TLS_MAX_WIRE_RECORD`.

**Gotchas** — it does not check that the full fragment is present. Use
`decodeRecord` or `RecordReader` for that.

### `decodeRecord`

**Purpose** — parses a header and returns the fragment.

**Signature** — `pub fn decodeRecord(raw: []const u8, header: *RecordHeader, fragment: *[]const u8) RecordError!void`

**Returns** — fills `header.*` and points `fragment.*` at
`raw[5 .. 5+length]`.

**Errors** — the `parseRecordHeader` errors, plus `error.Corrupt` when `raw` is
shorter than the declared header+fragment length.

**Gotchas** — `fragment` aliases `raw`; it stays valid only while `raw` does.
It does not decrypt.

### `RecordReader`

**Purpose** — incremental record input buffer with compaction.

**Signature** — `pub const RecordReader = struct { buf: [TLS_MAX_WIRE_RECORD + RECORD_HEADER_LEN]u8, start: usize, len: usize, closed: bool };`

**Gotchas** — treat `buf`/`start`/`len`/`closed` as opaque; use the reader
functions. The buffer is 16413 bytes. Returned fragments alias `buf` and remain
valid only until the next `readerAppend`.

### `readerInit`

**Purpose** — resets a reader to empty/open.

**Signature** — `pub fn readerInit(r: *RecordReader) void`

### `readerBuffered`

**Purpose** — number of unconsumed bytes currently buffered.

**Signature** — `pub fn readerBuffered(r: *const RecordReader) usize`

### `readerAppend`

**Purpose** — compacts consumed bytes with `memmove`-style copying, then appends
new input.

**Signature** — `pub fn readerAppend(r: *RecordReader, data: []const u8) RecordError!void`

**Errors** — `error.RecordTooLarge` when the remaining bytes plus `data.len`
exceed the 16413-byte buffer.

**Gotchas** — a single append can be at most the buffer capacity minus the
currently buffered bytes. `tlsStep` feeds large input in chunks so this is not
normally visible.

### `readerMarkClosed`

**Purpose** — marks the input stream as closed so truncation is detectable.

**Signature** — `pub fn readerMarkClosed(r: *RecordReader) void`

### `readerNext`

**Purpose** — returns the next complete record, if available.

**Signature** — `pub fn readerNext(r: *RecordReader, header: *RecordHeader, fragment: *[]const u8) RecordError!bool`

**Returns** — `true` with `header`/`fragment` set when a complete record is
buffered; `false` when more input is needed. On `true`, the reader advances past
the record.

**Errors** — `error.RecordTooLarge` for a declared length beyond the cap;
`error.Corrupt` when the stream is marked closed mid-header or mid-fragment;
`error.Closed` when the stream is marked closed exactly at a record boundary.

**Gotchas** — the returned fragment aliases the reader buffer and is valid
until the next append.

### `recordAad`

**Purpose** — builds TLS 1.2 AEAD additional data.

**Signature** — `pub fn recordAad(seq: u64, content_type: u8, version: u16, plaintext_len: usize, out: *[13]u8) RecordError!void`

**Returns** — `out = seq_be64 || content_type || version_be16 || plaintext_len_be16`.

**Errors** — `error.RecordTooLarge` when `plaintext_len > 16384`.

### `recordNonce`

**Purpose** — derives the 12-byte AEAD nonce for a suite and sequence number.

**Signature** — `pub fn recordNonce(suite: CipherSuite, fixed_iv: []const u8, seq: u64, out: *[12]u8) RecordError!void`

**Parameters** — `fixed_iv` must be exactly 4 bytes for AES-GCM or 12 bytes for
ChaCha20-Poly1305.

**Returns** — AES-GCM: `fixed_iv || seq_be64`; ChaCha20-Poly1305:
`(0^4 || seq_be64) XOR fixed_iv`.

**Errors** — `error.Corrupt` for the wrong fixed-IV length.

**Gotchas** — for AES-GCM this is the nonce used to seal; the last 8 bytes are
also transmitted explicitly in the record.

### `sealFragment`

**Purpose** — raw AEAD seal without record framing (KAT seam).

**Signature** — `pub fn sealFragment(suite: CipherSuite, key: []const u8, nonce: *const [12]u8, ad: []const u8, pt: []const u8, ct: []u8, tag: *[16]u8) RecordError!void`

**Errors** — `error.Corrupt` for the wrong key length or `ct.len != pt.len`.

**Gotchas** — `ad` is not framed; callers must pass the exact AAD. Prefer
`protectRecord` for normal TLS records.

### `openFragment`

**Purpose** — raw AEAD open without record framing (KAT seam).

**Signature** — `pub fn openFragment(suite: CipherSuite, key: []const u8, nonce: *const [12]u8, ad: []const u8, ct: []const u8, tag: *const [16]u8, pt: []u8) RecordError!void`

**Errors** — `error.Corrupt` for the wrong key length or `pt.len != ct.len`;
`error.AuthenticationFailed` for a tag mismatch.

**Gotchas** — authenticate-before-decrypt: `pt` is written only on a tag match.

### `protectRecord`

**Purpose** — encrypts one plaintext fragment into its on-wire AEAD fragment.

**Signature** — `pub fn protectRecord(suite: CipherSuite, key: []const u8, fixed_iv: []const u8, seq: u64, content_type: u8, version: u16, pt: []const u8, out: []u8) RecordError!usize`

**Parameters** — `key` is 16 or 32 bytes; `fixed_iv` is 4 or 12 bytes; `seq` is
the record sequence number; `content_type`/`version` feed the AAD; `pt` is at
most 16384 bytes; `out` holds the protected fragment.

**Returns** — protected fragment length: `8 + pt.len + 16` for AES-GCM,
`pt.len + 16` for ChaCha20-Poly1305.

**Errors** — `error.RecordTooLarge` for an oversized plaintext;
`error.Corrupt` for bad key/IV lengths or a short `out`.

**Gotchas** — AES-GCM writes `seq_be64` as the explicit nonce prefix; the
caller must use the same sequence for `unprotectRecord`. The output does not
include the 5-byte record header.

### `unprotectRecord`

**Purpose** — verifies and decrypts one protected fragment.

**Signature** — `pub fn unprotectRecord(suite: CipherSuite, key: []const u8, fixed_iv: []const u8, seq: u64, content_type: u8, version: u16, record: []const u8, out: []u8) RecordError!usize`

**Returns** — plaintext length in `out`.

**Errors** — `error.Corrupt` for bad key/IV lengths, a too-short record, or a
short `out`; `error.RecordTooLarge` for an oversized wire fragment or
plaintext; `error.AuthenticationFailed` for a tag mismatch.

**Gotchas** — AES-GCM uses the transmitted 8-byte explicit nonce, not the
`seq` argument, for the nonce tail, but still uses `seq` in the AAD. The AAD
length is the decrypted plaintext length, so the caller must pass the same
record content type/version. This is the TLS 1.2 framing function; use
`protectRecord13`/`unprotectRecord13` for TLS 1.3.

### `protectRecord13`

**Purpose** — encrypts one TLS 1.3 record fragment.

**Signature** — `pub fn protectRecord13(suite: CipherSuite, key: []const u8, fixed_iv: []const u8, seq: u64, inner_type: u8, pt: []const u8, out: []u8) RecordError!usize`

**Parameters** — `key` is 16 or 32 bytes; `fixed_iv` must be 12 bytes; `seq`
feeds the nonce; `inner_type` is appended to the plaintext as the real content
type; `pt` is at most 16384 bytes.

**Returns** — `pt.len + 1 + 16` (content + inner type + AEAD tag). The caller
frames the 5-byte outer header with content type `application_data` and version
`0x0303`.

**Errors** — `error.RecordTooLarge` for an oversized plaintext;
`error.Corrupt` for bad key/IV lengths or a short `out`.

**Gotchas** — the nonce is `static_iv XOR seq_be64` and the AAD is the 5-byte
TLSCiphertext header, whose length field is the full protected fragment
(`pt.len + 1 + 16`). There is no explicit nonce on the wire.

### `unprotectRecord13`

**Purpose** — verifies and decrypts one TLS 1.3 protected fragment.

**Signature** — `pub fn unprotectRecord13(suite: CipherSuite, key: []const u8, fixed_iv: []const u8, seq: u64, record: []const u8, out: []u8) RecordError!usize`

**Returns** — plaintext length **including** the trailing inner content type
byte, so `out[ret-1]` is the real content type and `out[0..ret-1]` is the
content.

**Errors** — `error.Corrupt` for bad key/IV lengths, a too-short record, or a
short `out`; `error.RecordTooLarge` for an oversized wire fragment or
plaintext; `error.AuthenticationFailed` for a tag mismatch.

**Gotchas** — the caller must split off the inner type before buffering
application data. The record argument is the protected fragment only (no 5-byte
header).

### `TLS_HANDSHAKE_MAX`

**Purpose** — handshake-message reassembly cap.

**Signature** — `pub const TLS_HANDSHAKE_MAX: usize = 65536;`

**Gotchas** — a Certificate message (or any handshake message) larger than
64 KiB is rejected with `error.RecordTooLarge`. Multi-record fragmentation below
the cap is reassembled.

### `TLS_FINISHED_LEN`

**Purpose** — TLS 1.2 `Finished` verify_data length.

**Signature** — `pub const TLS_FINISHED_LEN: usize = 12;`

**Gotchas** — TLS 1.3 `Finished` is 32 bytes (HMAC with the 32-byte
`finished_key`); that length is internal to the 1.3 path, not this constant.

### `TlsError`

**Purpose** — the module's full handshake/record error set.

**Signature**
```zig
pub const TlsError = error{
    BadAction, AppTooLarge, OutputTooSmall, BadConfig,
    HandshakeFailed, UnsupportedVersion, UnsupportedSuite, UnsupportedGroup,
    CertificateExpired, CertificateNotYetValid, UnknownIssuer, HostnameMismatch,
    BadSignature, ChainTooLong, UnsupportedAlgorithm,
    Corrupt, AuthenticationFailed, RecordTooLarge, Closed,
    WeakPublicKey, InvalidPrivateKey, InvalidPublicKey,
};
```

| Error | Meaning |
|---|---|
| `BadAction` | the caller invoked the state machine in a way that cannot produce an action (reserved; `tlsStep` currently uses the specific errors below). |
| `AppTooLarge` | decrypted application bytes would overflow the 32 KiB session buffer. |
| `OutputTooSmall` | the caller's `output` cannot hold the pending flight or a `tlsWrite` record set. |
| `BadConfig` | empty hostname or hostname longer than 255 bytes. |
| `HandshakeFailed` | wrong message kind/order, bad Finished, a PKCS#1 v1.5 CertificateVerify, non-`close_notify` alert, or use before `Established`. |
| `UnsupportedVersion` | the configured range does not intersect TLS 1.2/1.3, or the peer selected an unsupported version. |
| `UnsupportedSuite` | server selected a suite ID that was not offered. |
| `UnsupportedGroup` | TLS 1.2 ServerKeyExchange used a group other than P-256/X25519, or TLS 1.3 key_share was not x25519. |
| `CertificateExpired` | `x509VerifyChain` found a certificate expired at `now_unix`. |
| `CertificateNotYetValid` | `x509VerifyChain` found a certificate not yet valid at `now_unix`. |
| `UnknownIssuer` | the server chain does not reach the supplied trust store. |
| `HostnameMismatch` | the leaf SAN dNSName does not match `cfg.hostname`. |
| `BadSignature` | certificate/ServerKeyExchange signature or encoding is invalid. |
| `ChainTooLong` | the certificate list exceeds `x509.MAX_CHAIN` certificates. |
| `UnsupportedAlgorithm` | unsupported certificate key/signature algorithm, curve, or RSA exponent encoding. |
| `Corrupt` | malformed records/messages or invalid length fields. |
| `AuthenticationFailed` | AEAD tag mismatch after `Established`. |
| `RecordTooLarge` | record/handshake/reader limit exceeded. |
| `Closed` | clean end of stream (`close_notify` or record-boundary close), or a post-handshake TLS 1.3 `KeyUpdate` (no rekey support). |
| `WeakPublicKey` | the ECDH peer public key is invalid/all-zero. |
| `InvalidPrivateKey` | the locally generated ECDH private key is invalid. |
| `InvalidPublicKey` | the peer ECDH public key is invalid. |

**Gotchas** — certificate errors are propagated from `std_x509` unchanged.
Before `Established`, AEAD failures are folded into `error.HandshakeFailed` so
the handshake cannot be probed; after `Established` they surface as
`error.AuthenticationFailed`. `error.OutOfMemory` and `error.Time` are not in
this set because the module allocates nothing and never reads a clock.

### `TlsAction`

**Purpose** — the driver action returned by `tlsStep`.

**Signature** — `pub const TlsAction = union(enum) { send: []const u8, recv: usize, wait: u32, established: void, closed: void };`

**Fields**
- `send` — bytes to write to the socket. The slice aliases the caller's
  `tlsStep` output buffer and is valid until the next call.
- `recv` — the driver should read and pass in more bytes; the current
  implementation always sets the hint to `1`.
- `wait` — reserved for a future timer-driven driver; `tlsStep` never returns
  it.
- `established` — the handshake is complete and application data may be
  written/read.
- `closed` — the peer sent `close_notify` or the stream closed cleanly.

### `TlsConfig`

**Purpose** — per-session configuration supplied by the driver.

**Signature**
```zig
pub const TlsConfig = struct {
    hostname: []const u8,
    store: *x509.TrustStore,
    rng: *rand.Xoshiro256,
    now_unix: i64,
    min_version: u16,
    max_version: u16,
};
```

**Fields**
- `hostname` — SNI name and the name checked against the leaf SAN; must be
  1–255 bytes.
- `store` — loaded `std_x509.TrustStore`; borrowed for the session lifetime.
- `rng` — caller-owned `std_rand.Xoshiro256` used for `client_random` and the
  ECDHE private key.
- `now_unix` — wall clock in Unix seconds at session start; the only time
  source, passed to certificate validation.
- `min_version` / `max_version` — accepted protocol range, `TLS_VERSION_12`
  (`0x0303`) through `TLS_VERSION_13` (`0x0304`); `min_version <= max_version`
  and the range must include at least one of them. With both enabled the
  client offers 1.3 first and falls back to 1.2 if the server selects it.

### `HandshakeState`

**Purpose** — explicit client state-machine states.

**Signature**
```zig
pub const HandshakeState = enum {
    SendClientHello, RecvServerHello, RecvEncryptedExtensions, RecvCertificate,
    RecvServerKeyExchange, RecvServerHelloDone, SendClientKeyExchange,
    SendChangeCipherSpec, SendFinished, RecvChangeCipherSpec,
    RecvCertificateVerify, RecvFinished, Established, Error,
};
```

**Gotchas** — the enum is public for diagnostics; callers should not write
`sess.state` directly. TLS 1.3 uses `RecvEncryptedExtensions` and
`RecvCertificateVerify`; TLS 1.2 uses the ServerKeyExchange/CCS labels.
`SendClientKeyExchange`/`SendChangeCipherSpec`/`SendFinished` are intermediate
labels used while the client flight is queued; the externally observable
progression is driven by `tlsStep`. The `Error` value is not currently entered
by the implementation (errors are returned directly).

### `TlsSession`

**Purpose** — caller-allocated, fixed-size session state.

**Signature** — `pub const TlsSession = struct { ... fixed-size state ... };`

**Fields** (principal storage)
- `cfg` — copy of the `TlsConfig` values (borrowed slices/pointers).
- `state` — current `HandshakeState`.
- `reader` — `RecordReader` (16413 bytes).
- `hs_buf` / `hs_len` — 65536-byte handshake reassembly buffer and its length.
- `transcript` — streaming SHA-256 of handshake messages.
- `client_random` / `server_random` — 32 bytes each.
- `version` — negotiated `TLS_VERSION_12` or `TLS_VERSION_13`.
- `suite` / `peer_group` / `peer_pub` / `peer_key` — negotiated suite, group,
  peer ECDH public key, and parsed certificate public key (P-256, P-384, or
  RSA).
- `early_secret` / `handshake_secret` / `master_secret` /
  `client_hs_secret` / `server_hs_secret` / `client_app_secret` /
  `server_app_secret` — TLS 1.3 HKDF schedule material.
- `pre_master` / `master` / `client_key` / `server_key` / `client_iv` /
  `server_iv` — TLS 1.2 key schedule material and the active record keys.
- `write_seq` / `read_seq` / `write_cipher` / `read_cipher` — record counters
  and AEAD-active flags (reset per TLS 1.3 key epoch).
- `pending` / `pending_len` — 8192-byte queued output flight.
- `app` / `app_start` / `app_end` — 32768-byte decrypted application buffer.

**Gotchas** — treat every field as private. The struct is 124400 bytes (about
121.5 KiB); keep it out of small stacks and allocate it once (the demo uses a
global). Do not copy a live session: internal slices in `cfg` and the
RNG/store pointers are borrowed, and the record reader's fragments alias its
own buffer.

### `tlsInit`

**Purpose** — initializes a caller-allocated session.

**Signature** — `pub fn tlsInit(sess: *TlsSession, cfg: *TlsConfig) void`

**Parameters** — `sess` is uninitialized caller storage; `cfg` is copied by
value.

**Returns** — nothing.

**Errors** — none. Configuration validity is checked when the first
`tlsStep` sends the ClientHello (`error.BadConfig`, `error.UnsupportedVersion`).

### `tlsStep`

**Purpose** — advances the handshake by consuming input and producing one
driver action.

**Signature** — `pub fn tlsStep(sess: *TlsSession, input: []const u8, output: []u8) TlsError!TlsAction`

**Parameters**
- `sess` — initialized session.
- `input` — bytes read from the socket (may be empty, may contain a whole
  server flight; consumed incrementally with bounded memory).
- `output` — destination for a `.send` action; must hold the pending flight.

**Returns** — `.send`, `.recv`, `.established`, or `.closed` per `TlsAction`.

**Errors** — `TlsError` above. All pre-`Established` failures fail closed.

**Gotchas**
- The first call emits the ClientHello as `.send` before consuming `input`.
- If a complete flight is queued (TLS 1.2: ClientKeyExchange + CCS + Finished;
  TLS 1.3: client Finished), the whole queued flight is returned in one
  `.send`; the queue is then drained.
- `input` larger than the 16413-byte record buffer is fed in chunks; each
  complete record is drained before more is appended.
- A `recv` hint of `1` is advisory; the caller may read any size.
- Calling after `.closed` returns `.closed`. Errors are returned directly; the
  implementation does not latch `state == .Error`.

### `tlsRead`

**Purpose** — drains decrypted application data buffered by `tlsStep`.

**Signature** — `pub fn tlsRead(sess: *TlsSession, out: []u8) TlsError!usize`

**Returns** — number of bytes copied (0 when no application data is buffered,
including when `out.len == 0`). Never blocks and never produces `error.Closed`;
closure is reported by `tlsStep`/`tlsAction`.

**Errors** — none in the current implementation.

**Gotchas** — call it after each `tlsStep` that may have consumed application
records. The 32 KiB application buffer can return `error.AppTooLarge` from
`tlsStep` if the driver does not drain it between records.

### `tlsWrite`

**Purpose** — protects and frames application data into TLS records.

**Signature** — `pub fn tlsWrite(sess: *TlsSession, data: []const u8, output: []u8) TlsError!usize`

**Parameters** — `data` is split into ≤16384-byte records; `output` receives
the complete 5-byte-header-framed record set.

**Returns** — total bytes written to `output`.

**Errors** — `error.HandshakeFailed` before `Established`;
`error.OutputTooSmall` when `output` cannot hold every record.

**Gotchas** — with `n` chunks the required output is
`n*5 + data.len + n*overhead`. For TLS 1.2 overhead is 24 bytes for AES-GCM
(explicit nonce + tag) and 16 bytes for ChaCha20-Poly1305. For TLS 1.3 it is
17 bytes for both suites (tag + inner content type; no explicit nonce).
Sequence numbers advance per record.

## Buffer and record limits

| Limit | Value | Enforced by |
|---|---|---|
| Plaintext record fragment | 16384 | `protectRecord`, `recordAad`, `unprotectRecord` |
| TLS 1.3 inner plaintext (content + type) | 16385 | `protectRecord13`/`unprotectRecord13` |
| Protected wire fragment | 16408 | `parseRecordHeader`, `unprotectRecord`, `RecordReader` |
| Record header | 5 | `encodeRecord`/`decodeRecord` |
| `RecordReader` buffer | 16413 | `readerAppend` |
| Handshake reassembly | 65536 | `handleRecord`/`drainHandshake` |
| Pending output flight | 8192 | `queueRecord` |
| Application buffer | 32768 | `bufferApplication` |
| Finished verify_data | 12 (1.2) / 32 (1.3) | `handleFinished` / `verifyFinished13` |

## See also

- [`cipher.md`](cipher.md) — AES-128-GCM and ChaCha20-Poly1305 primitives.
- [`crypto.md`](crypto.md) — SHA-256/384, HMAC/PRF_SHA256, HKDF, and RSA
  PKCS#1 v1.5/PSS verification.
- [`ecc.md`](ecc.md) — P-256 ECDH/ECDSA, P-384 ECDSA, and X25519.
- [`x509.md`](x509.md) — certificate parsing, chain verification, and the
  trust-store format.
- [`examples/z98/demo/tls_demo/README.md`](../../../examples/z98/demo/tls_demo/README.md)
  — the HTTPS demo and `tier_tls.sh` gate.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
