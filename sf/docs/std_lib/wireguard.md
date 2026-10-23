# WireGuard — `std_wireguard`

| | |
|---|---|
| **Modules** | `std_wireguard` |
| **Layers** | `L5` — sans-I/O WireGuard initiator: NoiseIK handshake, transport data path, timers, replay window, cookie consumption |
| **Import (by path)** | `const std_wireguard = @import("std_wireguard.zig");` |
| **Consumes** | `std_cipher` (ChaCha20-Poly1305), `std_crypto` (BLAKE2s, HMAC-BLAKE2s), `std_ecc` (X25519), `std_rand` (xoshiro256\*\* ephemeral keys and sender indices) |

`std_wireguard` is not re-exported through `std`; import it by path.

## Module overview

`std_wireguard` implements the **initiator half** of the WireGuard protocol
from the specification in
`docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.7. It
is **sans-I/O**: there are no sockets, no clock reads, no environment reads,
and no hidden heap. The caller owns the UDP socket and both clocks, supplies
the fixed-size `WgDevice` and `WgPeer` state, and drives the protocol with
`wgTick`, `wgReceive`, and `wgSend`.

The protocol model is the WireGuard NoiseIK handshake plus the transport data
path:

- **Handshake.** `wgCreateInitiation` builds a 148-byte type-1 initiation
  (ephemeral X25519 public key, encrypted static key, encrypted TAI64N
  timestamp, `mac1`, optional `mac2`). `wgProcessResponse` consumes the
  92-byte type-2 response, performs the DH/KDF chain, verifies the encrypted
  empty value, and installs the transport keys.
- **KDF.** The construction is
  `Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s` with the WireGuard identifier. The
  chaining-key/KDF chain is HKDF-BLAKE2s as in the WireGuard paper §5.4;
  `mac1` is keyed BLAKE2s-128 and the transport AEAD is ChaCha20-Poly1305.
- **Transport.** `wgSend` encrypts one inner IP packet into a type-4 message
  (16-byte header, plaintext padded to a 16-byte boundary, 16-byte tag).
  `wgReceive` authenticates, enforces the replay window, decrypts, and strips
  the padding to the inner IP packet length.
- **Timers.** `wgTick` polls the per-peer timer state using the caller's
  monotonic `now_ms`. It never sleeps. The three exact WireGuard times are
  120 s rekey, 180 s reject, and 10 s keepalive; retries use a 5 s base plus
  bounded per-attempt jitter.
- **Cookies.** A received type-3 CookieReply is decrypted with XChaCha20
  (HChaCha20 subkey) into a 16-byte cookie. The next initiation then carries
  `mac2` = keyed BLAKE2s-128 over the initiation with the cookie as key.
  Cookie-reply *generation* is out of scope (initiator only).

All multi-byte wire integers are little-endian via explicit load/store
helpers; no pointer alignment is assumed. State is entirely caller-owned:
there is no arena parameter, no allocation, and no `free` (R1 does not apply
because nothing allocates; R6 holds because time is an explicit parameter).

**Scope.** Initiator only. The device keeps a caller-sized peer slice but the
protocol paths act on the first matching peer (the M6 contract is one peer in
the demo). Responder handshakes (received type 1) are rejected as
`error.Corrupt`; cookie-reply generation, PSK distribution, TUN/TAP, and
routing/allowed-IP enforcement are not implemented. `endpoint_ip`,
`endpoint_port`, and `allowed_ips` are carried in `WgPeer` for the caller's
use but `std_wireguard` does not consult them.

**Errors.** The module error set is
`error.{Corrupt, AuthenticationFailed, NoSession, SessionExpired,
OutputTooSmall, NoSpace, InvalidPeer}`. `Corrupt` covers length/type/mac
failures, `AuthenticationFailed` covers AEAD and DH failures,
`NoSession`/`SessionExpired` cover missing or expired sessions and pending
handshakes, `OutputTooSmall` a short caller `out` slice, `NoSpace` a full peer
slice, and `InvalidPeer` a zero/low-order static key or an uninitialised
device key.

## Message flow

```text
initiator (std_wireguard)                     responder (kernel/other WG)
        |                                                  |
        |  type 1  Handshake Initiation (148 B)            |
        |  eph_pub | enc_static | enc_ts | mac1 [| mac2]   |
        |------------------------------------------------->|
        |                                                  |
        |  type 2  Handshake Response (92 B)               |
        |  sender | eph_pub | enc_empty | mac1 [| mac2]    |
        |<-------------------------------------------------|
        |  -> session_up: install tx/rx keys and indices    |
        |                                                  |
        |  type 4  Transport Data (16 B hdr + pad + tag)    |
        |  receiver | counter | ciphertext | tag            |
        |<------------------------------------------------>|
        |                                                  |
        |  type 3  Cookie Reply (64 B)   [when under load] |
        |  receiver | nonce | enc_cookie | tag             |
        |<-------------------------------------------------|
        |  -> store cookie; next initiation carries mac2   |
