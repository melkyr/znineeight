# M7 Task 2 report — `std_tcpip` UDP + DNS + ICMP

Status: COMPLETE + FIX ROUNDS — targeted UDP/DNS/TCP fixtures PASS (3×)

## Environment

- Repo: `/workspace/znineeight`
- Base: `d2a0569d` (M7 T1 complete ledger)
- Seed compiler: `/tmp/m6_t3_v118_rotated/zig1_5_clean`
- Seed md5: `45158dcede81125a39a2c2c58478e21e`
- Targeted: `bash scripts/stdlib/run_fixtures.sh <zig1> <dir>`

## Step 1 — fixtures authored (pre-implementation)

Created:

- `repro/mi_matrix/stdlib_tcpip_udp_xmod` — UDP open/send/recv round-trip,
  byte-exact IPv4/UDP headers + checksum, zero-length datagrams, receive
  truncation, max payload at MTU 1400, no-route, oversize, bad UDP checksum
  (`Corrupt`), wrong-destination drop; ICMP echo request bytes, reply RTT,
  retry cadence, max-retry timeout, bad ICMP checksum (`Corrupt`), wrong-id
  ignore. Golden `tcpip udp ok\n`, rc 0.
- `repro/mi_matrix/stdlib_tcpip_dns_xmod` — byte-exact A query (header/flags/
  counts/qname/qtype/qclass), compressed-pointer A answer parse, ID mismatch
  ignored, no-answer / bad RDLENGTH / truncated / RCODE -> `DnsFailed`, and
  fixed-interval retry counts with identical query bytes/ID. Golden
  `tcpip dns ok\n`, rc 0.

Pinned both dirs in `scripts/stdlib/expected_dirs.txt` (LC_ALL=C order:
dns, tcp, udp).

## Step 2 — fail before implementation

Seed lib has the Task 1 module only (no UDP/DNS/ICMP):

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m6_t3_v118_rotated/zig1_5_clean repro/mi_matrix/stdlib_tcpip_udp_xmod repro/mi_matrix/stdlib_tcpip_dns_xmod
FAIL repro/mi_matrix/stdlib_tcpip_udp_xmod (DUMP-RC2)
    dump stderr: ^
FAIL repro/mi_matrix/stdlib_tcpip_dns_xmod (DUMP-RC2)
    dump stderr: ^
