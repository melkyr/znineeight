# z9torr — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `f2d627a3` (M4.1 sources Task 0–4 + Task 5 fallback fix; M4.1 Task 5 docs on top)

**MD5 (`--dump-c89`):** `fe6d03eb517d042c149b24a418a69d52` (seed `zig1_5_clean`; stable 3×; CP P3 BEP 5 PORT fix + per-peer frame trace)

## Build Recipes

### seed zig1_5_clean (build + run) — binding
```bash
mkdir -p /tmp/z9_m1_out
timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9_m1_out examples/z98/z9torr/main.zig
sh /tmp/z9_m1_out/build_target.sh linux /tmp/z9_m1_out/prog
/tmp/z9_m1_out/prog examples/z98/z9torr/testdata/t1_single_1m.torrent
```

### seed zig1_5_clean (dump C89) — for the MD5 above
```bash
timeout 120 /tmp/z9_m41_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum
# fe6d03eb517d042c149b24a418a69d52  -
```

## Expected Output
For `testdata/t1_single_1m.torrent`:
```
name: t1.bin
length: 1048576
piece length: 262144
pieces: 4
info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
```
Invoked with no torrent path (or `--help`), the program prints the `usage:`
block from `cli.usage` and exits 1 (0 for `--help`).

## Notes
M1 (core, pure) is complete: `cli.zig` (argv parsing, `usage`, `exitCodeFor`),
`torrent.zig` (single-file bencode parse + SHA-1 `info_hash`; `piece_hashes` is a
flat `[]const u8`, 20 B/piece), `tools/ref_check.c` (C89 reference), committed
`testdata/` fixtures, and `tests/tier1.sh` (end-to-end gate:
`15 passed, 0 failed / TIER1 PASS`). `main` prints the metadata summary above.

Task 1 of M1 adds `cli.zig` (argv parsing, `usage`, `exitCodeFor`) and wires `main.zig`
to it. `main` now has `pub fn main(argc: i32, argv: [*][*]u8) void` so the emitted C
wrapper forwards `argc`/`argv`; the return type stays `void`. `parseArgs` takes the
many-pointer `[*][*]u8` (M1a: no `[]synthetic` — D2).

**M1a amendment (2026-10-08):** design around compiler defect D2 (never `[]` a
synthetic type) and cap the `.torrent` metadata:
- `parseArgs`/`argAt` take `[*][*]u8`, not `[][*]u8`.
- `Torrent.announce_list` is the fixed `[8][]const u8` + `announce_count: u32`
  (extras dropped), not `[][]const u8`.
- `MAX_TORRENT_BYTES = 3145728` (3 MiB) caps the metadata before `readAll`; an
  oversize file prints `z9torr: torrent too large` and exits 2. `MAX_PIECES` is
  derived from it. The downloaded payload stays unbounded (`total_length`,
  streamed to disk).
With these, the emitted `.c` has **zero** `-Wincompatible-pointer-types`
warnings (previously two, from argv).

Exit codes per spec §8: 0 success, 1 usage, 2 torrent/file, 3 tracker/net, 4 peer,
5 disk. The seed compiler has no `anyerror`, so `exitCodeFor` uses the brief-authorized
fixed-mapping alternative: it takes a concrete `FailureClass` enum (usage=1..disk=5).

The seed `lib/std.zig` does not re-export `file`, so `std_file` is imported by path
(`@import("std_file.zig")`). Tests: `tests/tier1_cli.sh` (CLI shapes).

**Win9x argv caveat:** on Windows 9x the CRT builds `argv` from `GetCommandLineA`, which
is subject to the 16-bit command-line length limit and Win9x quoting rules. The parser
consumes the `argv` the runtime supplies and never re-tokenizes the raw command line, so
Win9x argument handling matches the CRT's, not a custom splitter.

**M2 (single-peer download + resume) is complete (2026-10-08).** New modules:
`wire.zig` (BE framing + handshake), `tracker.zig` (HTTP announce + compact
peers), `disk.zig` (single-file write-through + read-back), `resume.zig`
(fastresume sidecar `.z9torr.resume` + re-hash), `piece.zig` (depth-4 request
pipeline + SHA-1 verify), `peer.zig` (one peer coroutine), and
`tools/mock_tracker.zig` (`:6969`) + `tools/mock_peer.zig` (`:6970`). `main`
announces, downloads, verifies, and prints a `summary: fetched=<bytes>
requests=<n>` line at exit.

