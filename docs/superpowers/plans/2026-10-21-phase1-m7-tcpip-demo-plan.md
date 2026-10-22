# Phase 1 M7 — std_tcpip + wireguard_demo + Closeout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The userspace tunnel-side stack (`std_tcpip`: IPv4 + TCP client + UDP + DNS + ICMP) and the `wireguard_demo` — a real Linux kernel WireGuard far side with `mud_server` behind it, banner visible through the tunnel from the Z98 client — plus Phase 1 closeout.

**Architecture:** Sans-I/O `tcpipPoll` pump (spec §5.8): stack emits/receives raw IPv4 datagrams; the demo driver encrypts them through `std_wireguard` into `std_net` UDP, and feeds decrypted inner packets back. TCP client only: 3WHS, seq/ack, fixed 8 KB window, simplified Karn RTO + minimal Reno, MSS 1400, drop fragments. DNS = UDP A-record to `cfg.dns_server`; ICMP echo client. Demo reads `wg.conf`, connects to the mud server's tunnel IP, prints banner + one command exchange, resource line.

**Tech Stack:** Z98; M6 `std_wireguard`; existing `std_net`, `std_time`, `std_arena`; Linux `wg-quick` + repo `mud_server` as the far side (test infra); Wine for `-osw`.

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.8, §6, §7, §8 M7 (split contingency: if size demands, 7a=stack tasks / 7b=demo+closeout, controller-call, ledgered)

## Global Constraints

- Sans-I/O stack per §5.8 signatures (`tcpipInit` arena-allocated, `TcpipAction` union, socket ids `u32`); client-only (no listen); no fragment reassembly; no SACK/scaling.
- Errors: `error.{Corrupt, NoRoute, ConnRefused, Timeout, DnsFailed, OutOfMemory, OutputTooSmall, Closed}` + per-socket failure via `TcpipAction.failed`.
- Demo config `wg.conf` keys (hex/base64): private key, peer public key, endpoint host:port, allowed IPs, tunnel local IP, optional DNS server + `clock_override_unix`.
- RAM: 32 MB hard ceiling / 16 MB target, enforced + recorded (`ulimit -v 32768`, `/usr/bin/time -v`); resource line `wireguard_demo ok bytes=N arena_peak=N rss_peak=N cpu_ms=N`.
- Gates per task (hybrid): targeted `std_tcpip`/demo fixtures + affected `run_crosscheck.sh` modules + 3×; `tier_wireguard.sh` (kernel `wg-quick` netns far side + `mud_server` through tunnel; loud SKIP if `wg`/netns unavailable; never vacuous); `-osw` build + import gate (KERNEL32+WINMM+WSOCK32, no msvcrt). Full `verify_stdlib.sh` + full crosscheck is mandatory immediately after any change to existing module functions, shared harness/`expected_dirs.txt`, `std.zig`, or a cross-module contract, and at Task 4 closeout. `std_tcpip`/demo are new → targeted-only until closeout.
- Closeout rotates seed **v118** (47 lib files: +`std_tcpip`); fixed point unchanged `45158dcede81125a39a2c2c58478e21e`; Phase 1 defect ledger entries appended to `examples/torrent_example_defects.md` (next free slot).
- Commits `feat(std_tcpip): … (Phase1 M7)`, `example(z9demo): wireguard_demo …`, `test(tier): tier_wireguard …`, `docs(std_lib): …`, `chore(seed): rotate (M7)`, `docs(sdd): …`. STOP-present on contract change.

## Review Focus

1. TCP seq/ack wrap or retransmit double-delivery (synthetic packet-exchange fixtures with drops/dup/reorder).
2. The stack consuming unbounded memory per socket (fixed window/buffer asserts; OOM path tested).
3. DNS parser on malformed answers (must `DnsFailed`, never crash) and retry/timeout behavior.
4. Demo passing inner packets before handshake completes (`NoSession`/`SessionExpired` discipline end-to-end).
5. tier_wireguard vacuous pass when `wg-quick` missing → loud SKIP with reason.

---

### Task 1: `std_tcpip` — IPv4 + TCP client core