----------------------------------------
run_fixtures: 0 PASS / 2 FAIL over 2 dirs
```

## Step 3 — implementation

`sf/src/std_tcpip.zig` now adds UDP, DNS A-record, and ICMP echo while keeping
the Task 1 IPv4/TCP paths unchanged.

- **UDP**: `UdpSock` array allocated from the same arena (`max_sockets` entries),
  `udpOpen` (explicit local port, or deterministic `49152 + slot` for port 0),
  one pending TX datagram and one RX datagram per socket, `udpSendTo` builds a
  full IPv4/UDP packet with checksum through the poll (`send_pkt`),
  `udpRecvFrom` drains the RX slot (returns 0 when empty; truncates to the
  caller buffer). Outbound size is bounded by `cfg.mtu` and
  `UDP_MAX_PAYLOAD = 1472`; full TX slot / oversize -> `OutputTooSmall`;
  unroutable destination -> `NoRoute`. Inbound UDP validates length and
  checksum (checksum 0 accepted per IPv4 UDP), and packets for non-local IPs are
  ignored. Fragments still drop before protocol dispatch.
- **DNS**: internal resolver on UDP source port 40000 to `cfg.dns_server:53`.
  `dnsResolve` builds a byte-exact A/IN query (labels, no compression),
  increments a deterministic query ID, and starts a pending request. The poll
  retransmits the identical payload/ID on a fixed cadence and parses answers
  (compressed/name pointers, A/IN, 4-byte RDATA) without heap or clock reads.
  Malformed/truncated/bad-RCODE/no-answer -> `DnsFailed`; mismatched ID is
  ignored; final retry exhaustion -> `DnsFailed`.
- **ICMP**: `icmpPing` starts a pending echo request; the poll emits IPv4/ICMP
  echo with fixed ID `0x5A39`, increments the sequence per request, retries on
  the fixed cadence, validates checksum, and records `rtt = now_ms -
  last_send_ms` when the matching echo reply arrives. Exhaustion ->
  `error.Timeout`.

### DNS/ICMP step semantics (sans-I/O)

The spec signatures carry no `rx`/`now_ms` for these two helpers, so they are
pump-driven step functions: the first call starts the request and returns
`error.Timeout`; `tcpipPoll` emits/retries/parses; calling the same helper again
after the reply is consumed returns the IPv4 answer / RTT. This is documented in
the module header. The `Timeout` result therefore means "pending" during the
request and "no reply after retries" only for a consumed failed ICMP request;
DNS exhaustion is surfaced as `DnsFailed` per the binding context.

### Fixed constants (no wall clock)

- `DNS_RETRY_MS = 1000`, `DNS_MAX_TRIES = 3`: sends at start, +1 s, +2 s;
  failure observed at +3 s.
- `ICMP_RETRY_MS = 1000`, `ICMP_MAX_TRIES = 3`: same cadence.
- DNS query ID starts at `0x4D37`; DNS local port 40000; ICMP ID `0x5A39`.
- Waits returned by `tcpipPoll` include the earliest TCP RTO or DNS/ICMP retry
  deadline, clamped to `DEFAULT_WAIT_MS = 1000`.

## Step 4 — tests

Targeted harness (UDP, DNS, and the preserved Task 1 TCP fixture) 3×:

```
=== run 1 ===
PASS repro/mi_matrix/stdlib_tcpip_udp_xmod
PASS repro/mi_matrix/stdlib_tcpip_dns_xmod
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
=== run 2 ===
PASS repro/mi_matrix/stdlib_tcpip_udp_xmod
PASS repro/mi_matrix/stdlib_tcpip_dns_xmod
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
=== run 3 ===
PASS repro/mi_matrix/stdlib_tcpip_udp_xmod
PASS repro/mi_matrix/stdlib_tcpip_dns_xmod
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
```

Affected crosscheck: none — `std_tcpip` is a new independent module with no
`scripts/stdlib/ref/` or `scripts/stdlib/vectors/` entry and no
`run_crosscheck.sh` module. Full `verify_stdlib.sh` + full crosscheck stay
deferred to Task 4 closeout per brief.

## Concerns

- UDP uses one fixed TX and one fixed RX datagram slot per socket; a second
  `udpSendTo` before the poll drains the first returns `OutputTooSmall` (UDP
  lossy/drop policy), and an inbound datagram overwrites an unconsumed RX slot
  (latest wins).
- `dnsResolve`/`icmpPing` cannot be called as blocking one-shot helpers under
  the sans-I/O signature; callers must pump between calls (see step semantics).
- DNS supports A/IN only; CNAME chains are unsupported (CNAME-only answers
  resolve to `DnsFailed`).
- No DNS/ICMP socket consumes public `max_sockets` slots (internal resolver
  state is in `TcpipStack`).

## Fix round — completion contract + validation

Base `a0e60a5a` (plan contract update), original implementation `3abc2193`,
fix implementation `78f4348c`.

- **ICMP source validation**: `processIcmp` now receives `src_ip` and accepts an
  echo reply only when `src_ip == s.icmp_ip`, in addition to the existing
  pending/ID/sequence checks.
- **Completion contract**: `tcpipPoll` returns `.done` as soon as DNS or ICMP is
  in terminal `done`/`failed`. Pending requests still make
  `dnsResolve`/`icmpPing` return `error.Timeout`; the final call consumes the
  terminal state and returns the IPv4 answer / RTT or `DnsFailed` / terminal
  `error.Timeout`. A terminal ICMP failure is consumed without starting a new
  probe (fixture asserts no echo is emitted on the following poll).
- **DNS QNAME validation**: added case-insensitive, compression-aware
  `dnsNameMatches`; the response question and answer owner names must match the
  stored query QNAME. Mismatch -> `DnsFailed`. ID/source IP/port checks remain.
- **Fixtures**: wrong-source ICMP ignored; wrong-ID while pending ignored;
  pending vs terminal `.done` asserted for ICMP success and timeout; DNS QNAME
  mismatch -> `DnsFailed`; case-insensitive QNAME accepted; DNS terminal
  `.done` asserted for success and failures; no fresh DNS/ICMP request after
  terminal consumption. TCP/MTU fixture unchanged and green.

3× targeted gate after the fix (UDP/DNS/TCP):

```
PASS repro/mi_matrix/stdlib_tcpip_udp_xmod
PASS repro/mi_matrix/stdlib_tcpip_dns_xmod
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs   (three separate runs)
```

Affected crosscheck: none (same rationale as above).

## Fix round 2 — coverage pins + report truth-up

Base `e04678f4`, plan amendment `ee46edc6`. No source behavior changed.

- **DNS CNAME rejection fixture**: added `testCname` (`alias.example` ->
  `real.example`). The response is a CNAME-only answer with a matching
  ID/source/QNAME; `tcpipPoll` returns terminal `.done` and the final
  `dnsResolve` returns `DnsFailed`. This pins the updated plan/spec rule that
  CNAME chains are not followed.
- **ICMP timeout exactness**: added `icmpTimedOut`, which returns true only for
  `error.Timeout`. After terminal `.done` for an exhausted probe, the test now
  asserts the final `icmpPing` returns exactly `error.Timeout` (not merely
  null/no reply).
- **Report correction**: the concerns section no longer claims CNAME chains can
  be followed; CNAME is unsupported and fails `DnsFailed`. The fix-round base
  note now names both the original implementation (`3abc2193`) and the fix
  implementation (`78f4348c`).

3× targeted gate after fix round 2 (UDP/DNS/TCP):

```
PASS repro/mi_matrix/stdlib_tcpip_udp_xmod
PASS repro/mi_matrix/stdlib_tcpip_dns_xmod
PASS repro/mi_matrix/stdlib_tcpip_tcp_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs   (three separate runs)
```

## Commits

- Implementation + fixtures + pin:
  `3abc2193` `feat(std_tcpip): UDP + DNS + ICMP (Phase1 M7)`
- Initial report: `1c862bb9` `docs(sdd): M7 T2 report`
- Fix round (completion + validation):
  `78f4348c` `fix(std_tcpip): DNS/ICMP completion + validation (Phase1 M7)`
- Fix round report: `e04678f4` `docs(sdd): M7 T2 fix round`
- Fix round 2 (coverage + truth-up):
  `c027fa61` `test(std_tcpip): pin CNAME rejection + ICMP timeout (Phase1 M7)`
- This report: `docs(sdd): M7 T2 fix round 2` (this commit)
