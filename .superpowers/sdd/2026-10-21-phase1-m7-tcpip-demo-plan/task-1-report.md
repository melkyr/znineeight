# M7 Task 1 report — `std_tcpip` IPv4 + TCP client core

Status: COMPLETE + FIX ROUND 2 — targeted fixture PASS (3×) after coverage additions

## Environment

- Repo: `/workspace/znineeight`
- Base: `ece401f4` (initial task); fix-round base: `b47344be`
- Seed compiler: `/tmp/m6_t3_v118_rotated/zig1_5_clean`
- Seed md5: `45158dcede81125a39a2c2c58478e21e`

## Step 1 — fixture authored

Created `repro/mi_matrix/stdlib_tcpip_tcp_xmod/main.zig` covering:

- 3WHS (SYN + MSS option, SYN-ACK, ACK, `connected`)
- client->peer and peer->client data byte-exact
- FIN close (`fin_wait` + peer FIN|ACK -> `closed`)
- RST -> `failed`
- dropped ACK -> re-send of the same sequence after the 1 s RTO
- out-of-order peer segments buffered within 8 KB and delivered in order;
  duplicate bytes ACKed but not delivered twice
- `cfg.mtu=1400` -> local MSS 1360 split of a 5 KB `tcpSend`
  (1360/1360/1360/920) with `tcpClose` called while the whole buffer is still
  queued: pending data must drain before FIN
- peer-advertised MSS 1200 clamps outgoing segments (1200 + 100)
- receive/send sequence + ACK wrap across 2^32
- arena OOM at init and no-free-socket -> `OutOfMemory`
- `OutputTooSmall` during FIN leaves the socket retryable (same FIN seq)
- out-of-window FIN rejected, then a valid FIN -> `closed`
- malformed IPv4/TCP checksums -> `error.Corrupt`

Goldens: `expected.txt` = `tcpip tcp ok\n`, `expected.rc` = `0`.
Added `repro/mi_matrix/stdlib_tcpip_tcp_xmod` to `scripts/stdlib/expected_dirs.txt`
in LC_ALL=C sorted position (before `stdlib_time_monotonic_avail_xmod`).

## Step 2 — fixture fails before the module is installed

Before copying the new module into the seed's sibling `lib/` (test environment
only; no repo seed change):

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m6_t3_v118_rotated/zig1_5_clean repro/mi_matrix/stdlib_tcpip_tcp_xmod
FAIL repro/mi_matrix/stdlib_tcpip_tcp_xmod (DUMP-RC2)
    dump stderr:                      ^^^
----------------------------------------
run_fixtures: 0 PASS / 1 FAIL over 1 dirs
failed: repro/mi_matrix/stdlib_tcpip_tcp_xmod
```

Expected: the seed lib has no `std_tcpip.zig` yet.

## Step 3 — implementation

Created `sf/src/std_tcpip.zig`:

- `TcpipConfig`, `TcpipStack`, `tcpipInit` (arena-allocated stack + fixed
  `TcpSock` array; no heap).
- `TcpipAction`, `tcpipPoll` (one action per call: send / wait / event / done).
- `tcpConnect`, `tcpSend`, `tcpRecv`, `tcpClose`.
- IPv4 header build (DF, TTL 64, protocol 6) + one's-complement checksum
  (`ipv4Checksum` exposed) and inbound validation.
- TCP client FSM: SYN/SYN-ACK/ACK, seq/ack, 8 KB receive window,
  MTU-derived per-socket MSS, 16 KB fixed send buffer, out-of-order reassembly
  ring, retransmit with fixed 1 s RTO (Karn: no RTT samples), slow start +
  AIMD, RTO timeout halves `ssthresh` and restarts at 1 MSS, FIN close (active
  + passive), RST -> `failed`.
- Inbound fragments (MF or non-zero offset) are dropped; UDP/ICMP and
  non-local destinations are ignored.

Z98 notes: all edits are Z98-subset; no compiler/seed/std.zig changes. The new
module was copied into the seed's sibling `lib/` only for this targeted run
(test environment; the committed seed is untouched, rotation is Task 4).

## Step 4 — tests

Fixture: `repro/mi_matrix/stdlib_tcpip_tcp_xmod` (harness runs the program 3×
internally for byte-identical stdout/determinism).

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m6_t3_v118_rotated/zig1_5_clean repro/mi_matrix/stdlib_tcpip_tcp_xmod
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
----------------------------------------
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

3× (separate harness invocations):

```
=== run 1 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=== run 2 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=== run 3 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

Direct emit + build + run (context command shape):