Resume uses the sidecar's `completed_bits` plus a `partial` list of
`{index, block_mask}` entries (one per half-downloaded piece); on restart the
present 16 KiB blocks are seeded as already-received so only the missing blocks
are requested. A `bitfield` whose body is not exactly `ceil(n_pieces/8)` bytes
rejects the peer (exit 4).

Tests: `tests/tier1.sh` (15/0; parse + `ref_check`), `tests/tier1_cli.sh` (CLI
shapes), `tests/tier2.sh` (15/0; download `t1`/`t2`, interrupt+restart resume
with strictly-fewer fetched bytes, malformed-peer rejection). The `--dump-c89`
md5 above is stable 3× for the M2 source.

## M3 — multi-peer + scheduler + rate limits (2026-10-08)

New modules: `scheduler.zig` (rarest-first `Scheduler` + `addPeer`/`removePeer`),
`ratelimit.zig` (`TokenBucket`), `stats.zig` (`statsRender`); `main.zig` now
spawns one coroutine per announced peer (up to the 16-slot runtime cap) and
shares two global token buckets refilled on a 100 ms cadence. `mock_tracker.zig`
advertises N compact peers via `--peers a,b,c` / repeatable `--peer`.

Flags (from `cli.usage`): `--max-peers N` (1..100 accepted; runtime clamps to
`MAX_RUNTIME_PEERS = 16` and to the announced count), `--max-up N` (`0` or
`>= 13`), `--max-down N` (`0` or `16384..65535`). A nonzero rate below one
request/block quantum is a usage error (exit 1).

Operator ruling #3: the `main.zig` drive loop calls
`scheduler.removePeer(&g_sched, &g_sched.peers[slot])` for every spawned slot
whose task is `done`/`cancelled` after each `tick`, so finished peers stop
inflating `piece_rarest` and the stats peer count. `removePeer` early-returns on
an inactive slot (repeat-safe) and is never called on a live task.

Tests: `tests/tier2.sh` now runs 4 `mock_peer`s on the declared ports
(`testdata/ports.txt` = tracker `6969`, peers `6970`–`6973`) and asserts, for
`t2_single_25m`: exit 0 + SHA-1; the no-double-request invariant via
`Z9TORR_CLAIM_LOG=1` (100 claims / 100 unique pieces); that >1 peer slot worked
(observed 4); and a multi-peer interrupt/restart resume with strictly-fewer
fetched bytes. `tests/tier1.sh` fails closed if `127.0.0.1:6969` is already
listening (spec §12 item 9). Gates: tier1 `15/0`, tier1_cli all pass, tier2
`17/0`.

The `--dump-c89` md5 above is stable 3× for the M3 Task 4 source plus the
stats-delta guard; refresh with
`timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum`.

## M4 — real-swarm compatibility (2026-10-09)

M4 makes z9torr able to join real public swarms. New modules:
`mse.zig` (BitTorrent Protocol Encryption, MSE/PE: DH-768 + RC4 + `req1`/`req2`/
`req3` verification, `crypto_provide`/`crypto_select`, 1024-byte RC4 discard),
`udp_tracker.zig` (BEP 15 connect/announce with the explicit BEP 15↔HTTP event
map), `dht.zig` (BEP 5 KRPC `ping`/`find_node`/`get_peers`/`announce_peer` +
bounded routing table; env-gated in-process self-test), and `pex.zig` (BEP 10
extension handshake + BEP 11 `ut_pex` add/drop feeding the scheduler; env-gated
self-test), plus `tools/mock_mse_peer.zig` and `tools/mock_udp_tracker.zig`.
`std_crypto` gained RC4 + `modpow` (Task 1).

Key changes:
- **peer_id fix (Task 0):** `main.zig` copies the real `makePeerId` value into
  every `Peer.peer_id`, so outgoing handshakes no longer carry all zeros.
- **Encrypted-first transport (Task 2):** `peer.zig` attempts MSE first and, on
  failure, does a bounded plaintext reconnect; after an MSE handshake the whole
  `wire.zig` framing runs through the two RC4 contexts. RC4 keys are
  `SHA1("keyA"||S||info_hash)` / `SHA1("keyB"||S||info_hash)` (SKEY =
  info_hash).
- **UDP tracker (Task 3):** `main.zig` prefers the first `udp://` announce (primary
  or announce-list), else the HTTP tracker.