**Files:**
- Create: `sf/src/std_tcpip.zig`
- Test: `repro/mi_matrix/stdlib_tcpip_tcp_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: `std_arena`, `std_time` values (params only).
- Produces (spec §5.8): `TcpipConfig`, `TcpipStack`, `tcpipInit`, `TcpipAction`, `tcpipPoll`, `tcpConnect`, `tcpSend`, `tcpRecv`, `tcpClose`. IPv4 header build/check (checksum), TCP client FSM.

- [ ] **Step 1:** Failing fixture: scripted packet-exchange tests driving `tcpipPoll` with synthetic peer bytes — 3WHS, data both ways (byte-exact), FIN close, RST → `failed`, retransmission after dropped ACK (assert re-sent seq), out-of-order segment buffering (within 8 KB), MSS 1400 split of a 5 KB `tcpSend`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement IPv4 + TCP client (8 KB window, simplified RTO 1 s + Karn, slow-start/AIMD; fixed scratch; no fragmentation).
- [ ] **Step 4:** Run — PASS + targeted `std_tcpip` TCP fixtures + affected `run_crosscheck.sh` modules + 3×. Full gate at Task 4 closeout.
- [ ] **Step 5:** Commit `feat(std_tcpip): IPv4 + TCP client (Phase1 M7)`.

### Task 2: UDP + DNS + ICMP

**Files:**
- Modify: `sf/src/std_tcpip.zig`
- Test: `repro/mi_matrix/stdlib_tcpip_udp_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_tcpip_dns_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Produces: `udpOpen`/`udpSendTo`/`udpRecvFrom`; `dnsResolve(name, out_ip) !void` (A records, timeout+retry via `tcpipPoll` waits); `icmpPing(ip, now_ms) !u32` (echo, RTT ms).

- [ ] **Step 1:** Failing fixtures: UDP round-trip synthetic; DNS request/response byte-exact query + parsed A record (v4-mapped answer), malformed answers → `DnsFailed`, timeout+retry counts; ICMP echo reply parse → RTT.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement per §5.8.
- [ ] **Step 4:** Run — PASS + targeted `std_tcpip` UDP/DNS/ICMP fixtures + affected `run_crosscheck.sh` modules + 3×. Full gate at Task 4 closeout.
- [ ] **Step 5:** Commit `feat(std_tcpip): UDP + DNS + ICMP (Phase1 M7)`.

### Task 3: `wireguard_demo` + `tier_wireguard.sh`

**Files:**
- Create: `examples/z98/demo/wireguard_demo/{main.zig,wg.conf.example,README.md,NOTES.md}`
- Create: `scripts/stdlib/tier_wireguard.sh` (or tests/ placement per house tier convention)

**Interfaces:**
- Consumes: `std_wireguard` (M6), `std_tcpip` (T1/T2), `std_net` UDP, `std_time`, `std_arena`.
- Produces: config-driven demo: handshake → `dnsResolve`/direct IP → `tcpConnect` to mud server tunnel IP → print banner → send one command → print reply → resource line + exit 0.

- [ ] **Step 1:** Implement demo (WAV-style house CLI conventions not needed — plain console; explicit `wall_unix_ns`/`now_ms` from `std_time`; `clock_override_unix` support; precise failure text `wg: …`/`tcp: …`).
- [ ] **Step 2:** `tier_wireguard.sh`: start Linux kernel WireGuard (`wg-quick` netns, committed tiny conf template with generated keys) + `mud_server` bound on the tunnel net; run the demo (Linux build) asserting banner bytes + resource line; Wine `-osw` run of the same demo against the same far side (tier case); `check_win9x_imports.sh 9x` gate; RAM enforcement `ulimit -v 32768` + recorded peak; loud SKIP when `wg`/`ip netns` absent.
- [ ] **Step 3:** Run `tier_wireguard.sh` 2× deterministic + targeted demo checks + 3×. Full gate at Task 4 closeout.
- [ ] **Step 4:** Commits `example(z9demo): wireguard_demo (Phase1 M7)`, `test(tier): tier_wireguard (Phase1 M7)`.

### Task 4: Phase 1 closeout

**Files:**
- Create: `sf/docs/std_lib/tcpip.md`
- Modify: `examples/z98/demo/{tls_demo,wireguard_demo}/README.md` (final cross-links, resource tables from measured runs)
- Modify: `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md` (46→47 counts/rows + Phase 1 summary)
- Modify: `examples/torrent_example_defects.md` (any Phase 1 defects; next free slot)
- Modify: `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`
- Rotate: `release/seed/` → **v118** (47 files)

- [ ] **Step 1:** tcpip.md (API §5.8, TCP policy table, DNS/ICMP notes, memory bounds); demo READMEs get measured RAM/CPU tables (Linux + Wine).
- [ ] **Step 2:** Truth-ups; defect ledger sweep (all Phase 1 STOPs/defects recorded or fixed); seed scripts; rotate v118; verify archive/manifest 47/fixed point `45158dcede81125a39a2c2c58478e21e`/hop1==hop2 (std-only; compiler source unchanged); full gate + both tiers green on rotated compiler.
- [ ] **Step 3:** Commits `docs(std_lib): tcpip docs + Phase 1 closeout`, `chore(seed): rotate (M7)`, `docs(sdd): M7 closeout report`.