```
$ /tmp/m6_t3_v118_rotated/zig1_5_clean -ffast -o /tmp/tcpip_m7t1 repro/mi_matrix/stdlib_tcpip_tcp_xmod/main.zig
$ (cd /tmp/tcpip_m7t1 && sh build_target.sh linux prog && ./prog)
tcpip tcp ok
rc=0
```

Affected crosscheck: none — `std_tcpip` is a new independent module with no
`scripts/stdlib/ref/` or `scripts/stdlib/vectors/` entry. Skipped explicitly.

Full `verify_stdlib.sh` + full crosscheck deferred to Task 4 closeout per brief.

## Fix round — MTU/MSS + FIN state safety

Binding long-term rule implemented:

- `cfg.mtu` is the maximum inner IPv4 datagram (headers included; default 1400
  when zero). Local MSS = `cfg.mtu - 40`.
- `parseMssOption` reads the peer MSS option from the SYN-ACK. The per-socket
  effective `p.mss` = `min(peer MSS, local MSS)` (local when absent). It is used
  for the SYN MSS option, every data/retransmit segment, initial cwnd, slow
  start/AIMD (`m*m/cwnd`), and the RTO floor/restart.
- `buildSegment` rejects any datagram whose total size exceeds `cfg.mtu`.
- FIN emission now builds the segment first and commits
  `fin_wait1`/`fin_sent`/`fin_seq`/`snd_nxt` only after success, so an
  `OutputTooSmall` poll leaves the socket retryable with the same FIN seq.
- `handleFin` accepts a FIN only when `fin_seq - rcv_nxt` is inside the current
  8 KB advertised receive window; an out-of-window FIN is ACKed but does not
  poison `peer_fin_pending`, so a later valid FIN completes `.closed`.

Fixture additions: local 1360 split of 5 KB, peer MSS 1200 clamp, duplicate
inbound data, send/receive seq+ACK wrap, arena-init OOM and no-free-socket,
`OutputTooSmall` FIN retry, and out-of-window FIN followed by a valid FIN.

3× targeted gate after the fixes:

```
=== fix run 1 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=== fix run 2 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=== fix run 3 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

## Fix round 2 — coverage pins (fixture only)

No source changes; the scoped review found only a test-coverage gap. Added:

- `testMtu600`: separate stack with `cfg.mtu=600`; SYN advertises local MSS
  560, `cwnd == 560`, a 2×MSS (1120-byte) `tcpSend` splits into 560 + 560, and
  every emitted IPv4 datagram is checked `<= 600` (validator now takes the
  stack's configured MTU rather than a fixture-global 1400).
- `testCwnd`: at `mtu=1400` the post-handshake socket `cwnd == MSS == 1360`;
  with 2×MSS (2720 bytes) buffered, only one 1360-byte segment is emitted
  before an ACK (the next poll returns wait), then the second 1360-byte segment
  is emitted after the ACK.
- `testFinWindow`: bad FIN changed to the exact window boundary
  `off == 8192` (one past the 8 KB window); it is rejected, and the later valid
  FIN still yields `.closed`.
- `doConnectFull` now asserts the SYN MSS option against `cfg.mtu - 40` instead
  of the hard-coded 1360, so the same handshake helper works for mtu 600.

3× targeted gate:

```
=== r2 run 1 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=== r2 run 2 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=== r2 run 3 ===
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

## Concerns

- Configuration with `mtu < 44` cannot carry a TCP SYN with the MSS option;
  `localMss` floors at 1, but such an MTU is not a usable TCP config (not
  exercised; valid configs are `mtu >= 44`).
- The sequence-wrap fixture overrides the stack's deterministic client ISS
  through the public `TcpSock` fields before the SYN (white-box setup only).
- Passive close sends ACK then FIN when the peer initiates the FIN; the `closed`
  event is delivered after the app drains buffered data.
- The target fixture imports the new module; the seed sibling `lib/` copy used
  for testing is outside the repo and is not part of the commit.

## Commits

- Initial implementation: `6e14ce78fb8756dcb458cde9b9278b95de45133f`
  `feat(std_tcpip): IPv4 + TCP client (Phase1 M7)`
- Initial report: `72da436f596f109c90ed0b81ac133db08b17c2ad`
  `docs(sdd): M7 T1 report`
- Fix round: `5c532f83398df7a705345c8a53a7ee2308b307ef`
  `fix(std_tcpip): MTU-derived MSS + FIN state safety (Phase1 M7)`
- Fix round report: `415c4e688ea9c3de550750644499c2fde4d3d3ea`
  `docs(sdd): M7 T1 fix round`
- Fix round 2 (coverage): `48ab8bd2daf3fc73ef4761827c09f074685c6aab`
  `test(std_tcpip): pin MTU authority and cwnd (Phase1 M7)`
- This report update: `docs(sdd): M7 T1 fix round 2` (this commit)