- **DHT + PEX (Task 4):** `Z9TORR_DHT=host[:port],...` merges DHT-discovered
  peers into the candidate list; PEX-learned peers are dynamically spawned
  mid-run through the same `spawnPeerAt` path (`main.zig`), with a `g_started`
  slot flag.

Gates (all PASS): tier1 `16/0`, tier1_cli `8/8`, tier1_unit `3/3`, tier2 `17/0`,
`tier3_encrypted` `5/0` (MSE download), `tier_udp_tracker` `7/0`,
`tier_dht` `4/0` (real two-node `get_peers`), `tier_pex` `11/0` (control vs
injection proves a PEX peer is dialed). `scripts/stdlib/verify_stdlib.sh` is
green (`283 PASS / 0 FAIL`; Task 1 registered the RC4 + modpow fixtures) and the
compiler fixed point is untouched (`hop1 == hop2 ==
296c48f676deec290387b57132e4e2bd`). The `--dump-c89` md5 below was refreshed for
the M4 source and is stable 3×.

**`tests/tier_real.sh` (best-effort, NOT a hard gate).** It builds z9torr and
runs it against a real torrent (default: the `lin_bin/` Debian torrent, or
`Z9TORR_REAL_TORRENT`), with MSE always, a UDP tracker whenever the torrent
lists `udp://`, and public DHT bootstrap routers (disable with
`Z9TORR_REAL_DHT=`). It exits `0` only on measured payload progress, `77` with an
explicit classified `SKIP: <reason>` when the client exits a recognized
environmental code (2 parse / 3 tracker / 4 peer / 5 disk / 124 bounded-timeout)
because the environment denies reachability (no torrent / no egress / tracker
unreachable / peers unreachable), and `1` on a build error, an unexpected
internal state, or any other (crash/signal) client exit — it never passes
silently. In the build sandbox the
tracker returns peers and DHT is attempted, but peers close at the MSE handshake
(matches the M3 `lin_bin/` diagnostic), so it reports `SKIP` (exit 77).

## M4.1 — real MSE/PE handshake (2026-10-10)

M4.1 makes the encrypted handshake actually work against real implementations
and fixes the fallback. Spec `docs/superpowers/specs/2026-10-10-z9torr-mse-real-handshake-design.md`,
plan `docs/superpowers/plans/2026-10-10-z9torr-mse-real-handshake-plan.md`.

- **MSE correctness (Task 3):** `piece.bitGet`/`bitSet` now decode the BEP 3
  bitfield MSB-first (was LSB-first, so the client saw an empty peer and never
  sent requests); `resume.zig`'s private bitmap helpers flipped to match the
  shared `completed_bits`; `wire.reservedAccepted` was loosened to allow the
  BEP 6 Fast Extension reserved bit (`reserved[7]`, `0x04`, e.g. aria2c) (the
  predicate was later removed entirely by the M4 polish below).
- **Non-blocking connect + MSE probe (Task 4):** `peer.zig` gained `connectAsync`
  (raw non-blocking `connect(2)` that yields on WouldBlock), and `mse.zig`
  became `mseConnectAsync`, so one silent peer no longer freezes the
  single-threaded scheduler. New `tests/tier_stall.sh` (black-hole first,
  healthy MSE peer second) proves completion in <500 ms where the blocking
  probe serialized the 3 s deadline.
- **Fallback policy A + fix (Task 5):** encrypted-first, plaintext reconnect on
  MSE failure (operator ruling). **Fix:** `plainReconnect` was capped at 100
  attempts; after Task 4 replaced its 20 ms `sleepMs` pause with `@asyncSuspend`,
  those attempts exhausted in microseconds, so any peer that became reachable
  shortly after the probe got `reconnect-fail` — the fallback "never succeeded".
  The retry loop is now wall-clock throttled (`FALLBACK_RETRY_MS`) and bounded
  only by `FALLBACK_WINDOW_MS` (3 s), so it keeps trying and succeeds. New
  `tests/tier_fallback.sh` (8/0): the existing one-shot plaintext `mock_peer`
  behind a 200 ms restart gap, against which the encrypted-first client must
  fail MSE, then complete a byte-verified plaintext download.