```

The types are exclusive: type 1 initiation, type 2 response, type 3 cookie
reply, type 4 transport data. `wgReceive` accepts 2, 3, and 4; everything else
is `error.Corrupt`.

## Quick start

```zig
const std = @import("std");
const std_wireguard = @import("std_wireguard.zig");
const std_rand = @import("std_rand.zig");

var peers: [4]std_wireguard.WgPeer = undefined;
var dev: std_wireguard.WgDevice = undefined;
var iface_priv: [32]u8 = undefined;
var peer: std_wireguard.WgPeer = undefined;

// Fill iface_priv from configuration. The remote static key is the far side's
// public key; preshared_key is all-zero when no PSK is configured.
std_wireguard.wgInit(&dev, &iface_priv);
dev.peers = peers[0..];
dev.rng = std_rand.xoshiroInit(0x0123456789ABCDEF); // deterministic fixtures

peer.remote_static_pub = remote_static_pub;
peer.preshared_key = [_]u8{0} ** 32;
peer.endpoint_ip = 0;
peer.endpoint_port = 0;
peer.allowed_ip_count = 0;
try std_wireguard.wgAddPeer(&dev, &peer);

var out: [2048]u8 = undefined;
const now_ms: u64 = std.time.milliTimestamp();
const wall_unix_ns: u64 = std.time.wallClockUnix() * 1000000000;

// Poll timers: sends handshakes/keepalives; never sleeps.
const action = try std_wireguard.wgTick(&dev, now_ms, wall_unix_ns, out[0..]);
switch (action) {
    .send_handshake => |n| {
        _ = n; // send out[0..n] over UDP
    },
    .send_keepalive => |n| {
        _ = n; // send out[0..n] over UDP
    },
    else => {},
}

// Feed a received UDP datagram back into the state machine.
const inbound = try std_wireguard.wgReceive(&dev, now_ms, udp_payload, out[0..]);
switch (inbound) {
    .session_up => {},
    .inner_packet => |n| {
        _ = n; // deliver out[0..n] to the IP stack
    },
    .dropped_replay => {},
    else => {},
}

