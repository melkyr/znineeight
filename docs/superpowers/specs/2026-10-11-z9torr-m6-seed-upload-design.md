# z9torr M6 — Seed & Upload — Design

**Status:** Approved (operator, 2026-10-11)
**Goal:** make z9torr also **seed**: accept inbound peers (plaintext **and** MSE/PE), serve verified pieces from disk, broadcast `have`, and announce as a completed seeder — turning the download-only client into a working BitTorrent participant.
**Blueprint:** `examples/ztorr_blp.txt`
**Base spec of record:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md`
**Sequence:** PREVIOUS: M5 (`docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md`). NEXT (deferred arms): tit-for-tat choking; DHT `announce_peer` + PEX sending; Win9x inbound.

## §1 Evidence / motivation

The M0–M5 client is **download-only**. `examples/z98/z9torr/pex.zig:15` states
"A download-only client never accepts inbound connections"; there is no
listen/accept path anywhere, and `main.zig` advertises port `6881` in the
handshake and tracker announce **without binding it**. A participant that never
uploads is a pure leecher, so the example's "working system" goal is incomplete.

The primitives needed already exist, so this is an integration, not a rewrite:
- All wire encoders: `wire.zig` `writeBitfield`/`writeHave`/`writeChoke`/`writeUnchoke`/`writePiece`/`writeExtended` (+ `*Enc` variants for simple/interested/keepalive/request).
- `disk.readPiece(file, t, index, out)` reads a piece from the target file.
- Per-piece SHA-1 verification already tracks exactly what we hold (`piece.zig` -> `Corrupt`).
- `std_net.bindListen`/`accept`/`select` (used by the mock servers).
- A working **MSE responder** reference: `tools/mock_mse_peer.zig` (Z98, server role) and `tests/mse_ref.py` (Python, server role).
- `Stats.uploaded` already exists; the tracker announce already carries `event`/`left`/`uploaded`.

## §2 Scope and boundaries

**In scope:**
- An inbound listener + non-blocking `accept` coroutine that spawns a seeder coroutine per inbound connection.
- Inbound handshake: **plaintext AND MSE/PE responder** role.
- Seeder peer behaviour: `bitfield` on connect, `interested`->`unchoke`, `request`->serve from disk, `have` broadcasts, keep-alive.
- Choke policy = **unchoke a bounded set** (minimal; no tit-for-tat).
- Tracker as seeder: `left=0` / `event=completed`, periodic re-announce, `stopped` on exit (best-effort).
- Upload rate limiting: `--max-up` bounds **outgoing piece bytes** (in addition to request bytes).
- Host (Linux) first.

**Out of scope (deferred arms, not M6):**
tit-for-tat / optimistic choking + snub; DHT `announce_peer` persistence and PEX
**sending**; Win9x inbound; µTP; IPv6; multi-file; webseeds; HTTPS/TLS trackers;
magnet links. (Declared in the base spec §13 and the M4/M4.1 specs; unchanged.)

## §3 Architecture

- **Inbound path:** one listener task owns the bound socket and issues non-blocking
  `accept`s; on `WouldBlock` it yields, on a new connection it claims a free
  scheduler `Peer` slot and spawns a seeder coroutine — reusing the existing
  `Peer`/`wire`/`mse` code and the scheduler's slot machinery.
- **One peer implementation, two roles:** the same coroutine serves outbound
  (download) and inbound (upload) peers; the seeder role adds an inbound
  handshake-responder branch and a serving loop, while the download branch is
  unchanged.
- **MSE gains a responder function** (`mseAccept`) — the mirror of `mseConnect` —
  used for inbound encrypted peers.
- **Tracker:** the existing `announce` already takes `event`/`left`/`uploaded`;
  M6 supplies completed-seeder semantics plus a re-announce/`stopped` schedule.

## §4 Components / interfaces

### §4.1 Inbound listener (`peer.zig`, `main.zig`, `scheduler.zig`)
- Bind a listen socket to the advertised port (default `6881`, CLI-overridable).
- Non-blocking `accept` loop: `WouldBlock` -> `@asyncSuspend`; success -> claim a
  free slot (`firstInactiveSlot`) and `spawn` a seeder coroutine.
- Cap concurrent inbound peers at `MAX_RUNTIME_PEERS`; drop + close extras.
- Advertise the **bound** port in the handshake and in the tracker `port=`
  (replacing the current hard-coded `6881`).

### §4.2 Inbound handshake (`wire.zig`, `mse.zig`, `peer.zig`)
- **Plaintext:** read the 68-byte handshake (validate `pstrlen==19`/`pstr`/reserved
  per BEP 3/info_hash), send ours.
- **MSE/PE responder:** read initiator `Ya`; send `Yb = g^Xb mod P`;
  `S = Ya^Xb mod P`; `keyA = SHA1("keyA"|S|info_hash)`,
  `keyB = SHA1("keyB"|S|info_hash)`; verify `HASH('req1'|S)`; check
  `HASH('req2'|info_hash) XOR req3`; send `ENCRYPT_B(VC|crypto_select|padD)`;
  then run the encrypted stream. Port the responder body from
  `tools/mock_mse_peer.zig` into `mse.zig` as `mseAccept(...)`.
- Add the encrypted outbound encoders the seeder needs: bitfield, have, unchoke,
  piece (extend `wire.zig` alongside the existing `*Enc` writers).

### §4.3 Seeder peer loop (`peer.zig`, `piece.zig`, `scheduler.zig`)
- On connect: send `bitfield` of verified pieces (from `completed_bits`).
- On `interested`: `unchoke`.
- On `request{index,begin,length}`: bounds-check; read the block from disk
  (`disk.readPiece`/block read); `writePiece`; accumulate `Stats.uploaded`;
  respect the upload rate limit.
- As pieces verify (seeder or downloader): broadcast `have` to connected peers.
- Choke policy: `unchoke` a bounded set (minimal: all, or the first K); `choke`
  the remainder. Keep-alive on idle. D3/D4 discipline (per-peer state in `Peer`).

### §4.4 Tracker + rate limit (`tracker.zig`, `udp_tracker.zig`, `main.zig`)
- Announce `event=completed` + `left=0` once complete; periodic re-announce at
  `interval`; `event=stopped` on exit (best-effort). Extend `AnnounceEvent` with
  `stopped` and the BEP 15 code map (`1=completed, 2=started, 3=stopped`).
- Upload rate limit: `--max-up` bounds outgoing piece bytes via the existing
  token bucket (currently it bounds request bytes only).

### §4.5 Data structures
- `Peer` gains seeder/inbound fields (e.g. `inbound`, `am_choked`, `peer_interested`,
  `peer_choking`); no module-global scratch (M4 §5 rule). `Stats.uploaded` already
  present.

## §5 Gates and tests

- Compiler untouched; `scripts/stdlib/verify_stdlib.sh` stays green (284/0); no
  seed rotation.
- All existing 16 tiers stay green under `-fsafe`.
- New `tests/tier_seed.sh`: an inbound-leecher mock (or `aria2c` as a leecher)
  connects to a z9torr seeder over loopback and downloads a **byte-verified**
  payload — plaintext and MSE — asserting the leecher's SHA-1 and that
  `Stats.uploaded` increased.
- Best-effort real seeding against the live swarm is reported, never silently
  skipped.

## §6 Risks

1. **Inbound reachability** (NAT/firewall) — best-effort; the host-loopback seed
   tier is the hard gate.
2. **MSE responder correctness** (req2xor / VC / crypto_select / padD) — pin with
   the existing `mock_mse_peer` and `mse_ref.py` references.
3. **D3/D4 codegen hazards** in the new accept/seeder coroutines (per-peer state
   in `Peer`; no module-global across a suspension; no struct-return temp across a
   suspension).
4. **Choking correctness** — the minimal unchoke-set keeps it simple; tit-for-tat
   is a deferred arm.
5. **Win9x inbound deferred** — `select`-based accept is the future arm.

## §7 Out of scope
As §2.

## §8 Milestone index (updated)
`M0`..`M5` done. **`M6 seed & upload`** -> `docs/superpowers/plans/2026-10-11-z9torr-m6-seed-upload-plan.md`.
NEXT after M6 (deferred): tit-for-tat choking; DHT `announce_peer` + PEX sending; Win9x inbound.
