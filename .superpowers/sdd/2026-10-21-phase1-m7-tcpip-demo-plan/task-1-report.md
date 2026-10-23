# M7 Task 1 report — `std_tcpip` IPv4 + TCP client core

Status: COMPLETE — targeted fixture PASS (3×); implementation commit below

## Environment

- Repo: `/workspace/znineeight`
- Base: `ece401f4`
- Seed compiler: `/tmp/m6_t3_v118_rotated/zig1_5_clean`
- Seed md5: `45158dcede81125a39a2c2c58478e21e`

## Step 1 — fixture authored

Created `repro/mi_matrix/stdlib_tcpip_tcp_xmod/main.zig` covering:

- 3WHS (SYN + MSS option, SYN-ACK, ACK, `connected`)
- client->peer and peer->client data byte-exact
- FIN close (`fin_wait` + peer FIN|ACK -> `closed`)
- RST -> `failed`
- dropped ACK -> re-send of the same sequence after the 1 s RTO
- out-of-order peer segments buffered within 8 KB and delivered in order
- MSS 1400 split of a 5 KB `tcpSend` (1400/1400/1400/800) with `tcpClose`
  called while the whole buffer is still queued: pending data must drain
  before FIN
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
- TCP client FSM: SYN/SYN-ACK/ACK, seq/ack, 8 KB receive window, MSS 1400,
  16 KB fixed send buffer, out-of-order reassembly ring, retransmit with fixed
  1 s RTO (Karn: no RTT samples), slow start + AIMD, RTO timeout halves
  `ssthresh` and restarts at 1 MSS, FIN close (active + passive), RST ->
  `failed`.
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

## Concerns

- `TcpipConfig.mtu` is retained as config (defaulted to 1400 when zero), but the
  spec also fixes MSS = 1400. The implementation uses the fixed MSS 1400 for
  segmentation (as required by the 5 KB split test) rather than deriving an MSS
  from `mtu`.
- Passive close sends ACK then FIN when the peer initiates the FIN; the `closed`
  event is delivered after the app drains buffered data.
- The target fixture imports the new module; the seed sibling `lib/` copy used
  for testing is outside the repo and is not part of the commit.

## Commits

- Implementation: `6e14ce78fb8756dcb458cde9b9278b95de45133f`
  `feat(std_tcpip): IPv4 + TCP client (Phase1 M7)`
- This report: `docs(sdd): M7 T1 report` (this commit)