// Encrypt one inner IP packet. Requires a live session; wgTick owns initiation.
const n = std_wireguard.wgSend(&dev, now_ms, wall_unix_ns, inner_ip, out[0..]) catch |err| {
    if (err == error.NoSession) return; // call wgTick, then retry
    return err;
};
_ = n; // send out[0..n] over UDP
```

## `wall_unix_ns` vs `now_ms`

The two time bases are deliberately distinct:

- **`now_ms`** is the caller's **monotonic** millisecond clock. It drives
  retry/rekey/reject/keepalive timers and is never placed on the wire.
- **`wall_unix_ns`** is the **wall clock** in Unix nanoseconds (`sec * 1e9`
  for second-resolution callers). It is the sole source of the TAI64N
  timestamp in an initiation.

> **Never derive `wall_unix_ns` from `now_ms`.** A monotonic-derived TAI64N
> makes the kernel far side reject later initiations as timestamp replays
> after a client restart — a silent interop failure. `wgTai64n` rejects no
> input; correctness of the time base is the caller's contract.

`wgTick` and `wgSend` take `wall_unix_ns` for signature uniformity; only the
handshake initiation path consumes it. `wgSend` currently ignores it because
transport messages carry a counter, not a timestamp. `wgReceive` has no wall
clock parameter at all.

## Timers

All timer state is per peer and advanced only by `wgTick(now_ms)`. There are
no background threads and no `sleep`. `wgTick` returns at most one action per
call; with multiple peers, call it until it returns `.none` if every peer must
be serviced in one pass.

| Constant | Value | Behaviour |
|---|---:|---|
| `WG_KEEPALIVE_TIMEOUT_MS` | 10 000 ms | With a live session younger than `REKEY_AFTER_TIME` and no transmit for 10 s, `wgTick` emits an **empty** transport message (`.send_keepalive`). |
| `WG_REKEY_AFTER_TIME_MS` | 120 000 ms | Once the session is 120 s old, `wgTick` starts a rekey initiation (`.send_handshake`) when no handshake is in flight. The **active session remains usable**; `wgSend` keeps using its keys, indices, counter, and replay window. |
| `WG_REJECT_AFTER_TIME_MS` | 180 000 ms | At/after 180 s the session is dead: `wgSend` returns `error.SessionExpired` and `wgReceive` rejects inbound transport with `error.SessionExpired`. `wgTick` may still send an initiation; it never keepalives or encrypts an expired session. |
| `WG_REKEY_TIMEOUT_MS` | 5 000 ms | Base retry interval while an initiation is pending. The actual delay is `5000 + ((attempts * 137) % 334)` ms — bounded per-attempt jitter, deterministic, no RNG and no sleep. The first initiation is sent immediately; the first retry is at 5 137 ms. |
| `WG_REKEY_AFTER_MESSAGES` | `1 << 60` | Published policy constant; the current `wgSend` guard uses `WG_REJECT_AFTER_MESSAGES` only. |
| `WG_REJECT_AFTER_MESSAGES` | `2^64 - 8192` | `wgSend` returns `error.SessionExpired` once `sending_counter` reaches this value. |

A successful response resets `handshake_attempts` to zero, installs the new
session, and resets the transport counter and replay window.

**Rekey continuity.** While a session is live, the protocol keeps the active
indices, `tx_key`/`rx_key`, `sending_counter`, and the full replay window
untouched. A new initiation writes only the *pending* handshake state
(`pending_local_index`, ephemeral key, hash, chaining key, `mac1`). A pending
response is matched by `pending_local_index`; the transport/replay paths keep
matching the active `local_index`, so old-key inbound packets remain valid
until the response arrives. On success, `wgProcessResponse` installs the
pending indices and keys atomically, clears the pending state, and resets the
counter/replay state. The previous session remains usable right up to that
point.

## Replay window

Transport receive state is a **2048-bit sliding window** stored as 32 `u64`
words. Bit 0 of `replay_bitmap[0]` corresponds to `replay_counter` (the
highest accepted counter), bit 1 to the counter one below it, and so on.

- The first authenticated packet initialises the window and is accepted.
- A counter **above** `replay_counter` is accepted; the bitmap shifts by the
  difference. A jump of `>= 2048` clears the window instead of shifting.
- A counter **inside** the window is accepted only if its bit is clear;
  an already-set bit is a duplicate.
- A counter **below** the window (`diff >= 2048`) is rejected.
- Duplicate, too-old, and in-window-already-seen packets return
  `WgAction.dropped_replay`.

Authentication happens **before** the window is updated: a forged packet can
never advance the bitmap. Nonce reuse is a hard protocol bug; the sender
counter is monotonic and is reset only when a new session installs.

## Cookies and `mac2`

A CookieReply (type 3) is consumed by `wgReceive` for the pending initiation
matched by its receiver index:

1. The 24-byte XChaCha20 nonce is split into a 16-byte HChaCha20 input and an
   8-byte ChaCha20 nonce suffix.
2. The cookie key is the peer's `cookie--` label key; the associated data is
   the pending initiation's `mac1`.
3. The 16-byte encrypted cookie is opened and stored; `cookie_valid` is set.

The next initiation includes a non-zero `mac2`: keyed BLAKE2s-128 with the
cookie as key over the 132-byte initiation prefix (everything except the last
16-byte `mac2` field). Without a cookie, `mac2` is all zero. A response that
carries a non-zero `mac2` is accepted only when a cookie is stored and its
`mac2` verifies. Cookie **expiry** (`COOKIE_SECRET_MAX_AGE`) is not enforced
because initiation construction has no `now_ms` parameter; a consumed cookie
remains usable until replaced. CookieReply generation is not implemented.

## API (spec §5.7)

### `WG_KEY_LEN`, `WG_HASH_LEN`, `WG_MAC_LEN`, `WG_TAI64N_LEN`

**Purpose** — wire-size constants shared by the handshake and transport paths.

**Signatures**
```zig
pub const WG_KEY_LEN: usize = 32;
pub const WG_HASH_LEN: usize = 32;
pub const WG_MAC_LEN: usize = 16;
pub const WG_TAI64N_LEN: usize = 12;
```

**Gotchas** — `WG_KEY_LEN` is an X25519 key; `WG_HASH_LEN` a BLAKE2s-256
hash/chaining key; `WG_MAC_LEN` a `mac1`/`mac2`/AEAD tag; `WG_TAI64N_LEN` is
the 8-byte TAI64N seconds plus 4-byte nanoseconds emitted big-endian.

### `WG_AUTHTAG_LEN`, `WG_INITIATION_LEN`, `WG_RESPONSE_LEN`, `WG_COOKIE_REPLY_LEN`, `WG_COOKIE_LEN`, `WG_COOKIE_NONCE_LEN`, `WG_TRANSPORT_HDR_LEN`, `WG_MAX_ALLOWED_IPS`

**Purpose** — message and buffer sizes.

**Signatures**
```zig
pub const WG_AUTHTAG_LEN: usize = 16;
pub const WG_INITIATION_LEN: usize = 148;
pub const WG_RESPONSE_LEN: usize = 92;
pub const WG_COOKIE_REPLY_LEN: usize = 64;
pub const WG_COOKIE_LEN: usize = 16;
pub const WG_COOKIE_NONCE_LEN: usize = 24;
pub const WG_TRANSPORT_HDR_LEN: usize = 16;
pub const WG_MAX_ALLOWED_IPS: usize = 8;
```

**Gotchas** — type-1 messages are exactly 148 bytes, type-2 exactly 92, type-3
exactly 64. A type-4 message is `16 + padded_plaintext + 16`; the padded
plaintext length must be a multiple of 16. `WG_MAX_ALLOWED_IPS` bounds the
fixed `allowed_ips` array; the protocol layer does not enforce them.

### `WG_REKEY_AFTER_TIME_MS`, `WG_REJECT_AFTER_TIME_MS`, `WG_REKEY_TIMEOUT_MS`, `WG_KEEPALIVE_TIMEOUT_MS`, `WG_REKEY_AFTER_MESSAGES`, `WG_REJECT_AFTER_MESSAGES`, `WG_REPLAY_WINDOW_BITS`

**Purpose** — timer and replay policy constants; see [Timers](#timers) and
[Replay window](#replay-window).

**Signatures**
```zig
pub const WG_REKEY_AFTER_TIME_MS: u64 = 120 * 1000;
pub const WG_REJECT_AFTER_TIME_MS: u64 = 180 * 1000;
pub const WG_REKEY_TIMEOUT_MS: u64 = 5 * 1000;
pub const WG_KEEPALIVE_TIMEOUT_MS: u64 = 10 * 1000;
pub const WG_REKEY_AFTER_MESSAGES: u64 = 1 << 60;
pub const WG_REJECT_AFTER_MESSAGES: u64 = 0xFFFFFFFFFFFFFFFF - (1 << 13);
pub const WG_REPLAY_WINDOW_BITS: usize = 2048;
```

**Gotchas** — `WG_REKEY_AFTER_MESSAGES` is published but not consumed by the
current send guard; only `WG_REJECT_AFTER_MESSAGES` stops `wgSend`.

### `WgKey`

**Purpose** — a 32-byte key alias.

**Signature** — `pub const WgKey = [WG_KEY_LEN]u8;`

### `WgError`

**Purpose** — the module's single error set (R2).

**Signature**
```zig
pub const WgError = error{
    Corrupt,
    AuthenticationFailed,
    NoSession,
    SessionExpired,
    OutputTooSmall,
    NoSpace,
    InvalidPeer,
};
```

### `WgAction`

**Purpose** — the action returned by `wgTick`/`wgReceive`; each payload is a
byte count written to the caller's `out` slice.

**Signature**
```zig
pub const WgAction = union(enum) {
    none,
    send_handshake: usize,
    send_keepalive: usize,
    session_up: void,
    inner_packet: usize,
    dropped_replay: void,
};
```

**Gotchas** — `.send_handshake` and `.send_keepalive` mean "transmit
`out[0..n]` now"; `.inner_packet` means "deliver `out[0..n]` to the IP stack";
`.dropped_replay` is a successfully authenticated but replayed packet; `.none`
means nothing to do. A type-3 CookieReply also returns `.none` after storing
the cookie.

### `WgAllowedIp`

**Purpose** — caller-owned routing metadata (not consulted by the protocol).

**Signature**
```zig
pub const WgAllowedIp = struct {
    ip: u32,
    mask: u32,
};
```

### `WgPeer`

**Purpose** — all per-peer configuration, handshake state, transport keys,
counter/replay state, cookie, and timers.

**Signature** — `pub const WgPeer = struct { ... };` (see
`sf/src/std_wireguard.zig`). Public configuration fields are
`static_priv`, `remote_static_pub`, `preshared_key`, `endpoint_ip`,
`endpoint_port`, `allowed_ips`, and `allowed_ip_count`. Everything else is
protocol state.

**Gotchas** — `wgAddPeer` overwrites the runtime fields (including
`public_key_dh`, label keys, indices, keys, counters, replay, cookie, and
timers), so only the configuration fields need meaningful values. The
handshake authenticates the **device** interface key to
`remote_static_pub`; `static_priv` is retained for callers that keep a
per-peer copy and is not used by the handshake. `preshared_key` may be all
zero (Noise `psk2` with the zero PSK).

### `WgDevice`

**Purpose** — the device interface key, peer slice, RNG, and cached label
keys.

**Signature**
```zig
pub const WgDevice = struct {
    iface_priv: WgKey,
    iface_pub: WgKey,
    peers: []WgPeer,
    peer_count: usize,
    rng: rand.Xoshiro256,
    label_mac1_key: WgKey,
    label_cookie_key: WgKey,
};
```

**Gotchas** — `wgInit` sets `peer_count = 0` and resets `rng` to
`xoshiroInit(0)`; assign `dev.peers` to caller storage and re-seed `dev.rng`
after `wgInit` for deterministic ephemeral keys and sender indices. The
device does not allocate.

### `wgInit`

**Purpose** — initialise a device from its interface private key.

**When to use** — once before adding peers.

**Signature** — `pub fn wgInit(dev: *WgDevice, iface_priv: *const [WG_KEY_LEN]u8) void`

**Parameters**
- `dev` — caller-owned device; `peers` may be unset until after this call.
- `iface_priv` — 32-byte X25519 private key (clamped by the curve code).

**Returns** — nothing.

**Errors** — none. A failed X25519 base-point multiplication (only a bad
private key) leaves `iface_pub` all zero and later initiation fails with
`error.InvalidPeer`.

**Gotchas** — resets `peer_count` and the RNG. It derives the device
`mac1----`/`cookie--` label keys from `iface_pub` but does not add peers.

### `wgAddPeer`

**Purpose** — validate and install one peer configuration.

**When to use** — after `wgInit`, before any handshake or transport traffic.

**Signature** — `pub fn wgAddPeer(dev: *WgDevice, peer: *const WgPeer) WgError!void`

**Parameters**
- `dev` — initialised device with a caller-sized `peers` slice.
- `peer` — configuration template. `remote_static_pub` and `preshared_key`
  are required; `endpoint_*` and `allowed_ips` are copied for the caller.

**Returns** — nothing; increments `dev.peer_count` and initialises the runtime
state of the new slot.

**Errors**
- `error.InvalidPeer` — zero `remote_static_pub`, low-order/zero DH result, or
  an uninitialised device key (`iface_pub` all zero).
- `error.NoSpace` — `peer_count >= peers.len`.

**Gotchas** — `wgAddPeer` precomputes `DH(iface_priv, remote_static_pub)` and
the per-peer label keys, then zeroes every runtime field. Re-adding a peer is
not the same as updating it: the new slot starts with no session.

### `wgCreateInitiation`

**Purpose** — build a 148-byte type-1 handshake initiation.

**When to use** — normally via `wgTick`; call directly only for custom
scheduling or deterministic capture.

**Signature** — `pub fn wgCreateInitiation(dev: *WgDevice, peer: *WgPeer, wall_unix_ns: u64, out: []u8) WgError!usize`

**Parameters**
- `dev` — initialised device; `dev.rng` supplies the ephemeral key and sender
  index.
- `peer` — target peer; its `hs_*`/pending fields are updated.
- `wall_unix_ns` — wall-clock Unix nanoseconds for TAI64N (never `now_ms`).
- `out` — recipient buffer of at least 148 bytes.

**Returns** — `WG_INITIATION_LEN` (148).

**Errors** — `error.OutputTooSmall` for a short `out`; `error.InvalidPeer`
for a zero device key or a failed ephemeral base-point multiplication;
`error.AuthenticationFailed` for a zero DH; `error.Corrupt` for a failed
handshake seal.

**Gotchas** — writes only **pending** handshake state; it does not disturb a
live session. Draws from `dev.rng`, so seed it explicitly for repeatability.
The initiation carries `mac2` when `peer.cookie_valid` is set.

### `wgProcessResponse`

**Purpose** — process a 92-byte type-2 handshake response and install the
pending session.

**When to use** — normally via `wgReceive`; direct use is for tests/custom
drivers that have already matched the receiver index.

**Signature** — `pub fn wgProcessResponse(dev: *WgDevice, peer: *WgPeer, msg: []const u8) WgError!void`

**Parameters**
- `dev` — initialised device.
- `peer` — peer with a valid pending initiation.
- `msg` — exactly 92 bytes.

**Returns** — nothing.

**Errors** — `error.Corrupt` for a wrong length/type, a receiver index that is
not the pending index, or a bad `mac1`/`mac2`; `error.NoSession` when no
pending handshake exists; `error.AuthenticationFailed` for a failed DH or the
encrypted empty value.

**Gotchas** — on success the pending indices/keys become the active session
atomically, the pending state is cleared, `sending_counter` is reset to zero,
and the replay window is cleared. It does not update the timer timestamps;
`wgReceive` calls `setSessionUp` afterwards.

### `wgTai64n`

**Purpose** — encode a Unix wall time as the 12-byte WireGuard TAI64N value.

**When to use** — inside custom initiation construction or tests; the normal
path is `wgCreateInitiation`.

**Signature** — `pub fn wgTai64n(wall_unix_ns: u64, out: *[WG_TAI64N_LEN]u8) void`

**Parameters**
- `wall_unix_ns` — Unix nanoseconds.
- `out` — 12-byte destination.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — seconds are `0x400000000000000A + wall_unix_ns / 1e9`, written
big-endian, followed by the 4-byte big-endian nanosecond remainder. Feeding a
monotonic clock here is the timestamp-replay interop bug.

### `wgSend`

**Purpose** — encrypt one inner IP packet as a type-4 transport message.

**When to use** — whenever a live session exists and the IP stack has a packet
ready.

**Signature** — `pub fn wgSend(dev: *WgDevice, now_ms: u64, wall_unix_ns: u64, inner_ip: []const u8, out: []u8) WgError!usize`

**Parameters**
- `dev` — device with at least one live session.
- `now_ms` — monotonic milliseconds for the 180 s session-expiry check.
- `wall_unix_ns` — accepted for signature symmetry; currently unused by the
  transport path.
- `inner_ip` — the plaintext inner IP packet (may be empty for a keepalive).
- `out` — result buffer; needs `16 + round_up_16(inner_ip.len) + 16` bytes.

**Returns** — number of transport bytes written.

**Errors** — `error.NoSession` when no peer has a live session;
`error.SessionExpired` at/after 180 s or at `WG_REJECT_AFTER_MESSAGES`;
`error.OutputTooSmall` for a short `out`; `error.Corrupt` if encryption fails.

**Gotchas** — `wgSend` never initiates a handshake; call `wgTick` and retry.
It uses the active session even while a rekey is pending, advances only that
session's `sending_counter`, and pads the plaintext to a 16-byte boundary
(zero bytes). AEAD associated data is empty; the nonce is
`0^4 || counter_le64`. The output order is consistently
`[receiver index][counter]` in the header, then ciphertext, then tag.

### `wgTick`

**Purpose** — drive all per-peer timers and return the next action.

**When to use** — poll regularly (for example once per event-loop iteration or
every 100 ms). There is no internal clock.

**Signature** — `pub fn wgTick(dev: *WgDevice, now_ms: u64, wall_unix_ns: u64, out: []u8) WgError!WgAction`

**Parameters**
- `dev` — device to service.
- `now_ms` — monotonic milliseconds; must be non-decreasing.
- `wall_unix_ns` — wall-clock Unix nanoseconds for any initiation it builds.
- `out` — buffer for an initiation or keepalive.

**Returns** — `.send_handshake` (initiation bytes), `.send_keepalive` (empty
transport bytes), or `.none`. It returns at most one action per call.

**Errors** — `error.OutputTooSmall`; initiation errors from
`wgCreateInitiation`; transport errors from a keepalive encryption.

**Gotchas** — for a live session: rekey at 120 s (active session preserved),
keepalive after 10 s idle (only before 120 s), and initiation retries for an
expired (180 s) session. For a peer without a session: initiate immediately,
then retry at the jittered 5 s interval while the handshake stays pending. An
expired session is never used to encrypt or keepalive.

### `wgReceive`

**Purpose** — process one inbound WireGuard datagram.

**When to use** — for every UDP payload received from the far side.

**Signature** — `pub fn wgReceive(dev: *WgDevice, now_ms: u64, udp_payload: []const u8, out: []u8) WgError!WgAction`

**Parameters**
- `dev` — device state.
- `now_ms` — monotonic milliseconds for expiry and last-RX bookkeeping.
- `udp_payload` — the complete UDP payload (no UDP/IP header).
- `out` — plaintext destination for transport data; must hold the padded
  plaintext length.

**Returns**
- type 2: `.session_up`
- type 3: `.none` (cookie stored)
- type 4: `.inner_packet` with the inner IP length, `.none` for an empty
  keepalive, or `.dropped_replay`
- other types: error

**Errors** — `error.Corrupt` for shorter than 4 bytes, a wrong type-2/type-3
length, an invalid type-4 length/padding, a bad header, or a bad mac;
`error.NoSession` when no peer matches the receiver index or no pending
handshake exists; `error.SessionExpired` for transport at/after 180 s;
`error.OutputTooSmall` for a short `out`; `error.AuthenticationFailed` for a
failed AEAD open.

**Gotchas** — authentication is verified before the replay window is updated.
The inner length comes from the IP version and total-length fields when they
are plausible (IPv4 total length ≥ 20 and within the padded plaintext; IPv6
`40 + payload length`); otherwise the whole padded plaintext length is
returned. Received handshake initiations (type 1) are not supported and yield
`error.Corrupt`.

### `load32le`, `store32le`

**Purpose** — explicit little-endian 32-bit wire load/store helpers.

**Signatures**
```zig
pub fn load32le(p: []const u8, off: usize) u32
pub fn store32le(p: []u8, off: usize, v: u32) void
```

**Gotchas** — the caller guarantees `off + 4 <= p.len`; the helpers perform no
bounds checks and assume no alignment.

## Determinism

All inputs are explicit: `now_ms`, `wall_unix_ns`, the device RNG state, and
the caller's buffers. `wgInit` seeds the RNG with zero, so assign
`dev.rng = std_rand.xoshiroInit(seed)` after `wgInit` for repeatable ephemeral
keys, sender indices, and captures. There are no global mutable values and no
hidden allocations, and generation is independent of addresses or environment
(R6).

## Pins

- `repro/mi_matrix/stdlib_wg_handshake_xmod` — byte-exact canned initiation
  and response, derived transport keys, and handshake negatives.
- `repro/mi_matrix/stdlib_wg_transport_xmod` — transport byte-exactness,
  counters, replay window, timers, rekey continuity, and CookieReply/mac2.
- `repro/mi_matrix/stdlib_wireguard_cross_xmod` +
  `scripts/stdlib/vectors/std_wireguard/{handshake,transport,cookie}.{in,expected}`
  — Z98 == vendored C89 reference == committed expected.