Gates (run from the repo root with the binding seed, all PASS): tier1 `16/0`,
tier1_cli `8/8`, tier1_unit `3/3`, tier2 `17/0`, tier3_encrypted `5/0`,
tier_udp_tracker `7/0`, tier_dht `4/0`, tier_pex `11/0`, tier_stall `8/0`,
tier_fallback `8/0`, tier_refseed_py `6/0` (independent Python MSE responder),
tier_refseed `6/0` (real aria2c 1.36.0, forced encryption), tier_mse_diag
`11/0`. No compiler/seed change (closure `46e3e7af98af3b5ff2a960c7c96025e3`,
seed v96).

## M4 polish — ignore unknown reserved bits (BEP 3) (2026-10-10)

The M4.1 finding was that real peers set reserved bits the strict
`wire.reservedAccepted` predicate rejected (qBittorrent/libtorrent
`reserved[5]=0x18`, `0000000000180005`), so a successful MSE handshake was
followed by `HandshakeFailed`. Fixed: the predicate is removed and the peer
handshake no longer rejects on reserved bits (BEP 3: a client MUST ignore
reserved bits it does not understand). The field is still stored verbatim in
`Handshake.reserved`, so capability detection is preserved — `peer.zig` still
tests `reserved[5] & 0x10` for BEP 10, and we continue advertising our own
BEP 10 / BEP 5 bits. `tier_mse_diag.sh` now reaches `aria2: encrypted BT
handshake accepted` (aria2c `reserved[7]=0x04` Fast Extension) instead of the
pre-fix reserved-bit divergence; no tier asserted reserved-bit rejection.

**Live Debian retest (best-effort, `lin_bin/`, fixed client):** 50 tracker
peers, 7 TCP connects, **7 `handshake ok`** (2 encrypted + 5 plaintext); the
exact qBittorrent `reserved=0000000000180005` handshake now succeeds
(`handshake ok enc`, MSE `stage=done`). The 3 handshake failures were
transport-level (`PeerClosed`/`NetFailed`), none reserved-bit. First real
payload progress in this sandbox: **~37.75 MiB / 4.9 %** at ~1 MiB/s before the
bounded 100 s window (exit 124, resume sidecar written; see `z9torr.log`).

## CP P3 — post-handshake peer drops on the BEP 5 PORT message (2026-10-10)

Real peers (qBittorrent/libtorrent) closed the connection immediately after a
successful handshake. Diagnosis (env-gated per-peer frame trace in `peer.zig`:
`peer slot=<n> frame tx|rx id=<id> len=<len>`, `frame rx error=<PeerError>`;
strict no-op when `Z9TORR_LOG` is unset):

- **Root cause (CLIENT-side):** we advertise the BEP 5 DHT reserved bit
  (`reserved[7]=0x01`), so a DHT-enabled peer sends its DHT `PORT` message
  (wire id **9**, 3-byte frame). `wire.decodeMsgType` mapped only 0..8 and 20,
  so `decodeFrame` returned `PeerError.BadMessage` and `peerRun` broke with
  `read-error` on the first PORT — dropping a healthy peer. The pre-fix live
  log fingerprint is `enc frame len=3` with **no** following `id=` line (the
  length is logged before `decodeFrame`; the id only after it succeeds),
  immediately followed by `break reason=read-error`; the one peer that served
  data was the one that never sent PORT.
- **Hermetic repro:** a throwaway local peer that handshakes, sends
  bitfield+unchoke, then a PORT frame made the pre-fix client close the
  connection right after PORT (`frame rx error=BadMessage`); post-fix the
  client reads `frame rx id=9 len=3` and keeps the connection open.
- **Fix (minimal):** `wire.MsgType` gains `port = 9` and `decodeMsgType`
  decodes it; `peer.zig`'s existing `else => {}` ignores it (we neither use nor
  reply to PORT). Behavioral change only; no protocol/format change to frames
  we emit.

**Live Debian retest (best-effort, `lin_bin/`, fixed client):** 50 tracker
peers, 16 spawned, 18 connects; **5 `handshake ok`** (4 encrypted + 1
plaintext) and **all 5 stayed connected** to the bounded window — `0`
post-handshake `read-error` (pre-fix: 6 of 7 dropped). Three peers sent
`frame rx id=9 len=3`; all were tolerated. **~42.75 MiB** fetched at ~1.0 MiB/s
with `peers=5`, 4177 `piece` frames (exit 124, 100 s window; see
`lin_bin/z9torr.log`). New `--dump-c89` md5
`fe6d03eb517d042c149b24a418a69d52`.

Next: M5 — Win9x cross-compat
(`docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md`).
